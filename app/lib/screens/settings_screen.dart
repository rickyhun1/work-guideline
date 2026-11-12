import 'dart:io';

import 'package:flutter/material.dart';

import '../common.dart';
import '../local_server.dart';
import '../settings.dart';
import '../state.dart';
import '../widgets/editors.dart';
import 'startup.dart';

/// 서버 연결 설정 (이 PC에서 실행 / 회사 서버에 접속)
Future<bool> showServerSettingsDialog(BuildContext context) async {
  final s = AppState.I.settings;
  var mode = s.mode;
  final url = TextEditingController(text: s.remoteUrl);
  final port = TextEditingController(text: '${s.localPort}');

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: const Text('서버 연결 설정'),
        content: SizedBox(
          width: 480,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'local', label: Text('이 PC에서 실행'), icon: Icon(Icons.computer)),
                ButtonSegment(value: 'remote', label: Text('서버에 접속'), icon: Icon(Icons.dns_outlined)),
              ],
              selected: {mode},
              onSelectionChanged: (v) => setLocal(() => mode = v.first),
            ),
            const SizedBox(height: 16),
            if (mode == 'local') ...[
              const Text('프로그램과 함께 들어 있는 서버를 이 PC에서 실행합니다. 데이터는 이 PC에 저장됩니다.'),
              const SizedBox(height: 12),
              TextField(controller: port, decoration: const InputDecoration(labelText: '포트 (보통 바꿀 필요 없음)')),
            ] else ...[
              const Text('회사 서버 컴퓨터에서 실행 중인 업무표준 관리 서버에 접속합니다.'),
              const SizedBox(height: 12),
              TextField(controller: url, decoration: const InputDecoration(labelText: '서버 주소', hintText: 'http://192.168.0.10:3100')),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('저장')),
        ],
      ),
    ),
  );
  if (ok != true) return false;
  final newPort = int.tryParse(port.text.trim()) ?? s.localPort;
  final changed = mode != s.mode || url.text.trim() != s.remoteUrl || newPort != s.localPort;
  if (changed && s.mode == 'local') await LocalServer.shutdown(s);
  s.mode = mode;
  s.remoteUrl = url.text.trim();
  s.localPort = newPort;
  await s.save();
  return changed;
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final admin = st.isAdmin;
    final tabs = <(String, Widget)>[
      ('내 계정 · 연결', const _AccountTab()),
      if (admin) ('번호 체계', const _NumberingTab()),
      if (admin) ('부서', const _DepartmentsTab()),
      if (admin) ('사용자', const _UsersTab()),
      if (admin) ('권한', const _PermissionsTab()),
      if (admin) ('회사 정보', const _CompanyTab()),
    ];
    return DefaultTabController(
      length: tabs.length,
      child: Column(children: [
        TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [for (final t in tabs) Tab(text: t.$1)]),
        Expanded(child: TabBarView(children: [for (final t in tabs) t.$2])),
      ]),
    );
  }
}

Widget _page(List<Widget> children) => SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      ),
    );

// ------------------------------------------------------------------ 내 계정 · 연결
class _AccountTab extends StatefulWidget {
  const _AccountTab();

  @override
  State<_AccountTab> createState() => _AccountTabState();
}

class _AccountTabState extends State<_AccountTab> {
  String? serverVersion;

  @override
  void initState() {
    super.initState();
    LocalServer.health(st.settings.baseUrl).then((h) {
      if (mounted) setState(() => serverVersion = h?['version'] as String?);
    });
  }

