import 'dart:convert';
import 'dart:io';

final String sep = Platform.pathSeparator;

/// 프로그램 설정 저장 위치 (사용자별)
String appDataDir() {
  if (Platform.isWindows) {
    final base = Platform.environment['LOCALAPPDATA'] ?? Platform.environment['APPDATA'] ?? '.';
    return '$base${sep}WorkGuideline';
  }
  return '${Platform.environment['HOME'] ?? '.'}$sep.work-guideline-app';
}

/// PC 단독 모드 서버의 데이터(DB) 위치. 한글 경로를 피하려고 ProgramData 를 쓴다.
/// 서버에는 DATA_DIR 환경변수로 명시해서 넘긴다.
String serverDataDir() {
  if (Platform.isWindows) {
    final base = Platform.environment['ProgramData'] ?? 'C:\\ProgramData';
    return '$base${sep}WorkGuideline';
  }
  return '${Platform.environment['HOME'] ?? '.'}$sep.work-guideline';
}

class AppSettings {
  /// 'local' = 이 PC에서 서버 실행, 'remote' = 별도 서버에 접속
  String mode;
  String remoteUrl;
  int localPort;
  String? lastEmpNo;
  String companyName;

  AppSettings({
    this.mode = 'local',
    this.remoteUrl = '',
    this.localPort = 37220,
    this.lastEmpNo,
    this.companyName = '',
  });

  String get baseUrl =>
      mode == 'local' ? 'http://127.0.0.1:$localPort' : remoteUrl.trim().replaceAll(RegExp(r'/+$'), '');

  static File get _file => File('${appDataDir()}${sep}settings.json');

  static Future<AppSettings> load() async {
    try {
      final f = _file;
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        return AppSettings(
          mode: j['mode'] as String? ?? 'local',
          remoteUrl: j['remoteUrl'] as String? ?? '',
          localPort: (j['localPort'] as num?)?.toInt() ?? 37220,
          lastEmpNo: j['lastEmpNo'] as String?,
          companyName: j['companyName'] as String? ?? '',
        );
      }
    } catch (_) {
      // 손상된 설정 파일은 무시하고 기본값 사용
    }
    return AppSettings();
  }

  Future<void> save() async {
    final f = _file;
    await f.parent.create(recursive: true);
    await f.writeAsString(jsonEncode({
      'mode': mode,
      'remoteUrl': remoteUrl,
      'localPort': localPort,
      'lastEmpNo': lastEmpNo,
      'companyName': companyName,
    }));
  }
}
