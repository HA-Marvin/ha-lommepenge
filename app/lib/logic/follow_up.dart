import '../models/completion.dart';
import '../models/family_settings.dart';
import '../models/task.dart';
import 'recurrence.dart';

// Opfølgning på obligatoriske opgaver: hvad mangler et barn i dag, hvad
// er forsinket, og er barnets tablet spærret lige nu?
//
// Rene funktioner uden I/O, så reglerne kan testes og bruges ens af
// køleskabsskærmen (UI + Home Assistant-API'et) og af tabletten (besked
// til barnet). Reglerne er beskrevet i docs/lommepenge-integration.md,
// Del E og G.

DateTime _atTime(DateTime day, String hhmm) {
  final minutes = minutesOfDay(hhmm) ?? 0;
  return DateTime(day.year, day.month, day.day, minutes ~/ 60, minutes % 60);
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Fristen for [task] på dagen [day], eller `null` hvis opgaven ikke
/// følges op (kun obligatoriske opgaver har en frist).
DateTime? effectiveDue(Task task, FamilySettings settings, DateTime day) {
  if (!task.mandatory) return null;
  return _atTime(day, task.dueTime ?? settings.defaultDueTime);
}

/// Om en udførelse af [task] på tidspunktet [completedAt] er for sent.
bool isLateCompletion(
  Task task,
  FamilySettings settings,
  DateTime completedAt,
) {
  final due = effectiveDue(task, settings, completedAt);
  return due != null && completedAt.isAfter(due);
}

/// Om [now] ligger i spærre-vinduet. Et vindue der går over midnat (fx
/// 22:00-02:00) understøttes.
bool isInRestrictionWindow(FamilySettings settings, DateTime now) {
  final start = minutesOfDay(settings.restrictionStart) ?? 0;
  final end = minutesOfDay(settings.restrictionEnd) ?? 0;
  final current = now.hour * 60 + now.minute;
  if (start == end) return false;
  if (start < end) return current >= start && current < end;
  return current >= start || current < end;
}

/// Én obligatorisk opgave som barnet skal nå i dag.
class DueTask {
  final Task task;
  final DateTime due;
  const DueTask(this.task, this.due);

  String get dueLabel => normalizeTimeOfDay('${due.hour}:${due.minute}')!;
}

/// Opfølgnings-status for ét barn på et givet tidspunkt.
class ChildFollowUp {
  final String childId;

  /// Obligatoriske opgaver i dag, endnu ikke udført, frist ikke passeret.
  final List<DueTask> dueToday;

  /// Obligatoriske opgaver i dag, endnu ikke udført, frist passeret.
  final List<DueTask> overdue;

  /// Sat mens pausetiden efter en for sent udført opgave løber.
  final DateTime? latePauseUntil;

  final bool inWindow;

  /// En forælder har ophævet spærringen for i dag.
  final bool suspended;

  const ChildFollowUp({
    required this.childId,
    required this.dueToday,
    required this.overdue,
    required this.latePauseUntil,
    required this.inWindow,
    required this.suspended,
  });

  /// Om barnets tablet skal være spærret lige nu.
  bool get restricted =>
      inWindow && !suspended && (overdue.isNotEmpty || latePauseUntil != null);

  /// Kort forklaring til barnet/forældrene, eller `null` hvis ikke spærret.
  String? get reason {
    if (!restricted) return null;
    if (overdue.isNotEmpty) {
      final names = overdue
          .map((d) => '${d.task.title} (frist ${d.dueLabel})')
          .join(', ');
      return 'Mangler: $names';
    }
    final until = latePauseUntil!;
    return 'Opgaven er udført for sent - låses op kl. '
        '${normalizeTimeOfDay('${until.hour}:${until.minute}')}';
  }

  /// Den tidligste frist i dag der endnu ikke er nået (til advarsler).
  DueTask? get nextDue {
    if (dueToday.isEmpty) return null;
    return dueToday.reduce((a, b) => a.due.isBefore(b.due) ? a : b);
  }
}

/// Beregner [ChildFollowUp] for ét barn.
///
/// [tasks] er de aktive opgaver der gælder for barnet, og [completions]
/// barnets egne completions (alle opgaver). [suspendedOn] er datoen
/// (`YYYY-MM-DD`) for en evt. forælder-ophævelse.
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
      continue; // venter på godkendelse, allerede gjort, eller ikke i dag
    }
    // 'unlimited'-opgaver er altid "available" - en godkendt udførelse i
    // dag tæller alligevel som at dagens pligt er gjort.
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

/// `YYYY-MM-DD` for [d] (lokal tid).
String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
