// Tests for the follow-up rules (logic/follow_up.dart) and the family's
// settings: overdue, restricted, pause, suspension and restriction window.
import 'package:flutter_test/flutter_test.dart';

import 'package:lommepenge_app/l10n/l10n.dart';
import 'package:lommepenge_app/logic/follow_up.dart';
import 'package:lommepenge_app/models/completion.dart';
import 'package:lommepenge_app/models/family_settings.dart';
import 'package:lommepenge_app/models/task.dart';

void main() {
  const settings = FamilySettings(); // deadline 18:00, restriction 15-21, pause 10
  const childId = 'emma';

  Task task({
    String id = 'dishes',
    bool mandatory = true,
    String? dueTime,
    Recurrence recurrence = Recurrence.daily,
    List<int>? weekdays,
  }) =>
      Task(
        id: id,
        title: 'Empty the dishwasher',
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
    String taskId = 'dishes',
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

  // Monday 23 November 2026.
  DateTime at(int hour, [int minute = 0]) =>
      DateTime(2026, 11, 23, hour, minute);

  test('before the deadline: the task is missing, but nothing is restricted', () {
    final f = followUp(at(16));
    expect(f.dueToday, hasLength(1));
    expect(f.overdue, isEmpty);
    expect(f.restricted, isFalse);
    expect(f.nextDue!.dueLabel, '18:00');
  });

  test('after the default deadline 18:00 in the restriction time: restricted', () {
    final f = followUp(at(18, 1));
    expect(f.overdue, hasLength(1));
    expect(f.restricted, isTrue);
    expect(
      f.reason(l10nFor('en')),
      'Missing: Empty the dishwasher (due 18:00)',
    );
    // The same as Home Assistant writes in each language (logic.py).
    expect(
      f.reason(l10nFor('da')),
      'Mangler: Empty the dishwasher (frist 18:00)',
    );
    expect(
      f.reason(l10nFor('fr')),
      'Manquant : Empty the dishwasher (échéance 18:00)',
    );
  });

  test("the task's own deadline takes precedence over the default", () {
    final f = followUp(at(16), tasks: [task(dueTime: '07:30')]);
    expect(f.overdue, hasLength(1));
    expect(f.restricted, isTrue);
  });

  test('an overdue morning task only restricts from the start of the window', () {
    final morning = [task(dueTime: '07:30')];
    expect(followUp(at(12), tasks: morning).restricted, isFalse);
    expect(followUp(at(12), tasks: morning).overdue, hasLength(1));
    expect(followUp(at(15), tasks: morning).restricted, isTrue);
    expect(followUp(at(21), tasks: morning).restricted, isFalse);
  });

  test('marked as done (awaiting approval) lifts the restriction', () {
    final f = followUp(at(19), completions: [completion(at: at(17))]);
    expect(f.overdue, isEmpty);
    expect(f.restricted, isFalse);
  });

  test('a rejected completion counts as not done again', () {
    final f = followUp(at(19), completions: [
      completion(at: at(17), status: CompletionStatus.rejected),
    ]);
    expect(f.restricted, isTrue);
  });

  test('done late: restricted during the pause, then lifted', () {
    final done = completion(at: at(19), late: true);
    expect(followUp(at(19, 5), completions: [done]).restricted, isTrue);
    expect(
      followUp(at(19, 5), completions: [done]).latePauseUntil,
      at(19, 10),
    );
    expect(
      followUp(at(19, 5), completions: [done]).reason(l10nFor('en')),
      'The task was done late - unlocks at 19:10',
    );
    expect(followUp(at(19, 10), completions: [done]).restricted, isFalse);
  });

  test("a parent's suspension only applies today", () {
    expect(followUp(at(19), suspendedOn: '2026-11-23').restricted, isFalse);
    expect(followUp(at(19), suspendedOn: '2026-11-22').restricted, isTrue);
  });

  test('optional tasks are not followed up', () {
    expect(followUp(at(20), tasks: [task(mandatory: false)]).overdue, isEmpty);
  });

  test('tasks not on the week plan today are not followed up', () {
    final f = followUp(at(20), tasks: [task(weekdays: [2, 4])]);
    expect(f.overdue, isEmpty);
  });

  test('approved today counts as done - also for unlimited tasks', () {
    final f = followUp(
      at(20),
      tasks: [task(recurrence: Recurrence.unlimited)],
      completions: [
        completion(at: at(10), status: CompletionStatus.approved),
      ],
    );
    expect(f.overdue, isEmpty);
  });

  test("isLateCompletion uses the task's deadline or the default", () {
    expect(isLateCompletion(task(), settings, at(17, 59)), isFalse);
    expect(isLateCompletion(task(), settings, at(18, 1)), isTrue);
    expect(isLateCompletion(task(dueTime: '07:30'), settings, at(8)), isTrue);
    expect(isLateCompletion(task(mandatory: false), settings, at(23)), isFalse);
  });

  test('restriction window across midnight', () {
    final night = settings
        .withValue('restrictionStart', '22:00')
        .withValue('restrictionEnd', '02:00');
    expect(isInRestrictionWindow(night, at(23)), isTrue);
    expect(isInRestrictionWindow(night, at(1)), isTrue);
    expect(isInRestrictionWindow(night, at(12)), isFalse);
  });

  group('FamilySettings', () {
    test('defaults', () {
      expect(settings.defaultDueTime, '18:00');
      expect(settings.restrictionStart, '15:00');
      expect(settings.restrictionEnd, '21:00');
      expect(settings.latePauseMinutes, 10);
    });

    test('withValue normalizes times and rejects invalid values', () {
      expect(settings.withValue('defaultDueTime', '7:5').defaultDueTime,
          '07:05');
      expect(() => settings.withValue('defaultDueTime', '25:00'),
          throwsArgumentError);
      expect(() => settings.withValue('latePauseMinutes', -1),
          throwsArgumentError);
      expect(() => settings.withValue('unknown', 1), throwsArgumentError);
    });

    test('fromJson falls back to the default for invalid values', () {
      final s = FamilySettings.fromJson({
        'defaultDueTime': 'some nonsense',
        'latePauseMinutes': 15,
      });
      expect(s.defaultDueTime, '18:00');
      expect(s.latePauseMinutes, 15);
    });
  });
}
