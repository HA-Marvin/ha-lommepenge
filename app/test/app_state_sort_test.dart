// Tests for the "what needs doing now" sorting AppState.refreshFromLocal
// applies to the task list within the mandatory/optional groups - see
// AppState._sortByUrgency / _taskSortTuple / _childSortTuple.
//
// Runs without a real Android/iOS platform by using sqflite_common_ffi (the
// same pattern as task_balance_test.dart).
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

    childId = (await repository.addChild('Child 1')).id;
  });

  tearDown(() async {
    await dbHelper.close();
  });

  group('Task sorting ("what needs doing now")', () {
    test(
        'untouched tasks (tier 0) come first, in creation order - an '
        'approved "unlimited" completion today moves the task down to '
        'tier 2', () async {
      final t1 = await repository.createTask(
        title: 'First',
        amountOre: 100,
        recurrence: Recurrence.unlimited,
      );
      final t2 = await repository.createTask(
        title: 'Second',
        amountOre: 100,
        recurrence: Recurrence.unlimited,
      );
      final t3 = await repository.createTask(
        title: 'Third',
        amountOre: 100,
        recurrence: Recurrence.unlimited,
      );

      await appState.refreshFromLocal();
      expect(appState.tasks.map((t) => t.id).toList(),
          [t1.id, t2.id, t3.id]);

      // t2 is marked as done and approved right away - 'unlimited' has no
      // daily cool-down in computeAvailability (it is still "available"),
      // but the sorting must still recognise that t2 has actually been done
      // today and move it down to tier 2, while t1 and t3 stay at the top in
      // their original order.
      await repository.completeTask(t2.id, childId: childId);
      final pending = (await repository.getPendingCompletions())
          .firstWhere((c) => c.taskId == t2.id);
      await repository.approveCompletion(pending.id);

      await appState.refreshFromLocal();
      expect(appState.tasks.map((t) => t.id).toList(),
          [t1.id, t3.id, t2.id]);
    });

    test(
        'a pending approval and a one-off task that has already been '
        'approved are both sorted after an untouched, available task',
        () async {
      final ready = await repository.createTask(
        title: 'Ready to do',
        amountOre: 100,
        recurrence: Recurrence.daily,
      );
      final neverAgain = await repository.createTask(
        title: 'One-off task',
        amountOre: 100,
        recurrence: Recurrence.once,
      );
      final awaitingApproval = await repository.createTask(
        title: 'Awaiting approval',
        amountOre: 100,
        recurrence: Recurrence.daily,
      );

      // 'neverAgain' is done and approved -> completedOnce -> can never
      // become available again (tier 1).
      await repository.completeTask(neverAgain.id, childId: childId);
      final neverAgainCompletion = (await repository.getPendingCompletions())
          .firstWhere((c) => c.taskId == neverAgain.id);
      await repository.approveCompletion(neverAgainCompletion.id);

      // 'awaitingApproval' is done, but NOT approved -> pendingApproval
      // (tier 2, dayOffset 0).
      await repository.completeTask(awaitingApproval.id, childId: childId);

      await appState.refreshFromLocal();

      final order = appState.tasks.map((t) => t.id).toList();
      // 'ready' (tier 0) must come before 'neverAgain' (tier 1), which in
      // turn must come before 'awaitingApproval' (tier 2) - regardless of the
      // order they were created in.
      expect(order.indexOf(ready.id), lessThan(order.indexOf(neverAgain.id)));
      expect(order.indexOf(neverAgain.id),
          lessThan(order.indexOf(awaitingApproval.id)));
    });
  });
}
