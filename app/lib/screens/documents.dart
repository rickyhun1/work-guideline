import 'package:flutter/material.dart';

import '../common.dart';
import '../state.dart';
import '../widgets/editors.dart';
import '../widgets/export_dialog.dart';
import '../widgets/files_panel.dart';
import '../widgets/log_panel.dart';
import 'forms.dart' show showFormEditDialog;

const resKeys = ['시설', '장비/도구', '수단', '자재', '인원의적격성', '관련조직'];

/// 업무표준 문서 (매뉴얼·프로세스·지침)
class DocumentsPage extends StatefulWidget {
  const DocumentsPage({super.key});

  @override
  State<DocumentsPage> createState() => _DocumentsPageState();
}

class _DocumentsPageState extends State<DocumentsPage> {
  List<Map<String, dynamic>> docs = [];
  Map<String, dynamic>? doc; // 선택한 문서 상세
  int? selectedId;
  final checked = <int>{};
  String filter = '';
  String? typeFilter;
  bool loading = false;

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
    if (r != null && r.kind == 'document') {
      setState(() {
        filter = '';
        typeFilter = null;
      });
      _select(r.id);
    }
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      docs = maps(await api.get('/documents'));
      checked.retainAll(docs.map((d) => d['id'] as int));
      if (selectedId != null) await _select(selectedId!);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _select(int id) async {
    try {
      final d = Map<String, dynamic>.from(await api.get('/documents/$id') as Map);
      if (!mounted) return;
      setState(() {
        selectedId = id;
        doc = d;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          selectedId = null;
          doc = null;
        });
        showError(context, e);
      }
    }
  }

  List<Map<String, dynamic>> get shown {
    final f = filter.trim().toLowerCase();
    return docs.where((d) {
      if (typeFilter != null && d['type'] != typeFilter) return false;
      return f.isEmpty || '${d['code']} ${d['title']}'.toLowerCase().contains(f);
    }).toList();
  }

  Future<void> _edit({bool create = false}) async {
    final id = await showDocumentEditDialog(context, create ? null : doc);
    if (id != null) {
      selectedId = id;
      st.notifyDataChanged();
    }
  }

  Future<void> _delete() async {
    final d = doc;
    if (d == null) return;
    if (!await confirmDialog(context, '문서 삭제', "${d['code']} ${d['title']} 문서를 삭제할까요?\n소속 양식도 함께 삭제됩니다. (변경이력에 기록됩니다)",
        ok: '삭제', danger: true)) {
      return;
    }
    try {
      await api.delete('/documents/${d['id']}');
      setState(() {
        selectedId = null;
        doc = null;
      });
      st.notifyDataChanged();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = shown;
    final allChecked = list.isNotEmpty && list.every((d) => checked.contains(d['id']));
    return Row(children: [
      SizedBox(
        width: 400,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.filter_list), hintText: '번호·문서명 필터'),
              onChanged: (v) => setState(() => filter = v),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              ChoiceChip(label: const Text('전체'), selected: typeFilter == null, onSelected: (_) => setState(() => typeFilter = null)),
              for (final t in st.docTypes)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: ChoiceChip(
                    label: Text('${t['label']}'),
                    selected: typeFilter == t['key'],
                    onSelected: (_) => setState(() => typeFilter = t['key'] as String),
                  ),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
            child: Row(children: [
              Checkbox(
                value: allChecked,
                onChanged: (v) => setState(() {
                  final ids = list.map((d) => d['id'] as int);
                  if (v == true) {
                    checked.addAll(ids);
                  } else {
                    checked.removeAll(ids);
                  }
                }),
              ),
              Text(checked.isEmpty ? '${list.length}개' : '${checked.length}개 선택'),
              const Spacer(),
              if (checked.isNotEmpty)
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.archive_outlined, size: 18),
                  label: const Text('선택 내보내기'),
                  onPressed: () => showExportDialog(context, documentIds: checked, defaultName: '업무표준 문서'),
                ),
              PopupMenuButton<String>(
                tooltip: '더보기',
                onSelected: (v) {
                  if (v == 'list') downloadTo(context, '/export/lists/documents', '업무표준 문서 목록표.xlsx');
                  if (v == 'new') _edit(create: true);
                },
                itemBuilder: (_) => [
                  if (st.can('docs', 2)) const PopupMenuItem(value: 'new', child: Text('새 문서 등록')),
                  const PopupMenuItem(value: 'list', child: Text('문서 목록표 엑셀로 받기')),
                ],
              ),
            ]),
          ),
          if (loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (ctx, i) {
                final d = list[i];
                final first = i == 0 || list[i - 1]['type'] != d['type'];
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (first)
                    Container(
                      color: theme.colorScheme.surfaceContainerHigh,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      child: Text(st.typeLabel(d['type'] as String), style: theme.textTheme.labelLarge),
                    ),
                  ListTile(
                    dense: true,
                    selected: d['id'] == selectedId,
                    leading: Checkbox(
                      value: checked.contains(d['id']),
                      onChanged: (v) => setState(() => v == true ? checked.add(d['id'] as int) : checked.remove(d['id'])),
                    ),
                    title: Text('${d['code']}  ${d['title']}'),
                    subtitle: d['department'] == null ? null : Text('${d['department']}'),
                    onTap: () => _select(d['id'] as int),
                  ),
                ]);
              },
            ),
          ),
        ]),
      ),
      const VerticalDivider(width: 1),
      Expanded(
        child: doc == null
            ? Center(child: muted(context, '왼쪽에서 문서를 고르세요.'))
            : DocumentDetail(key: ValueKey('doc${doc!['id']}-${doc!['version']}'), doc: doc!, onEdit: _edit, onDelete: _delete),
      ),
    ]);
  }
}

