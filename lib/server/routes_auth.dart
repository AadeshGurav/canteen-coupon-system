import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../core/errors.dart';
import '../core/role.dart';
import '../domain/ops.dart';
import '../services/settings_service.dart';
import 'host_container.dart';
import 'http_json.dart';
import 'middleware.dart';

/// Unauthenticated `/api` routes — login and public branding only.
Router publicRoutes(HostContainer c) {
  final router = Router();

  router.post('/auth/login', (Request request) async {
    final body = await readJsonObject(request);
    final username = (body['username'] as String?)?.trim() ?? '';
    final password = body['password'] as String? ?? '';
    if (username.isEmpty || password.isEmpty) {
      throw const ValidationException('Username and password are required.');
    }
    final user = await c.auth.authenticate(username, password);
    if (user == null) {
      throw const AuthException('Incorrect username or password.');
    }
    final session = await c.auth.createSession(user);
    return jsonOk(
      AuthSession(
        token: session.token,
        username: session.username,
        role: Role.fromWire(session.role),
      ).toJson(),
    );
  });

  // The login screen needs the app name before anyone has a session.
  router.get('/settings/branding', (Request request) async {
    return jsonOk({'appName': await c.settings.readAppName()});
  });

  // Superset of /settings/branding: adds the host's appearance policy, so a
  // client renders the enforced theme on the login screen rather than
  // snapping to it after sign-in. /settings/branding stays for older clients.
  router.get('/settings/appearance', (Request request) async {
    return jsonOk(await c.settings.readPublicAppearance());
  });

  return router;
}

/// Authenticated `/api` routes for auth session ops, settings and users.
/// Ports v1 `routers/auth.py`, `settings.py`, `users.py`.
Router authedAuthRoutes(HostContainer c) {
  final router = Router();

  router.post('/auth/logout', (Request request) async {
    callerOf(request); // any valid session
    final header = request.headers['authorization'];
    final token = header?.split(' ').last;
    if (token != null) await c.auth.deleteSession(token);
    return jsonOk({'success': true});
  });

  router.get('/auth/me', (Request request) {
    final caller = callerOf(request);
    return jsonOk({'username': caller.username, 'role': caller.role.wire});
  });

  router.get('/settings', (Request request) async {
    requireRole(request, rolesBilling);
    return jsonOk((await c.settings.read()).toJson());
  });

  router.get('/settings/timezones', (Request request) {
    requireRole(request, rolesAdmin);
    return jsonList(c.settings.availableTimezones());
  });

  router.patch('/settings', (Request request) async {
    requireRole(request, rolesAdmin);
    final patch = SettingsPatch.fromJson(await readJsonObject(request));
    return jsonOk((await c.settings.update(patch)).toJson());
  });

  router.get('/users', (Request request) async {
    requireRole(request, rolesAdmin);
    return jsonList((await c.users.list()).map((u) => u.toJson()));
  });

  router.post('/users', (Request request) async {
    requireRole(request, rolesAdmin);
    final draft = UserDraft.fromJson(await readJsonObject(request));
    return jsonOk((await c.users.create(draft)).toJson());
  });

  router.patch('/users/<id>', (Request request, String id) async {
    final caller = requireRole(request, rolesAdmin);
    final patch = UserPatch.fromJson(await readJsonObject(request));
    final updated = await c.users.update(
      pathId(id, entity: 'user'),
      patch,
      actingUserId: caller.userId,
    );
    return jsonOk(updated.toJson());
  });

  router.delete('/users/<id>', (Request request, String id) async {
    final caller = requireRole(request, rolesAdmin);
    await c.users.delete(
      pathId(id, entity: 'user'),
      actingUserId: caller.userId,
    );
    return jsonOk({'success': true});
  });

  return router;
}
