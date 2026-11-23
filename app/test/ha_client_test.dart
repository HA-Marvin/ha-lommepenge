// The connection to Home Assistant: links, signature, language and AppState
// against a fake Lommepenge integration (a local HttpServer) that speaks the
// API in docs/app-api.md.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lommepenge_app/models/child.dart';
import 'package:lommepenge_app/providers/app_state.dart';
import 'package:lommepenge_app/services/crypto_service.dart';
import 'package:lommepenge_app/services/ha_client.dart';
import 'package:lommepenge_app/services/settings_service.dart';

/// How the fake answers actions.
enum ActionMode {
  /// Performs the action and answers with the new state.
  normal,

  /// HA is down: a plain-text 503, nothing is performed.
  down,

  /// HA performs the action, but the answer is lost (plain-text 503).
  answerLost,

  /// HA refuses: 400 with `task_not_available`.
  refuse,
}

/// A fake Lommepenge integration: pairing, signed requests, roles, the state
/// (Del H1), idempotent actions and the history pages.
class FakeHa {
  late HttpServer server;
  final devices = <String, ({String key, String role, String? childId})>{};
  final tokens = <String, ({String role, String? childId})>{};
  final actions = <Map<String, dynamic>>[];
  final languages = <String?>[];

  /// The signed request targets of `/history`, exactly as received.
  final historyRequests = <String>[];
  final client = HaClient();
  Map<String, dynamic>? appUpdate;
  String currency = 'DKK';
  int stateRequests = 0;
  ActionMode actionMode = ActionMode.normal;

  /// How far HA's clock is ahead of the device's. Like the real HA, a
  /// signature more than 5 minutes off is refused with `clock_skew`.
  Duration clockAhead = Duration.zero;
  int clockSkewAnswers = 0;

  /// Answer every signed request with this 401 `code` (without serverTime).
  String? forcedErrorCode;

  final children = <Map<String, dynamic>>[
    {'id': 'emma', 'name': 'Emma', 'balanceOre': 2500, 'earnedThisWeekOre': 1000},
    {'id': 'oscar', 'name': 'Oscar', 'balanceOre': 0, 'earnedThisWeekOre': 0},
  ];

  /// The task entries per child, as HA calculates them.
  final entries = <String, List<Map<String, dynamic>>>{
    'emma': [
      _entry('t1', 'Empty the dishwasher', '2026-11-23', 'available',
          deadline: '2026-11-23T18:00:00.000'),
      _entry('t2', 'Walk the dog', '2026-11-23', 'overdue',
          deadline: '2026-11-23T08:00:00.000'),
      _entry('t3', 'Tidy the room', '2026-11-25', 'upcoming',
          deadline: '2026-11-25T18:00:00.000'),
    ],
    'oscar': [_entry('t1', 'Empty the dishwasher', '2026-11-23', 'available')],
  };

  /// The completions HA knows (by the app's completion id).
  final completions = <String, Map<String, dynamic>>{};

  static Map<String, dynamic> _entry(
    String taskId,
    String title,
    String date,
    String status, {
    String? deadline,
  }) =>
      {
        'taskId': taskId,
        'title': title,
        'description': null,
        'amountOre': 500,
        'recurrence': 'daily',
        'mandatory': deadline != null,
        'startTime': null,
        'dueTime': null,
        'date': date,
        'deadline': deadline,
        'status': status,
        'completionId': null,
        'late': false,
      };

  /// History items: one approved task per child every 10 days, from
  /// 2026-11-23 back to 2026-09-04 (the last 30-day page is 2026-08-26 ..).
  List<Map<String, dynamic>> get historyItems => [
        for (var i = 0; i < 9; i++)
          for (final child in ['emma', 'oscar'])
            {
              'id': '$child-$i',
              'type': i.isEven ? 'approved' : 'missed',
              'at': DateTime(2026, 11, 23)
                      .subtract(Duration(days: 10 * i))
                      .toIso8601String(),
              'childId': child,
              'childName': child == 'emma' ? 'Emma' : 'Oscar',
              'taskId': 't1',
              'taskTitle': 'Empty the dishwasher',
              'amountOre': 500,
              'completedAt': null,
              'late': false,
              'note': null,
            },
      ];

