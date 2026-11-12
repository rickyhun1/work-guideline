import 'package:flutter/material.dart';

import '../common.dart';
import '../state.dart';
import '../widgets/editors.dart';
import '../widgets/export_dialog.dart';
import '../widgets/files_panel.dart';
import '../widgets/log_panel.dart';

const lawKinds = ['법률', '시행령', '시행규칙', '고시·훈령', '규격(ISO 등)', '사내규정', '기타'];

/// 법령: 직접 입력, 조문 내용까지 검색
class LawsPage extends StatefulWidget {
  const LawsPage({super.key});

  @override
  State<LawsPage> createState() => _LawsPageState();
}

class _LawsPageState extends State<LawsPage> {
  List<Map<String, dynamic>> laws = [];
  Map<String, dynamic>? law;
  int? selectedId;
  final checked = <int>{};
  final search = TextEditingController();
  String? kind;

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
    search.dispose();
    super.dispose();
  }

  void _nav() {
    final r = st.nav.value;
    if (r != null && r.kind == 'law') {
      search.clear();
      kind = null;
      _load().then((_) => _select(r.id));
    }
  }

  Future<void> _load() async {
    try {
      laws = maps(await api.get('/laws', query: {'q': search.text.trim(), 'kind': kind}));
      checked.retainAll(laws.map((l) => l['id'] as int));
      if (selectedId != null) await _select(selectedId!);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _select(int id) async {
    try {
      final l = Map<String, dynamic>.from(await api.get('/laws/$id') as Map);
      if (mounted) {
        setState(() {
          selectedId = id;
          law = l;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          selectedId = null;
          law = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final allChecked = laws.isNotEmpty && laws.every((l) => checked.contains(l['id']));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(children: [
          SizedBox(
            width: 380,
            child: TextField(
              controller: search,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: '법령명·조항·조문 내용 검색 (Enter)'),
              onSubmitted: (_) => _load(),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 180,
            child: Dropdown<String>(
              label: '구분',
              value: kind,
              items: [(null, '전체'), for (final k in lawKinds) (k, k)],
              onChanged: (v) {
                kind = v;
                _load();
              },
            ),
          ),
          const Spacer(),
          if (checked.isNotEmpty) ...[
            OutlinedButton.icon(
              icon: const Icon(Icons.table_view, size: 18),
              label: Text('선택 ${checked.length}건 엑셀'),
              onPressed: () => downloadTo(context, '/export/laws', '법령 목록.xlsx', query: {'ids': checked.join(',')}),
            ),
            const SizedBox(width: 6),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.archive_outlined, size: 18),
              label: const Text('첨부까지 zip'),
              onPressed: () => showExportDialog(context, lawIds: checked, defaultName: '법령'),
            ),
          ] else
            OutlinedButton.icon(
              icon: const Icon(Icons.table_view, size: 18),
              label: const Text('전체 엑셀'),
              onPressed: () => downloadTo(context, '/export/laws', '법령 목록.xlsx'),
            ),
          if (st.can('laws', 2)) ...[
            const SizedBox(width: 6),
            FilledButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('법령 등록'),
              onPressed: () async {
                final id = await showLawEditDialog(context, null);
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
          SizedBox(
            width: 460,
            child: Column(children: [
              Row(children: [
                Checkbox(
                  value: allChecked,
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      checked.addAll(laws.map((l) => l['id'] as int));
                    } else {
                      checked.clear();
                    }
                  }),
                ),
                Text('${laws.length}건'),
              ]),
              Expanded(
                child: laws.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: muted(context,
                              '등록된 법령이 없습니다.\n\n[법령 등록]으로 법령명·조항·조문 내용을 입력하세요.\n같은 법령의 여러 조항은 조항별로 따로 등록하면 검색과 문서 연결이 편합니다.'),
                        ),
                      )
                    : ListView(children: [
                        for (final l in laws)
                          ListTile(
                            dense: true,
                            selected: l['id'] == selectedId,
                            leading: Checkbox(
                              value: checked.contains(l['id']),
                              onChanged: (v) => setState(() => v == true ? checked.add(l['id'] as int) : checked.remove(l['id'])),
                            ),
                            title: Text('${l['name']} ${txt(l['article'])}'.trim()),
                            subtitle: Text([
                              if (txt(l['title']).isNotEmpty) txt(l['title']),
                              if (txt(l['kind']).isNotEmpty) txt(l['kind']),
                              if ((l['docCount'] as num? ?? 0) > 0) '문서 ${l['docCount']}개',
                            ].join(' · ')),
                            onTap: () => _select(l['id'] as int),
                          ),
                      ]),
              ),
            ]),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: law == null ? Center(child: muted(context, '법령을 고르세요.')) : _detail(context, law!)),
        ]),
      ),
    ]);
  }

  Widget _detail(BuildContext context, Map<String, dynamic> l) {
    final theme = Theme.of(context);
    final docs = maps(l['documents']);
    return DefaultTabController(
      length: 3,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${l['name']} ${txt(l['article'])}'.trim(), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                Text([
                  txt(l['kind']),
                  if (txt(l['effectiveDate']).isNotEmpty) '시행 ${fmtDate(txt(l['effectiveDate']))}',
                  '최종수정 ${fmtDateTime(txt(l['updatedAt']))} ${txt(l['updatedBy'])}',
                ].where((x) => x.isNotEmpty).join(' · '), style: theme.textTheme.bodySmall),
              ]),
            ),
            if (st.can('laws', 2))
              FilledButton.icon(
                icon: const Icon(Icons.edit, size: 18),
                label: const Text('수정'),
                onPressed: () async {
                  if (await showLawEditDialog(context, l) != null) st.notifyDataChanged();
                },
              ),
            if (st.can('laws', 3))
              IconButton(
                tooltip: '삭제',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  if (!await confirmDialog(context, '법령 삭제', '이 법령을 삭제할까요?', ok: '삭제', danger: true)) return;
                  try {
                    await api.delete('/laws/${l['id']}');
                    setState(() {
                      selectedId = null;
                      law = null;
                    });
                    st.notifyDataChanged();
                  } catch (e) {
                    if (context.mounted) showError(context, e);
                  }
                },
              ),
          ]),
        ),
        const TabBar(tabs: [Tab(text: '내용'), Tab(text: '첨부'), Tab(text: '변경이력')]),
        Expanded(
          child: TabBarView(children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (txt(l['title']).isNotEmpty) Section('조문 제목', [Text(txt(l['title']))]),
                Section('내용', [
                  txt(l['content']).isEmpty
                      ? muted(context, '(내용 미입력)')
                      : _highlight(context, txt(l['content']), search.text.trim()),
                ]),
                if (txt(l['url']).isNotEmpty) Section('원문 링크', [SelectableText(txt(l['url']))]),
                if (txt(l['memo']).isNotEmpty) Section('메모 (사내 적용사항 등)', [SelectableText(txt(l['memo']))]),
                Section('관련 문서', [
                  if (docs.isEmpty) muted(context, '(없음)'),
                  Wrap(spacing: 14, runSpacing: 6, children: [
                    for (final d in docs) LinkText('${d['code']} ${d['title']}', () => st.goto('document', d['id'] as int)),
                  ]),
                ]),
              ]),
            ),
            SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: FilesPanel(owner: 'law', ownerId: l['id'] as int, module: 'laws', title: '첨부 (법령 원문 PDF, 해설자료 등)'),
            ),
            SingleChildScrollView(padding: const EdgeInsets.all(20), child: LogPanel(entity: 'law', entityId: l['id'] as int)),
          ]),
        ),
      ]),
    );
  }

  /// 검색어를 노란색으로 표시
  Widget _highlight(BuildContext context, String text, String q) {
    if (q.isEmpty) return SelectableText(text, style: const TextStyle(height: 1.6));
    final spans = <TextSpan>[];
    final lower = text.toLowerCase();
    final ql = q.toLowerCase();
    var i = 0;
    while (true) {
      final j = lower.indexOf(ql, i);
      if (j < 0) {
        spans.add(TextSpan(text: text.substring(i)));
        break;
      }
      spans.add(TextSpan(text: text.substring(i, j)));
      spans.add(TextSpan(text: text.substring(j, j + q.length), style: const TextStyle(backgroundColor: Color(0xFFFFE58A))));
      i = j + q.length;
    }
    return SelectableText.rich(TextSpan(style: const TextStyle(height: 1.6), children: spans));
  }
}

