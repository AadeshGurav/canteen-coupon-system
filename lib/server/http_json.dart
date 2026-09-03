import 'dart:convert';

import 'package:shelf/shelf.dart';

import '../core/errors.dart';

/// Small helpers so route handlers stay one-liners and every response is
/// consistent JSON (Postel's Law, CLAUDE.md §11.2: conservative in what we send).

Response jsonOk(Object? body, {int status = 200}) => Response(
      status,
      body: jsonEncode(body),
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

Response jsonList(Iterable<Object?> items) => jsonOk(items.toList());

Response bytesOk(List<int> bytes, String contentType) => Response.ok(
      bytes,
      headers: {'content-type': contentType},
    );

Future<Map<String, dynamic>> readJsonObject(Request request) async {
  final text = await request.readAsString();
  if (text.isEmpty) return {};
  final decoded = jsonDecode(text);
  if (decoded is! Map<String, dynamic>) {
    throw const ValidationException('Request body must be a JSON object.');
  }
  return decoded;
}

Future<List<dynamic>> readJsonArray(Request request) async {
  final text = await request.readAsString();
  final decoded = jsonDecode(text.isEmpty ? '[]' : text);
  if (decoded is! List) {
    throw const ValidationException('Request body must be a JSON array.');
  }
  return decoded;
}

/// Parse a query param as int, or throw a clean 400.
int intParam(Request request, String name, {int? fallback}) {
  final raw = request.url.queryParameters[name];
  if (raw == null) {
    if (fallback != null) return fallback;
    throw ValidationException("Missing query parameter '$name'.");
  }
  final value = int.tryParse(raw);
  if (value == null) throw ValidationException("'$name' must be an integer.");
  return value;
}

DateTime? dateParam(Request request, String name) {
  final raw = request.url.queryParameters[name];
  if (raw == null) return null;
  return DateTime.parse(raw);
}

/// Path segment → int, or a clean 404-style error.
int pathId(String raw, {String entity = 'record'}) {
  final value = int.tryParse(raw);
  if (value == null) throw ValidationException('Invalid $entity id.');
  return value;
}
