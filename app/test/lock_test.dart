// Locks, pause and the child's notifications (Del H3/H4): HA's state is
// parsed defensively, the countdown is counted down locally from HA's time,
// the tablet shows the lock per type and the notifications, and parents can
// lift a lock, pause a child and reject with a reason - each confirmed by HA.
// Del H5: "Approve all", a parent's phone opens parent mode without a PIN
// (only the family screen has the PIN and the logout timer), and the child's
// tablet has no parent functions.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lommepenge_app/l10n/l10n.dart';
import 'package:lommepenge_app/models/child.dart';
import 'package:lommepenge_app/models/family_settings.dart';
import 'package:lommepenge_app/models/history.dart';
import 'package:lommepenge_app/models/lock.dart';
import 'package:lommepenge_app/providers/app_state.dart';
import 'package:lommepenge_app/screens/child_home_screen.dart';
import 'package:lommepenge_app/screens/child_tablet_home_screen.dart';
import 'package:lommepenge_app/screens/history_screen.dart';
import 'package:lommepenge_app/screens/parent_home_screen.dart';
import 'package:lommepenge_app/screens/pin_entry_screen.dart';
import 'package:lommepenge_app/screens/screen_overview_screen.dart';
import 'package:lommepenge_app/services/crypto_service.dart';
import 'package:lommepenge_app/services/ha_client.dart';
import 'package:lommepenge_app/services/settings_service.dart';
import 'package:lommepenge_app/widgets/lock_view.dart';

const _reasonText = 'Missing: Empty the dishwasher (due 18:00)';

Map<String, dynamic> _runningLock() => {
      'status': 'running',
      'reason': _reasonText,
      'reasons': [
        {
          'kind': 'overdue',
          'taskId': 't1',
          'taskTitle': 'Empty the dishwasher',
          'date': '2026-11-23',
          'deadline': '2026-11-23T18:00:00.000',
          'reason': null,
          'absorbed': false,
        },
      ],
      'minutes': 60,
      'pendingSince': '2026-11-23T18:00:30.000',
      'pendingUntil': null,
      'startedAt': '2026-11-23T18:20:00.000',
      'endsAt': '2026-11-23T19:20:00.000',
    };

Map<String, dynamic> _pendingLock() => {
      'status': 'pending',
      'reason': _reasonText,
      'reasons': const [],
      'minutes': 60,
      'pendingSince': '2026-11-23T18:00:30.000',
      'pendingUntil': '2026-11-24T18:00:30.000',
      'startedAt': null,
      'endsAt': null,
    };

Map<String, dynamic> _child({
  Map<String, dynamic>? lock,
  bool paused = false,
  String? pausedUntil,
  List<Object>? notifications,
}) =>
    {
      'id': 'emma',
      'name': 'Emma',
      'sortOrder': 0,
      'balanceOre': 2500,
      'earnedThisWeekOre': 1000,
      'tasks': const [],
      'lock': lock ?? {'status': 'none', 'reasons': const []},
      'paused': paused,
      'pausedUntil': pausedUntil,
      if (notifications != null) 'notifications': notifications,
    };

Map<String, dynamic> _state(Map<String, dynamic> child, {String role = 'child'}) => {
      'familyName': 'The Family',
      'now': '2026-11-23T18:20:00.000',
      'today': '2026-11-23',
      'children': [child],
      'currency': 'DKK',
      'device': {
        'id': 'd',
        'name': 'Device',
        'role': role,
        if (role == 'child') 'childId': 'emma',
      },
      'appUpdate': null,
      if (role != 'child') ...{
        'approvals': [
          {
            'completionId': 'c1',
            'childId': 'emma',
            'childName': 'Emma',
            'taskId': 't1',
            'taskTitle': 'Empty the dishwasher',
            'amountOre': 500,
            'completedAt': '2026-11-23T18:10:00.000',
            'late': true,
          },
        ],
        'tasks': const [],
        'settings': {'defaultDueTime': '18:00', 'lockMinutes': 45},
      },
      // Only the family screen gets the PIN (Del H5).
      if (role == 'screen') ...{
        'pinHash': CryptoService.hashPin('2468', 'salt'),
        'pinSalt': 'salt',
      },
    };

