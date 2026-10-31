// Restore keys (backend services/restore_keys.py): the install asks for its
// device's key once, keeps it beside the backed-up device id in plain
// SharedPreferences, and a reinstall that has the id but no token presents it
// at the mint — the server no longer serves a bare known id once it closes
// bare mints (audit H5).

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:almorabbi/api/tg_client.dart';

class _MemStorage implements FlutterSecureStorage {
  final Map<String, String> store = {};

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      store[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      store.remove(key);
    } else {
      store[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    store.remove(key);
  }

  @override
  Future<void> deleteAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    store.clear();
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _id = '6f1c2a9e-3b4d-4c5e-8f70-112233445566';
const _key = 'tgr_00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';

/// A fake server that mints for whatever id it is asked and hands out [_key].
class _Server {
  final mints = <http.Request>[];
  int keyAsks = 0;
  int keyStatus = 200;

  Future<http.Response> handle(http.Request req) async {
    if (req.url.path == '/api/chat/sessions') {
      mints.add(req);
      final id = (jsonDecode(req.body) as Map)['device_id'];
      return http.Response(
          jsonEncode({'session_id': 's${mints.length}', 'token': 'tok${mints.length}',
                      'device_id': id}),
          201,
          headers: {'content-type': 'application/json'});
    }
    if (req.url.path == '/api/chat/restore-key') {
      keyAsks++;
      if (keyStatus != 200) return http.Response('{"detail":{"code":"restore_key_unavailable"}}', keyStatus);
      return http.Response(jsonEncode({'restore_key': _key}), 200,
          headers: {'content-type': 'application/json'});
    }
    return http.Response('{}', 200, headers: {'content-type': 'application/json'});
  }
}

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('after a mint the install asks once and keeps the key beside the backed-up id',
      () async {
    SharedPreferences.setMockInitialValues({});
    final server = _Server();
    final storage = _MemStorage()..store['tg_device_id'] = _id;
    final c = TgClient.forTesting(
        baseUrl: 'http://t', httpClient: MockClient(server.handle), storage: storage);
    await c.createSession();
    await _settle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('tg_device_restore_key'), '$_id $_key');
    expect(server.keyAsks, 1);
    // Held: a later session use does not ask again.
    await c.ensureSession();
    await c.ensureRestoreKey();
    await _settle();
    expect(server.keyAsks, 1);
    // Never in the keystore: the phone backup leaves that out.
    expect(storage.store.values.any((v) => v.contains(_key)), isFalse);
  });

  test('a reinstall with the backed-up id and key, and no token, presents the key',
      () async {
    SharedPreferences.setMockInitialValues({
      'tg_device_id_backup': _id,
      'tg_device_restore_key': '$_id $_key',
    });
    final server = _Server();
    final c = TgClient.forTesting(
        baseUrl: 'http://t', httpClient: MockClient(server.handle), storage: _MemStorage());
    await c.createSession();
    final mint = server.mints.single;
    expect((jsonDecode(mint.body) as Map)['device_id'], _id);
    expect(mint.headers['X-Device-Restore'], _key);
    expect(mint.headers['Authorization'], isNull);
  });

  test('with a token to prove the device the key is not sent', () async {
    SharedPreferences.setMockInitialValues({'tg_device_restore_key': '$_id $_key'});
    final server = _Server();
    final storage = _MemStorage()
      ..store['tg_device_id'] = _id
      ..store['tg_device_proof'] = 'tok-old';
    final c = TgClient.forTesting(
        baseUrl: 'http://t', httpClient: MockClient(server.handle), storage: storage);
    await c.createSession();
    expect(server.mints.single.headers['Authorization'], 'Bearer tok-old');
    expect(server.mints.single.headers['X-Device-Restore'], isNull);
  });

  test('a key saved for another id is never sent', () async {
    SharedPreferences.setMockInitialValues({
      'tg_device_id_backup': _id,
      'tg_device_restore_key': 'another-device-id $_key',
    });
    final server = _Server();
    final c = TgClient.forTesting(
        baseUrl: 'http://t', httpClient: MockClient(server.handle), storage: _MemStorage());
    await c.createSession();
    expect(server.mints.single.headers['X-Device-Restore'], isNull);
  });

  test('a refused key (a bare session) is not asked again in this process', () async {
    SharedPreferences.setMockInitialValues({});
    final server = _Server()..keyStatus = 403;
    final c = TgClient.forTesting(
        baseUrl: 'http://t',
        httpClient: MockClient(server.handle),
        storage: _MemStorage()..store['tg_device_id'] = _id);
    await c.createSession();
    await _settle();
    await c.ensureSession();
    await c.ensureRestoreKey();
    await _settle();
    expect(server.keyAsks, 1);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('tg_device_restore_key'), isNull);
  });

  test('becoming another device drops the old key', () async {
    SharedPreferences.setMockInitialValues({'tg_device_restore_key': '$_id $_key'});
    final server = _Server();
    final c = TgClient.forTesting(
        baseUrl: 'http://t',
        storage: _MemStorage()..store['tg_device_id'] = _id,
        httpClient: MockClient((req) async {
          if (req.url.path == '/api/chat/sessions') {
            // The server moved this install to a new, empty device.
            return http.Response(
                jsonEncode({'session_id': 's', 'token': 'tok',
                            'device_id': '9a8b7c6d-0000-4000-8000-000000000001'}),
                201);
          }
          return server.handle(req);
        }));
    await c.createSession();
    await _settle();
    final prefs = await SharedPreferences.getInstance();
    // The old key is gone; the new device got its own.
    expect(prefs.getString('tg_device_restore_key'),
        '9a8b7c6d-0000-4000-8000-000000000001 $_key');
  });
}
