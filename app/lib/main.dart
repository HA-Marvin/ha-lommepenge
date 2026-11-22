import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'db/database_helper.dart';
import 'providers/app_state.dart';
import 'repositories/task_repository.dart';
import 'screens/child_home_screen.dart';
import 'screens/child_tablet_home_screen.dart';
import 'screens/connect_screen.dart';
import 'screens/screen_overview_screen.dart';
import 'services/settings_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Skal ske FØR runApp/noget som helst rører databasen - se
  // DatabaseHelper.initializeFactory().
  DatabaseHelper.initializeFactory();
  runApp(const LommepengeApp());
}

/// Rodwidget. Bygger [AppState] (læser lokale indstillinger + database)
/// og sørger for at [ChangeNotifierProvider] ligger UDENFOR [MaterialApp]
/// - altså over appens eneste [Navigator]. Det er nødvendigt for at alle
/// skærme, også dem der åbnes med `Navigator.push` (fx PIN-skærme og
/// forælder-tilstand), kan tilgå AppState via `context.read`/`watch`.
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
        // Vis fejlen synligt i stedet for at hænge på en spinner for evigt.
        if (snapshot.hasError) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Kunne ikke starte appen:\n${snapshot.error}',
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
          child: MaterialApp(
            title: 'Lommepenge',
            debugShowCheckedModeBanner: false,
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
        );
      },
    );
  }
}

/// Sender brugeren til det rigtige skærmbillede. Rollen kommer fra Home
/// Assistant, hvor enheden blev tilføjet:
///
/// - ikke forbundet endnu → [ConnectScreen] (scan QR-koden fra HA)
/// - fælles skærm → alle børn samlet
/// - barnets tablet → kun det barns opgaver, uden forælder-tilstand
/// - forælders telefon → fælles opgaveliste
class _StartRouter extends StatelessWidget {
  const _StartRouter();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    if (!appState.isConnected) return const ConnectScreen();
    if (appState.isScreen) return const ScreenOverviewScreen();
    if (appState.isChildTablet) return const ChildTabletHomeScreen();
    return const ChildHomeScreen();
  }
}
