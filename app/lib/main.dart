import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'db/database_helper.dart';
import 'l10n/l10n.dart';
import 'providers/app_state.dart';
import 'repositories/task_repository.dart';
import 'screens/child_home_screen.dart';
import 'screens/child_tablet_home_screen.dart';
import 'screens/connect_screen.dart';
import 'screens/language_screen.dart';
import 'screens/screen_overview_screen.dart';
import 'services/settings_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Must happen BEFORE runApp/anything touches the database - see
  // DatabaseHelper.initializeFactory().
  DatabaseHelper.initializeFactory();
  runApp(const LommepengeApp());
}

/// Root widget. Builds [AppState] (reads local settings + database) and makes
/// sure [ChangeNotifierProvider] sits OUTSIDE [MaterialApp] - i.e. above the
/// app's only [Navigator]. That is necessary for all screens, including those
/// opened with `Navigator.push` (e.g. PIN screens and parent mode), to reach
/// AppState via `context.read`/`watch`.
class LommepengeApp extends StatefulWidget {
  const LommepengeApp({super.key});

  @override
  State<LommepengeApp> createState() => _LommepengeAppState();
}

class _LommepengeAppState extends State<LommepengeApp> {
  late final Future<AppState> _future;

  @override
  void initState() {
    super.initState();
    _future = _build();
  }

  Future<AppState> _build() async {
    final settings = await SettingsService.create();
    final repository = TaskRepository(settings: settings);
    final appState = AppState(settings: settings, repository: repository);
    await appState.initialize();
    return appState;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppState>(
      future: _future,
      builder: (context, snapshot) {
        // Show the error visibly instead of hanging on a spinner forever.
        // (Before AppState exists the chosen language is unknown, so English.)
        if (snapshot.hasError) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Could not start the app:\n${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        final appState = snapshot.data!;
        return ChangeNotifierProvider<AppState>.value(
          value: appState,
          // Rebuilds MaterialApp (and thereby every text) when the language
          // changes.
          child: Selector<AppState, String>(
            selector: (_, state) => state.language,
            builder: (context, language, _) => MaterialApp(
              title: 'Lommepenge',
              debugShowCheckedModeBanner: false,
              locale: Locale(language),
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              theme: ThemeData(
                colorSchemeSeed: Colors.teal,
                useMaterial3: true,
                brightness: Brightness.light,
              ),
              darkTheme: ThemeData(
                colorSchemeSeed: Colors.teal,
                useMaterial3: true,
                brightness: Brightness.dark,
              ),
              home: const _StartRouter(),
            ),
          ),
        );
      },
    );
  }
}

/// Sends the user to the right screen. The role comes from Home Assistant,
/// where the device was added:
///
/// - first start → [LanguageScreen] (English is preselected)
/// - not connected yet → [ConnectScreen] (enter the code from HA)
/// - family screen → all children together
/// - child's tablet → only that child's tasks, without parent mode
/// - parent's phone → shared task list
class _StartRouter extends StatelessWidget {
  const _StartRouter();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    if (!appState.languageChosen) return const LanguageScreen();
    if (!appState.isConnected) return const ConnectScreen();
    if (appState.isScreen) return const ScreenOverviewScreen();
    if (appState.isChildTablet) return const ChildTabletHomeScreen();
    return const ChildHomeScreen();
  }
}
