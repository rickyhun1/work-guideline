import 'package:flutter/material.dart';

import '../common.dart';
import '../state.dart';
import '../widgets/editors.dart';
import '../widgets/export_dialog.dart';
import '../widgets/files_panel.dart';
import '../widgets/log_panel.dart';

const projectStatus = ['준비', '진행중', '완료', '보류'];
const itemStatus = ['미착수', '작성중', '검토중', '완료', '해당없음'];
const projectCategories = ['지원사업 신청', '인증심사(외부)', '내부심사', '고객 감사', '법정 신고·보고', '기타'];

/// 프로젝트: 지원사업 신청 등 건별로 부서·필요서류·기한 공유
class ProjectsPage extends StatefulWidget {
  const ProjectsPage({super.key});

  @override
  State<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends State<ProjectsPage> {
  List<Map<String, dynamic>> projects = [];
  Map<String, dynamic>? project;
  int? selectedId;
  int? itemId;
  final checked = <int>{};
  bool showDone = false;

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
    if (r != null && r.kind == 'project') {
      setState(() => showDone = true);
      _select(r.id);
    }
  }

  Future<void> _load() async {
    try {
      projects = maps(await api.get('/projects'));
      checked.retainAll(projects.map((p) => p['id'] as int));
      if (selectedId != null) await _select(selectedId!);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _select(int id) async {
    try {
      final p = Map<String, dynamic>.from(await api.get('/projects/$id') as Map);
      if (!mounted) return;
      setState(() {
        if (selectedId != id) itemId = null;
        selectedId = id;
        project = p;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          selectedId = null;
          project = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = projects.where((p) => showDone || p['status'] != '완료').toList();
    return Row(children: [
      SizedBox(
        width: 400,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(children: [
              FilterChip(label: const Text('완료 포함'), selected: showDone, onSelected: (v) => setState(() => showDone = v)),
              const Spacer(),
              if (checked.isNotEmpty)
                IconButton(
                  tooltip: '선택 프로젝트 zip',
                  icon: const Icon(Icons.archive_outlined),
                  onPressed: () => showExportDialog(context, projectIds: checked, defaultName: '프로젝트'),
                ),
              if (st.can('projects', 2))
                FilledButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('새 프로젝트'),
                  onPressed: () async {
                    final id = await showProjectEditDialog(context, null);
                    if (id != null) {
                      selectedId = id;
                      st.notifyDataChanged();
                    }
                  },
                ),
            ]),
          ),
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: muted(context, "프로젝트가 없습니다.\n\n예: '2027 스마트공장 지원사업 신청'을 만들고\n부서별 필요서류와 기한을 항목으로 등록하세요."),
                    ),
                  )
                : ListView(children: [
                    for (final p in list)
                      ListTile(
                        selected: p['id'] == selectedId,
                        leading: Checkbox(
                          value: checked.contains(p['id']),
                          onChanged: (v) => setState(() => v == true ? checked.add(p['id'] as int) : checked.remove(p['id'])),
                        ),
                        title: Text(txt(p['name'])),
                        subtitle: Row(children: [
                          Badge2(txt(p['status']), p['status'] == '완료' ? const Color(0xFF2E7D32) : theme.colorScheme.primary),
                          const SizedBox(width: 6),
                          Text('${p['doneCount']}/${p['itemCount']} 완료'),
                          const Spacer(),
                          if (txt(p['dueDate']).isNotEmpty && p['status'] != '완료')
                            Text('${fmtDate(txt(p['dueDate']))} ${dday(txt(p['dueDate']))}',
                                style: TextStyle(color: dueColor(txt(p['dueDate']), null))),
                        ]),
                        onTap: () => _select(p['id'] as int),
                      ),
                  ]),
          ),
        ]),
      ),
      const VerticalDivider(width: 1),
      Expanded(child: project == null ? Center(child: muted(context, '프로젝트를 고르세요.')) : _detail(context, project!)),
    ]);
  }

  Widget _detail(BuildContext context, Map<String, dynamic> p) {
    final theme = Theme.of(context);
    final items = maps(p['items']);
    final done = items.where((i) => i['status'] == '완료' || i['status'] == '해당없음').length;
    final item = items.where((i) => i['id'] == itemId).firstOrNull;
    final canEdit = st.can('projects', 2);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(txt(p['name']), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text([
                txt(p['category']),
                '상태 ${p['status']}',
                if (txt(p['owner']).isNotEmpty) '총괄 ${p['owner']}',
                '기간 ${fmtDate(txt(p['startDate']))} ~ ${fmtDate(txt(p['dueDate']))} ${dday(txt(p['dueDate']))}',
                '진행 $done/${items.length}',
              ].where((x) => x.isNotEmpty).join(' · ')),
              if (txt(p['departmentNames']).isNotEmpty) Text('참여부서: ${p['departmentNames']}', style: theme.textTheme.bodySmall),
              if (txt(p['description']).isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(txt(p['description']))),
            ]),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.table_view, size: 18),
            label: const Text('체크리스트 엑셀'),
            onPressed: () => downloadTo(context, '/export/projects/${p['id']}', '${p['name']}.xlsx'),
          ),
          const SizedBox(width: 6),
          OutlinedButton.icon(
            icon: const Icon(Icons.archive_outlined, size: 18),
            label: const Text('제출서류 zip'),
            onPressed: () => showExportDialog(context, projectIds: {p['id'] as int}, defaultName: txt(p['name'])),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              try {
                if (v == 'edit') {
                  if (await showProjectEditDialog(context, p) != null) st.notifyDataChanged();
                } else if (v == 'copy') {
                  final r = await api.post('/projects/${p['id']}/copy') as Map;
                  selectedId = (r['id'] as num).toInt();
                  st.notifyDataChanged();
                  if (context.mounted) showInfo(context, '복제했습니다. 이름과 기한을 고치세요.');
                } else if (v == 'delete') {
                  if (!context.mounted || !await confirmDialog(context, '프로젝트 삭제', '이 프로젝트를 삭제할까요?', ok: '삭제', danger: true)) return;
                  await api.delete('/projects/${p['id']}');
                  setState(() {
                    selectedId = null;
                    project = null;
                  });
                  st.notifyDataChanged();
                }
              } catch (e) {
                if (context.mounted) showError(context, e);
              }
            },
            itemBuilder: (_) => [
              if (canEdit) const PopupMenuItem(value: 'edit', child: Text('프로젝트 수정')),
              if (canEdit) const PopupMenuItem(value: 'copy', child: Text('복제 (같은 형태로 새로 시작)')),
              if (st.can('projects', 3)) const PopupMenuItem(value: 'delete', child: Text('삭제')),
            ],
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(children: [
          Text('필요 서류 · 업무 항목', style: theme.textTheme.titleSmall),
          const Spacer(),
          if (canEdit)
            TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('항목 추가'),
              onPressed: () async {
                if (await showItemEditDialog(context, p, null) != null) st.notifyDataChanged();
              },
            ),
        ]),
      ),
      Expanded(
        flex: 3,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: items.isEmpty
              ? muted(context, '항목이 없습니다. [항목 추가]로 부서별 필요서류와 기한을 등록하세요.')
              : SimpleTable(
                  headers: const ['항목(서류·업무)', '담당부서', '담당자', '기한', '상태', '연결 양식', '첨부', ''],
                  flex: const [4, 2, 2, 2, 2, 3, 1, 2],
                  rows: [
                    for (final i in items)
                      [
                        InkWell(
                          onTap: () => setState(() => itemId = i['id'] as int),
                          child: Text(txt(i['title']),
                              style: TextStyle(fontWeight: i['id'] == itemId ? FontWeight.bold : null,
                                  color: i['id'] == itemId ? theme.colorScheme.primary : null)),
                        ),
                        Text(txt(i['department'])),
                        Text(txt(i['assignee'])),
                        Text(txt(i['dueDate']).isEmpty ? '' : '${fmtDate(txt(i['dueDate']))}\n${i['status'] == '완료' || i['status'] == '해당없음' ? '' : dday(txt(i['dueDate']))}',
                            style: TextStyle(color: dueColor(txt(i['dueDate']), txt(i['status'])))),
                        Badge2(txt(i['status']), dueColor(txt(i['dueDate']), txt(i['status']))),
                        i['formId'] == null
                            ? const SizedBox.shrink()
                            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                LinkText('${i['formCode']} ${i['formName']}', () => st.goto('form', i['formId'] as int)),
                                if (i['formFileId'] != null)
                                  TextButton(
                                    onPressed: () => downloadTo(context, '/export/forms/${i['formId']}', '${i['formCode']} ${i['formName']}.xlsx'),
                                    child: const Text('양식 받기'),
                                  ),
                              ]),
                        Text((i['fileCount'] as num? ?? 0) > 0 ? '${i['fileCount']}개' : ''),
                        Wrap(children: [
                          IconButton(
                            tooltip: '첨부 보기',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.attach_file, size: 18),
                            onPressed: () => setState(() => itemId = i['id'] as int),
                          ),
                          if (canEdit)
                            IconButton(
                              tooltip: '수정',
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.edit, size: 18),
                              onPressed: () async {
                                if (await showItemEditDialog(context, p, i) != null) st.notifyDataChanged();
                              },
                            ),
                          if (st.can('projects', 3))
                            IconButton(
                              tooltip: '삭제',
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.delete_outline, size: 18),
                              onPressed: () async {
                                if (!await confirmDialog(context, '항목 삭제', "'${i['title']}' 항목을 삭제할까요?", ok: '삭제', danger: true)) return;
                                try {
                                  await api.delete('/items/${i['id']}');
                                  st.notifyDataChanged();
                                } catch (e) {
                                  if (context.mounted) showError(context, e);
                                }
                              },
                            ),
                        ]),
                      ],
                  ],
                ),
        ),
      ),
      const Divider(height: 1),
      Expanded(
        flex: 2,
        child: DefaultTabController(
          length: 3,
          child: Column(children: [
            TabBar(tabs: [
              Tab(text: item == null ? '항목 첨부 (항목을 고르세요)' : '항목 첨부: ${item['title']}'),
              const Tab(text: '공통 자료 (공고문 등)'),
              const Tab(text: '변경이력'),
            ]),
            Expanded(
              child: TabBarView(children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: FilesPanel(owner: 'item', ownerId: item?['id'] as int?, module: 'projects',
                      title: '제출서류 · 작성 완료본', onChanged: st.notifyDataChanged),
                ),
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: FilesPanel(owner: 'project', ownerId: p['id'] as int, module: 'projects', title: '공통 자료'),
                ),
                SingleChildScrollView(padding: const EdgeInsets.all(16), child: LogPanel(projectId: p['id'] as int)),
              ]),
            ),
          ]),
        ),
      ),
    ]);
  }
}

