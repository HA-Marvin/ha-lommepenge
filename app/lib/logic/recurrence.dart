import '../models/completion.dart';
import '../models/task.dart';

/// Hvor vidt en opgave kan markeres "udført" af barnet lige nu, og
/// hvorfor/hvornår ikke.
enum TaskAvailability {
  /// Kan markeres udført nu.
  available,

  /// Der ligger allerede en udførelse og venter på forælder-godkendelse.
  pendingApproval,

  /// Udført og godkendt i dag (kun for daglige opgaver) - tilgængelig igen
  /// i morgen.
  doneToday,

  /// Udført og godkendt inden for de sidste 7 dage (kun for ugentlige
  /// opgaver) - tilgængelig igen når der er gået 7 dage.
  doneThisWeek,

  /// Engangsopgave der allerede er godkendt - kan ikke udføres igen.
  completedOnce,

  /// Opgaven er ikke på ugeplanen i dag (jf. [Task.activeWeekdays]) -
  /// gælder alle gentagelsestyper undtagen [Recurrence.once].
  notScheduledToday,
}

/// Dato (uden klokkeslæt) der bruges til at sammenligne "kalenderdage".
DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Beregner om [task] kan markeres udført lige nu, ud fra dens tidligere
/// [completions] (kun completions for denne ene opgave).
///
/// Reglerne (jf. spec):
/// - Der kan aldrig markeres udført igen mens der er en 'pending'
///   completion (venter på godkendelse).
/// - En afvist ('rejected') completion blokerer ikke - opgaven kan
///   forsøges igen med det samme.
/// - Er opgaven gentagende (ikke 'once') og ikke på ugeplanen for
///   dags dato (jf. [Task.isActiveOn]), er den ikke tilgængelig i dag -
///   uanset hvad recurrence-reglerne ellers ville sige.
/// - 'once': kan kun udføres/godkendes én gang nogensinde.
/// - 'daily': kan udføres igen når kalenderdagen er en anden end den
///   senest godkendte completion.
/// - 'weekly': kan udføres igen når der er gået mindst 7 dage siden den
///   senest godkendte completion.
/// - 'unlimited': kan altid udføres igen (kun blokeret af en pending
///   completion) - ignorerer bevidst godkendt-historikken.
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

/// Hvor mange dage frem der maksimalt søges efter en tilgængelig dato i
/// [nextAvailableDate] - fx hvis alle ugedage er fravalgt, findes der
/// aldrig en tilgængelig dato, og søgningen skal give op frem for at
/// løbe uendeligt.
const int _searchWindowDays = 14;

/// Hvornår opgaven tidligst er tilgængelig igen.
///
/// Bygget som en generisk dag-for-dag-søgning (frem for en lukket-form
/// switch på recurrence-typen), fordi kombinationen af ugedags-filter
/// (Feature 2) og recurrence-nedkøling (daily/weekly) ellers hurtigt
/// bliver svær at holde korrekt i to parallelle implementeringer: her
/// genbruges [computeAvailability] selv som eneste kilde til sandhed, og
/// vi finder simpelthen den første kommende dato (inkl. i dag) hvor den
/// ville svare 'available'. Returnerer `null` hvis ingen sådan dato
/// findes inden for søgevinduet (fx en opgave hvor alle 7 ugedage er
/// fravalgt).
DateTime? nextAvailableDate(
  Task task,
  List<Completion> completionsForTask, {
  DateTime? now,
}) {
  final today = _dateOnly(now ?? DateTime.now());

  // Så længe der ligger en pending completion, er der ingen mening i at
  // lede efter en "næste tilgængelige dato" - den afhænger af en
  // godkendelse/afvisning der endnu ikke er sket.
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