  Future<void> _changePassword() async {
    final cur = TextEditingController();
    final p1 = TextEditingController();
    final p2 = TextEditingController();
    String? err;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) => AlertDialog(
        title: const Text('비밀번호 변경'),
        content: SizedBox(
          width: 400,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: cur, obscureText: true, decoration: const InputDecoration(labelText: '현재 비밀번호')),
            const SizedBox(height: 10),
            TextField(controller: p1, obscureText: true, decoration: const InputDecoration(labelText: '새 비밀번호 (4자 이상)')),
            const SizedBox(height: 10),
            TextField(controller: p2, obscureText: true, decoration: const InputDecoration(labelText: '새 비밀번호 확인')),
            if (err != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(err!, style: TextStyle(color: Theme.of(ctx).colorScheme.error))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          FilledButton(
            onPressed: () async {
              if (p1.text.length < 4) return setLocal(() => err = '4자 이상 입력하세요.');
              if (p1.text != p2.text) return setLocal(() => err = '새 비밀번호 확인이 일치하지 않습니다.');
              try {
                await api.post('/me/password', {'current': cur.text, 'next': p1.text});
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) showInfo(context, '비밀번호를 바꿨습니다.');
              } catch (e) {
                setLocal(() => err = errorText(e));
              }
            },
            child: const Text('변경'),
          ),
        ],
      )),
    );
  }

  void _logout() {
    api.token = null;
    st.me = {};
    Navigator.of(context, rootNavigator: true)
        .pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const StartupScreen()), (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final u = st.user;
    final s = st.settings;
    final levels = [for (final l in (st.me['levels'] as List? ?? const [])) '$l'];
    return _page([
      Section('내 계정', [
        Text('${u['name']} (${u['empNo']}) · ${u['department'] ?? '부서 없음'}${st.isAdmin ? ' · 관리자' : ''}'),
        const SizedBox(height: 8),
        Wrap(spacing: 12, children: [
          for (final m in maps(st.me['modules']))
            Chip(label: Text('${m['label']}: ${levels.isEmpty ? st.level(m['key'] as String) : levels[st.level(m['key'] as String)]}')),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          OutlinedButton.icon(icon: const Icon(Icons.password), label: const Text('비밀번호 변경'), onPressed: _changePassword),
          const SizedBox(width: 8),
          OutlinedButton.icon(icon: const Icon(Icons.logout), label: const Text('로그아웃'), onPressed: _logout),
        ]),
      ]),
      Section('연결', [
        Text(s.mode == 'local' ? '이 PC에서 실행 중인 서버 (포트 ${s.localPort})' : '서버: ${s.baseUrl}'),
        Text('프로그램 $appVersion · 서버 ${serverVersion ?? '-'}'),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.settings_ethernet),
            label: const Text('연결 설정'),
            onPressed: () async {
              if (await showServerSettingsDialog(context)) {
                if (!context.mounted) return;
                showInfo(context, '변경한 설정으로 다시 연결합니다.');
                _logout();
              }
            },
          ),
        ),
      ]),
      if (s.mode == 'local')
        Section('데이터', [
          SelectableText('데이터 저장 위치: ${serverDataDir()}'),
          const SizedBox(height: 4),
          muted(context, '이 폴더를 통째로 복사해 두면 백업이 됩니다. (프로그램을 닫은 상태에서 복사하세요)'),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.folder_open),
              label: const Text('폴더 열기'),
              onPressed: () {
                if (Platform.isWindows) Process.run('explorer', [serverDataDir()]);
              },
            ),
          ),
        ]),
    ]);
  }
}

// ------------------------------------------------------------------ 번호 체계
class _NumberingTab extends StatefulWidget {
  const _NumberingTab();

  @override
  State<_NumberingTab> createState() => _NumberingTabState();
}

class _NumberingTabState extends State<_NumberingTab> {
  List<Map<String, dynamic>> types = [];
  final docPattern = TextEditingController();
  final formPattern = TextEditingController();
  List<Map<String, dynamic>>? preview;
  bool loaded = false;
  int editorKey = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final nb = Map<String, dynamic>.from(await api.get('/settings/numbering') as Map);
      setState(() {
        types = maps(nb['types']);
        docPattern.text = txt(nb['docPattern']);
        formPattern.text = txt(nb['formPattern']);
        preview = null;
        loaded = true;
        editorKey++;
      });
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Map<String, dynamic> get body => {'types': types, 'docPattern': docPattern.text.trim(), 'formPattern': formPattern.text.trim()};

