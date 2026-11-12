import 'dart:convert';

import 'package:flutter/material.dart';

import '../common.dart';
import '../state.dart';

const entityLabels = {
  'document': '문서', 'form': '양식', 'law': '법령', 'project': '프로젝트', 'item': '프로젝트 항목',
  'file': '파일', 'user': '사용자', 'department': '부서', 'settings': '설정',
};

Color actionColorOf(String a) {
  switch (a) {
    case '등록':
    case '업로드':
      return const Color(0xFF2E7D32);
    case '수정':
    case '번호변경':
    case '설정':
      return const Color(0xFF1565C0);
    case '삭제':
    case '파일삭제':
      return const Color(0xFFC62828);
    default:
      return Colors.grey.shade700;
  }
}

String _fmtValue(dynamic v) {
  if (v == null) return '';
  if (v is String) return v;
  if (v is num || v is bool) return '$v';
  return const JsonEncoder.withIndent('  ').convert(v);
}

/// 변경이력 한 건의 상세 (변경 전 → 후)
Future<void> showLogDetail(BuildContext context, Map<String, dynamic> log) {
  final detail = Map<String, dynamic>.from(log['detail'] as Map? ?? {});
  final changes = Map<String, dynamic>.from(detail['changes'] as Map? ?? {});
  final codes = (detail['codes'] as List?) ?? const [];
  final theme = Theme.of(context);
  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('${log['action']} · ${log['label'] ?? ''}'),
      content: SizedBox(
        width: 820,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('${fmtDateTime(txt(log['at']))} · ${log['userName'] ?? ''} · ${entityLabels[log['entity']] ?? log['entity']}',
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            if (changes.isNotEmpty)
              SimpleTable(
                headers: const ['항목', '변경 전', '변경 후'],
                flex: const [1, 3, 3],
                rows: [
                  for (final e in changes.entries)
                    [
                      Text(e.key, style: const TextStyle(fontWeight: FontWeight.w600)),
                      SelectableText(_fmtValue((e.value as List)[0]), style: const TextStyle(color: Color(0xFF9A3B3B))),
                      SelectableText(_fmtValue((e.value as List)[1]), style: const TextStyle(color: Color(0xFF1D6B3A))),
                    ],
                ],
              ),
            if (codes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('번호 변경 ${codes.length}건', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              SimpleTable(headers: const ['이전 번호', '새 번호'], rows: [
                for (final c in codes) [Text(txt((c as List)[0])), Text(txt(c[1]))],
              ]),
            ],
            if (detail['note'] != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('메모: ${detail['note']}')),
            if (changes.isEmpty && codes.isEmpty && detail['note'] == null) muted(ctx, '세부 내용 없음'),
          ]),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('닫기'))],
    ),
  );
}

/// 대상별 변경이력 목록 (문서·양식·법령·프로젝트 상세 화면 안)
class LogPanel extends StatefulWidget {
  const LogPanel({super.key, this.entity, this.entityId, this.projectId});
  final String? entity;
  final int? entityId;
  final int? projectId;

  @override
  State<LogPanel> createState() => _LogPanelState();
}

class _LogPanelState extends State<LogPanel> {
  List<Map<String, dynamic>> logs = [];

  @override
  void initState() {
    super.initState();
    _load();
    st.dataVersion.addListener(_load);
  }

  @override
  void dispose() {
    st.dataVersion.removeListener(_load);
    super.dispose();
  }

  @override
  void didUpdateWidget(LogPanel old) {
    super.didUpdateWidget(old);
    if (old.entityId != widget.entityId || old.projectId != widget.projectId) _load();
  }

  Future<void> _load() async {
    if (widget.entityId == null && widget.projectId == null) {
      if (mounted) setState(() => logs = []);
      return;
    }
    try {
      final r = maps(await api.get('/logs', query: {
        'entity': widget.projectId == null ? widget.entity : null,
        'entityId': widget.entityId?.toString(),
        'projectId': widget.projectId?.toString(),
      }));
      if (mounted) setState(() => logs = r);
    } catch (_) {/* 권한이 없으면 비워 둔다 */}
  }

  @override
  Widget build(BuildContext context) {
    if (logs.isEmpty) return muted(context, '변경이력이 없습니다.');
    return Column(children: [
      for (final l in logs)
        ListTile(
          dense: true,
          leading: Badge2(txt(l['action']), actionColorOf(txt(l['action']))),
          title: Text(txt(l['label'])),
          subtitle: Text('${fmtDateTime(txt(l['at']))} · ${txt(l['userName'])}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showLogDetail(context, l),
        ),
    ]);
  }
}