class DocumentDetail extends StatelessWidget {
  const DocumentDetail({super.key, required this.doc, required this.onEdit, required this.onDelete});
  final Map<String, dynamic> doc;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  Map<String, dynamic> get data => Map<String, dynamic>.from(doc['data'] as Map? ?? {});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canEdit = st.can('docs', 2);
    return DefaultTabController(
      length: 6,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 16, 0),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${doc['code']}  ${doc['title']}', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                Text(
                  [
                    st.typeLabel(doc['type'] as String),
                    '주관부서: ${doc['department'] ?? '-'}',
                    if (txt(data['deptNote']).isNotEmpty) txt(data['deptNote']),
                    '최종수정 ${fmtDateTime(txt(doc['updatedAt']))} ${txt(doc['updatedBy'])}',
                  ].join(' · '),
                  style: theme.textTheme.bodySmall,
                ),
              ]),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.file_download_outlined, size: 18),
              label: const Text('엑셀로 내보내기'),
              onPressed: () => downloadTo(context, '/export/documents/${doc['id']}', '${doc['code']} ${doc['title']}.xlsx'),
            ),
            const SizedBox(width: 6),
            OutlinedButton.icon(
              icon: const Icon(Icons.archive_outlined, size: 18),
              label: const Text('양식까지 zip'),
              onPressed: () => showExportDialog(context, documentIds: {doc['id'] as int}, defaultName: '${doc['code']} ${doc['title']}'),
            ),
            if (canEdit) ...[
              const SizedBox(width: 6),
              FilledButton.icon(icon: const Icon(Icons.edit, size: 18), label: const Text('수정'), onPressed: onEdit),
            ],
            if (st.can('docs', 3))
              IconButton(tooltip: '삭제', icon: const Icon(Icons.delete_outline), onPressed: onDelete),
          ]),
        ),
        const TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
          Tab(text: '개요'), Tab(text: '업무절차'), Tab(text: '결재 · 서류'), Tab(text: '요구사항 · 법령'), Tab(text: '첨부파일'), Tab(text: '변경이력'),
        ]),
        Expanded(
          child: TabBarView(children: [
            _scroll(_overview(context)),
            _scroll(_steps(context)),
            _scroll(_approval(context)),
            _scroll(_requirements(context)),
            _scroll([FilesPanel(owner: 'document', ownerId: doc['id'] as int, module: 'docs', title: '첨부 파일 (원본 문서, 개정본, 참고자료)')]),
            _scroll([LogPanel(entity: 'document', entityId: doc['id'] as int)]),
          ]),
        ),
      ]),
    );
  }

  Widget _scroll(List<Widget> children) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );

  Widget _text(BuildContext c, dynamic v) => txt(v).isEmpty ? muted(c, '(입력 안 됨)') : SelectableText(txt(v), style: const TextStyle(height: 1.5));

  List<Widget> _overview(BuildContext context) {
    final d = data;
    final res = Map<String, dynamic>.from(d['resources'] as Map? ?? {});
    final kpis = maps(d['kpis']);
    final related = maps(doc['related']);
    final refBy = maps(doc['referencedBy']);
    final revs = maps(d['revisions']);
    return [
      Section('목적', [_text(context, d['purpose'])]),
      Section('적용범위', [_text(context, d['scope'])]),
      if (res.values.any((v) => txt(v).isNotEmpty))
        Section('프로세스 자원 (What / Who)', [
          SimpleTable(headers: const ['구분', '내용'], flex: const [1, 4], rows: [
            for (final k in resKeys) [Text(k), SelectableText(txt(res[k]))],
          ]),
        ]),
      if ((d['mainSteps'] as List? ?? const []).isNotEmpty)
        Section('주요 업무절차', [
          for (final (i, s) in (d['mainSteps'] as List).indexed) Padding(padding: const EdgeInsets.only(bottom: 2), child: Text('${i + 1}. $s')),
        ]),
      if (kpis.isNotEmpty)
        Section('성과 및 리스크 지표', [
          SimpleTable(headers: const ['지표', '산출식', '주기'], flex: const [2, 3, 1], rows: [
            for (final k in kpis) [Text(txt(k['name'])), Text(txt(k['formula'])), Text(txt(k['period']))],
          ]),
        ]),
      Section('관련 프로세스', [
        if (related.isEmpty) muted(context, '(없음)'),
        Wrap(spacing: 14, runSpacing: 6, children: [
          for (final r in related) LinkText('${r['code']} ${r['title']}', () => st.goto('document', r['id'] as int)),
        ]),
        if (refBy.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 10, runSpacing: 4, children: [
            muted(context, '이 문서를 참조하는 문서:'),
            for (final r in refBy) LinkText('${r['code']}', () => st.goto('document', r['id'] as int)),
          ]),
        ],
      ]),
      if (revs.isNotEmpty)
        Section('개정이력', [
          SimpleTable(headers: const ['개정번호', '제·개정일자', '사유 및 내용'], flex: const [1, 1, 4], rows: [
            for (final r in revs) [Text(txt(r['rev'])), Text(txt(r['date'])), Text(txt(r['desc']))],
          ]),
        ]),
    ];
  }

  List<Widget> _steps(BuildContext context) {
    final d = data;
    final steps = maps(d['steps']);
    final theme = Theme.of(context);
    return [
      if (steps.isNotEmpty)
        SimpleTable(
          headers: const ['입력사항', '업무 수행 내용', '출력사항(서류)', '전결권한'],
          flex: const [2, 5, 2, 1],
          rows: [
            for (final (i, s) in steps.indexed) ...[
              [
                Text('${i + 1}. ${txt(s['title'])}', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox.shrink(), const SizedBox.shrink(), const SizedBox.shrink(),
              ],
              [
                Text([for (final x in (s['inputs'] as List? ?? const [])) '▶ $x'].join('\n')),
                SelectableText(txt(s['content']), style: const TextStyle(height: 1.5)),
                Text([for (final x in (s['outputs'] as List? ?? const [])) '▶ $x'].join('\n')),
                Text(txt(s['approver']), style: TextStyle(color: theme.colorScheme.tertiary, fontWeight: FontWeight.bold)),
              ],
              if (txt(s['note']).isNotEmpty)
                [SelectableText(txt(s['note']), style: theme.textTheme.bodySmall), const SizedBox.shrink(), const SizedBox.shrink(), const SizedBox.shrink()],
            ],
          ],
        ),
      if (txt(d['body']).isNotEmpty) Section(steps.isEmpty ? '내용' : '본문', [SelectableText(txt(d['body']), style: const TextStyle(height: 1.6))]),
      if (steps.isEmpty && txt(d['body']).isEmpty) muted(context, '입력된 절차가 없습니다. [수정]에서 입력하세요.'),
    ];
  }

  List<Widget> _approval(BuildContext context) {
    final d = data;
    final line = maps(d['approvalLine']);
    final steps = maps(d['steps']).where((s) => txt(s['approver']).isNotEmpty).toList();
    final forms = maps(doc['forms']);
    final theme = Theme.of(context);
    return [
      Section('문서 결재라인 (작성 · 검토 · 승인)', [
        if (line.isEmpty) muted(context, '지정 안 됨 — [수정] › 결재라인에서 지정하세요.'),
        if (line.isNotEmpty)
          Row(children: [
            for (final (i, a) in line.indexed) ...[
              if (i > 0) const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Icon(Icons.arrow_forward, size: 18)),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Column(children: [Text(txt(a['stage']), style: theme.textTheme.labelSmall), Text(txt(a['role']))]),
                ),
              ),
            ],
          ]),
      ]),
      if (steps.isNotEmpty)
        Section('단계별 전결권한', [
          SimpleTable(headers: const ['업무 단계', '생성 서류', '전결권자'], flex: const [3, 3, 1], rows: [
            for (final s in steps)
              [Text(txt(s['title'])), Text((s['outputs'] as List? ?? const []).join(', ')), Text(txt(s['approver']))],
          ]),
        ]),
      Section(
        '관련 기록 및 양식',
        [
          if (forms.isEmpty) muted(context, '연결된 양식이 없습니다.'),
          if (forms.isNotEmpty)
            SimpleTable(
              headers: const ['양식번호', '양식명', '보존년한', '결재란', '파일'],
              flex: const [2, 4, 1, 2, 3],
              rows: [
                for (final f in forms)
                  [
                    LinkText(txt(f['code']), () => st.goto('form', f['id'] as int)),
                    Text('${f['name']}${f['own'] == true ? '' : '  (${f['docCode']} 양식)'}'),
                    Text(txt(f['retention'])),
                    Text(txt(f['approval'])),
                    f['latestFileId'] == null
                        ? muted(context, '파일 없음')
                        : Wrap(spacing: 4, children: [
                            TextButton(
                              onPressed: () => openWithDefaultApp(context, '/export/forms/${f['id']}', '${f['code']} ${f['name']}.xlsx'),
                              child: const Text('열기'),
                            ),
                            TextButton(
                              onPressed: () => downloadTo(context, '/export/forms/${f['id']}', '${f['code']} ${f['name']}.xlsx'),
                              child: const Text('저장'),
                            ),
                            if (f['own'] != true && st.can('docs', 2))
                              TextButton(
                                onPressed: () async {
                                  try {
                                    await api.delete('/documents/${doc['id']}/forms/${f['id']}');
                                    st.notifyDataChanged();
                                  } catch (e) {
                                    if (context.mounted) showError(context, e);
                                  }
                                },
                                child: const Text('연결 해제'),
                              ),
                          ]),
                  ],
              ],
            ),
        ],
        trailing: !st.can('docs', 2)
            ? null
            : Wrap(spacing: 6, children: [
                TextButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('새 양식'),
                  onPressed: () async {
                    if (await showFormEditDialog(context, null, documentId: doc['id'] as int) != null) st.notifyDataChanged();
                  },
                ),
                TextButton.icon(
                  icon: const Icon(Icons.link, size: 18),
                  label: const Text('다른 문서 양식 연결'),
                  onPressed: () => _linkForms(context),
                ),
              ]),
      ),
    ];
  }

  Future<void> _linkForms(BuildContext context) async {
    try {
      final all = maps(await api.get('/forms'));
      final have = {for (final f in maps(doc['forms'])) f['id'] as int};
      if (!context.mounted) return;
      final sel = await pickMany(context, '다른 문서의 양식 연결',
          [for (final f in all) if (!have.contains(f['id'])) (f['id'] as int, '${f['code']}  ${f['name']}')], {});
      if (sel == null || sel.isEmpty) return;
      for (final id in sel) {
        await api.put('/documents/${doc['id']}/forms/$id', {});
      }
      st.notifyDataChanged();
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  List<Widget> _requirements(BuildContext context) {
    final reqs = maps(data['requirements']);
    final laws = maps(doc['laws']);
    return [
      Section('요구사항 (규격 · 고객 · 법 · 규제)', [
        if (reqs.isEmpty) muted(context, '(없음)'),
        if (reqs.isNotEmpty)
          SimpleTable(headers: const ['구분', '조항', '내용'], flex: const [2, 1, 5], rows: [
            for (final r in reqs) [Text(txt(r['cat'])), Text(txt(r['no'])), Text(txt(r['name']))],
          ]),
      ]),
      Section(
        '연결된 법령 (법령 메뉴에 등록된 내용)',
        [
          if (laws.isEmpty) muted(context, '연결된 법령이 없습니다. 법령 메뉴에서 등록한 뒤 [법령 연결]로 연결하세요.'),
          if (laws.isNotEmpty)
            SimpleTable(headers: const ['법령명', '조항', '제목', '시행일'], flex: const [3, 1, 3, 1], rows: [
              for (final l in laws)
                [LinkText(txt(l['name']), () => st.goto('law', l['id'] as int)), Text(txt(l['article'])), Text(txt(l['title'])), Text(fmtDate(txt(l['effective_date'])))],
            ]),
        ],
        trailing: st.can('docs', 2)
            ? TextButton.icon(icon: const Icon(Icons.link, size: 18), label: const Text('법령 연결'), onPressed: () => _linkLaws(context))
            : null,
      ),
    ];
  }

  Future<void> _linkLaws(BuildContext context) async {
    try {
      final all = maps(await api.get('/laws'));
      if (!context.mounted) return;
      if (all.isEmpty) {
        showInfo(context, '등록된 법령이 없습니다. 먼저 법령 메뉴에서 등록하세요.');
        return;
      }
      final have = {for (final l in maps(doc['laws'])) l['id'] as int};
      final sel = await pickMany(context, '법령 연결',
          [for (final l in all) (l['id'] as int, '${l['name']} ${txt(l['article'])} ${txt(l['title'])}'.trim())], have);
      if (sel == null) return;
      await api.put('/documents/${doc['id']}/laws', {'lawIds': sel.toList()});
      st.notifyDataChanged();
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }
}

// ======================================================================= 편집

/// 문서 등록·수정. 저장하면 문서 id, 취소하면 null
Future<int?> showDocumentEditDialog(BuildContext context, Map<String, dynamic>? doc) async {
  List<Map<String, dynamic>> depts = [];
  List<Map<String, dynamic>> allDocs = [];
  try {
    depts = maps(await api.get('/departments'));
    allDocs = maps(await api.get('/documents'));
  } catch (e) {
    if (context.mounted) showError(context, e);
    return null;
  }
  if (!context.mounted) return null;
  return showDialog<int>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(width: 1180, height: 820, child: _DocEditor(doc: doc, depts: depts, allDocs: allDocs)),
    ),
  );
}

