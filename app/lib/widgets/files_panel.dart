import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../common.dart';
import '../state.dart';

/// 첨부 파일 목록 + 올리기/받기/열기/삭제. 같은 대상에 다시 올리면 최신 것이 위에 오고 이전 것도 남는다.
class FilesPanel extends StatefulWidget {
  const FilesPanel({super.key, required this.owner, required this.ownerId, required this.module, this.title = '파일', this.onChanged});
  final String owner; // document / form / law / project / item
  final int? ownerId;
  final String module; // 권한 확인용 메뉴
  final String title;
  final VoidCallback? onChanged;

  @override
  State<FilesPanel> createState() => _FilesPanelState();
}

class _FilesPanelState extends State<FilesPanel> {
  List<Map<String, dynamic>> files = [];
  bool loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(FilesPanel old) {
    super.didUpdateWidget(old);
    if (old.ownerId != widget.ownerId || old.owner != widget.owner) _load();
  }

  Future<void> _load() async {
    if (widget.ownerId == null) {
      setState(() => files = []);
      return;
    }
    setState(() => loading = true);
    try {
      files = maps(await api.get('/files', query: {'owner': widget.owner, 'ownerId': '${widget.ownerId}'}));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _upload() async {
    final picked = await openFiles();
    if (picked.isEmpty || !mounted) return;
    final note = await promptText(context, '파일 메모', label: '예: 2027년 개정본, 작성 완료본 (비워도 됨)');
    if (note == null) return;
    try {
      for (final f in picked) {
        final bytes = await File(f.path).readAsBytes();
        await api.upload('/files', bytes,
            query: {'owner': widget.owner, 'ownerId': '${widget.ownerId}', 'name': f.name, 'note': note},
            contentType: 'application/octet-stream');
      }
      if (mounted) showInfo(context, '${picked.length}개 파일을 올렸습니다.');
    } catch (e) {
      if (mounted) showError(context, e);
    }
    await _load();
    widget.onChanged?.call();
  }

  Future<void> _delete(Map<String, dynamic> f) async {
    if (!await confirmDialog(context, '파일 삭제', "'${f['filename']}' 파일을 삭제할까요?\n(변경이력에 기록됩니다)", ok: '삭제', danger: true)) return;
    try {
      await api.delete('/files/${f['id']}');
    } catch (e) {
      if (mounted) showError(context, e);
    }
    await _load();
    widget.onChanged?.call();
  }

  Future<void> _editNote(Map<String, dynamic> f) async {
    final note = await promptText(context, '메모 수정', initial: txt(f['note']));
    if (note == null) return;
    try {
      await api.patch('/files/${f['id']}', {'note': note});
      await _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canEdit = st.can(widget.module, 2);
    final canDel = st.can(widget.module, 3);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Text(widget.title, style: theme.textTheme.titleSmall),
        const SizedBox(width: 8),
        if (loading) const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
        const Spacer(),
        if (canEdit)
          FilledButton.tonalIcon(
            onPressed: widget.ownerId == null ? null : _upload,
            icon: const Icon(Icons.upload_file, size: 18),
            label: const Text('파일 올리기'),
          ),
      ]),
      const SizedBox(height: 6),
      if (files.isEmpty && !loading) muted(context, '파일이 없습니다.'),
      for (var i = 0; i < files.length; i++)
        Card(
          margin: const EdgeInsets.only(bottom: 4),
          child: ListTile(
            dense: true,
            leading: Icon(i == 0 ? Icons.insert_drive_file : Icons.history, color: i == 0 ? theme.colorScheme.primary : null),
            title: Text(txt(files[i]['filename'])),
            subtitle: Text([
              if (i == 0 && files.length > 1) '최신',
              if (txt(files[i]['note']).isNotEmpty) txt(files[i]['note']),
              humanSize(files[i]['size'] as num? ?? 0),
              '${fmtDateTime(txt(files[i]['uploadedAt']))} ${txt(files[i]['uploadedBy'])}',
            ].join(' · ')),
            trailing: Wrap(spacing: 2, children: [
              IconButton(
                tooltip: '열기',
                icon: const Icon(Icons.open_in_new, size: 20),
                onPressed: () => openWithDefaultApp(context, '/files/${files[i]['id']}/download', txt(files[i]['filename'])),
              ),
              IconButton(
                tooltip: '다른 이름으로 저장',
                icon: const Icon(Icons.download, size: 20),
                onPressed: () => downloadTo(context, '/files/${files[i]['id']}/download', txt(files[i]['filename'])),
              ),
              if (canEdit)
                IconButton(tooltip: '메모 수정', icon: const Icon(Icons.edit_note, size: 20), onPressed: () => _editNote(files[i])),
              if (canDel)
                IconButton(tooltip: '삭제', icon: const Icon(Icons.delete_outline, size: 20), onPressed: () => _delete(files[i])),
            ]),
          ),
        ),
    ]);
  }
}
