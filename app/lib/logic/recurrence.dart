import '../models/completion.dart';
import '../models/task.dart';

/// Whether a task can be marked "done" by the child right now, and why/when
/// not.
enum TaskAvailability {
  /// Can be marked as done now.
  available,

  /// A completion is already waiting for a parent's approval.
  pendingApproval,

  /// Done and approved today (daily tasks only) - available again tomorrow.
  doneToday,

  /// Done and approved within the last 7 days (weekly tasks only) - available
  /// again once 7 days have passed.
  doneThisWeek,

  /// One-off task that has already been approved - cannot be done again.
  completedOnce,

  /// The task is not on the week plan today (see [Task.activeWeekdays]) -
  /// applies to all recurrence types except [Recurrence.once].
  notScheduledToday,
}

/// Date (without time of day) used to compare "calendar days".
DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Calculates whether [task] can be marked as done right now, based on its
/// previous [completions] (only completions for this one task).
///
/// The rules:
/// - It can never be marked as done again while there is a 'pending'
///   completion (awaiting approval).
/// - A 'rejected' completion does not block - the task can be tried again
///   right away.
/// - If the task is recurring (not 'once') and not on the week plan for
///   today (see [Task.isActiveOn]), it is not available today - regardless
///   of what the recurrence rules would otherwise say.
/// - 'once': can only be done/approved once ever.
/// - 'daily': can be done again when the calendar day differs from the most
///   recently approved completion.
/// - 'weekly': can be done again when at least 7 days have passed since the
///   most recently approved completion.
/// - 'unlimited': can always be done again (only blocked by a pending
///   completion) - deliberately ignores the approved history.
TaskAvailability computeAvailability(
  Task task,
  List<Completion> completionsForTask, {
  DateTime? now,
}) {
  final today = now ?? DateTime.now();

  final hasPending =
      completionsForTask.any((c) => c.status == CompletionStatus.pending);
  if (hasPending) {
    return TaskAvailability.pendingApproval;
  }

  if (task.recurrence != Recurrence.once && !task.isActiveOn(today)) {
    return TaskAvailability.notScheduledToday;
  }

  final approved = completionsForTask
      .where((c) => c.status == CompletionStatus.approved)
      .toList()
    ..sort((a, b) => b.completedAt.compareTo(a.completedAt));

  if (approved.isEmpty) {
    return TaskAvailability.available;
  }

  final lastApproved = approved.first;

  switch (task.recurrence) {
    case Recurrence.once:
      return TaskAvailability.completedOnce;
    case Recurrence.daily:
      final sameDay =
          _dateOnly(lastApproved.completedAt) == _dateOnly(today);
      return sameDay ? TaskAvailability.doneToday : TaskAvailability.available;
    case Recurrence.weekly:
      final daysSince = _dateOnly(today)
          .difference(_dateOnly(lastApproved.completedAt))
          .inDays;
      return daysSince < 7
          ? TaskAvailability.doneThisWeek
          : TaskAvailability.available;
    case Recurrence.unlimited:
      return TaskAvailability.available;
  }
}

/// How many days ahead [nextAvailableDate] searches for an available date at
/// most - e.g. if all weekdays are deselected, there is never an available
/// date, and the search must give up rather than run forever.
const int _searchWindowDays = 14;

/// When the task is available again at the earliest.
///
/// Built as a generic day-by-day search (rather than a closed-form switch on
/// the recurrence type), because the combination of weekday filter and
/// recurrence cool-down (daily/weekly) otherwise quickly becomes hard to keep
/// correct in two parallel implementations: here [computeAvailability] itself
/// is reused as the only source of truth, and we simply find the first
/// upcoming date (including today) where it would answer 'available'.
/// Returns `null` if no such date exists within the search window (e.g. a
/// task where all 7 weekdays are deselected).
DateTime? nextAvailableDate(
  Task task,
  List<Completion> completionsForTask, {
  DateTime? now,
}) {
  final today = _dateOnly(now ?? DateTime.now());

  // As long as a pending completion exists, there is no point in looking for
  // a "next available date" - it depends on an approval/rejection that has
  // not happened yet.
  final hasPending =
      completionsForTask.any((c) => c.status == CompletionStatus.pending);
  if (hasPending) return null;

  for (var offset = 0; offset <= _searchWindowDays; offset++) {
    final candidate = today.add(Duration(days: offset));
    final availability =
        computeAvailability(task, completionsForTask, now: candidate);
    if (availability == TaskAvailability.available) {
      return candidate;
    }
  }
  return null;
}
