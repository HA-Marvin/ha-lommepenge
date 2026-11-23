// The logout timer: on the family screen parent mode closes after 2 minutes
// without a tap; on a parent's phone it stays open.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lommepenge_app/providers/app_state.dart';
import 'package:lommepenge_app/services/settings_service.dart';
import 'package:lommepenge_app/widgets/parent_mode_timeout.dart';

Future<AppState> _appState(String role) async {
  SharedPreferences.setMockInitialValues({'role': role});
  final settings = await SettingsService.create();
  return AppState(settings: settings);
}

/// A start screen with a button that opens a "parent mode" screen, wired up
/// like `main.dart`.
Future<void> _pumpApp(WidgetTester tester, AppState appState) async {
  final navigatorKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(MaterialApp(
    navigatorKey: navigatorKey,
    builder: (context, child) => ParentModeTimeout(
      appState: appState,
      navigatorKey: navigatorKey,
      child: child!,
    ),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () {
              appState.enterParentMode();
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    const Scaffold(body: Center(child: Text('Parent mode'))),
              ));
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  expect(find.text('Parent mode'), findsOneWidget);
}

void main() {
  testWidgets('family screen: parent mode closes after 2 minutes without a tap',
      (tester) async {
    final appState = await _appState('screen');
    await _pumpApp(tester, appState);

    await tester.pump(const Duration(minutes: 1, seconds: 50));
    expect(appState.parentModeUnlocked, isTrue);

    // A tap restarts the 2 minutes.
    await tester.tap(find.text('Parent mode'));
    await tester.pump(const Duration(minutes: 1, seconds: 50));
    expect(appState.parentModeUnlocked, isTrue);
    expect(find.text('Parent mode'), findsOneWidget);

    await tester.pump(const Duration(seconds: 15));
    await tester.pumpAndSettle();
    expect(appState.parentModeUnlocked, isFalse);
    expect(find.text('Parent mode'), findsNothing);
    expect(find.text('Open'), findsOneWidget);
    appState.dispose();
  });

  testWidgets("parent's phone: parent mode is not timed out", (tester) async {
    final appState = await _appState('phone');
    await _pumpApp(tester, appState);

    await tester.pump(const Duration(minutes: 30));
    await tester.pumpAndSettle();
    expect(appState.parentModeUnlocked, isTrue);
    expect(find.text('Parent mode'), findsOneWidget);
    appState.exitParentMode();
    appState.dispose();
  });

  testWidgets('leaving parent mode stops the timer', (tester) async {
    final appState = await _appState('screen');
    await _pumpApp(tester, appState);
    var timedOut = false;
    final previous = appState.onParentModeTimedOut;
    appState.onParentModeTimedOut = () {
      timedOut = true;
      previous?.call();
    };

    appState.exitParentMode();
    await tester.pump(const Duration(minutes: 5));
    expect(timedOut, isFalse);
    appState.dispose();
  });
}
