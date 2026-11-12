import 'package:flutter/material.dart';

import '../common.dart';
import '../state.dart';
import '../widgets/editors.dart';
import '../widgets/log_panel.dart';

/// 전체 변경이력
class LogsPage extends StatefulWidget {
  const LogsPage({super.key});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  List<Map<String, dynamic>> logs = [];
  final q = TextEditingController();
  String? entity;

  @override
  void initState() {
    super.initState();
    _load();
    st.dataVersion.addListener(_load);
  }

  @override
  void dispose() {
    st.dataVersion.removeListener(_load);
    q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      logs = maps(await api.get('/logs', query: {'q': q.text.trim(), 'entity': entity, 'limit': '1000'}));
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  void _open(Map<String, dynamic> l) {
    final id = l['entityId'] as int?;
    final e = l['entity'] as String?;
    if (l['projectId'] != null) {
      st.goto('project', l['projectId'] as int);
    } else if (id != null && const {'document', 'form', 'law', 'project'}.contains(e)) {
      st.goto(e!, id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(children: [
          SizedBox(
            width: 380,
            child: TextField(
              controller: q,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: '대상·사용자·내용 검색 (Enter)'),
              onSubmitted: (_) => _load(),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 200,
            child: Dropdown<String>(
              label: '대상',
              value: entity,
              items: [(null, '전체'), for (final e in entityLabels.entries) (e.key, e.value)],
              onChanged: (v) {
                entity = v;
                _load();
              },
            ),
          ),
          const SizedBox(width: 10),
          IconButton(tooltip: '새로고침', icon: const Icon(Icons.refresh), onPressed: _load),
          const Spacer(),
          muted(context, '최근 ${logs.length}건 · 누르면 변경 전/후를 봅니다'),
        ]),
      ),
      Expanded(
        child: ListView.separated(
          itemCount: logs.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (ctx, i) {
            final l = logs[i];
            return ListTile(
              dense: true,
              leading: SizedBox(width: 72, child: Badge2(txt(l['action']), actionColorOf(txt(l['action'])))),
              title: Text('[${entityLabels[l['entity']] ?? l['entity']}] ${txt(l['label'])}'),
              subtitle: Text('${fmtDateTime(txt(l['at']))} · ${txt(l['userName'])}'),
              trailing: IconButton(tooltip: '해당 화면으로', icon: const Icon(Icons.open_in_new, size: 18), onPressed: () => _open(l)),
              onTap: () => showLogDetail(context, l),
            );
          },
        ),
      ),
    ]);
  }
}
