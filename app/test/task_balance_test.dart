// Simple unit tests for the data layer: tasks, completions and balance logic.
//
// Runs without a real Android/iOS platform by using sqflite_common_ffi (a
// pure Dart/FFI sqlite implementation) instead of sqflite's normal platform
// channel, and shared_preferences' built-in mock values for settings.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lommepenge_app/db/database_helper.dart';
import 'package:lommepenge_app/logic/recurrence.dart';
import 'package:lommepenge_app/models/completion.dart';
import 'package:lommepenge_app/models/task.dart';
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

  // A fixed test child, created in each test's setUp and used consistently
  // as childId in all calls that require one - see the 'Several children'
  // group below for tests that use several children.
  late String childId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsService.create();

    dbHelper = DatabaseHelper.instance
      ..overridePath = ':memory:';
    // Make sure of a fresh database connection for each test.
    await dbHelper.close();

    repository = TaskRepository(databaseHelper: dbHelper, settings: settings);

    childId = (await repository.addChild('Child 1')).id;
  });

  tearDown(() async {
    await dbHelper.close();
  });

  group('Tasks and approval', () {
    test('create task -> mark as done -> approve -> balance rises correctly',
        () async {
      final task = await repository.createTask(
        title: 'Tidy the bedroom',
        amountOre: 1000, // 10 kr
        recurrence: Recurrence.once,
      );

      expect(await repository.currentBalanceOre(childId: childId), 0);

      final completion =
          await repository.completeTask(task.id, childId: childId);
      expect(completion.status, CompletionStatus.pending);

      // The balance does not rise before approval.
      expect(await repository.currentBalanceOre(childId: childId), 0);

      await repository.approveCompletion(completion.id);

      expect(await repository.currentBalanceOre(childId: childId), 1000);
      expect(await repository.totalEarnedOre(childId: childId), 1000);
    });

    test('a rejected completion does not count in the balance', () async {
      final task = await repository.createTask(
        title: 'Wash up',
        amountOre: 500,
        recurrence: Recurrence.once,
      );
      final completion =
          await repository.completeTask(task.id, childId: childId);
      await repository.rejectCompletion(completion.id);

      expect(await repository.currentBalanceOre(childId: childId), 0);

      final completions = await repository.getAllCompletions();
      expect(completions.single.status, CompletionStatus.rejected);
    });

    test('cannot mark as done again while a completion is waiting', () async {
      final task = await repository.createTask(
        title: 'Vacuum',
        amountOre: 700,
        recurrence: Recurrence.daily,
      );
      await repository.completeTask(task.id, childId: childId);

      expect(
        () => repository.completeTask(task.id, childId: childId),
        throwsA(isA<RepositoryException>()),
      );
    });

    test('mark as paid out resets the earned balance', () async {
      final task = await repository.createTask(
        title: 'Sweep the driveway',
        amountOre: 2000,
        recurrence: Recurrence.once,
      );
      final completion =
          await repository.completeTask(task.id, childId: childId);
      await repository.approveCompletion(completion.id);

      expect(await repository.currentBalanceOre(childId: childId), 2000);

      await repository.markPaidOut(childId: childId);

      expect(await repository.currentBalanceOre(childId: childId), 0);
      expect(repository.settings.paidOutOreFor(childId), 2000);
      // The history (totalEarnedOre) is not changed by a payout.
      expect(await repository.totalEarnedOre(childId: childId), 2000);
    });

    test('a manual balance adjustment (+/-) counts in the balance', () async {
      final task = await repository.createTask(
        title: 'Sweep the driveway',
        amountOre: 1000,
        recurrence: Recurrence.once,
      );
      final completion =
          await repository.completeTask(task.id, childId: childId);
      await repository.approveCompletion(completion.id);

      expect(await repository.currentBalanceOre(childId: childId), 1000);

      await repository.addBalanceAdjustment(
        amountOre: 500,
        note: 'Found a coin in the sofa',
        childId: childId,
      );
      expect(await repository.currentBalanceOre(childId: childId), 1500);

      await repository.addBalanceAdjustment(
        amountOre: -300,
        note: 'Corrected a wrong entry',
        childId: childId,
      );
      expect(await repository.currentBalanceOre(childId: childId), 1200);
      expect(await repository.totalAdjustmentsOre(childId: childId), 200);

      final adjustments = await repository.getAllBalanceAdjustments();
      expect(adjustments.length, 2);
    });

    test('a balance adjustment without a note is an error', () async {
      expect(
        () => repository.addBalanceAdjustment(
          amountOre: 100,
          note: '   ',
          childId: childId,
        ),
        throwsA(isA<RepositoryException>()),
      );
    });

    test('the balance never goes negative, even with a large negative adjustment',
        () async {
      await repository.addBalanceAdjustment(
        amountOre: -5000,
        note: 'Test of the lower limit',
        childId: childId,
      );
      expect(await repository.currentBalanceOre(childId: childId), 0);
    });
  });

  group('Several children', () {
    test(
        'a task without assignedChildIds (null) applies dynamically to ALL '
        'children, including a child created AFTER the task', () async {
      final task = await repository.createTask(
        title: 'Tidy the living room',
        amountOre: 300,
        recurrence: Recurrence.daily,
        // assignedChildIds left out -> null -> "all children".
      );

      // Only the one child from setUp exists so far.
      var resolved = await repository.resolvedChildIdsForTask(task);
      expect(resolved, [childId]);

      // A new child is created AFTER the task was created.
      final secondChild = await repository.addChild('Emma');

      resolved = await repository.resolvedChildIdsForTask(task);
      expect(resolved.toSet(), {childId, secondChild.id});
    });

    test(
        'two different children earn independently of each other on the '
        'same shared task - one does not block the other', () async {
      final secondChild = await repository.addChild('Emma');

      final task = await repository.createTask(
        title: 'Set the table',
        amountOre: 200,
        recurrence: Recurrence.daily,
        assignedChildIds: [childId, secondChild.id],
      );

      // Child 1 does it and is approved.
      final completionA =
          await repository.completeTask(task.id, childId: childId);
      await repository.approveCompletion(completionA.id);

      // Child 1's approved completion must NOT block child 2's own,
      // independent completion of the same task.
      final availabilityForB =
          await repository.availabilityFor(task, secondChild.id);
      expect(availabilityForB, TaskAvailability.available);

      final completionB =
          await repository.completeTask(task.id, childId: secondChild.id);
      await repository.approveCompletion(completionB.id);

      // Each of the two children has earned the amount for their OWN
      // completion, not both together, and on their own balance.
      expect(await repository.currentBalanceOre(childId: childId), 200);
      expect(
        await repository.currentBalanceOre(childId: secondChild.id),
        200,
      );
      expect(await repository.totalEarnedOre(childId: childId), 200);
      expect(await repository.totalEarnedOre(childId: secondChild.id), 200);

      // Child 1 is now "doneToday" (daily task, approved today), while
      // child 2 (also approved today) is likewise "doneToday" - both
      // statuses independent of each other, no cross-blocking.
      expect(
        await repository.availabilityFor(task, childId),
        TaskAvailability.doneToday,
      );
      expect(
        await repository.availabilityFor(task, secondChild.id),
        TaskAvailability.doneToday,
      );
    });

    test('a fresh database has no children', () async {
      await dbHelper.close();
      expect(await repository.getAllChildren(), isEmpty);
    });

    test('the last child can be deleted', () async {
      await repository.deleteChild(childId);
      expect(await repository.getAllChildren(), isEmpty);
    });

    test('completeTask throws if the task is not assigned to the child',
        () async {
      final otherChild = await repository.addChild('Emma');
      final task = await repository.createTask(
        title: 'Only for the original child',
        amountOre: 100,
        recurrence: Recurrence.once,
        assignedChildIds: [childId],
      );

      expect(
        () => repository.completeTask(task.id, childId: otherChild.id),
        throwsA(isA<RepositoryException>()),
      );
    });
  });

  group('Task model: week plan (activeWeekdays)', () {
    test('an empty or full list is normalized to null ("every day")', () {
      final allSeven = Task(
        id: 'w1',
        title: 'Every day given explicitly',
        amountOre: 100,
        recurrence: Recurrence.daily,
        createdAt: DateTime(2026, 1, 1),
        activeWeekdays: const [1, 2, 3, 4, 5, 6, 7],
      );
      expect(allSeven.activeWeekdays, isNull);

      final empty = Task(
        id: 'w2',
        title: 'Empty list',
        amountOre: 100,
        recurrence: Recurrence.daily,
        createdAt: DateTime(2026, 1, 1),
        activeWeekdays: const [],
      );
      expect(empty.activeWeekdays, isNull);
    });

    test('isActiveOn respects a partial filter', () {
      final task = Task(
        id: 'w3',
        title: 'Weekdays',
        amountOre: 100,
        recurrence: Recurrence.daily,
        createdAt: DateTime(2026, 1, 1),
        activeWeekdays: const [1, 2, 3, 4, 5],
      );
      // 2026-03-14 is a Saturday (weekday 6) - not in the list.
      expect(task.isActiveOn(DateTime(2026, 3, 14)), isFalse);
      // 2026-03-13 is a Friday (weekday 5) - in the list.
      expect(task.isActiveOn(DateTime(2026, 3, 13)), isTrue);
    });

    test('copyWith(clearActiveWeekdays: true) resets to "every day"', () {
      final task = Task(
        id: 'w4',
        title: 'Only Monday',
        amountOre: 100,
        recurrence: Recurrence.daily,
        createdAt: DateTime(2026, 1, 1),
        activeWeekdays: const [1],
      );
      final cleared = task.copyWith(clearActiveWeekdays: true);
      expect(cleared.activeWeekdays, isNull);
      expect(cleared.isActiveOn(DateTime(2026, 3, 14)), isTrue);
    });
  });

  group('Task model: child assignment (assignedChildIds)', () {
    test('an empty list is normalized to null ("all children")', () {
      final task = Task(
        id: 'c1',
        title: 'Empty list',
        amountOre: 100,
        recurrence: Recurrence.once,
        createdAt: DateTime(2026, 1, 1),
        assignedChildIds: const [],
      );
      expect(task.assignedChildIds, isNull);
    });

    test('copyWith(clearAssignedChildIds: true) resets to "all children"',
        () {
      final task = Task(
        id: 'c2',
        title: 'Only child A',
        amountOre: 100,
        recurrence: Recurrence.once,
        createdAt: DateTime(2026, 1, 1),
        assignedChildIds: const ['a'],
      );
      final cleared = task.copyWith(clearAssignedChildIds: true);
      expect(cleared.assignedChildIds, isNull);
    });
  });

  group('Recurrence logic', () {
    test('a one-off task cannot be done again after approval', () {
      final task = Task(
        id: 't1',
        title: 'Once',
        amountOre: 100,
        recurrence: Recurrence.once,
        createdAt: DateTime(2026, 1, 1),
      );
      final completions = [
        Completion(
          id: 'c1',
          taskId: 't1',
          childId: 'child-1',
          completedAt: DateTime(2026, 1, 2),
          status: CompletionStatus.approved,
          approvedAt: DateTime(2026, 1, 2),
          amountAtCompletionOre: 100,
        ),
      ];

      expect(
        computeAvailability(task, completions, now: DateTime(2026, 6, 1)),
        TaskAvailability.completedOnce,
      );
    });

    test('a daily task is available again the next calendar day', () {
      final task = Task(
        id: 't2',
        title: 'Daily',
        amountOre: 100,
        recurrence: Recurrence.daily,
        createdAt: DateTime(2026, 1, 1),
      );
      final completions = [
        Completion(
          id: 'c2',
          taskId: 't2',
          childId: 'child-1',
          completedAt: DateTime(2026, 3, 10, 8, 0),
          status: CompletionStatus.approved,
          approvedAt: DateTime(2026, 3, 10, 8, 0),
          amountAtCompletionOre: 100,
        ),
      ];

      // Same day, later time -> still not available.
      expect(
        computeAvailability(task, completions, now: DateTime(2026, 3, 10, 20)),
        TaskAvailability.doneToday,
      );

      // Next calendar day -> available again.
      expect(
        computeAvailability(task, completions, now: DateTime(2026, 3, 11, 0, 1)),
        TaskAvailability.available,
      );
    });

    test('a weekly task is available again after 7 days', () {
      final task = Task(
        id: 't3',
        title: 'Weekly',
        amountOre: 100,
        recurrence: Recurrence.weekly,
        createdAt: DateTime(2026, 1, 1),
      );
      final completions = [
        Completion(
          id: 'c3',
          taskId: 't3',
          childId: 'child-1',
          completedAt: DateTime(2026, 3, 10),
          status: CompletionStatus.approved,
          approvedAt: DateTime(2026, 3, 10),
          amountAtCompletionOre: 100,
        ),
      ];

      expect(
        computeAvailability(task, completions, now: DateTime(2026, 3, 15)),
        TaskAvailability.doneThisWeek,
      );
      expect(
        computeAvailability(task, completions, now: DateTime(2026, 3, 17)),
        TaskAvailability.available,
      );
    });

    test('an unlimited task is always available regardless of approved history', () {
      final task = Task(
        id: 't4',
        title: 'Walk the dog',
        amountOre: 50,
        recurrence: Recurrence.unlimited,
        createdAt: DateTime(2026, 1, 1),
      );
      // Even several approved completions on the same day change nothing -
      // 'unlimited' deliberately ignores the approved history.
      final completions = [
        Completion(
          id: 'c4a',
          taskId: 't4',
          childId: 'child-1',
          completedAt: DateTime(2026, 3, 10, 8),
          status: CompletionStatus.approved,
          approvedAt: DateTime(2026, 3, 10, 8),
          amountAtCompletionOre: 50,
        ),
        Completion(
          id: 'c4b',
          taskId: 't4',
          childId: 'child-1',
          completedAt: DateTime(2026, 3, 10, 14),
          status: CompletionStatus.approved,
          approvedAt: DateTime(2026, 3, 10, 14),
          amountAtCompletionOre: 50,
        ),
      ];

      expect(
        computeAvailability(task, completions, now: DateTime(2026, 3, 10, 20)),
        TaskAvailability.available,
      );
    });

    test('an unlimited task is still blocked by a pending approval', () {
      final task = Task(
        id: 't5',
        title: 'Walk the dog',
        amountOre: 50,
        recurrence: Recurrence.unlimited,
        createdAt: DateTime(2026, 1, 1),
      );
      final completions = [
        Completion(
          id: 'c5',
          taskId: 't5',
          childId: 'child-1',
          completedAt: DateTime(2026, 3, 10, 8),
          status: CompletionStatus.pending,
          amountAtCompletionOre: 50,
        ),
      ];

      expect(
        computeAvailability(task, completions, now: DateTime(2026, 3, 10, 9)),
        TaskAvailability.pendingApproval,
      );
    });

    test('the weekday filter blocks the task on deselected days', () {
      // Only active on Wednesday (weekday 3). 2026-03-10 is a Tuesday.
      final task = Task(
        id: 't6',
        title: 'Only Wednesday',
        amountOre: 100,
        recurrence: Recurrence.daily,
        createdAt: DateTime(2026, 1, 1),
        activeWeekdays: const [3],
      );

      expect(
        computeAvailability(task, const [], now: DateTime(2026, 3, 10)),
        TaskAvailability.notScheduledToday,
      );
      // 2026-03-11 is a Wednesday -> active again.
      expect(
        computeAvailability(task, const [], now: DateTime(2026, 3, 11)),
        TaskAvailability.available,
      );
    });

    test('the weekday filter does not apply to one-off tasks', () {
      final task = Task(
        id: 't7',
        title: 'Once, only Wednesday given but ignored',
        amountOre: 100,
        recurrence: Recurrence.once,
        createdAt: DateTime(2026, 1, 1),
        activeWeekdays: const [3],
      );

      // 2026-03-10 is a Tuesday - available anyway, because the weekday
      // filter only applies to recurring tasks.
      expect(
        computeAvailability(task, const [], now: DateTime(2026, 3, 10)),
        TaskAvailability.available,
      );
    });

    test('nextAvailableDate finds the next available weekday', () {
      // Only active on Friday (weekday 5). 2026-03-10 is a Tuesday.
      final task = Task(
        id: 't8',
        title: 'Only Friday',
        amountOre: 100,
        recurrence: Recurrence.weekly,
        createdAt: DateTime(2026, 1, 1),
        activeWeekdays: const [5],
      );

      final next = nextAvailableDate(task, const [], now: DateTime(2026, 3, 10));
      expect(next, DateTime(2026, 3, 13)); // The coming Friday.
    });

    test('nextAvailableDate is null while a completion is waiting', () {
      final task = Task(
        id: 't9',
        title: 'Only Friday',
        amountOre: 100,
        recurrence: Recurrence.weekly,
        createdAt: DateTime(2026, 1, 1),
        activeWeekdays: const [5],
      );
      final completions = [
        Completion(
          id: 'c9',
          taskId: 't9',
          childId: 'child-1',
          completedAt: DateTime(2026, 3, 6),
          status: CompletionStatus.pending,
          amountAtCompletionOre: 100,
        ),
      ];

      expect(
        nextAvailableDate(task, completions, now: DateTime(2026, 3, 10)),
        isNull,
      );
    });
  });
}
