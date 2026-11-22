import '../l10n/l10n.dart';
import '../models/completion.dart';
import '../models/family_settings.dart';
import '../models/task.dart';
import 'recurrence.dart';

// Follow-up on mandatory tasks: what is a child missing today, what is
// overdue, and is the child's tablet restricted right now?
//
// Pure functions without I/O, so the rules can be tested and used the same
// way by the family screen and the tablet (message to the child). Home
// Assistant calculates the same in the integration's `logic.py`.

DateTime _atTime(DateTime day, String hhmm) {
  final minutes = minutesOfDay(hhmm) ?? 0;
  return DateTime(day.year, day.month, day.day, minutes ~/ 60, minutes % 60);
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// The deadline for [task] on the day [day], or `null` if the task is not
/// followed up (only mandatory tasks have a deadline).
DateTime? effectiveDue(Task task, FamilySettings settings, DateTime day) {
  if (!task.mandatory) return null;
  return _atTime(day, task.dueTime ?? settings.defaultDueTime);
}

/// Whether a completion of [task] at [completedAt] is late.
bool isLateCompletion(
  Task task,
  FamilySettings settings,
  DateTime completedAt,
) {
  final due = effectiveDue(task, settings, completedAt);
  return due != null && completedAt.isAfter(due);
}

/// Whether [now] is in the restriction window. A window across midnight (e.g.
/// 22:00-02:00) is supported.
bool isInRestrictionWindow(FamilySettings settings, DateTime now) {
  final start = minutesOfDay(settings.restrictionStart) ?? 0;
  final end = minutesOfDay(settings.restrictionEnd) ?? 0;
  final current = now.hour * 60 + now.minute;
  if (start == end) return false;
  if (start < end) return current >= start && current < end;
  return current >= start || current < end;
}

/// One mandatory task the child has to do today.
class DueTask {
  final Task task;
  final DateTime due;
  const DueTask(this.task, this.due);

  String get dueLabel => normalizeTimeOfDay('${due.hour}:${due.minute}')!;
}

/// Follow-up status for one child at a given time.
class ChildFollowUp {
  final String childId;

  /// Mandatory tasks today, not done yet, deadline not passed.
  final List<DueTask> dueToday;

  /// Mandatory tasks today, not done yet, deadline passed.
  final List<DueTask> overdue;

  /// Set while the pause after a late completion is running.
  final DateTime? latePauseUntil;

  final bool inWindow;

  /// A parent has lifted the restriction for today.
  final bool suspended;

  const ChildFollowUp({
    required this.childId,
    required this.dueToday,
    required this.overdue,
    required this.latePauseUntil,
    required this.inWindow,
    required this.suspended,
  });

  /// Whether the child's tablet should be restricted right now.
  bool get restricted =>
      inWindow && !suspended && (overdue.isNotEmpty || latePauseUntil != null);

  /// A short explanation for the child/parents, or `null` if not restricted.
  String? reason(AppLocalizations l10n) {
    if (!restricted) return null;
    if (overdue.isNotEmpty) {
      final names = overdue
          .map((d) => l10n.reasonOverdueTask(d.task.title, d.dueLabel))
          .join(', ');
      return l10n.reasonOverdue(names);
    }
    final until = latePauseUntil!;
    return l10n.reasonLate(normalizeTimeOfDay('${until.hour}:${until.minute}')!);
  }

  /// The earliest deadline today that has not been reached yet (for warnings).
  DueTask? get nextDue {
    if (dueToday.isEmpty) return null;
    return dueToday.reduce((a, b) => a.due.isBefore(b.due) ? a : b);
  }
}

/// Calculates [ChildFollowUp] for one child.
///
/// [tasks] are the active tasks that apply to the child, and [completions]
/// the child's own completions (all tasks). [suspendedOn] is the date
/// (`YYYY-MM-DD`) of a parent's suspension, if any.
ChildFollowUp computeFollowUp({
  required String childId,
  required List<Task> tasks,
  required List<Completion> completions,
  required FamilySettings settings,
  required DateTime now,
  String? suspendedOn,
}) {
  final dueToday = <DueTask>[];
  final overdue = <DueTask>[];

  for (final task in tasks) {
    if (!task.active || !task.mandatory) continue;
    if (task.recurrence != Recurrence.once && !task.isActiveOn(now)) continue;

    final forTask = completions.where((c) => c.taskId == task.id).toList();
    if (computeAvailability(task, forTask, now: now) !=
        TaskAvailability.available) {
      continue; // awaiting approval, already done, or not today
    }
    // 'unlimited' tasks are always "available" - an approved completion
    // today still counts as today's duty being done.
    final approvedToday = forTask.any((c) =>
        c.status == CompletionStatus.approved && _sameDay(c.completedAt, now));
    if (approvedToday) continue;

    final due = effectiveDue(task, settings, now)!;
    (now.isBefore(due) ? dueToday : overdue).add(DueTask(task, due));
  }

  DateTime? latePauseUntil;
  final pause = Duration(minutes: settings.latePauseMinutes);
  for (final c in completions) {
    if (!c.late || c.status == CompletionStatus.rejected) continue;
    final until = c.completedAt.add(pause);
    if (now.isBefore(until) &&
        (latePauseUntil == null || until.isAfter(latePauseUntil))) {
      latePauseUntil = until;
    }
  }

  return ChildFollowUp(
    childId: childId,
    dueToday: dueToday,
    overdue: overdue,
    latePauseUntil: latePauseUntil,
    inWindow: isInRestrictionWindow(settings, now),
    suspended: suspendedOn != null && suspendedOn == dateKey(now),
  );
}

/// `YYYY-MM-DD` for [d] (local time).
String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