class _DocEditor extends StatefulWidget {
  const _DocEditor({required this.doc, required this.depts, required this.allDocs});
  final Map<String, dynamic>? doc;
  final List<Map<String, dynamic>> depts;
  final List<Map<String, dynamic>> allDocs;

  @override
  State<_DocEditor> createState() => _DocEditorState();
}

class _DocEditorState extends State<_DocEditor> {
  late String type;
  late final TextEditingController numCtl, code, title, purpose, scope, body, deptNote;
  late final Map<String, TextEditingController> res;
  late bool codeManual;
  int? deptId;
  late Map<String, dynamic> data;
  late List<int> related;
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    final d = widget.doc;
    data = Map<String, dynamic>.from(d?['data'] as Map? ?? {});
    type = d?['type'] as String? ?? (st.docTypes.isNotEmpty ? st.docTypes.first['key'] as String : 'P');
    numCtl = TextEditingController(text: d == null ? _nextNum(type) : '${d['num']}');
    code = TextEditingController(text: txt(d?['code']));
    title = TextEditingController(text: txt(d?['title']));
    codeManual = d?['codeManual'] == true;
    deptId = d?['departmentId'] as int?;
    purpose = TextEditingController(text: txt(data['purpose']));
    scope = TextEditingController(text: txt(data['scope']));
    body = TextEditingController(text: txt(data['body']));
    deptNote = TextEditingController(text: txt(data['deptNote']));
    final r = Map<String, dynamic>.from(data['resources'] as Map? ?? {});
    res = {for (final k in resKeys) k: TextEditingController(text: txt(r[k]))};
    related = [for (final x in (data['related'] as List? ?? const [])) (x as num).toInt()];
  }

  String _nextNum(String t) {
    final nums = widget.allDocs.where((d) => d['type'] == t).map((d) => (d['num'] as num).toInt());
    return '${nums.isEmpty ? 1 : nums.reduce((a, b) => a > b ? a : b) + 1}';
  }

  @override
  void dispose() {
    for (final c in [numCtl, code, title, purpose, scope, body, deptNote, ...res.values]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (title.text.trim().isEmpty) {
      setState(() => error = '문서명을 입력하세요.');
      return;
    }
    if (codeManual && code.text.trim().isEmpty) {
      setState(() => error = '문서번호를 직접 지정하려면 번호를 입력하세요.');
      return;
    }
    final out = {
      ...data,
      'purpose': purpose.text.trim(),
      'scope': scope.text.trim(),
      'body': body.text.trim(),
      'deptNote': deptNote.text.trim(),
      'resources': {for (final e in res.entries) e.key: e.value.text.trim()},
      'related': related,
    };
    final payload = {
      'type': type,
      'num': int.tryParse(numCtl.text.trim()) ?? 0,
      'code': code.text.trim(),
      'codeManual': codeManual,
      'title': title.text.trim(),
      'departmentId': deptId,
      'data': out,
      if (widget.doc != null) 'version': widget.doc!['version'],
    };
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final r = widget.doc == null
          ? await api.post('/documents', payload) as Map
          : await api.patch('/documents/${widget.doc!['id']}', payload) as Map;
      if (mounted) Navigator.pop(context, (r['id'] as num).toInt());
    } catch (e) {
      setState(() {
        saving = false;
        error = errorText(e);
      });
    }
  }

  Widget _pad(List<Widget> children) => SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );

  Widget _gap() => const SizedBox(height: 12);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final docLabel = {for (final d in widget.allDocs) d['id'] as int: '${d['code']}  ${d['title']}'};
    return DefaultTabController(
      length: 10,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Text(widget.doc == null ? '새 문서 등록' : '문서 수정 — ${widget.doc!['code']} ${widget.doc!['title']}',
              style: theme.textTheme.titleLarge),
        ),
        const TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
          Tab(text: '기본정보'), Tab(text: '프로세스 자원'), Tab(text: '주요업무절차'), Tab(text: '세부 절차 · 전결'),
          Tab(text: '본문'), Tab(text: '결재라인'), Tab(text: '요구사항'), Tab(text: '성과지표'), Tab(text: '관련 프로세스'), Tab(text: '개정이력'),
        ]),
        Expanded(
          child: TabBarView(children: [
            _pad([
              Row(children: [
                Expanded(
                  child: Dropdown<String>(
                    label: '구분',
                    value: type,
                    items: [for (final t in st.docTypes) (t['key'] as String, '${t['label']} (${t['prefix']})')],
                    onChanged: (v) => setState(() {
                      type = v ?? type;
                      if (widget.doc == null) numCtl.text = _nextNum(type);
                    }),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: TextField(controller: numCtl, decoration: const InputDecoration(labelText: '번호 (숫자)'))),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: code,
                    enabled: codeManual,
                    decoration: InputDecoration(
                      labelText: '문서번호',
                      helperText: codeManual ? '직접 지정 (번호 체계 일괄 적용에서 제외)' : '저장할 때 번호 체계에 따라 자동으로 붙습니다',
                    ),
                  ),
                ),
              ]),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: codeManual,
                onChanged: (v) => setState(() => codeManual = v ?? false),
                title: const Text('문서번호를 직접 지정'),
              ),
              TextField(controller: title, decoration: const InputDecoration(labelText: '문서명')),
              _gap(),
              Row(children: [
                Expanded(
                  child: Dropdown<int>(
                    label: '주관부서',
                    value: deptId,
                    items: [(null, '(미지정)'), for (final d in widget.depts) (d['id'] as int, '${d['name']}')],
                    onChanged: (v) => setState(() => deptId = v),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: TextField(controller: deptNote, decoration: const InputDecoration(labelText: '부서 비고 (예: 전부서, 협조부서)'))),
              ]),
              _gap(),
              TextField(controller: purpose, minLines: 3, maxLines: 8, decoration: const InputDecoration(labelText: '목적')),
              _gap(),
              TextField(controller: scope, minLines: 3, maxLines: 8, decoration: const InputDecoration(labelText: '적용범위')),
            ]),
            _pad([
              for (final k in resKeys) ...[
                TextField(controller: res[k], minLines: 1, maxLines: 4, decoration: InputDecoration(labelText: k == '인원의적격성' ? '인원의 적격성' : k)),
                _gap(),
              ],
            ]),
            _pad([
              ListEditor(
                columns: const [('v', '주요 업무절차 (개요, 순서대로)', 1)],
                initial: [for (final x in (data['mainSteps'] as List? ?? const [])) {'v': x}],
                onChanged: (v) => data['mainSteps'] = [for (final x in v) x['v']],
              ),
            ]),
            StepsEditor(initial: maps(data['steps']), onChanged: (v) => data['steps'] = v),
            Padding(
              padding: const EdgeInsets.all(20),
              child: TextField(
                controller: body,
                expands: true,
                maxLines: null,
                minLines: null,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(labelText: '본문 (지침의 용어 정의, 책임과 권한, 세부 기준 등)', alignLabelWithHint: true),
              ),
            ),
            _pad([
              ListEditor(
                hint: '문서 자체의 결재라인입니다. 예) 작성 - 담당, 검토 - 팀장, 승인 - 대표이사',
                columns: const [('stage', '단계 (작성/검토/승인)', 1), ('role', '직책 · 담당자', 2)],
                initial: maps(data['approvalLine']),
                onChanged: (v) => data['approvalLine'] = v,
              ),
            ]),
            _pad([
              ListEditor(
                columns: const [('cat', '구분 (ISO 9001 / 14001 / 45001 / 고객 / 법 / 규제)', 2), ('no', '조항', 1), ('name', '내용', 4)],
                initial: maps(data['requirements']),
                onChanged: (v) => data['requirements'] = v,
              ),
            ]),
            _pad([
              ListEditor(
                columns: const [('name', '지표', 2), ('formula', '산출식', 3), ('period', '주기', 1)],
                initial: maps(data['kpis']),
                onChanged: (v) => data['kpis'] = v,
              ),
            ]),
            _pad([
              Row(children: [
                Text('${related.length}개 연결됨'),
                const Spacer(),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.edit),
                  label: const Text('관련 프로세스 고르기'),
                  onPressed: () async {
                    final sel = await pickMany(context, '관련 프로세스',
                        [for (final d in widget.allDocs) if (d['id'] != widget.doc?['id']) (d['id'] as int, '${d['code']}  ${d['title']}')],
                        related.toSet());
                    if (sel != null) {
                      setState(() => related = [...related.where(sel.contains), ...sel.where((x) => !related.contains(x))]);
                    }
                  },
                ),
              ]),
              const SizedBox(height: 8),
              for (final id in related)
                ListTile(
                  dense: true,
                  title: Text(docLabel[id] ?? '(삭제된 문서)'),
                  trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => related.remove(id))),
                ),
            ]),
            _pad([
              ListEditor(
                columns: const [('rev', '개정번호', 1), ('date', '제·개정일자', 1), ('desc', '개정 사유 및 내용', 4)],
                initial: maps(data['revisions']),
                onChanged: (v) => data['revisions'] = v,
              ),
            ]),
          ]),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
          child: Row(children: [
            if (error != null) Expanded(child: Text(error!, style: TextStyle(color: theme.colorScheme.error))) else const Spacer(),
            TextButton(onPressed: saving ? null : () => Navigator.pop(context), child: const Text('취소')),
            const SizedBox(width: 8),
            FilledButton.icon(onPressed: saving ? null : _save, icon: const Icon(Icons.save), label: const Text('저장')),
          ]),
        ),
      ]),
    );
  }
}

