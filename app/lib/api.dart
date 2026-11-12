import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);

  @override
  String toString() => message;
}

/// 서버 API 호출. 응답은 JSON (파일 내려받기만 바이트).
class Api {
  Api(this.baseUrl);

  String baseUrl;
  String? token;
  void Function()? onUnauthorized;
  final http.Client _client = http.Client();

  Future<dynamic> get(String path, {Map<String, String?>? query}) => _json('GET', path, query: query);
  Future<dynamic> post(String path, [Object? body]) => _json('POST', path, body: body ?? const <String, dynamic>{});
  Future<dynamic> patch(String path, Object body) => _json('PATCH', path, body: body);
  Future<dynamic> put(String path, Object body) => _json('PUT', path, body: body);
  Future<dynamic> delete(String path) => _json('DELETE', path);

  /// 파일 올리기 (본문 = 파일 바이트)
  Future<dynamic> upload(String path, Uint8List bytes,
      {Map<String, String?>? query, String contentType = 'application/pdf'}) async {
    final res = await _send('POST', path, query: query, rawBody: bytes, contentType: contentType,
        timeout: const Duration(minutes: 5));
    return _decode(res);
  }

  /// 파일 내려받기
  Future<Uint8List> download(String path, {Map<String, String?>? query}) async {
    final res = await _send('GET', path, query: query, timeout: const Duration(minutes: 5));
    if (res.$1 >= 400) _decode(res);
    return res.$2;
  }

  /// 본문을 보내고 파일로 받기 (묶음 내보내기)
  Future<Uint8List> postDownload(String path, Object body) async {
    final res = await _send('POST', path,
        rawBody: utf8.encode(jsonEncode(body)),
        contentType: 'application/json; charset=utf-8',
        timeout: const Duration(minutes: 10));
    if (res.$1 >= 400) _decode(res);
    return res.$2;
  }

  Future<dynamic> _json(String method, String path, {Map<String, String?>? query, Object? body}) async {
    final res = await _send(method, path,
        query: query,
        rawBody: body == null ? null : utf8.encode(jsonEncode(body)),
        contentType: 'application/json; charset=utf-8');
    return _decode(res);
  }

  Uri _uri(String path, Map<String, String?>? query) {
    var uri = Uri.parse('$baseUrl$path');
    if (query != null) {
      final q = <String, String>{};
      query.forEach((k, v) {
        if (v != null && v.isNotEmpty) q[k] = v;
      });
      if (q.isNotEmpty) uri = uri.replace(queryParameters: q);
    }
    return uri;
  }

  Future<(int, Uint8List)> _send(String method, String path,
      {Map<String, String?>? query,
      List<int>? rawBody,
      String? contentType,
      Duration timeout = const Duration(seconds: 60)}) async {
    final req = http.Request(method, _uri(path, query));
    if (token != null) req.headers['authorization'] = 'Bearer $token';
    if (rawBody != null) {
      req.headers['content-type'] = contentType ?? 'application/octet-stream';
      req.bodyBytes = rawBody;
    }
    http.StreamedResponse res;
    try {
      res = await _client.send(req).timeout(timeout);
    } catch (e) {
      throw ApiException(0, '서버에 연결할 수 없습니다. ($e)');
    }
    return (res.statusCode, await res.stream.toBytes());
  }

  dynamic _decode((int, Uint8List) res) {
    final (status, bytes) = res;
    final text = utf8.decode(bytes, allowMalformed: true);
    dynamic data;
    if (text.isNotEmpty) {
      try {
        data = jsonDecode(text);
      } catch (_) {
        data = text;
      }
    }
    if (status >= 400) {
      if (status == 401 && token != null) onUnauthorized?.call();
      final msg = data is Map && data['error'] != null ? data['error'].toString() : '요청 실패 (HTTP $status)';
      throw ApiException(status, msg);
    }
    return data;
  }
}
