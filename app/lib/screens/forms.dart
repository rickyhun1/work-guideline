import 'package:flutter/material.dart';

import '../common.dart';
import '../state.dart';
import '../widgets/editors.dart';
import '../widgets/export_dialog.dart';
import '../widgets/files_panel.dart';
import '../widgets/log_panel.dart';

/// 양식(기록) 목록 · 파일 · 내보내기
class FormsPage extends StatefulWidget {
  const FormsPage({super.key});

  @override
  State<FormsPage> createState() => _FormsPageState();
}

class _FormsPageState extends State<FormsPage> {
  List<Map<String, dynamic>> forms = [];
  Map<String, dynamic>? form;
  int? selectedId;
  final checked = <int>{};
  String filter = '';
  int fileFilter = 0; // 0 전체, 1 파일 있음, 2 파일 없음

  @override
  void initState() {
    super.initState();
    _load();
    st.dataVersion.addListener(_load);
    st.nav.addListener(_nav);
  }

  @override
  void dispose() {
    st.dataVersion.removeListener(_load);
    st.nav.removeListener(_nav);
    super.dispose();
  }

  void _nav() {
    final r = st.nav.value;
    if (r != null && r.kind == 'form') {
      setState(() {
        filter = '';
        fileFilter = 0;
      });
      _select(r.id);
    }
  }

