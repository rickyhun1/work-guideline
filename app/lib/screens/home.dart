import 'package:flutter/material.dart';

import '../common.dart';
import '../state.dart';
import 'dashboard.dart';
import 'documents.dart';
import 'forms.dart';
import 'laws.dart';
import 'logs.dart';
import 'projects.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _Dest {
  const _Dest(this.key, this.icon, this.selectedIcon, this.label, this.page);
  final String key;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final Widget page;
}

class _HomeScreenState extends State<HomeScreen> {
  int index = 0;
  late final List<_Dest> dests;
  final search = TextEditingController();

  @override
  void initState() {
    super.initState();
    dests = [
      const _Dest('home', Icons.dashboard_outlined, Icons.dashboard, '첫 화면', DashboardPage()),
      if (st.can('docs', 1)) const _Dest('document', Icons.description_outlined, Icons.description, '업무표준', DocumentsPage()),
      if (st.can('docs', 1)) const _Dest('form', Icons.assignment_outlined, Icons.assignment, '양식', FormsPage()),
      if (st.can('laws', 1)) const _Dest('law', Icons.balance_outlined, Icons.balance, '법령', LawsPage()),
      if (st.can('projects', 1)) const _Dest('project', Icons.flag_outlined, Icons.flag, '프로젝트', ProjectsPage()),
      if (st.can('logs', 1)) const _Dest('logs', Icons.history_outlined, Icons.history, '변경이력', LogsPage()),
      const _Dest('settings', Icons.settings_outlined, Icons.settings, '설정', SettingsPage()),
    ];
    st.nav.addListener(_nav);
  }

  @override
  void dispose() {
    st.nav.removeListener(_nav);
    search.dispose();
    super.dispose();
  }

  /// 다른 화면으로 이동 요청이 오면 해당 메뉴로 바꾼다 (선택은 각 화면이 처리)
  void _nav() {
    final r = st.nav.value;
    if (r == null) return;
    final i = dests.indexWhere((d) => d.key == r.kind);
    if (i >= 0 && i != index) setState(() => index = i);
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) return;
    List<Map<String, dynamic>> res;
    try {
      res = maps(await api.get('/search', query: {'q': q.trim()}));
    } catch (e) {
      if (mounted) showError(context, e);
      return;
    }
    if (!mounted) return;
    const kinds = {'document': '문서', 'form': '양식', 'law': '법령', 'project': '프로젝트'};
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("'${q.trim()}' 검색 결과 ${res.length}건"),
        content: SizedBox(
          width: 760,
          height: 520,
          child: res.isEmpty
              ? Center(child: muted(ctx, '찾은 결과가 없습니다.'))
              : ListView(children: [
                  for (final r in res)
                    ListTile(
                      dense: true,
                      leading: SizedBox(width: 64, child: Badge2(kinds[r['kind']] ?? '', Theme.of(ctx).colorScheme.primary)),
                      title: Text('${txt(r['code'])}  ${txt(r['title'])}'.trim()),
                      subtitle: txt(r['snippet']).isEmpty ? null : Text(txt(r['snippet']), maxLines: 2, overflow: TextOverflow.ellipsis),
                      onTap: () {
                        Navigator.pop(ctx);
                        st.goto(r['kind'] as String, (r['id'] as num).toInt());
                      },
                    ),
                ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('닫기'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = st.user;
    final theme = Theme.of(context);
    return Scaffold(
      body: Row(children: [
        NavigationRail(
          selectedIndex: index,
          onDestinationSelected: (i) => setState(() => index = i),
          labelType: NavigationRailLabelType.all,
          leading: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(children: [
              Icon(Icons.account_circle, size: 32, color: theme.colorScheme.primary),
              const SizedBox(height: 4),
              Text(txt(user['name']), style: theme.textTheme.labelLarge),
              Text(txt(user['department'] ?? (st.isAdmin ? '관리자' : '')), style: theme.textTheme.labelSmall),
            ]),
          ),
          destinations: [
            for (final d in dests) NavigationRailDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: Text(d.label)),
          ],
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: Column(children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              color: theme.colorScheme.surfaceContainerLow,
              child: Row(children: [
                Text(dests[index].label, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                SizedBox(
                  width: 420,
                  child: TextField(
                    controller: search,
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: '통합 검색: 문서 내용·양식·법령 조문·프로젝트 (Enter)'),
                    onSubmitted: _search,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(tooltip: '새로고침', icon: const Icon(Icons.refresh), onPressed: st.notifyDataChanged),
              ]),
            ),
            const Divider(height: 1),
            Expanded(child: IndexedStack(index: index, children: [for (final d in dests) d.page])),
          ]),
        ),
      ]),
    );
  }
}
