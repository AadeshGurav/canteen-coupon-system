/// Typed application errors shared by every layer.
///
/// The whole point (PRD §7, CLAUDE.md §8): a failure carries *what* went wrong
/// as a specific type and a human-readable message, never a bare `throw` or a
/// generic 500. The server's error middleware maps each type to an HTTP status
/// (see `server/middleware/error_middleware.dart`); the client's API layer maps
/// the status back to the same type, so host mode and client mode surface an
/// identical error to the UI.
library;

/// Base class for every expected, explainable failure in the system.
///
/// `message` is safe to show a user as-is. `code` is a short stable slug for
/// logs and for the client to switch on without string-matching the message.
sealed class AppException implements Exception {
  const AppException(this.message, {required this.code});

  final String message;
  final String code;

  @override
  String toString() => '$runtimeType($code): $message';
}

/// Input failed a business or schema rule. HTTP 400.
class ValidationException extends AppException {
  const ValidationException(super.message, {super.code = 'validation'});
}

/// The requested record does not exist. HTTP 404.
class NotFoundException extends AppException {
  const NotFoundException(super.message, {super.code = 'not_found'});
}

/// The action conflicts with current state (duplicate key, already-reversed
/// scan, member with history that can't be deleted). HTTP 409.
class ConflictException extends AppException {
  const ConflictException(super.message, {super.code = 'conflict'});
}

/// No valid session, or the session expired. HTTP 401.
class AuthException extends AppException {
  const AuthException(super.message, {super.code = 'unauthenticated'});
}

/// A valid session, but the role isn't allowed this action. HTTP 403.
class ForbiddenException extends AppException {
  const ForbiddenException(super.message, {super.code = 'forbidden'});
}

/// Client mode only: the discovered host stopped answering (PRD §13.2). Distinct
/// from a generic network error so the UI can offer "retry / re-discover"
/// instead of a blank failure.
class HostUnreachableException extends AppException {
  const HostUnreachableException([
    super.message = 'The host device is not responding. It may be offline or on a different network.',
  ]) : super(code: 'host_unreachable');
}

/// A dependency that isn't business logic failed in a way the caller can't fix
/// (PDF engine, cert generation, filesystem). HTTP 500. The message is
/// deliberately vague to the user; the real detail goes to the log.
class InternalException extends AppException {
  const InternalException([
    super.message = 'Something went wrong on the host. Check the host device logs.',
  ]) : super(code: 'internal');
}