  Future<void> _preview() async {
    try {
      final r = Map<String, dynamic>.from(await api.post('/settings/numbering/preview', body) as Map);
      setState(() => preview = maps(r['changes']));
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _apply() async {
    if (!await confirmDialog(context, '번호 체계 적용',
        '직접 지정하지 않은 모든 문서·양식 번호를 새 체계로 바꿉니다. 변경 내역은 변경이력에 남습니다. 적용할까요?')) {
      return;
    }
    try {
      final r = Map<String, dynamic>.from(await api.put('/settings/numbering', body) as Map);
      await st.reloadMe();
      st.notifyDataChanged();
      if (mounted) showInfo(context, '${(r['changes'] as List).length}건의 번호를 바꿨습니다.');
      await _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) return const Center(child: CircularProgressIndicator());
    final sample = {
      '{prefix}-{num}': 'P-801',
      'KS-{prefix}-{num}': 'KS-P-801',
      '{prefix}{num:04}': 'P0801',
    };
    return _page([
      Section('문서 구분', [
        ListEditor(
          key: ValueKey('types$editorKey'),
          hint: '코드는 내부 구분값이라 사용 중인 것은 지우거나 바꾸지 마세요. 이름과 접두어는 자유롭게 바꿀 수 있습니다.',
          columns: const [('key', '코드', 1), ('label', '이름 (예: 프로세스, 지침)', 3), ('prefix', '접두어 (번호 앞글자)', 2)],
          initial: types,
          onChanged: (v) => types = v,
        ),
      ]),
      Section('번호 형식', [
        TextField(
          controller: docPattern,
          decoration: const InputDecoration(labelText: '문서번호 형식', helperText: '{prefix} 접두어, {num} 번호, {num:04} 4자리 0채움. 예: KS-{prefix}-{num}'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: formPattern,
          decoration: const InputDecoration(labelText: '양식번호 형식', helperText: '{doc} 문서번호, {seq:02} 양식 순번(2자리). 예: {doc}-F{seq:02}'),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          for (final e in sample.entries)
            ActionChip(label: Text('${e.key} → ${e.value}'), onPressed: () => setState(() => docPattern.text = e.key)),
        ]),
      ]),
      Row(children: [
        OutlinedButton.icon(icon: const Icon(Icons.preview), label: const Text('미리보기'), onPressed: _preview),
        const SizedBox(width: 8),
        FilledButton.icon(icon: const Icon(Icons.check), label: const Text('저장하고 일괄 적용'), onPressed: _apply),
        const SizedBox(width: 8),
        TextButton(onPressed: _load, child: const Text('되돌리기')),
      ]),
      if (preview != null) ...[
        const SizedBox(height: 16),
        Text(preview!.isEmpty ? '바뀌는 번호가 없습니다.' : '바뀌는 번호 ${preview!.length}건 (아직 적용 전)'),
        const SizedBox(height: 6),
        if (preview!.isNotEmpty)
          SimpleTable(headers: const ['구분', '현재 번호', '새 번호'], flex: const [1, 2, 2], rows: [
            for (final c in preview!.take(300))
              [Text(c['kind'] == 'document' ? '문서' : '양식'), Text(txt(c['from'])), Text(txt(c['to']), style: const TextStyle(fontWeight: FontWeight.bold))],
          ]),
      ],
    ]);
  }
}

// ------------------------------------------------------------------ 부서
class _DepartmentsTab extends StatefulWidget {
  const _DepartmentsTab();

  @override
  State<_DepartmentsTab> createState() => _DepartmentsTabState();
}

class _DepartmentsTabState extends State<_DepartmentsTab> {
  List<Map<String, dynamic>> depts = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      depts = maps(await api.get('/departments'));
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _run(Future<void> Function() f) async {
    try {
      await f();
      await _load();
      st.notifyDataChanged();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _page([
      Section('부서', [
        for (final (i, d) in depts.indexed)
          ListTile(
            dense: true,
            title: Text(txt(d['name'])),
            trailing: Wrap(children: [
              IconButton(
                tooltip: '위로',
                icon: const Icon(Icons.arrow_upward, size: 18),
                onPressed: i == 0
                    ? null
                    : () => _run(() async {
                          await api.patch('/departments/${d['id']}', {'sortOrder': (depts[i - 1]['sortOrder'] as num).toInt()});
                          await api.patch('/departments/${depts[i - 1]['id']}', {'sortOrder': (d['sortOrder'] as num).toInt()});
                        }),
              ),
              IconButton(
                tooltip: '이름 바꾸기',
                icon: const Icon(Icons.edit, size: 18),
                onPressed: () async {
                  final n = await promptText(context, '부서 이름 바꾸기', initial: txt(d['name']), required: true);
                  if (n != null && n.isNotEmpty) await _run(() => api.patch('/departments/${d['id']}', {'name': n}));
                },
              ),
              IconButton(
                tooltip: '삭제',
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: () async {
                  if (await confirmDialog(context, '부서 삭제', "'${d['name']}' 부서를 삭제할까요?", ok: '삭제', danger: true)) {
                    await _run(() => api.delete('/departments/${d['id']}'));
                  }
                },
              ),
            ]),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('부서 추가'),
            onPressed: () async {
              final n = await promptText(context, '부서 추가', label: '부서명', required: true);
              if (n != null && n.isNotEmpty) await _run(() => api.post('/departments', {'name': n}));
            },
          ),
        ),
        muted(context, '부서별 등록·수정 권한은 [권한] 탭에서 정합니다. 처음에는 총무팀만 편집할 수 있습니다.'),
      ]),
    ]);
  }
}

// ------------------------------------------------------------------ 사용자
class _UsersTab extends StatefulWidget {
  const _UsersTab();

  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> {
  List<Map<String, dynamic>> users = [];
  List<Map<String, dynamic>> depts = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      users = maps(await api.get('/users'));
      depts = maps(await api.get('/departments'));
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _edit(Map<String, dynamic>? u) async {
    final empNo = TextEditingController(text: txt(u?['empNo']));
    final name = TextEditingController(text: txt(u?['name']));
    final position = TextEditingController(text: txt(u?['position']));
    final pw = TextEditingController();
    int? deptId = u?['departmentId'] as int?;
    var isAdmin = u?['isAdmin'] == true;
    var active = u?['active'] != false;
    String? err;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) => AlertDialog(
        title: Text(u == null ? '사용자 추가' : '사용자 수정'),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(controller: empNo, enabled: u == null, decoration: const InputDecoration(labelText: '사번 (로그인 아이디)')),
            const SizedBox(height: 10),
            TextField(controller: name, decoration: const InputDecoration(labelText: '이름')),
            const SizedBox(height: 10),
            Dropdown<int>(
              label: '부서',
              value: deptId,
              items: [(null, '(없음)'), for (final d in depts) (d['id'] as int, txt(d['name']))],
              onChanged: (v) => setLocal(() => deptId = v),
            ),
            const SizedBox(height: 10),
            TextField(controller: position, decoration: const InputDecoration(labelText: '직책 (선택)')),
            const SizedBox(height: 10),
            TextField(
              controller: pw,
              obscureText: true,
              decoration: InputDecoration(labelText: u == null ? '처음 비밀번호 (4자 이상)' : '비밀번호 초기화 (바꿀 때만 입력)'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: isAdmin,
              onChanged: (v) => setLocal(() => isAdmin = v ?? false),
              title: const Text('관리자 (사용자·권한·번호 체계 관리, 모든 메뉴 편집)'),
            ),
            if (u != null)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: active,
                onChanged: (v) => setLocal(() => active = v ?? true),
                title: const Text('사용 (끄면 로그인 불가 — 퇴사 등)'),
              ),
            if (err != null) Text(err!, style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          FilledButton(
            onPressed: () async {
              if (empNo.text.trim().isEmpty || name.text.trim().isEmpty) return setLocal(() => err = '사번과 이름을 입력하세요.');
              if (u == null && pw.text.length < 4) return setLocal(() => err = '비밀번호를 4자 이상 입력하세요.');
              final body = {
                'empNo': empNo.text.trim(), 'name': name.text.trim(), 'departmentId': deptId, 'position': position.text.trim(),
                'isAdmin': isAdmin, if (u != null) 'active': active, if (pw.text.isNotEmpty) 'password': pw.text,
              };
              try {
                if (u == null) {
                  await api.post('/users', body);
                } else {
                  await api.patch('/users/${u['id']}', body);
                }
                if (ctx.mounted) Navigator.pop(ctx);
                await _load();
              } catch (e) {
                setLocal(() => err = errorText(e));
              }
            },
            child: const Text('저장'),
          ),
        ],
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _page([
      Section(
        '사용자 ${users.length}명',
        [
          SimpleTable(
            headers: const ['사번', '이름', '부서', '직책', '구분', ''],
            flex: const [2, 2, 2, 2, 2, 1],
            rows: [
              for (final u in users)
                [
                  Text(txt(u['empNo'])),
                  Text(txt(u['name'])),
                  Text(txt(u['department'])),
                  Text(txt(u['position'])),
                  Text([if (u['isAdmin'] == true) '관리자', if (u['active'] == false) '사용 중지'].join(' · ')),
                  IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.edit, size: 18), onPressed: () => _edit(u)),
                ],
            ],
          ),
        ],
        trailing: FilledButton.icon(icon: const Icon(Icons.person_add), label: const Text('사용자 추가'), onPressed: () => _edit(null)),
      ),
    ]);
  }
}

// ------------------------------------------------------------------ 권한
class _PermissionsTab extends StatefulWidget {
  const _PermissionsTab();