Map<String, dynamic> _approval(String id, String title) => {
      'completionId': id,
      'childId': 'emma',
      'childName': 'Emma',
      'taskId': 't-$id',
      'taskTitle': title,
      'amountOre': 500,
      'completedAt': '2026-11-23T18:10:00.000',
      'late': false,
    };

/// Answers like Home Assistant without a network; an action waits for
/// [actionAnswer].
class StubHa extends HaClient {
  StubHa(this.state);

  Map<String, dynamic> state;
  final actions = <Map<String, dynamic>>[];
  Completer<HaResult>? actionAnswer;

  @override
  Future<HaResult> fetchState(HaConnection connection) async =>
      HaResult.ok(state);

  @override
  Future<HaResult> sendAction(
    HaConnection connection,
    Map<String, dynamic> action,
  ) {
    actions.add(action);
    actionAnswer = Completer<HaResult>();
    return actionAnswer!.future;
  }

  @override
  Future<HaResult> fetchHistory(
    HaConnection connection, {
    String? before,
    String? childId,
    List<String>? types,
  }) async =>
      const HaResult.ok({
        'from': '2026-10-25',
        'before': '2026-11-24',
        'items': [
          {
            'id': 'lock1-started',
            'type': 'lock',
            'at': '2026-11-23T18:20:00.000',
            'childId': 'emma',
            'childName': 'Emma',
            'taskId': null,
            'taskTitle': null,
            'amountOre': 0,
            'completedAt': null,
            'late': false,
            'note': _reasonText,
            'lockEvent': 'started',
            'minutes': 60,
            'reasons': [],
          },
        ],
        'nextBefore': null,
      });
}

Future<(AppState, StubHa)> _appState(
  Map<String, dynamic> child, {
  String role = 'child',
}) async {
  SharedPreferences.setMockInitialValues({
    'language': 'en',
    'role': role == 'child'
        ? 'child_tablet'
        : role == 'parent'
            ? 'phone'
            : 'screen',
    if (role == 'child') 'bound_child_id': 'emma',
    'ha_url': 'http://ha.local:8123',
    'ha_device_id': 'dev',
    'ha_device_key': 'key',
  });
  final stub = StubHa(_state(child, role: role));
  final appState = AppState(
    settings: await SettingsService.create(),
    client: stub,
  );
  await appState.syncNow();
  return (appState, stub);
}

