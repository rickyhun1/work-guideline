import 'package:flutter/material.dart';

import '../common.dart';
import '../state.dart';
import '../widgets/log_panel.dart';

/// 첫 화면: 건수, 기한 임박·지난 항목, 최근 변경
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  Map<String, dynamic>? data;

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

  Future<void> _load() async {
    try {
      final d = Map<String, dynamic>.from(await api.get('/dashboard') as Map);
      if (mounted) setState(() => data = d);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = data;
    if (d == null) return const Center(child: CircularProgressIndicator());
    final c = Map<String, dynamic>.from(d['counts'] as Map);
    final upcoming = maps(d['upcoming']);
    final recent = maps(d['recent']);
    Widget stat(String label, dynamic n, IconData icon) => Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Icon(icon, size: 30, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: theme.textTheme.bodySmall),
                  Text('$n', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                ]),
              ]),
            ),
          ),
        );
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('${st.user['name'] ?? ''}님, 안녕하세요.', style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        muted(context, '오늘 ${fmtDate(txt(d['today']))}'),
        const SizedBox(height: 16),
        Row(children: [
          stat('업무표준 문서', c['documents'], Icons.description_outlined),
          stat('양식', c['forms'], Icons.assignment_outlined),
          stat('법령', c['laws'], Icons.balance_outlined),
          stat('진행 중 프로젝트', c['projects'], Icons.flag_outlined),
        ]),
        const SizedBox(height: 20),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Section('기한이 다가오거나 지난 항목 (2주 이내)', [
              if (upcoming.isEmpty) muted(context, '없습니다.'),
              for (final u in upcoming)
                ListTile(
                  dense: true,
                  leading: SizedBox(
                    width: 64,
                    child: Text(dday(txt(u['dueDate'])),
                        style: TextStyle(fontWeight: FontWeight.bold, color: dueColor(txt(u['dueDate']), txt(u['status'])))),
                  ),
                  title: Text(txt(u['title'])),
                  subtitle: Text([txt(u['project']), txt(u['department']), txt(u['assignee']), txt(u['status'])]
                      .where((x) => x.isNotEmpty).join(' · ')),
                  trailing: Text(fmtDate(txt(u['dueDate']))),
                  onTap: () => st.goto('project', u['projectId'] as int),
                ),
            ]),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Section('최근 변경', [
              if (recent.isEmpty) muted(context, '변경이력 조회 권한이 없거나 기록이 없습니다.'),
              for (final l in recent)
                ListTile(
                  dense: true,
                  leading: SizedBox(width: 72, child: Badge2(txt(l['action']), actionColorOf(txt(l['action'])))),
                  title: Text(txt(l['label']), overflow: TextOverflow.ellipsis),
                  subtitle: Text('${fmtDateTime(txt(l['at']))} · ${txt(l['userName'])}'),
                  onTap: () => showLogDetail(context, l),
                ),
            ]),
          ),
        ]),
      ]),
    );
  }
}