Future<int?> showProjectEditDialog(BuildContext context, Map<String, dynamic>? p) async {
  List<Map<String, dynamic>> depts;
  try {
    depts = maps(await api.get('/departments'));
  } catch (e) {
    if (context.mounted) showError(context, e);
    return null;
  }
  if (!context.mounted) return null;
  final name = TextEditingController(text: txt(p?['name']));
  final category = TextEditingController(text: txt(p?['category'] ?? projectCategories.first));
  final owner = TextEditingController(text: txt(p?['owner'] ?? (p == null ? st.user['name'] : '')));
  final desc = TextEditingController(text: txt(p?['description']));
  String? start = p == null ? todayStr() : p['startDate'] as String?;
  String? due = p?['dueDate'] as String?;
  var status = txt(p?['status'] ?? '준비');
  var deptIds = {for (final d in (p?['departments'] as List? ?? const [])) (d as num).toInt()};
  String? error;
  final r = await showDialog<int>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
      Future<void> save() async {
        if (name.text.trim().isEmpty) return setLocal(() => error = '프로젝트명을 입력하세요.');
        final body = {
          'name': name.text.trim(), 'category': category.text.trim(), 'owner': owner.text.trim(), 'description': desc.text.trim(),
          'startDate': start, 'dueDate': due, 'status': status, 'departments': deptIds.toList(),
          if (p != null) 'version': p['version'],
        };
        try {
          final res = p == null ? await api.post('/projects', body) as Map : await api.patch('/projects/${p['id']}', body) as Map;
          if (ctx.mounted) Navigator.pop(ctx, (res['id'] as num).toInt());
        } catch (e) {
          setLocal(() => error = errorText(e));
        }
      }

      return AlertDialog(
        title: Text(p == null ? '새 프로젝트' : '프로젝트 수정'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: '프로젝트명', hintText: '예: 2027 스마트공장 구축 지원사업 신청')),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: category,
                    decoration: InputDecoration(
                      labelText: '분류',
                      suffixIcon: PopupMenuButton<String>(
                        icon: const Icon(Icons.arrow_drop_down),
                        onSelected: (v) => setLocal(() => category.text = v),
                        itemBuilder: (_) => [for (final c in projectCategories) PopupMenuItem(value: c, child: Text(c))],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: owner, decoration: const InputDecoration(labelText: '총괄 담당'))),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: DateField(label: '시작일', value: start, onChanged: (v) => setLocal(() => start = v))),
                const SizedBox(width: 10),
                Expanded(child: DateField(label: '마감일', value: due, onChanged: (v) => setLocal(() => due = v))),
                const SizedBox(width: 10),
                Expanded(
                  child: Dropdown<String>(label: '상태', value: status, items: [for (final x in projectStatus) (x, x)],
                      onChanged: (v) => setLocal(() => status = v ?? status)),
                ),
              ]),
              const SizedBox(height: 10),
              TextField(controller: desc, minLines: 2, maxLines: 6, decoration: const InputDecoration(labelText: '설명 (공고 요약, 제출처, 유의사항 등)')),
              const SizedBox(height: 10),
              Text('참여부서', style: Theme.of(ctx).textTheme.titleSmall),
              Wrap(spacing: 6, runSpacing: 4, children: [
                for (final d in depts)
                  FilterChip(
                    label: Text(txt(d['name'])),
                    selected: deptIds.contains(d['id']),
                    onSelected: (v) => setLocal(() => v ? deptIds.add(d['id'] as int) : deptIds.remove(d['id'])),
                  ),
              ]),
              if (depts.length <= 1) muted(ctx, '부서는 [설정 → 부서]에서 추가할 수 있습니다.'),
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
  for (final c in [name, category, owner, desc]) {
    c.dispose();
  }
  return r;
}