/// 세부 업무절차 편집: 왼쪽 단계 목록, 오른쪽 단계 내용
class StepsEditor extends StatefulWidget {
  const StepsEditor({super.key, required this.initial, required this.onChanged});
  final List<Map<String, dynamic>> initial;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;

  @override
  State<StepsEditor> createState() => _StepsEditorState();
}

class _StepsEditorState extends State<StepsEditor> {
  late List<Map<String, dynamic>> steps;
  int idx = -1;
  final t = TextEditingController();
  final inputs = TextEditingController();
  final content = TextEditingController();
  final outputs = TextEditingController();
  final approver = TextEditingController();
  final note = TextEditingController();

  @override
  void initState() {
    super.initState();
    steps = [for (final s in widget.initial) Map<String, dynamic>.from(s)];
    if (steps.isNotEmpty) _load(0);
  }

  @override
  void dispose() {
    for (final c in [t, inputs, content, outputs, approver, note]) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> _lines(TextEditingController c) => [for (final l in c.text.split('\n')) if (l.trim().isNotEmpty) l.trim()];

  void _store() {
    if (idx < 0 || idx >= steps.length) return;
    steps[idx] = {
      'title': t.text.trim(),
      'inputs': _lines(inputs),
      'content': content.text.trim(),
      'outputs': _lines(outputs),
      'approver': approver.text.trim(),
      'note': note.text.trim(),
    };
    widget.onChanged(steps);
  }

  void _load(int i) {
    idx = i;
    final s = i >= 0 && i < steps.length ? steps[i] : <String, dynamic>{};
    t.text = txt(s['title']);
    inputs.text = (s['inputs'] as List? ?? const []).join('\n');
    content.text = txt(s['content']);
    outputs.text = (s['outputs'] as List? ?? const []).join('\n');
    approver.text = txt(s['approver']);
    note.text = txt(s['note']);
  }

  @override
  Widget build(BuildContext context) {
    final has = idx >= 0 && idx < steps.length;
    final roles = {...st.approvalRoles, '해당부서장', '발행부서장', '사장'};
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 300,
          child: Column(children: [
            Expanded(
              child: Card(
                child: ListView(children: [
                  for (final (i, s) in steps.indexed)
                    ListTile(
                      dense: true,
                      selected: i == idx,
                      title: Text('${i + 1}. ${txt(s['title']).isEmpty ? '(제목 없음)' : s['title']}'),
                      subtitle: txt(s['approver']).isEmpty ? null : Text('전결: ${s['approver']}'),
                      onTap: () => setState(() {
                        _store();
                        _load(i);
                      }),
                    ),
                ]),
              ),
            ),
            Row(children: [
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('단계 추가'),
                onPressed: () => setState(() {
                  _store();
                  steps.add({'title': '새 단계', 'inputs': [], 'content': '', 'outputs': [], 'approver': '', 'note': ''});
                  _load(steps.length - 1);
                  widget.onChanged(steps);
                }),
              ),
              const Spacer(),
              IconButton(
                tooltip: '위로',
                icon: const Icon(Icons.arrow_upward),
                onPressed: idx <= 0 ? null : () => setState(() {
                  _store();
                  final s = steps.removeAt(idx);
                  steps.insert(idx - 1, s);
                  idx -= 1;
                  widget.onChanged(steps);
                }),
              ),
              IconButton(
                tooltip: '아래로',
                icon: const Icon(Icons.arrow_downward),
                onPressed: !has || idx >= steps.length - 1 ? null : () => setState(() {
                  _store();
                  final s = steps.removeAt(idx);
                  steps.insert(idx + 1, s);
                  idx += 1;
                  widget.onChanged(steps);
                }),
              ),
              IconButton(
                tooltip: '삭제',
                icon: const Icon(Icons.delete_outline),
                onPressed: !has ? null : () => setState(() {
                  steps.removeAt(idx);
                  _load(steps.isEmpty ? -1 : (idx > 0 ? idx - 1 : 0));
                  widget.onChanged(steps);
                }),
              ),
            ]),
          ]),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: !has
              ? Center(child: muted(context, '왼쪽에서 단계를 고르거나 [단계 추가]를 누르세요.'))
              : SingleChildScrollView(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    TextField(controller: t, decoration: const InputDecoration(labelText: '단계명'), onChanged: (_) => setState(_store)),
                    const SizedBox(height: 10),
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                        child: TextField(controller: inputs, minLines: 3, maxLines: 6, onChanged: (_) => _store(),
                            decoration: const InputDecoration(labelText: '입력사항 (한 줄에 하나)', alignLabelWithHint: true)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(controller: outputs, minLines: 3, maxLines: 6, onChanged: (_) => _store(),
                            decoration: const InputDecoration(labelText: '출력사항 · 생성 서류 (한 줄에 하나)', alignLabelWithHint: true)),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    TextField(controller: content, minLines: 8, maxLines: 18, onChanged: (_) => _store(),
                        decoration: const InputDecoration(labelText: '업무 수행 내용', alignLabelWithHint: true)),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                        child: TextField(controller: approver, onChanged: (_) => setState(_store),
                            decoration: const InputDecoration(labelText: '전결권한 (결재권자)')),
                      ),
                      const SizedBox(width: 8),
                      PopupMenuButton<String>(
                        tooltip: '직책 고르기',
                        icon: const Icon(Icons.arrow_drop_down_circle_outlined),
                        onSelected: (v) => setState(() {
                          approver.text = v;
                          _store();
                        }),
                        itemBuilder: (_) => [for (final r in roles) PopupMenuItem(value: r, child: Text(r))],
                      ),
                    ]),
                    const SizedBox(height: 10),
                    TextField(controller: note, minLines: 2, maxLines: 8, onChanged: (_) => _store(),
                        decoration: const InputDecoration(labelText: '비고 · 표 (선택)', alignLabelWithHint: true)),
                  ]),
                ),
        ),
      ]),
    );
  }
}
