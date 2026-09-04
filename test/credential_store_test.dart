import 'package:tiffin/app/credential_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Saved logins have real branching — keep the password, forget the password,
/// drop a rejected token but keep the account — and getting any of it wrong
/// either strands someone at a login form or leaves a credential behind after
/// they asked for it to go.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  late Map<String, String> backing;
  late CredentialStore store;

  setUp(() {
    backing = {};
    // Stands in for the keychain/keystore, which has no implementation in a
    // test host.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final args = (call.arguments as Map).cast<String, dynamic>();
      switch (call.method) {
        case 'write':
          backing[args['key'] as String] = args['value'] as String;
          return null;
        case 'read':
          return backing[args['key'] as String];
        case 'readAll':
          return backing;
        case 'delete':
          backing.remove(args['key'] as String);
          return null;
        case 'deleteAll':
          backing.clear();
          return null;
        case 'containsKey':
          return backing.containsKey(args['key'] as String);
      }
      return null;
    });
    store = CredentialStore();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> signIn(
    String hostId,
    String username, {
    String? password,
    bool rememberPassword = true,
    String? token,
    Duration validFor = const Duration(hours: 12),
  }) =>
      store.remember(
        hostId: hostId,
        hostName: 'Canteen $hostId',
        baseUrl: 'http://192.168.1.5:8710',
        username: username,
        password: rememberPassword ? password : null,
        forgetPassword: !rememberPassword,
        token: token,
        tokenExpiresAt: DateTime.now().toUtc().add(validFor),
      );

  test('remembers the username but not the password by default', () async {
    await signIn('host-a', 'admin',
        password: 'lunchtime99', rememberPassword: false);

    final login = (await store.read('host-a'))!.loginFor('admin')!;
    expect(login.username, 'admin');
    expect(login.password, isNull,
        reason: 'a password is kept only when explicitly asked for');
  });

  test('keeps the password when asked', () async {
    await signIn('host-a', 'admin', password: 'lunchtime99');
    expect((await store.read('host-a'))!.loginFor('admin')!.password,
        'lunchtime99');
  });

  test('unticking the box forgets a previously saved password', () async {
    await signIn('host-a', 'admin', password: 'lunchtime99');
    await signIn('host-a', 'admin',
        password: 'lunchtime99', rememberPassword: false);

    expect((await store.read('host-a'))!.loginFor('admin')!.password, isNull,
        reason: 'clearing the tick must actively remove it, not just skip it');
  });

  test('keeps several accounts per host, and several hosts', () async {
    await signIn('host-a', 'admin');
    await signIn('host-a', 'counter1');
    await signIn('host-b', 'admin');

    expect((await store.read('host-a'))!.logins.map((l) => l.username),
        containsAll(['admin', 'counter1']));
    expect((await store.readAll()).map((h) => h.hostId),
        containsAll(['host-a', 'host-b']));
  });

  test('the same host is recognised after its address changes', () async {
    await signIn('host-a', 'admin', password: 'lunchtime99');
    // DHCP moves the host; the id is what identifies it.
    await store.remember(
      hostId: 'host-a',
      hostName: 'Canteen host-a',
      baseUrl: 'http://192.168.1.77:8710',
      username: 'admin',
    );

    final host = (await store.read('host-a'))!;
    expect(host.logins, hasLength(1));
    expect(host.baseUrl, 'http://192.168.1.77:8710');
    expect(host.loginFor('admin')!.password, 'lunchtime99');
  });

  test('an expired token is not offered for a silent sign-in', () async {
    await signIn('host-a', 'admin',
        token: 'tok', validFor: const Duration(hours: -1));
    expect((await store.read('host-a'))!.loginFor('admin')!.tokenLooksValid,
        isFalse);
  });

  test('a rejected token is dropped but the account is kept', () async {
    await signIn('host-a', 'admin', password: 'lunchtime99', token: 'tok');
    await store.invalidateToken('host-a', 'admin');

    final login = (await store.read('host-a'))!.loginFor('admin')!;
    expect(login.token, isNull);
    expect(login.password, 'lunchtime99',
        reason: 'a dead token should not cost the one-tap sign-in');
  });

  test('forgetting the last account forgets the host entirely', () async {
    await signIn('host-a', 'admin');
    await store.forgetLogin('host-a', 'admin');
    expect(await store.read('host-a'), isNull);
  });

  test('forgetting one account leaves the others alone', () async {
    await signIn('host-a', 'admin');
    await signIn('host-a', 'counter1');
    await store.forgetLogin('host-a', 'admin');

    final host = (await store.read('host-a'))!;
    expect(host.logins.map((l) => l.username), ['counter1']);
  });

  test('forget-everything clears every host', () async {
    await signIn('host-a', 'admin');
    await signIn('host-b', 'admin');
    await store.forgetEverything();
    expect(await store.readAll(), isEmpty);
  });

  test('a corrupt entry is skipped rather than blocking sign-in', () async {
    await signIn('host-a', 'admin');
    backing['host:broken'] = 'not json at all';

    expect(await store.read('broken'), isNull);
    expect((await store.readAll()).map((h) => h.hostId), ['host-a']);
  });
}