/// Pumps [home]. With a running lock the countdown ticks every second, so
/// the screen never "settles" - then only a few frames are pumped.
Future<void> _pump(
  WidgetTester tester,
  AppState appState,
  Widget home, {
  bool settle = true,
}) async {
  await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
    value: appState,
    child: MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: home,
    ),
  ));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  group('Parsing', () {
    test("a child's lock, pause and notifications are read from HA's state",
        () {
      final child = Child.fromJson(_child(
        lock: _runningLock(),
        paused: true,
        pausedUntil: '2026-12-01',
        notifications: [
          {
            'id': 'n1',
            'type': 'lockStarted',
            'at': '2026-11-23T18:20:00.000',
            'reason': _reasonText,
            'minutes': 60,
            'endsAt': '2026-11-23T19:20:00.000',
            'message': 'The tablet is locked for 60 minutes.',
          },
          {'id': 'broken'}, // no time: skipped
          'not an object',
          {
            'id': 'n0',
            'type': 'rejected',
            'at': '2026-11-23T17:00:00.000',
            'taskTitle': 'Tidy up',
            'reason': 'Not done properly',
            'message': 'Tidy up was rejected: Not done properly',
          },
        ],
      ));
      final lock = child.lock;
      expect(lock.status, LockStatus.running);
      expect(lock.isRunning, isTrue);
      expect(lock.reason, _reasonText);
      expect(lock.minutes, 60);
      expect(lock.endsAt, DateTime(2026, 11, 23, 19, 20));
      expect(lock.reasons.single.kind, 'overdue');
      expect(lock.reasons.single.deadline, DateTime(2026, 11, 23, 18));
      expect(lock.type, LockType.inApp);
      expect(child.paused, isTrue);
      expect(child.pausedUntil, '2026-12-01');
      expect(child.notifications.map((n) => n.id), ['n1', 'n0']);
      expect(child.notifications.first.type, 'lockStarted');
      expect(child.notifications.first.minutes, 60);
      expect(child.notifications.last.reason, 'Not done properly');
    });

    test('anything unreadable is "no lock", not paused, no notifications', () {
      for (final raw in <Object?>[
        null,
        'running',
        {'status': 'overlay-of-the-future'},
        {'status': 'none'},
      ]) {
        final child = Child.fromJson({'id': 'x', 'name': 'X', 'lock': raw});
        expect(child.lock.isNone, isTrue, reason: '$raw');
        expect(child.paused, isFalse);
        expect(child.pausedUntil, isNull);
        expect(child.notifications, isEmpty);
      }
      // A running lock without an end cannot be counted down.
      expect(
        ChildLock.fromJson({'status': 'running', 'endsAt': null}).isRunning,
        isFalse,
      );
    });

    test('a forfeited task entry is read', () {
      final entry = TaskEntry.tryParse({
        'taskId': 't1',
        'title': 'Walk the dog',
        'amountOre': 0,
        'recurrence': 'daily',
        'date': '2026-11-23',
        'status': 'overdue',
        'forfeited': true,
      })!;
      expect(entry.forfeited, isTrue);
    });

    test('lockMinutes is a family setting (1-480)', () {
      expect(FamilySettings.fromJson({'lockMinutes': 30}).lockMinutes, 30);
      expect(FamilySettings.fromJson({'lockMinutes': 0}).lockMinutes, 60);
      expect(FamilySettings.fromJson({'lockMinutes': 481}).lockMinutes, 60);
      expect(FamilySettings.defaults.toJson()['lockMinutes'], 60);
    });

    test('a lock history item is read', () {
      final item = HistoryItem.tryParse({
        'id': 'l-ended',
        'type': 'lock',
        'at': '2026-11-23T19:20:00.000',
        'lockEvent': 'ended',
        'minutes': 60,
        'note': _reasonText,
      })!;
      expect(item.lockEvent, 'ended');
      expect(item.minutes, 60);
      expect(historyTypes, contains('lock'));
    });
  });

  group('Countdown', () {
    final lock = ChildLock.fromJson(_runningLock());
    final serverNow = DateTime(2026, 11, 23, 18, 20);
    // The tablet's own clock is wildly wrong - only the time that has passed
    // on it counts.
    final receivedAt = DateTime(2001, 1, 1, 12);

    test('is endsAt - HA\'s now, minus the time since the state arrived', () {
      expect(
        lockRemaining(lock,
            serverNow: serverNow, receivedAt: receivedAt, deviceNow: receivedAt),
        const Duration(hours: 1),
      );
      expect(
        lockRemaining(lock,
            serverNow: serverNow,
            receivedAt: receivedAt,
            deviceNow: receivedAt.add(const Duration(minutes: 10, seconds: 5))),
        const Duration(minutes: 49, seconds: 55),
      );
    });

    test('never goes below zero or up when the clock jumps back', () {
      expect(
        lockRemaining(lock,
            serverNow: serverNow,
            receivedAt: receivedAt,
            deviceNow: receivedAt.add(const Duration(hours: 2))),
        Duration.zero,
      );
      expect(
        lockRemaining(lock,
            serverNow: serverNow,
            receivedAt: receivedAt,
            deviceNow: receivedAt.subtract(const Duration(minutes: 5))),
        const Duration(hours: 1),
      );
    });

    test('is null for a lock that does not run', () {
      expect(
        lockRemaining(ChildLock.fromJson(_pendingLock()),
            serverNow: serverNow, receivedAt: receivedAt, deviceNow: receivedAt),
        isNull,
      );
      expect(
        lockRemaining(lock,
            serverNow: null, receivedAt: receivedAt, deviceNow: receivedAt),
        isNull,
      );
    });

    test('is shown as m:ss or h:mm:ss', () {
      expect(formatCountdown(const Duration(minutes: 9, seconds: 5)), '9:05');
      expect(formatCountdown(const Duration(hours: 1)), '1:00:00');
      expect(formatCountdown(const Duration(seconds: -3)), '0:00');
    });

    test("AppState counts down from HA's time in the latest state", () async {
      final (appState, _) = await _appState(_child(lock: _runningLock()));
      expect(appState.serverNow, serverNow);
      final remaining = appState.lockRemainingFor(
        appState.boundChild!.lock,
        deviceNow: appState.stateReceivedAt.add(const Duration(minutes: 1)),
      );
      expect(remaining, const Duration(minutes: 59));
      appState.dispose();
    });
  });

  group("Child's tablet", () {
    test('every lock type has a view', () {
      for (final type in LockType.values) {
        expect(lockViews.containsKey(type), isTrue, reason: '$type');
      }
    });

    testWidgets('a running lock shows a big countdown with the reason below',
        (tester) async {
      final (appState, _) = await _appState(_child(lock: _runningLock()));
      await _pump(tester, appState, const ChildTabletHomeScreen(),
          settle: false);

      expect(find.byKey(const ValueKey('lock-running')), findsOneWidget);
      expect(find.text('The tablet is locked'), findsOneWidget);
      expect(find.text('Unlocks at 19:20'), findsOneWidget);
      expect(find.text(_reasonText), findsOneWidget);
      final countdown = tester.widget<Text>(
        find.byKey(const ValueKey('lock-countdown')),
      );
      expect(countdown.data, anyOf('1:00:00', '59:59'));
      await tester.pumpWidget(const SizedBox());
      appState.dispose();
    });

    testWidgets('a pending lock shows a calm notice', (tester) async {
      final (appState, _) = await _appState(_child(lock: _pendingLock()));
      await _pump(tester, appState, const ChildTabletHomeScreen());

      expect(find.byKey(const ValueKey('lock-pending')), findsOneWidget);
      expect(find.byKey(const ValueKey('lock-running')), findsNothing);
      expect(find.text('A lock is waiting'), findsOneWidget);
      expect(
        find.textContaining('It lasts 60 minutes and starts the next time'),
        findsOneWidget,
      );
      expect(find.textContaining(_reasonText), findsOneWidget);
      appState.dispose();
    });

    testWidgets('without a lock nothing is shown; a pause is', (tester) async {
      final (appState, _) =
          await _appState(_child(paused: true, pausedUntil: '2026-12-01'));
      await _pump(tester, appState, const ChildTabletHomeScreen());

      expect(find.byKey(const ValueKey('lock-pending')), findsNothing);
      expect(find.byKey(const ValueKey('lock-running')), findsNothing);
      expect(find.text('Paused until 12/1/2026'), findsOneWidget);
      appState.dispose();
    });

    testWidgets('the notifications page lists HA\'s notifications',
        (tester) async {
      final (appState, stub) = await _appState(_child(notifications: [
        {
          'id': 'n2',
          'type': 'forgotten',
          'at': '2026-11-23T19:20:00.000',
          'message': 'You forgot Walk the dog - it gives no money today',
        },
        {
          'id': 'n1',
          'type': 'deadlineWarning',
          'at': '2026-11-23T17:00:00.000',
          'message': 'Remember Walk the dog by 18:00',
        },
      ]));
      await _pump(tester, appState, const ChildTabletHomeScreen());

      await tester.tap(find.byTooltip('Notifications'));
      await tester.pumpAndSettle();
      expect(
        find.text('You forgot Walk the dog - it gives no money today'),
        findsOneWidget,
      );
      expect(find.text('Remember Walk the dog by 18:00'), findsOneWidget);
      expect(find.text('11/23/2026 19:20'), findsOneWidget);
      expect(find.text('No notifications in the last 7 days.'), findsNothing);

      // HA deleted them (7 days): the page follows the state.
      stub.state = _state(_child(notifications: const []));
      await appState.syncNow();
      await tester.pumpAndSettle();
      expect(find.text('No notifications in the last 7 days.'), findsOneWidget);
      appState.dispose();
    });
  });

  group('Family screen and phones', () {
    testWidgets('the family screen shows a running lock and a pause per child',
        (tester) async {
      final (appState, _) = await _appState(
        _child(lock: _runningLock(), paused: true),
        role: 'screen',
      );
      await _pump(tester, appState, const ScreenOverviewScreen(), settle: false);

      expect(
        find.byWidgetPredicate((w) =>
            w is Text && (w.data ?? '').startsWith('Locked · ') &&
            (w.data!.endsWith('1:00:00 left') || w.data!.endsWith('59:59 left'))),
        findsOneWidget,
      );
      expect(find.text('Paused'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      appState.dispose();
    });

    testWidgets('a pending lock is shown as waiting', (tester) async {
      final (appState, _) =
          await _appState(_child(lock: _pendingLock()), role: 'screen');
      await _pump(tester, appState, const ScreenOverviewScreen());
      expect(find.text('Lock waiting'), findsOneWidget);
      appState.dispose();
    });
  });

  group('Parent mode', () {
    Future<(AppState, StubHa)> openTab(
      WidgetTester tester,
      String tab, {
      Map<String, dynamic>? lock,
      bool paused = false,
    }) async {
      final (appState, stub) =
          await _appState(_child(lock: lock, paused: paused), role: 'parent');
      await _pump(tester, appState, const ParentHomeScreen());
      // The tab bar scrolls; the later tabs may be outside the screen.
      await tester.ensureVisible(find.text(tab));
      await tester.pumpAndSettle();
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      return (appState, stub);
    }

    testWidgets('"Lift lock" shows a spinner and changes nothing on failure',
        (tester) async {
      final (appState, stub) =
          await openTab(tester, 'Overview', lock: _pendingLock());
      expect(find.text('Lock waiting'), findsOneWidget);

      await tester.tap(find.text('Lift lock'));
      await tester.pump();
      expect(stub.actions.single, {
        'type': 'lift_lock',
        'payload': {'childId': 'emma'},
      });
      expect(appState.isBusy(AppState.lockKey('emma')), isTrue);
      final button = find.ancestor(
        of: find.text('Lift lock'),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      );
      expect(tester.widget<ButtonStyleButton>(button).onPressed, isNull);

      stub.actionAnswer!.complete(const HaResult.failure(
        'No connection to Home Assistant – try again',
        offline: true,
      ));
      await tester.pumpAndSettle();
      expect(find.text('No connection to Home Assistant – try again'),
          findsOneWidget);
      expect(find.text('Lock waiting'), findsOneWidget);
      expect(appState.isBusy(AppState.lockKey('emma')), isFalse);

      // HA confirms: the lock is gone.
      await tester.tap(find.text('Lift lock'));
      await tester.pump();
      stub.state = _state(_child(), role: 'parent');
      stub.actionAnswer!.complete(HaResult.ok(stub.state));
      await tester.pumpAndSettle();
      expect(find.text('Lock waiting'), findsNothing);
      expect(find.text('Lift lock'), findsNothing);
      appState.dispose();
    });

    testWidgets('pausing asks for an optional end date; resuming does not',
        (tester) async {
      final (appState, stub) = await openTab(tester, 'Overview');

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.text('Pause Emma'), findsOneWidget);
      expect(find.text('No end date'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Pause'));
      await tester.pump();
      expect(stub.actions.single, {
        'type': 'set_pause',
        'payload': {'childId': 'emma', 'paused': true, 'until': null},
      });
      expect(appState.isBusy(AppState.pauseKey('emma')), isTrue);
      // Still not paused until HA has answered.
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

      stub.state = _state(_child(paused: true), role: 'parent');
      stub.actionAnswer!.complete(HaResult.ok(stub.state));
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(stub.actions.last, {
        'type': 'set_pause',
        'payload': {'childId': 'emma', 'paused': false},
      });
      stub.actionAnswer!.complete(const HaResult.failure(
        'Unknown child.',
        code: 'child_not_found',
      ));
      await tester.pumpAndSettle();
      expect(find.text('Unknown child.'), findsOneWidget);
      appState.dispose();
    });

    test('a pause with an end date sends it', () async {
      final (appState, stub) = await _appState(_child(), role: 'parent');
      final done = appState.setPause('emma', paused: true, until: '2026-12-01');
      stub.actionAnswer!.complete(HaResult.ok(stub.state));
      await done;
      expect(stub.actions.single['payload'],
          {'childId': 'emma', 'paused': true, 'until': '2026-12-01'});
      appState.dispose();
    });

    testWidgets('rejecting asks for an optional reason', (tester) async {
      final (appState, stub) = await openTab(tester, 'Approvals');

      await tester.tap(find.byTooltip('Reject'));
      await tester.pumpAndSettle();
      expect(find.text('Reject the task?'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '  Not done properly ');
      await tester.tap(find.widgetWithText(FilledButton, 'Reject'));
      await tester.pump();
      expect(stub.actions.single, {
        'type': 'reject_completion',
        'payload': {'completionId': 'c1', 'reason': 'Not done properly'},
      });
      expect(appState.isBusy(AppState.completionKey('c1')), isTrue);
      stub.actionAnswer!.complete(const HaResult.failure(
        'No connection to Home Assistant – try again',
        offline: true,
      ));
      await tester.pumpAndSettle();
      expect(find.text('No connection to Home Assistant – try again'),
          findsOneWidget);
      expect(find.text('Empty the dishwasher'), findsOneWidget);

      // Without a reason no reason is sent.
      await tester.tap(find.byTooltip('Reject'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Reject'));
      await tester.pump();
      expect(stub.actions.last['payload'], {'completionId': 'c1'});
      stub.actionAnswer!.complete(HaResult.ok(stub.state));
      await tester.pumpAndSettle();
      appState.dispose();
    });

    testWidgets('cancelling the reject dialog sends nothing', (tester) async {
      final (appState, stub) = await openTab(tester, 'Approvals');
      await tester.tap(find.byTooltip('Reject'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(stub.actions, isEmpty);
      appState.dispose();
    });

    testWidgets('the lock duration is a setting', (tester) async {
      final (appState, _) = await openTab(tester, 'Settings');
      expect(find.text('Lock duration'), findsOneWidget);
      expect(find.text('45 min'), findsOneWidget);
      appState.dispose();
    });

    testWidgets('history shows lock items and can be filtered by them',
        (tester) async {
      final (appState, _) = await _appState(_child(), role: 'parent');
      await _pump(
        tester,
        appState,
        const Scaffold(body: HistoryScreen(embedded: true)),
      );
      expect(find.text('Lock started (60 min)'), findsOneWidget);
      expect(find.textContaining(_reasonText), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'Lock'), findsOneWidget);
      expect(historyTypeLabel(l10nFor('en'), 'lock'), 'Lock');
      expect(historyTypeLabel(l10nFor('da'), 'lock'), 'Lås');
      expect(lockEventLabel(l10nFor('en'), 'lifted'), 'Lock lifted');
      appState.dispose();
    });

    testWidgets('a number setting is saved from its dialog', (tester) async {
      final (appState, stub) = await openTab(tester, 'Settings');
      await tester.tap(find.text('Lock duration'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '30');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      // The dialog's closing animation must not use a disposed controller.
      // (The spinner runs until HA answers, so the frames are pumped.)
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsNothing);
      expect(appState.isBusy(AppState.settingKey('lockMinutes')), isTrue);
      expect(stub.actions.single, {
        'type': 'set_setting',
        'payload': {'key': 'lockMinutes', 'value': 30},
      });
      stub.actionAnswer!.complete(HaResult.ok(stub.state));
      await tester.pumpAndSettle();
      appState.dispose();
    });
  });

  group('Approve all (Del H5)', () {
    Future<(AppState, StubHa)> openApprovals(WidgetTester tester) async {
      final (appState, stub) = await _appState(_child(), role: 'parent');
      stub.state = {
        ...stub.state,
        'approvals': [
          _approval('c1', 'Empty the dishwasher'),
          _approval('c2', 'Walk the dog'),
        ],
      };
      await appState.syncNow();
      await _pump(tester, appState, const ParentHomeScreen());
      await tester.tap(find.text('Approvals'));
      await tester.pumpAndSettle();
      return (appState, stub);
    }

    testWidgets('approves exactly the shown list after one confirmation',
        (tester) async {
      final (appState, stub) = await openApprovals(tester);

      await tester.tap(find.text('Approve all'));
      await tester.pumpAndSettle();
      expect(find.text('Approve 2 tasks?'), findsOneWidget);
      expect(find.text("Reject the ones you don't want to approve first."),
          findsOneWidget);

      // A completion that arrives while the dialog is open is not approved
      // unseen.
      stub.state = {
        ...stub.state,
        'approvals': [
          _approval('c1', 'Empty the dishwasher'),
          _approval('c2', 'Walk the dog'),
          _approval('c3', 'Tidy the room'),
        ],
      };
      await appState.syncNow();
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Approve all').last);
      await tester.pump();
      expect(stub.actions.single, {
        'type': 'approve_completions',
        'payload': {
          'completionIds': ['c1', 'c2'],
        },
      });
      // Spinner: the button and every row are busy until HA answers.
      expect(appState.isBusy(AppState.approveAllKey), isTrue);
      final button = find.ancestor(
        of: find.text('Approve all'),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      );
      expect(tester.widget<ButtonStyleButton>(button.first).onPressed, isNull);
      expect(find.byTooltip('Approve'), findsNothing);

      stub.state = {
        ...stub.state,
        'approvals': [_approval('c3', 'Tidy the room')],
      };
      stub.actionAnswer!.complete(HaResult.ok(stub.state));
      await tester.pumpAndSettle();
      expect(find.text('Empty the dishwasher'), findsNothing);
      expect(find.text('Tidy the room'), findsOneWidget);
      expect(appState.isBusy(AppState.approveAllKey), isFalse);
      appState.dispose();
    });

    testWidgets('a failure changes nothing; cancelling sends nothing',
        (tester) async {
      final (appState, stub) = await openApprovals(tester);

      await tester.tap(find.text('Approve all'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(stub.actions, isEmpty);

      await tester.tap(find.text('Approve all'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Approve all').last);
      await tester.pump();
      stub.actionAnswer!.complete(const HaResult.failure(
        'No connection to Home Assistant – try again',
        offline: true,
      ));
      await tester.pumpAndSettle();
      expect(find.text('No connection to Home Assistant – try again'),
          findsOneWidget);
      expect(find.text('Empty the dishwasher'), findsOneWidget);
      expect(find.text('Walk the dog'), findsOneWidget);
      expect(appState.isBusy(AppState.approveAllKey), isFalse);
      appState.dispose();
    });
  });

  group('Who gets parent mode (Del H5)', () {
    testWidgets("a parent's phone opens parent mode without PIN or timer",
        (tester) async {
      final (appState, _) = await _appState(_child(), role: 'parent');
      expect(appState.parentModeNeedsPin, isFalse);
      await _pump(tester, appState, const ChildHomeScreen());

      await tester.tap(find.byTooltip('Parent mode'));
      await tester.pumpAndSettle();
      expect(find.byType(PinEntryScreen), findsNothing);
      expect(find.byType(ParentHomeScreen), findsOneWidget);
      expect(appState.parentModeUnlocked, isTrue);

      await tester.pump(const Duration(minutes: 30));
      expect(appState.parentModeUnlocked, isTrue);
      expect(find.byType(ParentHomeScreen), findsOneWidget);

      await tester.tap(find.byTooltip('Switch to child mode'));
      await tester.pumpAndSettle();
      expect(appState.parentModeUnlocked, isFalse);
      appState.dispose();
    });

    testWidgets('the family screen still asks for the PIN and logs out',
        (tester) async {
      final (appState, _) = await _appState(_child(), role: 'screen');
      expect(appState.parentModeNeedsPin, isTrue);
      await _pump(tester, appState, const ScreenOverviewScreen());

      await tester.tap(find.byTooltip('Parent mode'));
      await tester.pumpAndSettle();
      expect(find.byType(PinEntryScreen), findsOneWidget);
      await tester.enterText(find.byType(TextField), '1111');
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      expect(find.byType(ParentHomeScreen), findsNothing);

      await tester.enterText(find.byType(TextField), '2468');
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      expect(find.byType(ParentHomeScreen), findsOneWidget);
      expect(appState.parentModeUnlocked, isTrue);

      await tester.pump(const Duration(minutes: 2, seconds: 1));
      expect(appState.parentModeUnlocked, isFalse);
      await tester.pumpWidget(const SizedBox());
      appState.dispose();
    });

    testWidgets("the child's tablet has no parent functions", (tester) async {
      final (appState, _) = await _appState(_child(lock: _pendingLock()));
      expect(appState.isChildTablet, isTrue);
      await _pump(tester, appState, const ChildTabletHomeScreen());

      expect(find.byTooltip('Parent mode'), findsNothing);
      for (final text in [
        'Approve all',
        'Approve',
        'Reject',
        'Lift lock',
        'Pause',
        'Approvals',
      ]) {
        expect(find.text(text), findsNothing, reason: text);
        expect(find.byTooltip(text), findsNothing, reason: text);
      }
      expect(find.byType(Switch), findsNothing);
      // HA sends a tablet no approvals and no PIN.
      expect(appState.approvals, isEmpty);
      expect(appState.settings.pinHash, isNull);

      // Even if something tried to open parent mode, it stays closed.
      final context = tester.element(find.byType(ChildTabletHomeScreen));
      await openParentMode(context);
      await tester.pumpAndSettle();
      expect(find.byType(PinEntryScreen), findsNothing);
      expect(find.byType(ParentHomeScreen), findsNothing);
      appState.enterParentMode();
      expect(appState.parentModeUnlocked, isFalse);
      appState.dispose();
    });
  });
}
