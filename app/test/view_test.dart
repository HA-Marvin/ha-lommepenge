// The screens as a view of Home Assistant's state: the child's task list is
// rendered from HA's entries, actions show a spinner and change nothing until
// HA confirms, and the history is fetched page by page while it is open.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lommepenge_app/l10n/l10n.dart';
import 'package:lommepenge_app/models/family_settings.dart';
import 'package:lommepenge_app/models/task.dart';
import 'package:lommepenge_app/providers/app_state.dart';
import 'package:lommepenge_app/screens/child_tablet_home_screen.dart';
import 'package:lommepenge_app/screens/history_screen.dart';
import 'package:lommepenge_app/services/ha_client.dart';
import 'package:lommepenge_app/services/settings_service.dart';

Map<String, dynamic> _entry(String taskId, String title, String status,
        {String date = '2026-11-23', String? deadline, String? completionId}) =>
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
      'completionId': completionId,
      'late': false,
    };

Map<String, dynamic> _state(List<Map<String, dynamic>> tasks) => {
      'familyName': 'The Family',
      'now': '2026-11-23T12:00:00.000',
      'today': '2026-11-23',
      'children': [
        {
          'id': 'emma',
          'name': 'Emma',
          'sortOrder': 0,
          'balanceOre': 2500,
          'earnedThisWeekOre': 1000,
          'tasks': tasks,
        },
      ],
      'currency': 'DKK',
      'device': {'id': 'd', 'name': 'Tablet', 'role': 'child', 'childId': 'emma'},
      'appUpdate': null,
    };

/// Answers like Home Assistant without a network. An action waits for
/// [actionAnswer] to be completed, so the spinner can be seen.
class StubHa extends HaClient {
  Map<String, dynamic> state = _state([
    _entry('t1', 'Empty the dishwasher', 'available',
        deadline: '2026-11-23T18:00:00.000'),
    _entry('t2', 'Walk the dog', 'overdue', deadline: '2026-11-23T08:00:00.000'),
    _entry('t3', 'Tidy the room', 'upcoming',
        date: '2026-11-25', deadline: '2026-11-25T18:00:00.000'),
  ]);
  final actions = <Map<String, dynamic>>[];
  Completer<HaResult>? actionAnswer;
  final historyCalls = <({String? before, String? childId, List<String>? types})>[];

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
  }) async {
    historyCalls.add((before: before, childId: childId, types: types));
    Map<String, dynamic> item(String id, String title, String at) => {
          'id': id,
          'type': 'approved',
          'at': at,
          'childId': 'emma',
          'childName': 'Emma',
          'taskId': 't1',
          'taskTitle': title,
          'amountOre': 500,
          'completedAt': at,
          'late': false,
          'note': null,
        };
    if (before == null) {
      return HaResult.ok({
        'from': '2026-10-25',
        'before': '2026-11-24',
        'items': [item('c1', 'Recent task', '2026-11-20T18:00:00.000')],
        'nextBefore': '2026-10-25',
      });
    }
    return HaResult.ok({
      'from': '2026-09-25',
      'before': '2026-10-25',
      'items': [item('c0', 'Old task', '2026-10-01T18:00:00.000')],
      'nextBefore': null,
    });
  }
}

Future<(AppState, StubHa)> _tablet() async {
  SharedPreferences.setMockInitialValues({
    'language': 'en',
    'role': 'child_tablet',
    'bound_child_id': 'emma',
    'ha_url': 'http://ha.local:8123',
    'ha_device_id': 'dev',
    'ha_device_key': 'key',
  });
  final stub = StubHa();
  final appState = AppState(
    settings: await SettingsService.create(),
    client: stub,
  );
  await appState.syncNow();
  return (appState, stub);
}

Future<void> _pump(WidgetTester tester, AppState appState, Widget home) async {
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
  await tester.pumpAndSettle();
}

Finder _doneButtons() => find.ancestor(
      of: find.text('Done'),
      matching: find.byType(ElevatedButton),
    );