  @override
  State<_PermissionsTab> createState() => _PermissionsTabState();
}

class _PermissionsTabState extends State<_PermissionsTab> {
  Map<String, dynamic>? p;
  List<Map<String, dynamic>> depts = [];
  List<Map<String, dynamic>> users = [];
  Map<String, int> defaults = {};
  Map<String, Map<String, int>> deptPerms = {};
  Map<String, Map<String, int>> userPerms = {};
  bool dirty = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Map<String, Map<String, int>> _conv(dynamic m) => {
        for (final e in (m as Map? ?? {}).entries)
          '${e.key}': {for (final x in (e.value as Map).entries) '${x.key}': (x.value as num).toInt()},
      };

  Future<void> _load() async {
    try {
      final r = Map<String, dynamic>.from(await api.get('/permissions') as Map);
      depts = maps(await api.get('/departments'));
      users = maps(await api.get('/users'));
      setState(() {
        p = r;
        defaults = {for (final e in (r['defaults'] as Map).entries) '${e.key}': (e.value as num).toInt()};
        deptPerms = _conv(r['departments']);
        userPerms = _conv(r['users']);
        dirty = false;
      });
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _save() async {
    try {
      await api.put('/permissions', {'defaults': defaults, 'departments': deptPerms, 'users': userPerms});
      await st.reloadMe();
      st.notifyDataChanged();
      if (mounted) showInfo(context, '권한을 저장했습니다. 바로 적용됩니다.');
      await _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Widget _levelBox(int value, ValueChanged<int> onChanged, {bool allowNone = true}) {
    final levels = [for (final l in (p?['levels'] as List? ?? const [])) '$l'];
    return DropdownButton<int>(
      value: value,
      isDense: true,
      underline: const SizedBox.shrink(),
      items: [for (var i = allowNone ? 0 : 0; i < levels.length; i++) DropdownMenuItem(value: i, child: Text(i == 0 && !allowNone ? '(기본값)' : levels[i]))],
      onChanged: (v) {
        if (v == null) return;
        setState(() {
          onChanged(v);
          dirty = true;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (p == null) return const Center(child: CircularProgressIndicator());
    final modules = maps(p!['modules']);
    final flex = [3, for (final _ in modules) 2];
    return _page([
      muted(context, '실제 권한 = 기본값, 소속 부서 권한, 개인 권한 중 가장 높은 것. 관리자는 모든 메뉴를 편집할 수 있습니다.\n'
          '단계: 없음 → 조회 → 등록·수정 → 등록·수정·삭제'),
      const SizedBox(height: 16),
      Section('모든 사람 기본값', [
        SimpleTable(headers: ['', for (final m in modules) txt(m['label'])], flex: flex, rows: [
          [
            const Text('기본값'),
            for (final m in modules)
              _levelBox(defaults[m['key']] ?? 1, (v) => defaults[m['key'] as String] = v),
          ],
        ]),
      ]),
      Section('부서별', [
        SimpleTable(headers: ['부서', for (final m in modules) txt(m['label'])], flex: flex, rows: [
          for (final d in depts)
            [
              Text(txt(d['name'])),
              for (final m in modules)
                _levelBox(deptPerms['${d['id']}']?[m['key']] ?? 0, (v) => (deptPerms['${d['id']}'] ??= {})[m['key'] as String] = v,
                    allowNone: false),
            ],
        ]),
      ]),
      Section('개인별 (부서와 다르게 줄 사람만)', [
        SimpleTable(headers: ['사용자', for (final m in modules) txt(m['label'])], flex: flex, rows: [
          for (final u in users.where((u) => u['isAdmin'] != true && u['active'] != false))
            [
              Text('${u['name']} (${txt(u['department'])})'),
              for (final m in modules)
                _levelBox(userPerms['${u['id']}']?[m['key']] ?? 0, (v) => (userPerms['${u['id']}'] ??= {})[m['key'] as String] = v,
                    allowNone: false),
            ],
        ]),
      ]),
      Row(children: [
        FilledButton.icon(onPressed: dirty ? _save : null, icon: const Icon(Icons.save), label: const Text('권한 저장')),
        const SizedBox(width: 8),
        TextButton(onPressed: _load, child: const Text('되돌리기')),
      ]),
    ]);
  }
}

// ------------------------------------------------------------------ 회사 정보
class _CompanyTab extends StatefulWidget {
  const _CompanyTab();

  @override
  State<_CompanyTab> createState() => _CompanyTabState();
}

class _CompanyTabState extends State<_CompanyTab> {
  final name = TextEditingController();
  List<String> roles = [];
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    api.get('/settings/company').then((r) {
      final m = Map<String, dynamic>.from(r as Map);
      if (!mounted) return;
      setState(() {
        name.text = txt(m['name']);
        roles = [for (final x in (m['approvalRoles'] as List? ?? const [])) '$x'];
        loaded = true;
      });
    }).catchError((Object e) {
      if (mounted) showError(context, e);
    });
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) return const Center(child: CircularProgressIndicator());
    return _page([
      Section('회사 정보', [
        TextField(controller: name, decoration: const InputDecoration(labelText: '회사명 (내보내는 문서 머리글·목록표에 들어감)')),
      ]),
      Section('결재 직책 (전결권한 고를 때 목록)', [
        ListEditor(
          columns: const [('v', '직책', 1)],
          initial: [for (final r in roles) {'v': r}],
          onChanged: (v) => roles = [for (final x in v) '${x['v']}'],
        ),
      ]),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          icon: const Icon(Icons.save),
          label: const Text('저장'),
          onPressed: () async {
            try {
              await api.put('/settings/company', {'name': name.text.trim(), 'approvalRoles': roles});
              await st.reloadMe();
              if (context.mounted) showInfo(context, '저장했습니다.');
            } catch (e) {
              if (context.mounted) showError(context, e);
            }
          },
        ),
      ),
    ]);
  }
}
