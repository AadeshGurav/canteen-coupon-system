import 'dart:convert';

import 'package:shelf/shelf.dart';

import '../core/config.dart';
import '../core/errors.dart';
import '../core/logging.dart';
import '../core/role.dart';
import '../data/local/database.dart';
import '../services/auth_service.dart';

final _log = log('server');

/// Turns any thrown [AppException] into a clean JSON error with the right
/// status, and anything else into a logged 500 that never leaks internals
/// (PRD §7, §8; CLAUDE.md §8).
Middleware errorMiddleware() => (Handler inner) {
      return (Request request) async {
        try {
          return await inner(request);
        } on AppException catch (e) {
          return _error(e.code, e.message, _statusFor(e));
        } catch (e, st) {
          _log.severe('unhandled ${request.method} ${request.url.path}', e, st);
          return _error(
            'internal',
            'Something went wrong on the host. Check the host device logs.',
            500,
          );
        }
      };
    };

int _statusFor(AppException e) => switch (e) {
      ValidationException() => 400,
      AuthException() => 401,
      ForbiddenException() => 403,
      NotFoundException() => 404,
      ConflictException() => 409,
      HostUnreachableException() => 503,
      InternalException() => 500,
    };

Response _error(String code, String message, int status) => Response(
      status,
      body: jsonEncode({'error': code, 'message': message}),
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

/// Wide-open CORS — every client is on the same trusted LAN (matches v1's
/// rationale). Also answers preflight so a browser desktop-admin fetch works.
Middleware corsMiddleware() => (Handler inner) {
      return (Request request) async {
        if (request.method == 'OPTIONS') {
          return Response.ok('', headers: _corsHeaders);
        }
        final response = await inner(request);
        return response.change(headers: {...response.headers, ..._corsHeaders});
      };
    };

const _corsHeaders = {
  'access-control-allow-origin': '*',
  'access-control-allow-methods': 'GET, POST, PATCH, DELETE, OPTIONS',
  'access-control-allow-headers': 'authorization, content-type',
};

/// API responses must never be cached (a stale member list or balance is a
/// correctness bug); the static desktop-admin bundle may be cached but must
/// always revalidate, so a rebuilt host serves the new JS immediately.
Middleware cacheControlMiddleware() => (Handler inner) {
      return (Request request) async {
        final response = await inner(request);
        if (response.headers.containsKey('cache-control')) return response;
        final isApi = request.url.path.startsWith('api/');
        return response.change(headers: {
          'cache-control': isApi ? 'no-store' : 'no-cache',
        });
      };
    };

/// The authenticated caller, attached to the request context by
/// [authMiddleware] and read by handlers via [callerOf].
class Caller {
  const Caller(
      {required this.userId, required this.username, required this.role});

  final int userId;
  final String username;
  final Role role;
}

Caller callerOf(Request request) {
  final caller = request.context['caller'];
  if (caller is! Caller) {
    // Programming error — a protected route was mounted without the middleware.
    throw StateError('No caller on request context');
  }
  return caller;
}

/// Requires a valid bearer session and attaches the [Caller] to the request.
/// Does NOT filter by role — handlers call [requireRole] for that, so a single
/// domain sub-router can mix admin-only and shared routes. Sweeps expired
/// sessions opportunistically (no cron), matching v1.
Middleware requireSessionMiddleware(AuthService auth) {
  return (Handler inner) {
    return (Request request) async {
      final header = request.headers[AppConfig.authHeader.toLowerCase()];
      // `?token=` is a fallback for browser file downloads (bill PDF / QR
      // image opened in a new tab), where a request header can't be set.
      final token = _bearer(header) ?? request.url.queryParameters['token'];
      final Session session = await auth.requireSession(token);
      unawaited(auth.sweepExpired());
      return inner(request.change(context: {
        'caller': Caller(
          userId: session.userId,
          username: session.username,
          role: Role.fromWire(session.role),
        ),
      }));
    };
  };
}

/// Throws [ForbiddenException] unless the authenticated caller's role is in
/// [allowed]. Call at the top of a protected handler.
Caller requireRole(Request request, Set<Role> allowed) {
  final caller = callerOf(request);
  if (!allowed.contains(caller.role)) {
    throw ForbiddenException(
      "Your role (${caller.role.wire}) doesn't have access to this action.",
    );
  }
  return caller;
}

const rolesAll = {Role.admin, Role.counter, Role.scanner};
const rolesBilling = {Role.admin, Role.counter};
const rolesAdmin = {Role.admin};

String? _bearer(String? header) {
  if (header == null) return null;
  final parts = header.split(' ');
  if (parts.length == 2 && parts.first.toLowerCase() == 'bearer') {
    return parts.last;
  }
  return header; // tolerate a bare token
}

void unawaited(Future<void> future) {
  // Deliberately fire-and-forget; failures are logged inside the future.
  future.catchError((Object e, StackTrace st) {
    _log.warning('background task failed', e, st);
  });
}