  int get serverTime =>
      DateTime.now().add(clockAhead).millisecondsSinceEpoch ~/ 1000;

  Uri get baseUrl => Uri.parse('http://127.0.0.1:${server.port}');

  String installLink(String token) => '$baseUrl/api/lommepenge/install/$token';

  Map<String, dynamic> state(String role, String? childId) => {
        'familyName': 'The Family',
        'now': '2026-11-23T12:00:00.000',
        'today': '2026-11-23',
        'children': [
          for (final (i, child) in children.indexed)
            if (role != 'child' || child['id'] == childId)
              {
                ...child,
                'sortOrder': i,
                'tasks': entries[child['id']] ?? const [],
              },
        ],
        'currency': currency,
        'device': {'id': 'd', 'name': 'Device', 'role': role, 'childId': childId},
        'appUpdate': appUpdate,
        if (role != 'child') ...{
          'approvals': [
            for (final c in completions.values)
              if (c['status'] == 'pending') c,
          ],
          'tasks': [
            {
              'id': 't1',
              'title': 'Empty the dishwasher',
              'description': null,
              'amountOre': 500,
              'recurrence': 'daily',
              'mandatory': true,
              'activeWeekdays': [1, 2, 3, 4, 5],
              'assignedChildIds': null,
              'startTime': null,
              'dueTime': '17:30',
              'showInCalendar': false,
              'createdAt': '2026-11-01T10:00:00.000',
            },
          ],
          'settings': {
            'defaultDueTime': '17:30',
            'restrictionStart': '15:00',
            'restrictionEnd': '21:00',
            'latePauseMinutes': 10,
            'warningMinutes': 60,
            'winterFromWeek': 43,
            'winterToWeek': 13,
          },
          'pinHash': CryptoService.hashPin('2468', 'salt'),
          'pinSalt': 'salt',
        },
      };

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(_handle);
  }

  void _apply(Map<String, dynamic> action) {
    final payload = action['payload'] as Map<String, dynamic>;
    switch (action['type']) {
      case 'complete_task':
        final id = payload['completionId'] as String;
        // Idempotent: a known completion id changes nothing.
        if (completions.containsKey(id)) return;
        final childEntries = entries[payload['childId']]!;
        final i = childEntries.indexWhere((e) => e['taskId'] == payload['taskId']);
        final entry = childEntries[i];
        completions[id] = {
          'completionId': id,
          'childId': payload['childId'],
          'childName': 'Emma',
          'taskId': payload['taskId'],
          'taskTitle': entry['title'],
          'amountOre': entry['amountOre'],
          'completedAt': '2026-11-23T12:00:00.000',
          'late': entry['status'] == 'overdue',
          'status': 'pending',
        };
        childEntries[i] = {
          ...entry,
          'status': 'awaitingApproval',
          'completionId': id,
          'late': entry['status'] == 'overdue',
        };
      case 'add_child':
        children.add({
          'id': payload['id'],
          'name': payload['name'],
          'balanceOre': 0,
          'earnedThisWeekOre': 0,
        });
    }
  }

  Map<String, dynamic> history(Map<String, String> query, String? ownChild) {
    final before = DateTime.parse(query['before'] ?? '2026-11-24');
    final from = before.subtract(const Duration(days: 30));
    final childId = ownChild ?? query['childId'];
    final types = query['types']?.split(',').toSet();
    final items = historyItems
        .where((i) => childId == null || i['childId'] == childId)
        .where((i) => types == null || types.contains(i['type']))
        .toList();
    String day(DateTime d) => d.toIso8601String().substring(0, 10);
    bool inPage(Map<String, dynamic> i) {
      final at = DateTime.parse(i['at'] as String);
      return !at.isBefore(from) && at.isBefore(before);
    }

    return {
      'from': day(from),
      'before': day(before),
      'items': items.where(inPage).toList(),
      'nextBefore': items.any((i) => DateTime.parse(i['at'] as String).isBefore(from))
          ? day(from)
          : null,
    };
  }

  Future<void> _error(HttpResponse response, int status, Map<String, dynamic> body) async {
    response.statusCode = status;
    response.write(jsonEncode(body));
    await response.close();
  }

  Future<void> _plainText503(HttpResponse response) async {
    response.statusCode = 503;
    response.headers.contentType = ContentType.text;
    response.write('Lommepenge is not set up');
    await response.close();
  }

  Future<void> _handle(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    final path = request.uri.path;
    // The request target exactly as sent - what the app must have signed.
    final target = request.uri.toString();
    languages.add(request.headers.value(HaClient.languageHeader));
    final response = request.response..headers.contentType = ContentType.json;
    if (path == '/api/lommepenge/pair') {
      final token = (jsonDecode(body) as Map)['token'];
      final pairing = tokens.remove(token);
      if (pairing == null) {
        return _error(response, 410, {'error': 'The link has expired.'});
      }
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
            target,
            utf8.encode(body),
            now: DateTime.fromMillisecondsSinceEpoch(
              int.parse(request.headers.value('X-Timestamp')!) * 1000,
            ),
          )['X-Signature'];
    if (device == null || expected != request.headers.value('X-Signature')) {
      return _error(response, 401, {
        'error': 'Unknown device.',
        'code': device == null ? 'device_not_connected' : 'invalid_signature',
        'serverTime': serverTime,
      });
    }
    if (forcedErrorCode != null) {
      return _error(response, 401, {'error': 'Refused.', 'code': forcedErrorCode});
    }
    final timestamp = int.parse(request.headers.value('X-Timestamp')!);
    if ((timestamp - serverTime).abs() > 300) {
      clockSkewAnswers++;
      return _error(response, 401, {
        'error': "The device's clock is wrong, or the request is too old.",
        'code': 'clock_skew',
        'serverTime': serverTime,
      });
    }
    if (path == '/api/lommepenge/history') {
      historyRequests.add(target);
      final asked = request.uri.queryParameters['childId'];
      if (device.role == 'child' && asked != null && asked != device.childId) {
        return _error(response, 403, {
          'error': 'Not allowed.',
          'code': 'forbidden_action',
        });
      }
      response.write(jsonEncode(history(
        request.uri.queryParameters,
        device.role == 'child' ? device.childId : null,
      )));
      await response.close();
      return;
    }
    if (path == '/api/lommepenge/action') {
      final action = jsonDecode(body) as Map<String, dynamic>;
      actions.add(action);
      switch (actionMode) {
        case ActionMode.down:
          return _plainText503(response);
        case ActionMode.answerLost:
          _apply(action);
          return _plainText503(response);
        case ActionMode.refuse:
          return _error(response, 400, {
            'error': 'The task cannot be marked as done right now.',
            'code': 'task_not_available',
          });
        case ActionMode.normal:
          _apply(action);
      }
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

  test('the history query string is built in a fixed order', () {
    expect(HaClient.historyPath(), '/api/lommepenge/history');
    expect(
      HaClient.historyPath(
        before: '2026-10-25',
        childId: 'emma',
        types: ['approved', 'rejected'],
      ),
      '/api/lommepenge/history?before=2026-10-25&childId=emma&types=approved,rejected',
    );
  });

  group('AppState against Home Assistant', () {
    late FakeHa ha;
    late SettingsService settings;
    late AppState appState;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      ha = FakeHa();
      await ha.start();
      settings = await SettingsService.create();
      appState = AppState(settings: settings);
    });

    tearDown(() async {
      await ha.server.close(force: true);
    });

    Future<void> connect(String role, [String? childId]) async {
      ha.tokens['t'] = (role: role, childId: childId);
      expect(await appState.connectWithLink(ha.installLink('t')), isNull);
    }

    TaskEntry entry(String childId, String taskId) => appState
        .childrenById[childId]!.tasks
        .firstWhere((e) => e.taskId == taskId);

    test('family screen: role, data and PIN come from HA', () async {
      await connect('screen');

      expect(appState.isConnected, isTrue);
      expect(appState.isScreen, isTrue);
      expect(appState.children.map((c) => c.name), ['Emma', 'Oscar']);
      expect(appState.familySettings.defaultDueTime, '17:30');
      expect(appState.tasks.single.activeWeekdays, [1, 2, 3, 4, 5]);
      expect(appState.verifyPin('2468'), isTrue);
      expect(appState.verifyPin('0000'), isFalse);

      // The link only works once; HA's own error message is shown.
      expect(
        await appState.connectWithLink(ha.installLink('t')),
        'The link has expired.',
      );
    });

    test("the child's task list, balance and week come from HA as they are",
        () async {
      await connect('child', 'emma');
      final emma = appState.boundChild!;
      expect(emma.balanceOre, 2500);
      expect(emma.earnedThisWeekOre, 1000);
      expect(emma.tasks.map((e) => (e.taskId, e.status)), [
        ('t1', TaskEntryStatus.available),
        ('t2', TaskEntryStatus.overdue),
        ('t3', TaskEntryStatus.upcoming),
      ]);
      expect(emma.tasks.first.deadline, DateTime(2026, 11, 23, 18));
      expect(emma.tasks.map((e) => e.canComplete), [true, true, false]);
      expect(appState.today, '2026-11-23');
    });

    test('connect with code (no camera)', () async {
      ha.tokens['K7M2QDXA'] = (role: 'screen', childId: null);
      final address = '127.0.0.1:${ha.server.port}';
      expect(await appState.connectWithCode(address, 'k7m2qdxa'), isNull);
      expect(appState.isScreen, isTrue);
    });

    test("child's tablet: one child, no PIN, cannot change role", () async {
      await connect('child', 'emma');

      expect(appState.isChildTablet, isTrue);
      expect(appState.boundChild?.name, 'Emma');
      expect(appState.children, hasLength(1));
      expect(appState.hasPin, isFalse);

      ha.tokens['t2'] = (role: 'screen', childId: null);
      expect(
        await appState.connectWithLink(ha.installLink('t2')),
        contains('Reinstall'),
      );
      expect(appState.isChildTablet, isTrue);
    });

    test("actions are sent signed and the screen shows HA's answer", () async {
      await connect('parent');
      final requestsBefore = ha.stateRequests;
      await appState.addChild('Ida');
      expect(ha.actions.single['type'], 'add_child');
      expect(ha.actions.single['payload']['name'], 'Ida');
      expect(ha.actions.single['payload']['id'], hasLength(36));
      // Shown from the action's answer, not from a new fetch.
      expect(appState.children.map((c) => c.name), ['Emma', 'Oscar', 'Ida']);
      expect(ha.stateRequests, requestsBefore);
    });

    test('marking a task as done shows the state HA confirmed', () async {
      await connect('child', 'emma');
      final key = AppState.completeKey('emma', 't1');
      final done = appState.completeTask(entry('emma', 't1'), childId: 'emma');
      // A spinner while HA has not answered.
      expect(appState.isBusy(key), isTrue);
      await done;
      expect(appState.isBusy(key), isFalse);

      final payload = ha.actions.single['payload'] as Map<String, dynamic>;
      expect(payload['taskId'], 't1');
      expect(payload['childId'], 'emma');
      expect(payload['completionId'], hasLength(36));
      expect(entry('emma', 't1').status, TaskEntryStatus.awaitingApproval);
      expect(entry('emma', 't1').completionId, payload['completionId']);
    });

    test('no connection: nothing changes and the user is told to try again',
        () async {
      await connect('parent');
      ha.actionMode = ActionMode.down;

      await expectLater(
        appState.completeTask(entry('emma', 't1'), childId: 'emma'),
        throwsA(isA<ActionFailed>()
            .having((e) => e.message, 'message',
                'No connection to Home Assistant – try again')
            .having((e) => e.offline, 'offline', isTrue)),
      );
      expect(entry('emma', 't1').status, TaskEntryStatus.available);
      expect(appState.isBusy(AppState.completeKey('emma', 't1')), isFalse);

      await expectLater(appState.addChild('Ida'), throwsA(isA<ActionFailed>()));
      expect(appState.children.map((c) => c.name), ['Emma', 'Oscar']);
      expect(appState.isConnected, isTrue);
    });

    test("HA refuses: HA's message is shown and nothing changes", () async {
      await connect('child', 'emma');
      ha.actionMode = ActionMode.refuse;
      final t1 = entry('emma', 't1');

      await expectLater(
        appState.completeTask(t1, childId: 'emma'),
        throwsA(isA<ActionFailed>()
            .having((e) => e.message, 'message',
                'The task cannot be marked as done right now.')
            .having((e) => e.code, 'code', 'task_not_available')
            .having((e) => e.offline, 'offline', isFalse)),
      );
      expect(entry('emma', 't1').status, TaskEntryStatus.available);
      // HA answered, so the id is used up: the next tap is a new one.
      expect(appState.pendingCompletionId('emma', t1), isNull);
    });

    test('a retry after a lost answer reuses the completion id', () async {
      await connect('child', 'emma');
      final t1 = entry('emma', 't1');
      ha.actionMode = ActionMode.answerLost;

      await expectLater(
        appState.completeTask(t1, childId: 'emma'),
        throwsA(isA<ActionFailed>()),
      );
      // HA registered it, but the app did not get the answer: unchanged.
      expect(entry('emma', 't1').status, TaskEntryStatus.available);
      final firstId = appState.pendingCompletionId('emma', t1);
      expect(firstId, isNotNull);

      // "Try again" on the same entry.
      ha.actionMode = ActionMode.normal;
      await appState.completeTask(entry('emma', 't1'), childId: 'emma');

      final ids = [for (final a in ha.actions) a['payload']['completionId']];
      expect(ids, [firstId, firstId]);
      expect(ha.completions, hasLength(1));
      expect(entry('emma', 't1').status, TaskEntryStatus.awaitingApproval);
      expect(appState.pendingCompletionId('emma', t1), isNull);
    });

    test('a new tap after a confirmed one gets a new completion id', () async {
      await connect('child', 'emma');
      await appState.completeTask(entry('emma', 't1'), childId: 'emma');
      await appState.completeTask(entry('emma', 't2'), childId: 'emma');
      final ids = {for (final a in ha.actions) a['payload']['completionId']};
      expect(ids, hasLength(2));
    });

    test('approvals come from HA and are answered there', () async {
      await connect('parent');
      await appState.completeTask(entry('emma', 't2'), childId: 'emma');
      final approval = appState.approvals.single;
      expect(approval.taskTitle, 'Walk the dog');
      expect(approval.late, isTrue);

      await appState.approveCompletion(approval.completionId);
      expect(ha.actions.last, {
        'type': 'approve_completion',
        'payload': {'completionId': approval.completionId},
      });
    });

    test('history: 30 days per page, "Show older" until nothing is older',
        () async {
      await connect('parent');

      final first = await appState.fetchHistory();
      expect(first.before, '2026-11-24');
      expect(first.from, '2026-10-25');
      // 23/11, 13/11, 3/11 for both children, newest first.
      expect(first.items, hasLength(6));
      expect(first.nextBefore, '2026-10-25');

      final second = await appState.fetchHistory(before: first.nextBefore);
      expect(second.items, hasLength(6));
      final third = await appState.fetchHistory(before: second.nextBefore);
      expect(third.items, hasLength(6));
      expect(third.nextBefore, isNull);

      expect(ha.historyRequests, [
        '/api/lommepenge/history',
        '/api/lommepenge/history?before=2026-10-25',
        '/api/lommepenge/history?before=2026-09-25',
      ]);
    });

    test('history filters are part of the signed query string', () async {
      await connect('parent');
      final page = await appState.fetchHistory(
        childId: 'oscar',
        types: ['missed'],
      );
      expect(ha.historyRequests.single,
          '/api/lommepenge/history?childId=oscar&types=missed');
      expect(page.items.map((i) => (i.childId, i.type)).toSet(),
          {('oscar', 'missed')});
    });

    test("a child's tablet only gets its own child's history", () async {
      await connect('child', 'emma');
      final page = await appState.fetchHistory(childId: 'oscar');
      expect(ha.historyRequests.single,
          '/api/lommepenge/history?childId=emma');
      expect(page.items, isNotEmpty);
      expect(page.items.every((i) => i.childId == 'emma'), isTrue);
    });

    test('history without a connection gives an error, not a page', () async {
      await connect('parent');
      await ha.server.close(force: true);
      await expectLater(
        appState.fetchHistory(),
        throwsA(isA<ActionFailed>().having((e) => e.offline, 'offline', true)),
      );
    });

    test('coming to the foreground fetches the state', () async {
      await connect('parent');
      final before = ha.stateRequests;
      appState.didChangeAppLifecycleState(AppLifecycleState.paused);
      await appState.syncNow();
      expect(ha.stateRequests, before + 1);

      appState.didChangeAppLifecycleState(AppLifecycleState.resumed);
      // syncNow() shares the fetch that is already running.
      await appState.syncNow();
      expect(ha.stateRequests, before + 2);
    });

    test('a failed poll keeps showing the latest state', () async {
      await connect('parent');
      await ha.server.close(force: true);
      await appState.syncNow();
      expect(appState.syncStatus, SyncStatus.offline);
      expect(appState.children.map((c) => c.name), ['Emma', 'Oscar']);
    });

    test('removed in HA: the device forgets the connection', () async {
      await connect('parent');
      ha.devices.clear();

      await appState.syncNow();
      expect(appState.isConnected, isFalse);
      expect(appState.connectionMessage, contains('removed in Home Assistant'));
      expect(appState.hasPin, isFalse);
      expect(appState.children, isEmpty);
    });

    test('a wrong clock is corrected without a new pairing', () async {
      // HA's clock is an hour ahead (or the device's is an hour behind).
      ha.clockAhead = const Duration(hours: 1);
      await connect('parent');

      expect(appState.isConnected, isTrue);
      expect(appState.syncStatus, SyncStatus.connected);
      expect(appState.children.map((c) => c.name), ['Emma', 'Oscar']);
      expect(ha.clockSkewAnswers, 1);
      expect(
        settings.clockOffsetMs,
        closeTo(const Duration(hours: 1).inMilliseconds, 5000),
      );

      // Actions are signed with the corrected time too.
      await appState.addChild('Ida');
      expect(ha.actions.single['payload']['name'], 'Ida');
      expect(ha.clockSkewAnswers, 1);

      // The correction is remembered after a restart.
      final restarted = AppState(settings: settings);
      await restarted.syncNow();
      expect(restarted.syncStatus, SyncStatus.connected);
      expect(ha.clockSkewAnswers, 1);
      restarted.dispose();
    });

    test('only a revoked or invalid key forgets the connection', () async {
      await connect('parent');

      // Other refusals (e.g. a missing timestamp) keep the connection.
      ha.forcedErrorCode = 'missing_timestamp';
      await appState.syncNow();
      expect(appState.isConnected, isTrue);
      expect(appState.syncStatus, SyncStatus.offline);
      expect(appState.syncMessage, 'Refused.');

      ha.forcedErrorCode = 'invalid_signature';
      await appState.syncNow();
      expect(appState.isConnected, isFalse);
      expect(appState.connectionMessage, contains('removed in Home Assistant'));
    });

    test('a new version in HA is shown as an update', () async {
      ha.appUpdate = {
        'version': '1.1.0',
        'versionCode': 10100,
        'sha256': 'a' * 64,
        'size': 10,
      };
      appState.appVersionCode = 10000;
      await connect('parent');
      expect(appState.availableUpdate?.version, '1.1.0');

      appState.appVersionCode = 10100;
      await appState.syncNow();
      expect(appState.availableUpdate, isNull);
    });

    test('the currency comes from HA (DKK until then)', () async {
      expect(appState.currency, 'DKK');
      ha.currency = '€';
      await connect('parent');
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
      await connect('parent');
      expect(ha.languages, isNotEmpty);
      expect(ha.languages.toSet(), {'es'});
    });

    test('an existing (connected) installation keeps Danish', () async {
      await connect('parent');
      expect(appState.languageChosen, isFalse);

      // The next start after updating the app.
      final restarted = AppState(settings: settings);
      await restarted.initialize();
      expect(restarted.language, 'da');
      expect(restarted.l10n.connectButton, 'Forbind');
      restarted.dispose();
    });

    test("the old copy of the family's data is removed at startup", () async {
      SharedPreferences.setMockInitialValues({
        'offline_action_queue': ['{"type":"add_child"}'],
        'paid_out_by_child': '{"emma":500}',
        'family_settings': '{}',
        'language': 'en',
      });
      final old = await SettingsService.create();
      final restarted = AppState(settings: old);
      await restarted.initialize();
      final prefs = await SharedPreferences.getInstance();
      for (final key in SettingsService.obsoleteKeys) {
        expect(prefs.containsKey(key), isFalse, reason: key);
      }
      expect(prefs.getString('language'), 'en');
      restarted.dispose();
    });
  });
}