void main() {
  testWidgets("the child's tablet shows HA's task entries as they are",
      (tester) async {
    final (appState, _) = await _tablet();
    await _pump(tester, appState, const ChildTabletHomeScreen());

    expect(find.text('Hi Emma!'), findsOneWidget);
    expect(find.text('25 DKK'), findsOneWidget);
    expect(find.text('This week: 10 DKK'), findsOneWidget);
    expect(find.text('Empty the dishwasher'), findsOneWidget);
    expect(find.text('Ready to be done'), findsOneWidget);
    expect(find.text('Deadline 18:00'), findsOneWidget);
    expect(find.text('Overdue - can still be done'), findsOneWidget);
    expect(find.text('Can be done Wed, 11/25'), findsOneWidget);
    expect(find.text('Deadline Wed, 11/25 18:00'), findsOneWidget);

    final buttons = tester.widgetList<ElevatedButton>(_doneButtons()).toList();
    expect(buttons.map((b) => b.onPressed != null), [true, true, false]);
    appState.dispose();
  });

  testWidgets(
      'Done shows a spinner, changes nothing on failure and retries with '
      'the same completion id', (tester) async {
    final (appState, stub) = await _tablet();
    await _pump(tester, appState, const ChildTabletHomeScreen());

    await tester.tap(_doneButtons().first);
    await tester.pump();
    // Waiting for HA: a spinner on the button, which cannot be tapped again.
    final spinner = find.ancestor(
      of: find.byType(CircularProgressIndicator),
      matching: find.byType(ElevatedButton),
    );
    expect(spinner, findsOneWidget);
    expect(tester.widget<ElevatedButton>(spinner).onPressed, isNull);

    stub.actionAnswer!.complete(const HaResult.failure(
      'No connection to Home Assistant – try again',
      offline: true,
    ));
    await tester.pumpAndSettle();
    expect(find.text('No connection to Home Assistant – try again'),
        findsOneWidget);
    expect(find.text('Ready to be done'), findsOneWidget);
    expect(find.text('Waiting for approval'), findsNothing);

    // "Try again" sends the same completion id; HA confirms this time.
    await tester.tap(find.text('Try again'));
    await tester.pump();
    final id = stub.actions.first['payload']['completionId'];
    expect(stub.actions.last['payload']['completionId'], id);
    stub.state = _state([
      _entry('t1', 'Empty the dishwasher', 'awaitingApproval',
          deadline: '2026-11-23T18:00:00.000', completionId: id as String),
    ]);
    stub.actionAnswer!.complete(HaResult.ok(stub.state));
    await tester.pumpAndSettle();

    expect(find.text('Waiting for approval'), findsOneWidget);
    expect(find.text('Sent for approval!'), findsOneWidget);
    expect(stub.actions, hasLength(2));
    appState.dispose();
  });

  testWidgets("the child's tablet opens its own history, 30 days at a time",
      (tester) async {
    final (appState, stub) = await _tablet();
    await _pump(tester, appState, const ChildTabletHomeScreen());

    await tester.tap(find.byTooltip('History'));
    await tester.pumpAndSettle();
    expect(find.text('Recent task'), findsOneWidget);
    expect(find.text('Old task'), findsNothing);

    await tester.tap(find.text('Show older'));
    await tester.pumpAndSettle();
    expect(find.text('Recent task'), findsOneWidget);
    expect(find.text('Old task'), findsOneWidget);
    expect(find.text('Show older'), findsNothing);
    expect(stub.historyCalls.map((c) => (c.before, c.childId)), [
      (null, 'emma'),
      ('2026-10-25', 'emma'),
    ]);
    // No filters on the child's tablet.
    expect(find.byType(FilterChip), findsNothing);

    // Closing the history drops it; opening it again fetches it again.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(HistoryScreen), findsNothing);
    await tester.tap(find.byTooltip('History'));
    await tester.pumpAndSettle();
    expect(stub.historyCalls, hasLength(3));
    expect(find.text('Old task'), findsNothing);
    appState.dispose();
  });

  testWidgets('parent history can be filtered by type', (tester) async {
    final (appState, stub) = await _tablet();
    // The parent view (no fixed child).
    await _pump(tester, appState, const Scaffold(body: HistoryScreen(embedded: true)));
    expect(stub.historyCalls.single.types, isNull);

    await tester.tap(find.widgetWithText(FilterChip, 'Missed'));
    await tester.pumpAndSettle();
    expect(stub.historyCalls.last.types, ['missed']);
    expect(stub.historyCalls.last.before, isNull);
    appState.dispose();
  });

  group('Models', () {
    test('a task normalizes "every day" and "all children" to null', () {
      final task = Task(
        id: 't',
        title: 'x',
        amountOre: 0,
        recurrence: Recurrence.daily,
        activeWeekdays: [1, 2, 3, 4, 5, 6, 7],
        assignedChildIds: [],
        dueTime: '7:5',
      );
      expect(task.activeWeekdays, isNull);
      expect(task.assignedChildIds, isNull);
      expect(task.dueTime, '07:05');
      expect(
        Task(
          id: 't',
          title: 'x',
          amountOre: 0,
          recurrence: Recurrence.daily,
          activeWeekdays: [3, 1, 3],
        ).activeWeekdays,
        [1, 3],
      );
    });

    test("a one-off task's payload has no week plan; null clears values", () {
      final payload = Task(
        id: 't',
        title: 'x',
        amountOre: 500,
        recurrence: Recurrence.once,
        activeWeekdays: [1],
      ).toPayload();
      expect(payload['activeWeekdays'], isNull);
      expect(payload.containsKey('dueTime'), isTrue);
      expect(payload['dueTime'], isNull);
      expect(payload['recurrence'], 'once');
    });

    test('family settings fall back to the default for invalid values', () {
      final s = FamilySettings.fromJson({
        'defaultDueTime': '7:30',
        'latePauseMinutes': 999,
        'warningMinutes': 30,
        'restrictionStart': '15:00',
      });
      expect(s.defaultDueTime, '07:30');
      expect(s.latePauseMinutes, FamilySettings.defaults.latePauseMinutes);
      expect(s.warningMinutes, 30);
    });
  });
}