Future<int?> showItemEditDialog(BuildContext context, Map<String, dynamic> project, Map<String, dynamic>? item) async {
  List<Map<String, dynamic>> depts;
  List<Map<String, dynamic>> forms;
  List<Map<String, dynamic>> docs;
  try {
    depts = maps(await api.get('/departments'));
    forms = maps(await api.get('/forms'));
    docs = maps(await api.get('/documents'));
  } catch (e) {
    if (context.mounted) showError(context, e);
    return null;
  }
  if (!context.mounted) return null;
  final projDepts = {for (final d in (project['departments'] as List? ?? const [])) (d as num).toInt()};
  final title = TextEditingController(text: txt(item?['title']));
  final assignee = TextEditingController(text: txt(item?['assignee']));
  final note = TextEditingController(text: txt(item?['note']));
  final sort = TextEditingController(text: '${item?['sortOrder'] ?? 0}');
  int? deptId = item?['departmentId'] as int?;
  int? formId = item?['formId'] as int?;
  int? docId = item?['documentId'] as int?;
  String? due = item?['dueDate'] as String?;
  var status = txt(item?['status'] ?? '미착수');
  String? error;
  final formLabel = {for (final f in forms) f['id'] as int: '${f['code']}  ${f['name']}'};
  final docLabel = {for (final d in docs) d['id'] as int: '${d['code']}  ${d['title']}'};
  final r = await showDialog<int>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
      Future<void> save() async {
        if (title.text.trim().isEmpty) return setLocal(() => error = '항목명을 입력하세요.');
        final body = {
          'title': title.text.trim(), 'departmentId': deptId, 'assignee': assignee.text.trim(), 'dueDate': due, 'status': status,
          'formId': formId, 'documentId': docId, 'note': note.text.trim(), 'sortOrder': int.tryParse(sort.text.trim()) ?? 0,
          if (item != null) 'version': item['version'],
        };
        try {
          final res = item == null
              ? await api.post('/projects/${project['id']}/items', body) as Map
              : await api.patch('/items/${item['id']}', body) as Map;
          if (ctx.mounted) Navigator.pop(ctx, (res['id'] as num).toInt());
        } catch (e) {
          setLocal(() => error = errorText(e));
        }
      }

      Widget picker(String label, String? text, Future<void> Function() onTap) => InkWell(
            onTap: onTap,
            child: InputDecorator(
              decoration: InputDecoration(labelText: label, suffixIcon: const Icon(Icons.arrow_drop_down)),
              child: Text(text ?? '(없음)'),
            ),
          );

      return AlertDialog(
        title: Text(item == null ? '항목 추가' : '항목 수정'),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(controller: title, decoration: const InputDecoration(labelText: '항목 (서류·업무)', hintText: '예: 사업계획서, 재무제표(최근 3년)')),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: Dropdown<int>(
                    label: '담당부서',
                    value: deptId,
                    items: [(null, '(미지정)'), for (final d in depts) (d['id'] as int, '${d['name']}${projDepts.contains(d['id']) ? ' ★' : ''}')],
                    onChanged: (v) => setLocal(() => deptId = v),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: assignee, decoration: const InputDecoration(labelText: '담당자'))),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: DateField(label: '기한', value: due, onChanged: (v) => setLocal(() => due = v))),
                const SizedBox(width: 10),
                Expanded(
                  child: Dropdown<String>(label: '상태', value: status, items: [for (final x in itemStatus) (x, x)],
                      onChanged: (v) => setLocal(() => status = v ?? status)),
                ),
                const SizedBox(width: 10),
                SizedBox(width: 100, child: TextField(controller: sort, decoration: const InputDecoration(labelText: '정렬 순서'))),
              ]),
              const SizedBox(height: 10),
              picker('연결 양식 (작성할 양식)', formId == null ? null : formLabel[formId], () async {
                final v = await pickOne(ctx, '연결 양식', [for (final e in formLabel.entries) (e.key, e.value)], current: formId);
                if (v != null) setLocal(() => formId = v < 0 ? null : v);
              }),
              const SizedBox(height: 10),
              picker('관련 문서 (업무 절차)', docId == null ? null : docLabel[docId], () async {
                final v = await pickOne(ctx, '관련 문서', [for (final e in docLabel.entries) (e.key, e.value)], current: docId);
                if (v != null) setLocal(() => docId = v < 0 ? null : v);
              }),
              const SizedBox(height: 10),
              TextField(controller: note, minLines: 2, maxLines: 5, decoration: const InputDecoration(labelText: '비고')),
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
  for (final c in [title, assignee, note, sort]) {
    c.dispose();
  }
  return r;
}
