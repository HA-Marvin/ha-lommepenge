// Forbindelsen til Home Assistant: links, signatur og AppState mod en
// falsk Lommepenge-integration (en lokal HttpServer).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lommepenge_app/db/database_helper.dart';
import 'package:lommepenge_app/providers/app_state.dart';
import 'package:lommepenge_app/repositories/task_repository.dart';
import 'package:lommepenge_app/services/crypto_service.dart';
import 'package:lommepenge_app/services/ha_client.dart';
import 'package:lommepenge_app/services/settings_service.dart';

/// En falsk Lommepenge-integration: parring, signerede kald og roller.
class FakeHa {
  late HttpServer server;
  final devices = <String, ({String key, String role, String? childId})>{};
  final tokens = <String, ({String role, String? childId})>{};
  final actions = <Map<String, dynamic>>[];
  final client = HaClient();
  Map<String, dynamic>? appUpdate;
  int stateRequests = 0;

  Uri get baseUrl => Uri.parse('http://127.0.0.1:${server.port}');

  String installLink(String token) => '$baseUrl/api/lommepenge/install/$token';

  Map<String, dynamic> state(String role, String? childId) => {
        'familyName': 'Familien',
        'children': [
          {'id': 'emma', 'name': 'Emma', 'sortOrder': 0, 'createdAt': '2026-11-01T10:00:00.000'},
          if (role != 'child')
            {'id': 'oskar', 'name': 'Oskar', 'sortOrder': 1, 'createdAt': '2026-11-01T10:00:00.000'},
        ],
        'tasks': [],
        'completions': [],
        'balanceAdjustments': [],
        'paidOutOreByChild': {},
        'familySettings': {'defaultDueTime': '17:30'},
        'restrictionSuspensions': {},
        'device': {'id': 'd', 'name': 'Enhed', 'role': role, 'childId': childId},
        'appUpdate': appUpdate,
        if (role != 'child') 'pinHash': CryptoService.hashPin('2468', 'salt'),
        if (role != 'child') 'pinSalt': 'salt',
      };

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(_handle);
  }

  Future<void> _handle(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    final path = request.uri.path;
    final response = request.response..headers.contentType = ContentType.json;
    if (path == '/api/lommepenge/pair') {
      final token = (jsonDecode(body) as Map)['token'];
      final pairing = tokens.remove(token);
      if (pairing == null) {
        response.statusCode = 410;
        response.write(jsonEncode({'error': 'Linket er udløbet.'}));
      } else {
        final id = 'dev-${devices.length}';
        devices[id] = (key: 'key-$id', role: pairing.role, childId: pairing.childId);
        response.write(jsonEncode({
          'deviceId': id,
          'deviceKey': 'key-$id',
          'role': pairing.role,
          'childId': pairing.childId,
          'deviceName': 'Enhed',
          'familyName': 'Familien',
        }));
      }
      await response.close();
      return;
    }
    final device = devices[request.headers.value('X-Device-Id')];
    final connection = device == null
        ? null
        : HaConnection(
            baseUrl: baseUrl,
            deviceId: request.headers.value('X-Device-Id')!,
            key: device.key,
          );
    final expected = connection == null
        ? null
        : client.signedHeaders(
            connection,
            request.method,
            path,
            utf8.encode(body),
            now: DateTime.fromMillisecondsSinceEpoch(
              int.parse(request.headers.value('X-Timestamp')!) * 1000,
            ),
          )['X-Signature'];
    if (device == null || expected != request.headers.value('X-Signature')) {
      response.statusCode = 401;
      response.write(jsonEncode({'error': 'Ukendt enhed.'}));
      await response.close();
      return;
    }
    if (path == '/api/lommepenge/action') {
      actions.add(jsonDecode(body) as Map<String, dynamic>);
    } else {
      stateRequests++;
    }
    response.write(jsonEncode(state(device.role, device.childId)));
    await response.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // Testbindingen svarer ellers 400 på al HTTP - her skal appen tale med
    // den falske Home Assistant på localhost.
    HttpOverrides.global = null;
  });

  group('Links fra Home Assistant', () {
    test('QR-koden peger på installationssiden', () {
      final link = parseConnectLink(
        'http://192.168.1.10:8123/api/lommepenge/install/abc123',
      )!;
      expect(link.baseUrl.toString(), 'http://192.168.1.10:8123');
      expect(link.token, 'abc123');
    });

    test('"Åbn appen og forbind" bruger lommepenge://', () {
      final link = parseConnectLink(
        'lommepenge://pair?url=http%3A%2F%2F192.168.1.10%3A8123&token=xyz',
      )!;
      expect(link.baseUrl.toString(), 'http://192.168.1.10:8123');
      expect(link.token, 'xyz');
    });

    test('andre links afvises', () {
      expect(parseConnectLink('https://example.com/noget'), isNull);
      expect(parseConnectLink('lommepenge://pair?token=x'), isNull);
      expect(parseConnectLink('ikke et link'), isNull);
    });
  });

  test('signaturen er den samme som Home Assistants', () {
    // Referenceværdier beregnet med integrationens runtime.sign().
    final client = HaClient();
    final connection = HaConnection(
      baseUrl: Uri.parse('http://ha'),
      deviceId: 'd',
      key: 'nøgle',
    );
    final at = DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000);
    expect(
      client.signedHeaders(
        connection,
        'POST',
        '/api/lommepenge/action',
        utf8.encode('{"type":"x"}'),
        now: at,
      )['X-Signature'],
      '857837c554f57748ff1d7fe579ad4f0d8c3ec773a4aa2e1af479af8f21ecb305',
    );
    expect(
      client.signedHeaders(connection, 'GET', '/api/lommepenge/state', const [],
          now: at)['X-Signature'],
      'c80550d4e77109612b8da883bb9c76cf7ae981417107579d1173f94329da8308',
    );
  });

  group('AppState mod Home Assistant', () {
    late FakeHa ha;
    late DatabaseHelper dbHelper;
    late AppState appState;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      ha = FakeHa();
      await ha.start();
      final settings = await SettingsService.create();
      dbHelper = DatabaseHelper.instance..overridePath = ':memory:';
      await dbHelper.close();
      final repository =
          TaskRepository(databaseHelper: dbHelper, settings: settings);
      appState = AppState(settings: settings, repository: repository);
    });

    tearDown(() async {
      await ha.server.close(force: true);
      await dbHelper.close();
    });

    test('fælles skærm: rolle, data og PIN kommer fra HA', () async {
      ha.tokens['t1'] = (role: 'screen', childId: null);
      expect(await appState.connectWithLink(ha.installLink('t1')), isNull);

      expect(appState.isConnected, isTrue);
      expect(appState.isScreen, isTrue);
      expect(appState.children.map((c) => c.name), ['Emma', 'Oskar']);
      expect(appState.familySettings.defaultDueTime, '17:30');
      expect(appState.verifyPin('2468'), isTrue);
      expect(appState.verifyPin('0000'), isFalse);

      // Linket virker kun én gang.
      expect(
        await appState.connectWithLink(ha.installLink('t1')),
        'Linket er udløbet.',
      );
    });

    test('barnets tablet: ét barn, ingen PIN, kan ikke skifte rolle', () async {
      ha.tokens['t1'] = (role: 'child', childId: 'emma');
      await appState.connectWithLink(ha.installLink('t1'));

      expect(appState.isChildTablet, isTrue);
      expect(appState.boundChild?.name, 'Emma');
      expect(appState.hasPin, isFalse);

      ha.tokens['t2'] = (role: 'screen', childId: null);
      expect(
        await appState.connectWithLink(ha.installLink('t2')),
        contains('Geninstallér'),
      );
      expect(appState.isChildTablet, isTrue);
    });

    test('handlinger sendes signeret til HA', () async {
      ha.tokens['t1'] = (role: 'parent', childId: null);
      await appState.connectWithLink(ha.installLink('t1'));
      await appState.addChild('Ida');
      expect(ha.actions.single['type'], 'add_child');
      expect(ha.actions.single['payload']['name'], 'Ida');
    });

    test('fjernet i HA: enheden glemmer forbindelsen', () async {
      ha.tokens['t1'] = (role: 'parent', childId: null);
      await appState.connectWithLink(ha.installLink('t1'));
      ha.devices.clear();

      await appState.syncNow();
      expect(appState.isConnected, isFalse);
      expect(appState.connectionMessage, contains('fjernet i Home Assistant'));
      expect(appState.hasPin, isFalse);
    });

    test('ny version i HA vises som opdatering', () async {
      ha.appUpdate = {
        'version': '1.1.0',
        'versionCode': 10100,
        'sha256': 'a' * 64,
        'size': 10,
      };
      ha.tokens['t1'] = (role: 'parent', childId: null);
      appState.appVersionCode = 10000;
      await appState.connectWithLink(ha.installLink('t1'));
      expect(appState.availableUpdate?.version, '1.1.0');

      appState.appVersionCode = 10100;
      await appState.syncNow();
      expect(appState.availableUpdate, isNull);
    });
  });
}