  Future<void> _load() async {
    try {
      forms = maps(await api.get('/forms'));
      checked.retainAll(forms.map((f) => f['id'] as int));
      if (selectedId != null) await _select(selectedId!);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _select(int id) async {
    try {
      final f = Map<String, dynamic>.from(await api.get('/forms/$id') as Map);
      if (mounted) {
        setState(() {
          selectedId = id;
          form = f;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          selectedId = null;
          form = null;
        });
      }
    }
  }

  List<Map<String, dynamic>> get shown {
    final f = filter.trim().toLowerCase();
    return forms.where((x) {
      final n = (x['fileCount'] as num? ?? 0).toInt();
      if (fileFilter == 1 && n == 0) return false;
      if (fileFilter == 2 && n > 0) return false;
      return f.isEmpty || '${x['code']} ${x['name']} ${x['docCode']} ${x['docTitle']}'.toLowerCase().contains(f);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = shown;
    final allChecked = list.isNotEmpty && list.every((x) => checked.contains(x['id']));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(children: [
          SizedBox(
            width: 360,
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: '양식번호·양식명·문서 검색'),
              onChanged: (v) => setState(() => filter = v),
            ),
          ),
          const SizedBox(width: 10),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('전체')),
              ButtonSegment(value: 1, label: Text('파일 있음')),
              ButtonSegment(value: 2, label: Text('파일 없음')),
            ],
            selected: {fileFilter},
            onSelectionChanged: (v) => setState(() => fileFilter = v.first),
          ),
          const Spacer(),
          if (checked.isNotEmpty)
            FilledButton.tonalIcon(
              icon: const Icon(Icons.archive_outlined, size: 18),
              label: Text('선택 ${checked.length}개 내보내기'),
              onPressed: () => showExportDialog(context, formIds: checked, defaultName: '양식'),
            ),
          const SizedBox(width: 6),
          OutlinedButton.icon(
            icon: const Icon(Icons.table_view, size: 18),
            label: const Text('양식 목록 엑셀'),
            onPressed: () => downloadTo(context, '/export/lists/forms', '양식 목록.xlsx'),
          ),
          if (st.can('docs', 2)) ...[
            const SizedBox(width: 6),
            FilledButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('새 양식'),
              onPressed: () async {
                final id = await showFormEditDialog(context, null);
                if (id != null) {
                  selectedId = id;
                  st.notifyDataChanged();
                }
              },
            ),
          ],
        ]),
      ),
      Expanded(
        child: Row(children: [
          Expanded(
            flex: 5,
            child: Column(children: [
              Container(
                color: theme.colorScheme.surfaceContainerHigh,
                child: Row(children: [
                  Checkbox(
                    value: allChecked,
                    onChanged: (v) => setState(() {
                  final ids = list.map((x) => x['id'] as int);
                  if (v == true) {
                    checked.addAll(ids);
                  } else {
                    checked.removeAll(ids);
                  }
                }),
                  ),
                  const Expanded(flex: 2, child: Text('양식번호', style: TextStyle(fontWeight: FontWeight.bold))),
                  const Expanded(flex: 4, child: Text('양식명', style: TextStyle(fontWeight: FontWeight.bold))),
                  const Expanded(flex: 3, child: Text('소속 문서', style: TextStyle(fontWeight: FontWeight.bold))),
                  const Expanded(flex: 1, child: Text('보존', style: TextStyle(fontWeight: FontWeight.bold))),
                  const SizedBox(width: 60, child: Text('파일', style: TextStyle(fontWeight: FontWeight.bold))),
                ]),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (ctx, i) {
                    final f = list[i];
                    final sel = f['id'] == selectedId;
                    final n = (f['fileCount'] as num? ?? 0).toInt();
                    return Material(
                      color: sel ? theme.colorScheme.primaryContainer : (i.isOdd ? theme.colorScheme.surfaceContainerLowest : null),
                      child: InkWell(
                        onTap: () => _select(f['id'] as int),
                        onDoubleTap: n == 0 ? null : () => openWithDefaultApp(context, '/export/forms/${f['id']}', '${f['code']} ${f['name']}.xlsx'),
                        child: Row(children: [
                          Checkbox(
                            value: checked.contains(f['id']),
                            onChanged: (v) => setState(() => v == true ? checked.add(f['id'] as int) : checked.remove(f['id'])),
                          ),
                          Expanded(flex: 2, child: Text(txt(f['code']))),
                          Expanded(flex: 4, child: Text(txt(f['name']))),
                          Expanded(flex: 3, child: Text('${f['docCode']} ${f['docTitle']}', overflow: TextOverflow.ellipsis)),
                          Expanded(flex: 1, child: Text(txt(f['retention']))),
                          SizedBox(width: 60, child: n == 0 ? muted(context, '없음') : Text('$n개')),
                        ]),
                      ),
                    );
                  },
                ),
              ),
            ]),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            flex: 4,
            child: form == null
                ? Center(child: muted(context, '양식을 고르세요. (두 번 누르면 바로 열립니다)'))
                : _detail(context, form!),
          ),
        ]),
      ),
    ]);
  }

  Widget _detail(BuildContext context, Map<String, dynamic> f) {
    final theme = Theme.of(context);
    final usedBy = maps(f['usedBy']);
    final hasFile = f['latestFileId'] != null;
    return DefaultTabController(
      length: 2,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text('${f['code']}  ${f['name']}', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
              if (st.can('docs', 2))
                IconButton(
                  tooltip: '수정',
                  icon: const Icon(Icons.edit),
                  onPressed: () async {
                    if (await showFormEditDialog(context, f) != null) st.notifyDataChanged();
                  },
                ),
              if (st.can('docs', 3))
                IconButton(
                  tooltip: '삭제',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    if (!await confirmDialog(context, '양식 삭제', '${f['code']} ${f['name']} 양식을 삭제할까요?', ok: '삭제', danger: true)) return;
                    try {
                      await api.delete('/forms/${f['id']}');
                      setState(() {
                        selectedId = null;
                        form = null;
                      });
                      st.notifyDataChanged();
                    } catch (e) {
                      if (context.mounted) showError(context, e);
                    }
                  },
                ),
            ]),
            const SizedBox(height: 4),
            Wrap(spacing: 16, runSpacing: 4, children: [
              Text('보존년한: ${txt(f['retention']).isEmpty ? '-' : f['retention']}'),
              Text('결재란: ${txt(f['approval']).isEmpty ? '-' : f['approval']}'),
              Text(f['codeManual'] == true ? '번호 직접 지정' : '번호 자동 (순번 ${f['seq']})'),
            ]),
            const SizedBox(height: 4),
            Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              muted(context, '사용 문서:'),
              for (final u in usedBy) LinkText('${u['code']} ${u['title']}', () => st.goto('document', u['id'] as int)),
            ]),
            if (txt(f['memo']).isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('메모: ${f['memo']}')),
            const SizedBox(height: 8),
            Row(children: [
              FilledButton.icon(
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('최신 양식 열기'),
                onPressed: !hasFile ? null : () => openWithDefaultApp(context, '/export/forms/${f['id']}', '${f['code']} ${f['name']}.xlsx'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.download, size: 18),
                label: const Text('현재 번호로 저장'),
                onPressed: !hasFile ? null : () => downloadTo(context, '/export/forms/${f['id']}', '${f['code']} ${f['name']}.xlsx'),
              ),
            ]),
          ]),
        ),
        const TabBar(tabs: [Tab(text: '파일 · 버전'), Tab(text: '변경이력')]),
        Expanded(
          child: TabBarView(children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: FilesPanel(
                owner: 'form',
                ownerId: f['id'] as int,
                module: 'docs',
                title: '양식 파일 (새 버전은 [파일 올리기], 맨 위가 최신)',
                onChanged: st.notifyDataChanged,
              ),
            ),
            SingleChildScrollView(padding: const EdgeInsets.all(16), child: LogPanel(entity: 'form', entityId: f['id'] as int)),
          ]),
        ),
      ]),
    );
  }
}

