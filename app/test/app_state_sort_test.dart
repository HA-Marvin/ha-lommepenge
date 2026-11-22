// Tests for den "hvad skal gøres nu"-sortering AppState.refreshFromLocal
// laver af opgavelisten inden i mandatory/valgfri-grupperne - se
// AppState._sortByUrgency / _taskSortTuple / _childSortTuple.
//
// Kører uden en rigtig Android/iOS-platform ved at bruge
// sqflite_common_ffi (samme mønster som task_balance_test.dart).
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lommepenge_app/db/database_helper.dart';
import 'package:lommepenge_app/models/task.dart';
import 'package:lommepenge_app/providers/app_state.dart';
import 'package:lommepenge_app/repositories/task_repository.dart';
import 'package:lommepenge_app/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late TaskRepository repository;
  late DatabaseHelper dbHelper;
  late AppState appState;
  late String childId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsService.create();

    dbHelper = DatabaseHelper.instance
      ..overridePath = ':memory:';
    await dbHelper.close();

    repository = TaskRepository(databaseHelper: dbHelper, settings: settings);
    appState = AppState(settings: settings, repository: repository);

    childId = (await repository.addChild('Barn 1')).id;
  });

  tearDown(() async {
    await dbHelper.close();
  });

  group('Opgave-sortering ("hvad skal gøres nu")', () {
    test(
        'uberørte opgaver (tier 0) kommer først, i oprettelsesrækkefølge - '
        'en godkendt "unlimited"-completion i dag flytter opgaven ned på '
        'tier 2', () async {
      final t1 = await repository.createTask(
        title: 'Første',
        amountOre: 100,
        recurrence: Recurrence.unlimited,
      );
      final t2 = await repository.createTask(
        title: 'Anden',
        amountOre: 100,
        recurrence: Recurrence.unlimited,
      );
      final t3 = await repository.createTask(
        title: 'Tredje',
        amountOre: 100,
        recurrence: Recurrence.unlimited,
      );

      await appState.refreshFromLocal();
      expect(appState.tasks.map((t) => t.id).toList(),
          [t1.id, t2.id, t3.id]);

      // t2 markeres udført og godkendes med det samme - 'unlimited' har
      // ingen dags-nedkøling i computeAvailability (den er stadig
      // "available"), men den nye sortering skal alligevel genkende at
      // t2 reelt er udført i dag og sende den ned til tier 2, mens t1
      // og t3 bliver liggende øverst i deres oprindelige rækkefølge.
      await repository.completeTask(t2.id, childId: childId);
      final pending = (await repository.getPendingCompletions())
          .firstWhere((c) => c.taskId == t2.id);
      await repository.approveCompletion(pending.id);

      await appState.refreshFromLocal();
      expect(appState.tasks.map((t) => t.id).toList(),
          [t1.id, t3.id, t2.id]);
    });

    test(
        'en afventende godkendelse og en engangsopgave der allerede er '
        'godkendt sorteres begge efter en uberørt, tilgængelig opgave',
        () async {
      final ready = await repository.createTask(
        title: 'Klar til at udføre',
        amountOre: 100,
        recurrence: Recurrence.daily,
      );
      final neverAgain = await repository.createTask(
        title: 'Engangsopgave',
        amountOre: 100,
        recurrence: Recurrence.once,
      );
      final awaitingApproval = await repository.createTask(
        title: 'Afventer godkendelse',
        amountOre: 100,
        recurrence: Recurrence.daily,
      );

      // 'neverAgain' udføres og godkendes -> completedOnce -> kan aldrig
      // blive tilgængelig igen (tier 1).
      await repository.completeTask(neverAgain.id, childId: childId);
      final neverAgainCompletion = (await repository.getPendingCompletions())
          .firstWhere((c) => c.taskId == neverAgain.id);
      await repository.approveCompletion(neverAgainCompletion.id);

      // 'awaitingApproval' udføres, men godkendes IKKE -> pendingApproval
      // (tier 2, dayOffset 0).
      await repository.completeTask(awaitingApproval.id, childId: childId);

      await appState.refreshFromLocal();

      final order = appState.tasks.map((t) => t.id).toList();
      // 'ready' (tier 0) skal ligge før 'neverAgain' (tier 1), som igen
      // skal ligge før 'awaitingApproval' (tier 2) - uanset hvilken
      // rækkefølge de blev oprettet i.
      expect(order.indexOf(ready.id), lessThan(order.indexOf(neverAgain.id)));
      expect(order.indexOf(neverAgain.id),
          lessThan(order.indexOf(awaitingApproval.id)));
    });
  });
}
