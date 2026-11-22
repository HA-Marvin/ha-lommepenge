// The connection to Home Assistant: links, signature, language and AppState
// against a fake Lommepenge integration (a local HttpServer).
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

/// A fake Lommepenge integration: pairing, signed requests and roles.
class FakeHa {
  late HttpServer server;
  final devices = <String, ({String key, String role, String? childId})>{};
  final tokens = <String, ({String role, String? childId})>{};
  final actions = <Map<String, dynamic>>[];
  final languages = <String?>[];
  final client = HaClient();
  Map<String, dynamic>? appUpdate;
  String currency = 'DKK';
  int stateRequests = 0;

  Uri get baseUrl => Uri.parse('http://127.0.0.1:${server.port}');

  String installLink(String token) => '$baseUrl/api/lommepenge/install/$token';

  Map<String, dynamic> state(String role, String? childId) => {
        'familyName': 'The Family',
        'children': [
          {'id': 'emma', 'name': 'Emma', 'sortOrder': 0, 'createdAt': '2026-11-01T10:00:00.000'},
          if (role != 'child')
            {'id': 'oscar', 'name': 'Oscar', 'sortOrder': 1, 'createdAt': '2026-11-01T10:00:00.000'},
        ],
        'tasks': [],
        'completions': [],
        'balanceAdjustments': [],
        'paidOutOreByChild': {},
        'familySettings': {'defaultDueTime': '17:30'},
        'restrictionSuspensions': {},
        'device': {'id': 'd', 'name': 'Device', 'role': role, 'childId': childId},
        'appUpdate': appUpdate,
        'currency': currency,
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
    languages.add(request.headers.value(HaClient.languageHeader));
    final response = request.response..headers.contentType = ContentType.json;
    if (path == '/api/lommepenge/pair') {
      final token = (jsonDecode(body) as Map)['token'];
      final pairing = tokens.remove(token);
      if (pairing == null) {
        response.statusCode = 410;
        response.write(jsonEncode({'error': 'The link has expired.'}));
      } else {
        final id = 'dev-${devices.length}';
        devices[id] = (key: 'key-$id', role: pairing.role, childId: pairing.childId);
        response.write(jsonEncode({
          'deviceId': id,
          'deviceKey': 'key-$id',
          'role': pairing.role,
          'childId': pairing.childId,
          'deviceName': 'Device',
          'familyName': 'The Family',
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
      response.write(jsonEncode({'error': 'Unknown device.'}));
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
    // The test binding otherwise answers 400 to all HTTP - here the app has to
    // talk to the fake Home Assistant on localhost.
    HttpOverrides.global = null;
  });

  group('Links from Home Assistant', () {
    test('the QR code points to the install page', () {
      final link = parseConnectLink(
        'http://192.168.1.10:8123/api/lommepenge/install/abc123',
      )!;
      expect(link.baseUrl.toString(), 'http://192.168.1.10:8123');
      expect(link.token, 'abc123');
    });

    test('"Open the app and connect" uses lommepenge://', () {
      final link = parseConnectLink(
        'lommepenge://pair?url=http%3A%2F%2F192.168.1.10%3A8123&token=xyz',
      )!;
      expect(link.baseUrl.toString(), 'http://192.168.1.10:8123');
      expect(link.token, 'xyz');
    });

    test('code typed by hand: address without scheme and port works', () {
      final link = connectLinkFromCode('192.168.1.10', 'k7m2-qdxa ')!;
      expect(link.baseUrl.toString(), 'http://192.168.1.10:8123');
      expect(link.token, 'K7M2QDXA');
      final https = connectLinkFromCode('https://ha.local:443', 'AB')!.baseUrl;
      expect(https.scheme, 'https');
      expect(https.port, 443);
      expect(connectLinkFromCode('', 'AB'), isNull);
      expect(connectLinkFromCode('192.168.1.10', '  '), isNull);
    });

    test('other links are rejected', () {
      expect(parseConnectLink('https://example.com/something'), isNull);
      expect(parseConnectLink('lommepenge://pair?token=x'), isNull);
      expect(parseConnectLink('not a link'), isNull);
    });
  });

  test("the signature is the same as Home Assistant's", () {
    // Reference values calculated with the integration's runtime.sign()
    // (the key deliberately contains a non-ASCII character).
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

  group('AppState against Home Assistant', () {
    late FakeHa ha;
    late DatabaseHelper dbHelper;
    late SettingsService settings;
    late AppState appState;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      ha = FakeHa();
      await ha.start();
      settings = await SettingsService.create();
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

    test('family screen: role, data and PIN come from HA', () async {
      ha.tokens['t1'] = (role: 'screen', childId: null);
      expect(await appState.connectWithLink(ha.installLink('t1')), isNull);

      expect(appState.isConnected, isTrue);
      expect(appState.isScreen, isTrue);
      expect(appState.children.map((c) => c.name), ['Emma', 'Oscar']);
      expect(appState.familySettings.defaultDueTime, '17:30');
      expect(appState.verifyPin('2468'), isTrue);
      expect(appState.verifyPin('0000'), isFalse);

      // The link only works once; HA's own error message is shown.
      expect(
        await appState.connectWithLink(ha.installLink('t1')),
        'The link has expired.',
      );
    });

    test('connect with code (no camera)', () async {
      ha.tokens['K7M2QDXA'] = (role: 'screen', childId: null);
      final address = '127.0.0.1:${ha.server.port}';
      expect(await appState.connectWithCode(address, 'k7m2qdxa'), isNull);
      expect(appState.isScreen, isTrue);
    });

    test("child's tablet: one child, no PIN, cannot change role", () async {
      ha.tokens['t1'] = (role: 'child', childId: 'emma');
      await appState.connectWithLink(ha.installLink('t1'));

      expect(appState.isChildTablet, isTrue);
      expect(appState.boundChild?.name, 'Emma');
      expect(appState.hasPin, isFalse);

      ha.tokens['t2'] = (role: 'screen', childId: null);
      expect(
        await appState.connectWithLink(ha.installLink('t2')),
        contains('Reinstall'),
      );
      expect(appState.isChildTablet, isTrue);
    });

    test('actions are sent signed to HA', () async {
      ha.tokens['t1'] = (role: 'parent', childId: null);
      await appState.connectWithLink(ha.installLink('t1'));
      await appState.addChild('Ida');
      expect(ha.actions.single['type'], 'add_child');
      expect(ha.actions.single['payload']['name'], 'Ida');
    });

    test('removed in HA: the device forgets the connection', () async {
      ha.tokens['t1'] = (role: 'parent', childId: null);
      await appState.connectWithLink(ha.installLink('t1'));
      ha.devices.clear();

      await appState.syncNow();
      expect(appState.isConnected, isFalse);
      expect(appState.connectionMessage, contains('removed in Home Assistant'));
      expect(appState.hasPin, isFalse);
    });

    test('a new version in HA is shown as an update', () async {
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

    test('the currency comes from HA (DKK until then)', () async {
      expect(appState.currency, 'DKK');
      ha.currency = '€';
      ha.tokens['t1'] = (role: 'parent', childId: null);
      await appState.connectWithLink(ha.installLink('t1'));
      expect(appState.currency, '€');
    });

    test('English until a language is chosen; the choice is kept', () async {
      expect(appState.languageChosen, isFalse);
      expect(appState.language, 'en');

      await appState.setLanguage('de');
      expect(appState.languageChosen, isTrue);
      expect(appState.language, 'de');
      expect(
        await appState.connectWithCode('', ''),
        'Gib die Adresse von Home Assistant und den Code ein.',
      );

      // Forgetting the connection keeps the language.
      await appState.disconnect();
      expect(settings.language, 'de');
    });

    test('the app sends its language to HA', () async {
      await appState.setLanguage('es');
      ha.tokens['t1'] = (role: 'parent', childId: null);
      await appState.connectWithLink(ha.installLink('t1'));
      expect(ha.languages, isNotEmpty);
      expect(ha.languages.toSet(), {'es'});
    });

    test('an existing (connected) installation keeps Danish', () async {
      ha.tokens['t1'] = (role: 'parent', childId: null);
      await appState.connectWithLink(ha.installLink('t1'));
      expect(appState.languageChosen, isFalse);

      // The next start after updating the app.
      final restarted = AppState(settings: settings, repository: appState.repository);
      await restarted.initialize();
      expect(restarted.language, 'da');
      expect(restarted.l10n.connectButton, 'Forbind');
      restarted.dispose();
    });
  });
}