/// 양식 등록·수정. 저장하면 양식 id
Future<int?> showFormEditDialog(BuildContext context, Map<String, dynamic>? form, {int? documentId}) async {
  List<Map<String, dynamic>> docs;
  try {
    docs = maps(await api.get('/documents'));
  } catch (e) {
    if (context.mounted) showError(context, e);
    return null;
  }
  if (!context.mounted) return null;
  int? docId = form?['documentId'] as int? ?? documentId;
  final seq = TextEditingController(text: form == null ? '' : '${form['seq']}');
  final code = TextEditingController(text: txt(form?['code']));
  final name = TextEditingController(text: txt(form?['name']));
  final retention = TextEditingController(text: txt(form?['retention']));
  final approval = TextEditingController(text: txt(form?['approval']));
  final memo = TextEditingController(text: txt(form?['memo']));
  var manual = form?['codeManual'] == true;
  String? error;
  final docLabel = {for (final d in docs) d['id'] as int: '${d['code']}  ${d['title']}'};
  final r = await showDialog<int>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
      Future<void> save() async {
        if (docId == null || name.text.trim().isEmpty) return setLocal(() => error = '소속 문서와 양식명을 입력하세요.');
        final body = {
          'documentId': docId,
          if (seq.text.trim().isNotEmpty) 'seq': int.tryParse(seq.text.trim()) ?? 0,
          'code': code.text.trim(),
          'codeManual': manual,
          'name': name.text.trim(),
          'retention': retention.text.trim(),
          'approval': approval.text.trim(),
          'memo': memo.text.trim(),
          if (form != null) 'version': form['version'],
        };
        try {
          final res = form == null ? await api.post('/forms', body) as Map : await api.patch('/forms/${form['id']}', body) as Map;
          if (ctx.mounted) Navigator.pop(ctx, (res['id'] as num).toInt());
        } catch (e) {
          setLocal(() => error = errorText(e));
        }
      }

      return AlertDialog(
        title: Text(form == null ? '새 양식 등록' : '양식 수정'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              InkWell(
                onTap: () async {
                  final v = await pickOne(ctx, '소속 문서', [for (final d in docs) (d['id'] as int, '${d['code']}  ${d['title']}')], current: docId);
                  if (v != null && v > 0) setLocal(() => docId = v);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: '소속 문서', suffixIcon: Icon(Icons.arrow_drop_down)),
                  child: Text(docId == null ? '선택' : (docLabel[docId] ?? '')),
                ),
              ),
              const SizedBox(height: 10),
              Row(children: [
                SizedBox(
                  width: 120,
                  child: TextField(controller: seq, decoration: const InputDecoration(labelText: '순번', hintText: '자동')),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: code,
                    enabled: manual,
                    decoration: InputDecoration(labelText: '양식번호', helperText: manual ? '직접 지정' : '번호 체계에 따라 자동'),
                  ),
                ),
              ]),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: manual,
                title: const Text('양식번호 직접 지정'),
                onChanged: (v) => setLocal(() => manual = v ?? false),
              ),
              TextField(controller: name, decoration: const InputDecoration(labelText: '양식명')),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: TextField(controller: retention, decoration: const InputDecoration(labelText: '보존년한', hintText: '예: 3년, 영구'))),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: approval, decoration: const InputDecoration(labelText: '결재란', hintText: '담당 → 팀장 → 부서장'))),
              ]),
              const SizedBox(height: 10),
              TextField(controller: memo, minLines: 2, maxLines: 5, decoration: const InputDecoration(labelText: '메모')),
              if (form == null) Padding(padding: const EdgeInsets.only(top: 10), child: muted(ctx, '저장한 뒤 [파일 올리기]로 엑셀 파일을 등록하세요.')),
              if (error != null)
                Padding(padding: const EdgeInsets.only(top: 10), child: Text(error!, style: TextStyle(color: Theme.of(ctx).colorScheme.error))),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          FilledButton(onPressed: save, child: const Text('저장')),
        ],
      );
    }),
  );
  for (final c in [seq, code, name, retention, approval, memo]) {
    c.dispose();
  }
  return r;
}
