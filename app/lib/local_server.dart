import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'settings.dart';

class LocalServerException implements Exception {
  final String message;
  LocalServerException(this.message);

  @override
  String toString() => message;
}

/// PC 단독 모드: 프로그램 폴더 안의 server 를 실행·종료한다.
class LocalServer {
  /// 배포판: 서버 전체를 한 파일로 묶은 것. 개발 중: 소스
  static const _bundle = 'local.mjs';
  static final _source = 'src${sep}local.js';

  /// 실행 파일 옆의 server 폴더 (개발 중에는 한 단계 위도 찾아본다)
  static Directory? findServerDir() {
    final exeDir = File(Platform.resolvedExecutable).parent;
    final candidates = [
      Directory('${exeDir.path}${sep}server'),
      Directory('${exeDir.parent.path}${sep}server'),
      Directory('${Directory.current.path}$sep..${sep}server'),
    ];
    for (final d in candidates) {
      if (File('${d.path}$sep$_bundle').existsSync() || File('${d.path}$sep$_source').existsSync()) return d;
    }
    return null;
  }

  static String? bundledVersion(Directory dir) {
    try {
      final j = jsonDecode(File('${dir.path}${sep}package.json').readAsStringSync()) as Map<String, dynamic>;
      return j['version'] as String?;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> health(String base) async {
    try {
      final r = await http.get(Uri.parse('$base/health')).timeout(const Duration(seconds: 3));
      if (r.statusCode == 200) return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {}
    return null;
  }

  static Future<void> ensureRunning(AppSettings s, void Function(String) onStatus) async {
    final base = s.baseUrl;
    final dir = findServerDir();
    if (dir == null) {
      throw LocalServerException('서버 폴더(server)를 찾을 수 없습니다.\n'
          '압축을 풀 때 프로그램과 같은 위치에 server 폴더가 있어야 합니다.');
    }
    final want = bundledVersion(dir);

    final h = await health(base);
    if (h != null) {
      if (h['mode'] == 'local' && h['version'] == want) {
        // 이미 켜진 서버: 이 프로그램이 꺼지면 서버도 꺼지도록 등록
        try {
          await trustedCall(s, 'POST', '/local/attach', {'pid': pid});
        } catch (_) {}
        return;
      }
      if (h['mode'] == 'local') {
        onStatus('이전 버전 서버를 종료하는 중...');
        await shutdown(s);
        await _waitDown(base);
      } else {
        throw LocalServerException('포트 ${s.localPort}을(를) 다른 프로그램이 사용 중입니다.\n연결 설정에서 포트를 바꿔주세요.');
      }
    }

    onStatus('서버를 시작하는 중...');
    final dataDir = serverDataDir();
    await Directory(dataDir).create(recursive: true);
    final logFile = File('$dataDir${sep}server.log');
    final logStart = await logFile.exists() ? await logFile.length() : 0;

    final bundledNode = File('${dir.path}${sep}node.exe');
    final node = Platform.isWindows && bundledNode.existsSync() ? bundledNode.path : 'node';
    try {
      await Process.start(
        node,
        [File('${dir.path}$sep$_bundle').existsSync() ? _bundle : _source],
        workingDirectory: dir.path,
        // APP_PID: 이 프로그램이 꺼지면(창 닫기·강제 종료) 서버도 스스로 꺼진다
        environment: {'DATA_DIR': dataDir, 'PORT': '${s.localPort}', 'HOST': '127.0.0.1', 'APP_PID': '$pid'},
        mode: ProcessStartMode.detached,
      );
    } catch (e) {
      throw LocalServerException('서버 프로그램을 실행할 수 없습니다.\n$e');
    }

    final deadline = DateTime.now().add(const Duration(minutes: 4));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (await health(base) != null) return;
      final newLog = await _readFrom(logFile, logStart);
      if (newLog.contains('시작 실패')) {
        throw LocalServerException('서버 시작에 실패했습니다.\n\n${_tail(newLog, 12)}\n\n로그 파일: ${logFile.path}');
      }
      final lines = newLog.trim().split('\n').where((l) => l.trim().isNotEmpty).toList();
      if (lines.isNotEmpty) onStatus(lines.last.replaceFirst(RegExp(r'^\[[^\]]*\]\s*'), ''));
    }
    throw LocalServerException('서버가 응답하지 않습니다.\n로그 파일: ${logFile.path}');
  }

  /// 로컬 서버 종료 요청 (DB 정상 종료 포함)
  static Future<void> shutdown(AppSettings s) async {
    try {
      final cfgFile = File('${serverDataDir()}${sep}local.json');
      if (!await cfgFile.exists()) return;
      final cfg = jsonDecode(await cfgFile.readAsString()) as Map<String, dynamic>;
      await http
          .post(Uri.parse('${s.baseUrl}/local/shutdown'), headers: {'x-shutdown-token': '${cfg['shutdownToken']}'})
          .timeout(const Duration(seconds: 3));
    } catch (_) {}
  }

  /// 이 PC의 데이터 폴더에 있는 토큰으로만 쓸 수 있는 요청 (비밀번호 재설정 등)
  static Future<dynamic> trustedCall(AppSettings s, String method, String path, [Object? body]) async {
    final cfgFile = File('${serverDataDir()}${sep}local.json');
    if (!await cfgFile.exists()) throw LocalServerException('이 PC의 서버 설정 파일을 찾을 수 없습니다.');
    final cfg = jsonDecode(await cfgFile.readAsString()) as Map<String, dynamic>;
    final headers = {'x-shutdown-token': '${cfg['shutdownToken']}', 'content-type': 'application/json'};
    final uri = Uri.parse('${s.baseUrl}$path');
    final r = method == 'GET'
        ? await http.get(uri, headers: headers).timeout(const Duration(seconds: 10))
        : await http.post(uri, headers: headers, body: jsonEncode(body ?? {})).timeout(const Duration(seconds: 10));
    final data = r.bodyBytes.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));
    if (r.statusCode >= 400) {
      throw LocalServerException(data is Map && data['error'] != null ? '${data['error']}' : '요청 실패 (${r.statusCode})');
    }
    return data;
  }

  static Future<void> _waitDown(String base) async {
    for (var i = 0; i < 30; i++) {
      if (await health(base) == null) return;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }

  static Future<String> _readFrom(File f, int start) async {
    try {
      if (!await f.exists()) return '';
      final len = await f.length();
      if (len <= start) return '';
      final raf = await f.open();
      try {
        await raf.setPosition(start);
        final bytes = await raf.read(len - start);
        return utf8.decode(bytes, allowMalformed: true);
      } finally {
        await raf.close();
      }
    } catch (_) {
      return '';
    }
  }

  static String _tail(String text, int n) {
    final lines = text.trim().split('\n');
    return lines.length <= n ? lines.join('\n') : lines.sublist(lines.length - n).join('\n');
  }
}
