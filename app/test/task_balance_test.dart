// Simple unit-tests for data-laget: opgaver, completions og saldo-logik.
//
// Kører uden en rigtig Android/iOS-platform ved at bruge
// sqflite_common_ffi (en ren Dart/FFI sqlite-implementering) i stedet
// for sqflite's normale platform-kanal, og shared_preferences' indbyggede
// mock-værdier til indstillinger.
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

  // Et fast test-barn, oprettet i hver test's setUp og brugt konsekvent
  // som childId i alle kald der nu kræver ét - se
  // 'Flere børn'-gruppen nedenfor for tests der bruger flere børn.
  late String childId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsService.create();

    dbHelper = DatabaseHelper.instance
      ..overridePath = ':memory:';
    // Sørg for en frisk database-forbindelse for hver test.
    await dbHelper.close();

    repository = TaskRepository(databaseHelper: dbHelper, settings: settings);

    childId = (await repository.addChild('Barn 1')).id;
  });

  tearDown(() async {
    await dbHelper.close();
  });

  group('Opgaver og godkendelse', () {
    test('opret opgave -> markér udført -> godkend -> saldo stiger korrekt',
        () async {
      final task = await repository.createTask(
        title: 'Rydde op på værelset',
        amountOre: 1000, // 10 kr
        recurrence: Recurrence.once,
      );

      expect(await repository.currentBalanceOre(childId: childId), 0);

      final completion =
          await repository.completeTask(task.id, childId: childId);
      expect(completion.status, CompletionStatus.pending);

      // Saldoen stiger ikke før godkendelse.
      expect(await repository.currentBalanceOre(childId: childId), 0);

      await repository.approveCompletion(completion.id);

      expect(await repository.currentBalanceOre(childId: childId), 1000);
      expect(await repository.totalEarnedOre(childId: childId), 1000);
    });

    test('afvist udførelse tæller ikke med i saldoen', () async {
      final task = await repository.createTask(
        title: 'Vaske op',
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

    test('kan ikke markere udført igen mens en completion venter', () async {
      final task = await repository.createTask(
        title: 'Støvsuge',
        amountOre: 700,
        recurrence: Recurrence.daily,
      );
      await repository.completeTask(task.id, childId: childId);

      expect(
        () => repository.completeTask(task.id, childId: childId),
        throwsA(isA<RepositoryException>()),
      );
    });

    test('marker som udbetalt nulstiller den optjente saldo', () async {
      final task = await repository.createTask(
        title: 'Fejer indkørslen',
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
      // Historikken (totalEarnedOre) ændres ikke af en udbetaling.
      expect(await repository.totalEarnedOre(childId: childId), 2000);
    });

    test('manuel saldo-justering (+/-) tælles med i saldoen', () async {
      final task = await repository.createTask(
        title: 'Fejer indkørslen',
        amountOre: 1000,
        recurrence: Recurrence.once,
      );
      final completion =
          await repository.completeTask(task.id, childId: childId);
      await repository.approveCompletion(completion.id);

      expect(await repository.currentBalanceOre(childId: childId), 1000);

      await repository.addBalanceAdjustment(
        amountOre: 500,
        note: "Fandt en 5'er i sofaen",
        childId: childId,
      );
      expect(await repository.currentBalanceOre(childId: childId), 1500);

      await repository.addBalanceAdjustment(
        amountOre: -300,
        note: 'Rettede en fejlregistrering',
        childId: childId,
      );
      expect(await repository.currentBalanceOre(childId: childId), 1200);
      expect(await repository.totalAdjustmentsOre(childId: childId), 200);

      final adjustments = await repository.getAllBalanceAdjustments();
      expect(adjustments.length, 2);
    });

    test('saldo-justering uden note kastes som fejl', () async {
      expect(
        () => repository.addBalanceAdjustment(
          amountOre: 100,
          note: '   ',
          childId: childId,
        ),
        throwsA(isA<RepositoryException>()),
      );
    });

    test('saldoen bliver aldrig negativ selv med en stor negativ justering',
        () async {
      await repository.addBalanceAdjustment(
        amountOre: -5000,
        note: 'Test af nedre grænse',
        childId: childId,
      );
      expect(await repository.currentBalanceOre(childId: childId), 0);
    });
  });

  group('Flere børn', () {
    test(
        'en opgave uden assignedChildIds (null) gælder dynamisk for ALLE '
        'børn, inkl. et barn oprettet EFTER opgaven', () async {
      final task = await repository.createTask(
        title: 'Rydde op i fællesrummet',
        amountOre: 300,
        recurrence: Recurrence.daily,
        // assignedChildIds udeladt -> null -> "alle børn".
      );

      // Kun det ene barn fra setUp findes endnu.
      var resolved = await repository.resolvedChildIdsForTask(task);
      expect(resolved, [childId]);

      // Et nyt barn oprettes EFTER opgaven blev oprettet.
      final secondChild = await repository.addChild('Emma');

      resolved = await repository.resolvedChildIdsForTask(task);
      expect(resolved.toSet(), {childId, secondChild.id});
    });

    test(
        'to forskellige børn optjener uafhængigt af hinanden på samme '
        'delte opgave - den ene blokerer ikke den anden', () async {
      final secondChild = await repository.addChild('Emma');

      final task = await repository.createTask(
        title: 'Dække bord',
        amountOre: 200,
        recurrence: Recurrence.daily,
        assignedChildIds: [childId, secondChild.id],
      );

      // Barn 1 udfører og bliver godkendt.
      final completionA =
          await repository.completeTask(task.id, childId: childId);
      await repository.approveCompletion(completionA.id);

      // Barn 1's godkendte completion må IKKE blokere barn 2's egen,
      // uafhængige udførelse af samme opgave (availability-fix).
      final availabilityForB =
          await repository.availabilityFor(task, secondChild.id);
      expect(availabilityForB, TaskAvailability.available);

      final completionB =
          await repository.completeTask(task.id, childId: secondChild.id);
      await repository.approveCompletion(completionB.id);

      // Hver af de to børn har optjent beløbet for deres EGEN completion,
      // ikke begges tilsammen, og på hver sin egen saldo.
      expect(await repository.currentBalanceOre(childId: childId), 200);
      expect(
        await repository.currentBalanceOre(childId: secondChild.id),
        200,
      );
      expect(await repository.totalEarnedOre(childId: childId), 200);
      expect(await repository.totalEarnedOre(childId: secondChild.id), 200);

      // Barn 1 er nu "doneToday" (daglig opgave, godkendt i dag), mens
      // barn 2 (også godkendt i dag) ligeledes er "doneToday" - begge
      // status uafhængigt af hinanden, ingen krydsblokering.
      expect(
        await repository.availabilityFor(task, childId),
        TaskAvailability.doneToday,
      );
      expect(
        await repository.availabilityFor(task, secondChild.id),
        TaskAvailability.doneToday,
      );
    });

    test('en frisk database har ingen børn', () async {
      await dbHelper.close();
      expect(await repository.getAllChildren(), isEmpty);
    });

    test('det sidste barn kan slettes', () async {
      await repository.deleteChild(childId);
      expect(await repository.getAllChildren(), isEmpty);
    });

    test('completeTask kaster fejl hvis opgaven ikke er tildelt barnet',
        () async {
      final otherChild = await repository.addChild('Emma');
      final task = await repository.createTask(
        title: 'Kun til det oprindelige barn',
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

  group('Task-model: ugeplan (activeWeekdays)', () {
    test('tom eller fuld liste normaliseres til null ("alle dage")', () {
      final allSeven = Task(
        id: 'w1',
        title: 'Alle dage angivet eksplicit',
        amountOre: 100,
        recurrence: Recurrence.daily,
        createdAt: DateTime(2026, 1, 1),
        activeWeekdays: const [1, 2, 3, 4, 5, 6, 7],
      );
      expect(allSeven.activeWeekdays, isNull);

      final empty = Task(
        id: 'w2',
        title: 'Tom liste',
        amountOre: 100,
        recurrence: Recurrence.daily,
        createdAt: DateTime(2026, 1, 1),
        activeWeekdays: const [],
      );
      expect(empty.activeWeekdays, isNull);
    });

    test('isActiveOn respekterer et delvist filter', () {
      final task = Task(
        id: 'w3',
        title: 'Hverdage',
        amountOre: 100,
        recurrence: Recurrence.daily,
        createdAt: DateTime(2026, 1, 1),
        activeWeekdays: const [1, 2, 3, 4, 5],
      );
      // 2026-03-14 er en lørdag (weekday 6) - ikke i listen.
      expect(task.isActiveOn(DateTime(2026, 3, 14)), isFalse);
      // 2026-03-13 er en fredag (weekday 5) - i listen.
      expect(task.isActiveOn(DateTime(2026, 3, 13)), isTrue);
    });

    test('copyWith(clearActiveWeekdays: true) nulstiller til "alle dage"', () {
      final task = Task(
        id: 'w4',
        title: 'Kun mandag',
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

  group('Task-model: børn-tildeling (assignedChildIds)', () {
    test('tom liste normaliseres til null ("alle børn")', () {
      final task = Task(
        id: 'c1',
        title: 'Tom liste',
        amountOre: 100,
        recurrence: Recurrence.once,
        createdAt: DateTime(2026, 1, 1),
        assignedChildIds: const [],
      );
      expect(task.assignedChildIds, isNull);
    });

    test('copyWith(clearAssignedChildIds: true) nulstiller til "alle børn"',
        () {
      final task = Task(
        id: 'c2',
        title: 'Kun barn A',
        amountOre: 100,
        recurrence: Recurrence.once,
        createdAt: DateTime(2026, 1, 1),
        assignedChildIds: const ['a'],
      );
      final cleared = task.copyWith(clearAssignedChildIds: true);
      expect(cleared.assignedChildIds, isNull);
    });
  });

  group('Gentagelses-logik (recurrence)', () {
    test('engangsopgave kan ikke udføres igen efter godkendelse', () {
      final task = Task(
        id: 't1',
        title: 'Engang',
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

    test('daglig opgave er tilgængelig igen næste kalenderdag', () {
      final task = Task(
        id: 't2',
        title: 'Dagligt',
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

      // Samme dag, senere klokkeslæt -> stadig ikke tilgængelig.
      expect(
        computeAvailability(task, completions, now: DateTime(2026, 3, 10, 20)),
        TaskAvailability.doneToday,
      );

      // Næste kalenderdag -> tilgængelig igen.
      expect(
        computeAvailability(task, completions, now: DateTime(2026, 3, 11, 0, 1)),
        TaskAvailability.available,
      );
    });

    test('ugentlig opgave er tilgængelig igen efter 7 dage', () {
      final task = Task(
        id: 't3',
        title: 'Ugentligt',
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

    test('ubegrænset opgave er altid tilgængelig uden godkendt historik', () {
      final task = Task(
        id: 't4',
        title: 'Gå tur med hunden',
        amountOre: 50,
        recurrence: Recurrence.unlimited,
        createdAt: DateTime(2026, 1, 1),
      );
      // Selv adskillige godkendte completions samme dag ændrer intet -
      // 'unlimited' ignorerer bevidst godkendt-historikken.
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

    test('ubegrænset opgave blokeres stadig af en ventende godkendelse', () {
      final task = Task(
        id: 't5',
        title: 'Gå tur med hunden',
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

    test('ugedags-filter blokerer opgaven på fravalgte dage', () {
      // Kun aktiv onsdag (weekday 3). 2026-03-10 er en tirsdag.
      final task = Task(
        id: 't6',
        title: 'Kun onsdag',
        amountOre: 100,
        recurrence: Recurrence.daily,
        createdAt: DateTime(2026, 1, 1),
        activeWeekdays: const [3],
      );

      expect(
        computeAvailability(task, const [], now: DateTime(2026, 3, 10)),
        TaskAvailability.notScheduledToday,
      );
      // 2026-03-11 er en onsdag -> aktiv igen.
      expect(
        computeAvailability(task, const [], now: DateTime(2026, 3, 11)),
        TaskAvailability.available,
      );
    });

    test('ugedags-filter gælder ikke for engangsopgaver', () {
      final task = Task(
        id: 't7',
        title: 'Engang, kun onsdag angivet men ignoreres',
        amountOre: 100,
        recurrence: Recurrence.once,
        createdAt: DateTime(2026, 1, 1),
        activeWeekdays: const [3],
      );

      // 2026-03-10 er en tirsdag - alligevel tilgængelig, fordi
      // ugedags-filteret kun gælder gentagende opgaver.
      expect(
        computeAvailability(task, const [], now: DateTime(2026, 3, 10)),
        TaskAvailability.available,
      );
    });

    test('nextAvailableDate finder næste tilgængelige ugedag', () {
      // Kun aktiv fredag (weekday 5). 2026-03-10 er en tirsdag.
      final task = Task(
        id: 't8',
        title: 'Kun fredag',
        amountOre: 100,
        recurrence: Recurrence.weekly,
        createdAt: DateTime(2026, 1, 1),
        activeWeekdays: const [5],
      );

      final next = nextAvailableDate(task, const [], now: DateTime(2026, 3, 10));
      expect(next, DateTime(2026, 3, 13)); // Den kommende fredag.
    });

    test('nextAvailableDate er null mens en completion venter', () {
      final task = Task(
        id: 't9',
        title: 'Kun fredag',
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
