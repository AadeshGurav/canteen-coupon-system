import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/config.dart';
import '../../core/errors.dart';

/// Thin HTTP/JSON client the client-mode app uses to talk to a discovered host.
///
/// Maps transport failures to [HostUnreachableException] and HTTP error status
/// codes back to the same [AppException] subtypes the host threw, so client
/// mode and host mode surface identical errors to the UI (PRD §7, §13.2).
class ApiClient {
  ApiClient({required this.baseUrl, http.Client? inner})
      : _http = inner ?? http.Client();

  /// e.g. `http://192.168.1.5:8710` — no trailing slash, no `/api`.
  final String baseUrl;
  final http.Client _http;

  String? token;

  Uri _uri(String path, [Map<String, dynamic>? query]) => Uri.parse(
        '$baseUrl/api$path',
      ).replace(
        queryParameters: query?.map((k, v) => MapEntry(k, '$v')),
      );

  Map<String, String> get _headers => {
        'content-type': 'application/json',
        if (token != null)
          AppConfig.authHeader: '${AppConfig.authScheme} $token',
      };

  Future<dynamic> getJson(String path, {Map<String, dynamic>? query}) =>
      _send(() => _http.get(_uri(path, query), headers: _headers));

  Future<dynamic> postJson(String path, Object? body,
          {Map<String, dynamic>? query}) =>
      _send(() => _http.post(_uri(path, query),
          headers: _headers, body: jsonEncode(body)));

  Future<dynamic> patchJson(String path, Object? body) => _send(
      () => _http.patch(_uri(path), headers: _headers, body: jsonEncode(body)));

  Future<dynamic> deleteJson(String path) =>
      _send(() => _http.delete(_uri(path), headers: _headers));

  /// Raw bytes (bill PDF, QR image).
  Future<List<int>> getBytes(String path) async {
    final response = await _guarded(() => _http.get(_uri(path), headers: _headers));
    _throwForStatus(response);
    return response.bodyBytes;
  }

  Future<dynamic> _send(Future<http.Response> Function() call) async {
    final response = await _guarded(call);
    _throwForStatus(response);
    if (response.body.isEmpty) return null;
    return jsonDecode(response.body);
  }

  Future<http.Response> _guarded(Future<http.Response> Function() call) async {
    try {
      return await call();
    } on SocketException {
      throw const HostUnreachableException();
    } on http.ClientException {
      throw const HostUnreachableException();
    } on HttpException {
      throw const HostUnreachableException();
    }
  }

  void _throwForStatus(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;

    String message = 'Request failed (${response.statusCode}).';
    String code = 'internal';
    try {
      final body = jsonDecode(response.body);
      if (body is Map) {
        message = (body['message'] ?? body['error'] ?? message).toString();
        code = (body['error'] ?? code).toString();
      }
    } catch (_) {/* non-JSON error body */}

    throw switch (response.statusCode) {
      400 => ValidationException(message, code: code),
      401 => AuthException(message),
      403 => ForbiddenException(message, code: code),
      404 => NotFoundException(message, code: code),
      409 => ConflictException(message, code: code),
      503 => const HostUnreachableException(),
      _ => InternalException(message),
    };
  }

  void close() => _http.close();
}
