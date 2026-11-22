// Tests for opfølgningsreglerne (logic/follow_up.dart) og familiens
// indstillinger: forsinket, spærret, pausetid, ophævelse og spærre-vindue.
import 'package:flutter_test/flutter_test.dart';

import 'package:lommepenge_app/logic/follow_up.dart';
import 'package:lommepenge_app/models/completion.dart';
import 'package:lommepenge_app/models/family_settings.dart';
import 'package:lommepenge_app/models/task.dart';

void main() {
  const settings = FamilySettings(); // frist 18:00, spærring 15-21, pause 10
  const childId = 'emma';

  Task task({
    String id = 'opvask',
    bool mandatory = true,
    String? dueTime,
    Recurrence recurrence = Recurrence.daily,
    List<int>? weekdays,
  }) =>
      Task(
        id: id,
        title: 'Tøm opvaskeren',
        amountOre: 1000,
        recurrence: recurrence,
        createdAt: DateTime(2026, 11, 1),
        mandatory: mandatory,
        dueTime: dueTime,
        activeWeekdays: weekdays,
      );

  Completion completion({
    required DateTime at,
    CompletionStatus status = CompletionStatus.pending,
    bool late = false,
    String taskId = 'opvask',
  }) =>
      Completion(
        id: 'c-${at.millisecondsSinceEpoch}',
        taskId: taskId,
        childId: childId,
        completedAt: at,
        status: status,
        amountAtCompletionOre: 1000,
        late: late,
      );

  ChildFollowUp followUp(
    DateTime now, {
    List<Task>? tasks,
    List<Completion> completions = const [],
    String? suspendedOn,
  }) =>
      computeFollowUp(
        childId: childId,
        tasks: tasks ?? [task()],
        completions: completions,
        settings: settings,
        now: now,
        suspendedOn: suspendedOn,
      );

  // Mandag 23. november 2026.
  DateTime at(int hour, [int minute = 0]) =>
      DateTime(2026, 11, 23, hour, minute);

  test('før fristen: opgaven mangler, men intet er spærret', () {
    final f = followUp(at(16));
    expect(f.dueToday, hasLength(1));
    expect(f.overdue, isEmpty);
    expect(f.restricted, isFalse);
    expect(f.nextDue!.dueLabel, '18:00');
  });

  test('efter standardfristen 18:00 i spærretiden: spærret', () {
    final f = followUp(at(18, 1));
    expect(f.overdue, hasLength(1));
    expect(f.restricted, isTrue);
    expect(f.reason, contains('Tøm opvaskeren'));
  });

  test('egen frist på opgaven går forud for standardfristen', () {
    final f = followUp(at(16), tasks: [task(dueTime: '07:30')]);
    expect(f.overdue, hasLength(1));
    expect(f.restricted, isTrue);
  });

  test('forsinket morgenopgave spærrer først fra spærretidens start', () {
    final morning = [task(dueTime: '07:30')];
    expect(followUp(at(12), tasks: morning).restricted, isFalse);
    expect(followUp(at(12), tasks: morning).overdue, hasLength(1));
    expect(followUp(at(15), tasks: morning).restricted, isTrue);
    expect(followUp(at(21), tasks: morning).restricted, isFalse);
  });

  test('markeret udført (venter på godkendelse) ophæver spærringen', () {
    final f = followUp(at(19), completions: [completion(at: at(17))]);
    expect(f.overdue, isEmpty);
    expect(f.restricted, isFalse);
  });

  test('afvist udførelse tæller som ikke udført igen', () {
    final f = followUp(at(19), completions: [
      completion(at: at(17), status: CompletionStatus.rejected),
    ]);
    expect(f.restricted, isTrue);
  });

  test('for sent udført: spærret i pausetiden, derefter ophævet', () {
    final done = completion(at: at(19), late: true);
    expect(followUp(at(19, 5), completions: [done]).restricted, isTrue);
    expect(
      followUp(at(19, 5), completions: [done]).latePauseUntil,
      at(19, 10),
    );
    expect(followUp(at(19, 10), completions: [done]).restricted, isFalse);
  });

  test('forælder-ophævelse gælder kun for i dag', () {
    expect(followUp(at(19), suspendedOn: '2026-11-23').restricted, isFalse);
    expect(followUp(at(19), suspendedOn: '2026-11-22').restricted, isTrue);
  });

  test('valgfri opgaver følges ikke op', () {
    expect(followUp(at(20), tasks: [task(mandatory: false)]).overdue, isEmpty);
  });

  test('opgaver der ikke er på ugeplanen i dag følges ikke op', () {
    final f = followUp(at(20), tasks: [task(weekdays: [2, 4])]);
    expect(f.overdue, isEmpty);
  });

  test('godkendt i dag tæller som gjort - også for ubegrænsede opgaver', () {
    final f = followUp(
      at(20),
      tasks: [task(recurrence: Recurrence.unlimited)],
      completions: [
        completion(at: at(10), status: CompletionStatus.approved),
      ],
    );
    expect(f.overdue, isEmpty);
  });

  test('isLateCompletion bruger opgavens frist eller standardfristen', () {
    expect(isLateCompletion(task(), settings, at(17, 59)), isFalse);
    expect(isLateCompletion(task(), settings, at(18, 1)), isTrue);
    expect(isLateCompletion(task(dueTime: '07:30'), settings, at(8)), isTrue);
    expect(isLateCompletion(task(mandatory: false), settings, at(23)), isFalse);
  });

  test('spærre-vindue over midnat', () {
    final night = settings
        .withValue('restrictionStart', '22:00')
        .withValue('restrictionEnd', '02:00');
    expect(isInRestrictionWindow(night, at(23)), isTrue);
    expect(isInRestrictionWindow(night, at(1)), isTrue);
    expect(isInRestrictionWindow(night, at(12)), isFalse);
  });

  group('FamilySettings', () {
    test('standardværdier', () {
      expect(settings.defaultDueTime, '18:00');
      expect(settings.restrictionStart, '15:00');
      expect(settings.restrictionEnd, '21:00');
      expect(settings.latePauseMinutes, 10);
    });

    test('withValue normaliserer klokkeslæt og afviser ugyldige værdier', () {
      expect(settings.withValue('defaultDueTime', '7:5').defaultDueTime,
          '07:05');
      expect(() => settings.withValue('defaultDueTime', '25:00'),
          throwsArgumentError);
      expect(() => settings.withValue('latePauseMinutes', -1),
          throwsArgumentError);
      expect(() => settings.withValue('ukendt', 1), throwsArgumentError);
    });

    test('fromJson falder tilbage til standard ved ugyldige værdier', () {
      final s = FamilySettings.fromJson({
        'defaultDueTime': 'noget sludder',
        'latePauseMinutes': 15,
      });
      expect(s.defaultDueTime, '18:00');
      expect(s.latePauseMinutes, 15);
    });
  });
}
