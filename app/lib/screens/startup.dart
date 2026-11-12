import 'package:flutter/material.dart';

import '../api.dart';
import '../common.dart';
import '../local_server.dart';
import '../settings.dart';
import '../state.dart';
import 'home.dart';
import 'settings_screen.dart';

enum _Phase { connecting, error, setup, login }

/// 시작 화면: 서버 연결 → (최초 관리자 등록) → 로그인
class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key});

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  _Phase phase = _Phase.connecting;
  String status = '준비 중...';
  String? error;
  bool busy = false;

  final empNo = TextEditingController();
  final name = TextEditingController();
  final pw = TextEditingController();
  final pw2 = TextEditingController();

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void dispose() {
    empNo.dispose();
    name.dispose();
    pw.dispose();
    pw2.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      phase = _Phase.connecting;
      error = null;
      status = '설정을 불러오는 중...';
    });
    try {
      final s = await AppSettings.load();
      AppState.I.settings = s;
      AppState.I.api = Api(s.baseUrl);
      if (empNo.text.isEmpty) empNo.text = s.lastEmpNo ?? '';

      if (s.mode == 'local') {
        await LocalServer.ensureRunning(s, (m) {
          if (mounted) setState(() => status = m);
        });
      } else {
        if (s.remoteUrl.trim().isEmpty) throw LocalServerException('접속할 서버 주소를 입력하세요.');
        setState(() => status = '서버에 연결하는 중...');
        if (await LocalServer.health(s.baseUrl) == null) {
          throw LocalServerException('서버(${s.baseUrl})에 연결할 수 없습니다.');
        }
      }
      final st = await api.get('/setup/status') as Map<String, dynamic>;
      if (!mounted) return;
      setState(() => phase = st['needsSetup'] == true ? _Phase.setup : _Phase.login);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        phase = _Phase.error;
        error = errorText(e);
      });
    }
  }

  Future<void> _setup() async {
    if (empNo.text.trim().isEmpty || name.text.trim().isEmpty || pw.text.length < 4) {
      setState(() => error = '사번, 이름, 비밀번호(4자 이상)를 입력하세요.');
      return;
    }
    if (pw.text != pw2.text) {
      setState(() => error = '비밀번호 확인이 일치하지 않습니다.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await api.post('/setup', {'empNo': empNo.text.trim(), 'name': name.text.trim(), 'password': pw.text});
      await _login();
    } catch (e) {
      setState(() => error = errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// 비밀번호를 잊었을 때: 관리자에게 초기화를 부탁하거나, 이 PC 서버라면 관리자 비밀번호를 다시 정한다
  Future<void> _forgotPassword() async {
    final local = AppState.I.settings.mode == 'local';
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('비밀번호를 잊으셨나요?'),
        content: SizedBox(
          width: 420,
          child: Text(local
              ? '관리자에게 [설정 → 사용자]에서 비밀번호를 초기화해 달라고 요청하세요.\n\n'
                  '관리자 본인이 잊었다면, 이 PC에 저장된 데이터의 관리자 비밀번호를 여기서 다시 정할 수 있습니다.'
              : '관리자에게 [설정 → 사용자]에서 비밀번호를 초기화해 달라고 요청하세요.'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('닫기')),
          if (local) FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('관리자 비밀번호 다시 정하기')),
        ],
      ),
    );
    if (go == true) await _resetPassword();
  }

  /// 이 PC에서 실행 중인 서버일 때만: 관리자 비밀번호 다시 정하기 (초기화 코드도 모를 때)
  Future<void> _resetPassword() async {
    final s = AppState.I.settings;
    List<Map<String, dynamic>> admins;
    try {
      admins = [
        for (final a in (await LocalServer.trustedCall(s, 'GET', '/local/admins') as List)) Map<String, dynamic>.from(a as Map),
      ];
    } catch (e) {
      setState(() => error = errorText(e));
      return;
    }
    if (!mounted) return;
    if (admins.isEmpty) {
      setState(() => error = '관리자 계정이 없습니다.');
      return;
    }
    var chosen = admins.any((a) => a['empNo'] == empNo.text.trim()) ? empNo.text.trim() : '${admins.first['empNo']}';
    final p1 = TextEditingController();
    final p2 = TextEditingController();
    String? err;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('관리자 비밀번호 다시 정하기'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('이 PC에 저장된 데이터의 관리자 계정만 바꿀 수 있습니다. 다른 PC에서는 할 수 없습니다.'),
              const SizedBox(height: 14),
              InputDecorator(
                decoration: const InputDecoration(labelText: '계정'),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: chosen,
                    isDense: true,
                    isExpanded: true,
                    items: [
                      for (final a in admins)
                        DropdownMenuItem(
                          value: '${a['empNo']}',
                          child: Text('${a['empNo']}  ${a['name']}${a['active'] == true ? '' : ' (사용 중지됨)'}'),
                        ),
                    ],
                    onChanged: (v) => setLocal(() => chosen = v ?? chosen),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(controller: p1, obscureText: true, decoration: const InputDecoration(labelText: '새 비밀번호 (4자 이상)')),
              const SizedBox(height: 10),
              TextField(controller: p2, obscureText: true, decoration: const InputDecoration(labelText: '새 비밀번호 확인')),
              if (err != null) Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(err!, style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
            FilledButton(
              onPressed: () {
                if (p1.text.length < 4) return setLocal(() => err = '4자 이상 입력하세요.');
                if (p1.text != p2.text) return setLocal(() => err = '비밀번호 확인이 일치하지 않습니다.');
                Navigator.pop(ctx, true);
              },
              child: const Text('바꾸기'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await LocalServer.trustedCall(s, 'POST', '/local/reset-password', {'empNo': chosen, 'password': p1.text});
      if (!mounted) return;
      setState(() {
        empNo.text = chosen;
        pw.text = '';
        error = null;
      });
      showInfo(context, '비밀번호를 바꿨습니다. 새 비밀번호로 로그인하세요.');
    } catch (e) {
      if (mounted) setState(() => error = errorText(e));
    }
  }

  Future<void> _login() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final res = await api.post('/auth/login', {'empNo': empNo.text.trim(), 'password': pw.text})
          as Map<String, dynamic>;
      api.token = res['token'] as String;
      await AppState.I.reloadMe();
      AppState.I.settings.lastEmpNo = empNo.text.trim();
      await AppState.I.settings.save();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
    } catch (e) {
      if (mounted) setState(() => error = errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      body: Center(
        child: SingleChildScrollView(
          child: SizedBox(
            width: 440,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      Icon(Icons.fact_check_outlined, color: theme.colorScheme.primary, size: 30),
                      const SizedBox(width: 10),
                      Text('업무표준 관리', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                    ]),
                    const SizedBox(height: 24),
                    ..._content(theme),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _content(ThemeData theme) {
    final errorBox = error == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(error!, style: TextStyle(color: theme.colorScheme.error)),
          );

    switch (phase) {
      case _Phase.connecting:
        return [
          const Center(child: CircularProgressIndicator()),
          const SizedBox(height: 16),
          Text(status, textAlign: TextAlign.center),
        ];
      case _Phase.error:
        return [
          Icon(Icons.error_outline, color: theme.colorScheme.error, size: 36),
          const SizedBox(height: 8),
          SelectableText(error ?? '', style: const TextStyle(height: 1.5)),
          const SizedBox(height: 20),
          Row(children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.settings),
              label: const Text('연결 설정'),
              onPressed: () async {
                if (await showServerSettingsDialog(context)) _connect();
              },
            ),
            const Spacer(),
            FilledButton.icon(icon: const Icon(Icons.refresh), label: const Text('다시 시도'), onPressed: _connect),
          ]),
        ];
      case _Phase.setup:
        return [
          Text('처음 사용하시는군요. 관리자 계정을 만들어 주세요.\n이 계정은 총무팀 소속 관리자로 만들어집니다.', style: theme.textTheme.bodyLarge),
          const SizedBox(height: 16),
          TextField(controller: empNo, decoration: const InputDecoration(labelText: '사번 (로그인 아이디)')),
          const SizedBox(height: 10),
          TextField(controller: name, decoration: const InputDecoration(labelText: '이름')),
          const SizedBox(height: 10),
          TextField(controller: pw, obscureText: true, decoration: const InputDecoration(labelText: '비밀번호')),
          const SizedBox(height: 10),
          TextField(
            controller: pw2,
            obscureText: true,
            decoration: const InputDecoration(labelText: '비밀번호 확인'),
            onSubmitted: (_) => _setup(),
          ),
          errorBox,
          const SizedBox(height: 20),
          FilledButton(onPressed: busy ? null : _setup, child: const Text('관리자 계정 만들기')),
        ];
      case _Phase.login:
        return [
          TextField(
            controller: empNo,
            autofocus: empNo.text.isEmpty,
            decoration: const InputDecoration(labelText: '사번'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: pw,
            autofocus: empNo.text.isNotEmpty,
            obscureText: true,
            decoration: const InputDecoration(labelText: '비밀번호'),
            onSubmitted: (_) => _login(),
          ),
          errorBox,
          const SizedBox(height: 20),
          FilledButton(onPressed: busy ? null : _login, child: const Text('로그인')),
          TextButton(onPressed: busy ? null : _forgotPassword, child: const Text('비밀번호를 잊으셨나요?')),
          const SizedBox(height: 8),
          Text(
            AppState.I.settings.mode == 'local' ? '이 PC에서 실행 중인 서버' : '서버: ${AppState.I.settings.baseUrl}',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ];
    }
  }
}
