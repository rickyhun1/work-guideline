import 'package:flutter/foundation.dart';

import 'api.dart';
import 'settings.dart';

const String appVersion = String.fromEnvironment('APP_VERSION', defaultValue: 'dev');

/// 다른 화면으로 이동 요청 (예: 문서 화면에서 양식을 눌렀을 때)
class NavRequest {
  NavRequest(this.kind, this.id);
  final String kind; // document / form / law / project
  final int id;
}

/// 프로그램 전역 상태
class AppState {
  AppState._();
  static final AppState I = AppState._();

  AppSettings settings = AppSettings();
  Api api = Api('');

  /// /me 결과: user, perms, modules, levels, numbering, company
  Map<String, dynamic> me = {};

  Map<String, dynamic> get user => Map<String, dynamic>.from(me['user'] as Map? ?? {});
  bool get isAdmin => user['isAdmin'] == true;

  /// 메뉴별 권한 단계: 0 없음, 1 조회, 2 등록·수정, 3 삭제 포함
  int level(String module) => ((me['perms'] as Map?)?[module] as num?)?.toInt() ?? 0;
  bool can(String module, int lv) => level(module) >= lv;

  List<Map<String, dynamic>> get docTypes => [
        for (final t in ((me['numbering'] as Map?)?['types'] as List? ?? const []))
          Map<String, dynamic>.from(t as Map),
      ];
  String typeLabel(String key) =>
      docTypes.firstWhere((t) => t['key'] == key, orElse: () => {'label': key})['label'] as String;
  List<String> get approvalRoles =>
      [for (final r in ((me['company'] as Map?)?['approvalRoles'] as List? ?? const [])) '$r'];

  Future<void> reloadMe() async {
    me = Map<String, dynamic>.from(await api.get('/me') as Map);
  }

  /// 데이터가 바뀌면 증가 → 각 화면이 새로고침
  final ValueNotifier<int> dataVersion = ValueNotifier<int>(0);
  void notifyDataChanged() => dataVersion.value++;

  /// 화면 이동 요청
  final ValueNotifier<NavRequest?> nav = ValueNotifier<NavRequest?>(null);
  void goto(String kind, int id) => nav.value = NavRequest(kind, id);
}

Api get api => AppState.I.api;
AppState get st => AppState.I;