/// 법령 등록·수정
Future<int?> showLawEditDialog(BuildContext context, Map<String, dynamic>? law) async {
  List<Map<String, dynamic>> docs;
  List<String> names;
  try {
    docs = maps(await api.get('/documents'));
    names = {for (final l in maps(await api.get('/laws'))) txt(l['name'])}.toList()..sort();
  } catch (e) {
    if (context.mounted) showError(context, e);
    return null;
  }
  if (!context.mounted) return null;
  final name = TextEditingController(text: txt(law?['name']));
  final article = TextEditingController(text: txt(law?['article']));
  final title = TextEditingController(text: txt(law?['title']));
  final content = TextEditingController(text: txt(law?['content']));
  final url = TextEditingController(text: txt(law?['url']));
  final memo = TextEditingController(text: txt(law?['memo']));
  String? kind = law?['kind'] as String? ?? '법률';
  String? eff = (law?['effectiveDate'] as String?);
  var docIds = {for (final d in maps(law?['documents'])) d['id'] as int};
  String? error;
  final docLabel = {for (final d in docs) d['id'] as int: '${d['code']} ${d['title']}'};
  final r = await showDialog<int>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
      Future<void> save() async {
        if (name.text.trim().isEmpty) return setLocal(() => error = '법령명을 입력하세요.');
        final body = {
          'name': name.text.trim(), 'kind': kind, 'article': article.text.trim(), 'title': title.text.trim(),
          'content': content.text.trim(), 'effectiveDate': eff, 'url': url.text.trim(), 'memo': memo.text.trim(),
          'documentIds': docIds.toList(),
          if (law != null) 'version': law['version'],
        };
        try {
          final res = law == null ? await api.post('/laws', body) as Map : await api.patch('/laws/${law['id']}', body) as Map;
          if (ctx.mounted) Navigator.pop(ctx, (res['id'] as num).toInt());
        } catch (e) {
          setLocal(() => error = errorText(e));
        }
      }

      return AlertDialog(
        title: Text(law == null ? '법령 등록' : '법령 수정'),
        content: SizedBox(
          width: 860,
          height: 640,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: name,
                    decoration: InputDecoration(
                      labelText: '법령명 (예: 산업안전보건법)',
                      suffixIcon: names.isEmpty
                          ? null
                          : PopupMenuButton<String>(
                              tooltip: '등록된 법령명에서 고르기',
                              icon: const Icon(Icons.arrow_drop_down),
                              onSelected: (v) => setLocal(() => name.text = v),
                              itemBuilder: (_) => [for (final n in names) PopupMenuItem(value: n, child: Text(n))],
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: Dropdown<String>(label: '구분', value: kind, items: [for (final k in lawKinds) (k, k)], onChanged: (v) => setLocal(() => kind = v)),
                ),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: TextField(controller: article, decoration: const InputDecoration(labelText: '조항 (예: 제38조, 제2조 제1항)'))),
                const SizedBox(width: 10),
                Expanded(flex: 2, child: TextField(controller: title, decoration: const InputDecoration(labelText: '조문 제목 (예: 안전조치)'))),
                const SizedBox(width: 10),
                Expanded(child: DateField(label: '시행일', value: eff, onChanged: (v) => setLocal(() => eff = v))),
              ]),
              const SizedBox(height: 10),
              TextField(
                controller: content,
                minLines: 10,
                maxLines: 20,
                decoration: const InputDecoration(labelText: '내용 (조문을 붙여넣으세요)', alignLabelWithHint: true),
              ),
              const SizedBox(height: 10),
              TextField(controller: url, decoration: const InputDecoration(labelText: '원문 링크 (예: 국가법령정보센터 주소)')),
              const SizedBox(height: 10),
              TextField(controller: memo, minLines: 2, maxLines: 6, decoration: const InputDecoration(labelText: '메모 (사내 적용 방법, 해당 업무, 점검 주기 등)')),
              const SizedBox(height: 10),
              Row(children: [
                Text('관련 문서 ${docIds.length}개', style: Theme.of(ctx).textTheme.titleSmall),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.link),
                  label: const Text('문서 고르기'),
                  onPressed: () async {
                    final sel = await pickMany(ctx, '관련 문서', [for (final d in docs) (d['id'] as int, '${d['code']}  ${d['title']}')], docIds);
                    if (sel != null) setLocal(() => docIds = sel);
                  },
                ),
              ]),
              Wrap(spacing: 6, runSpacing: 4, children: [
                for (final id in docIds) Chip(label: Text(docLabel[id] ?? '?'), onDeleted: () => setLocal(() => docIds.remove(id))),
              ]),
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
  for (final c in [name, article, title, content, url, memo]) {
    c.dispose();
  }
  return r;
}
