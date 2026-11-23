/// How often a task can be done.
///
/// [weekly] is no longer offered in the create/edit task UI (30 Aug 2026) - a
/// "week plan" (Task.activeWeekdays) on a [daily] task covers the same need
/// (e.g. "only Tuesday and Thursday") more flexibly. The value is kept in the
/// enum for backwards compatibility, so a task that was already created as
/// weekly keeps working.
///
/// The display text per language is `RecurrenceLabel.label` in
/// `l10n/l10n.dart`.
enum Recurrence {
  once('once'),
  daily('daily'),
  weekly('weekly'),
  unlimited('unlimited');

  final String value;
  const Recurrence(this.value);

  static Recurrence fromValue(String value) {
    return Recurrence.values.firstWhere(
      (r) => r.value == value,
      orElse: () => Recurrence.once,
    );
  }
}

/// Normalizes a list of weekdays (1=Monday..7=Sunday) to `null` when the list
/// actually means "every day" (empty, or contains all 7), so there is always
/// one unambiguous representation of "no filter".
List<int>? _normalizeWeekdays(List<int>? weekdays) {
  if (weekdays == null || weekdays.isEmpty) return null;
  final unique = weekdays.toSet();
  if (unique.length >= 7) return null;
  final sorted = unique.toList()..sort();
  return sorted;
}

/// Normalizes a list of child ids to `null` when the list is empty ("all
/// children", see [Task.assignedChildIds]).
List<String>? _normalizeChildIds(List<String>? childIds) {
  if (childIds == null || childIds.isEmpty) return null;
  final unique = <String>[];
  for (final id in childIds) {
    if (!unique.contains(id)) unique.add(id);
  }
  return unique;
}

/// A task as a parent edits it - from `state.tasks[]` in parent mode. What a
/// child sees is a [TaskEntry] (see `child.dart`), calculated by HA.
///
/// [amountOre] is the amount in 1/100 of the family's currency (øre, cents
/// ...; the name is historic).
class Task {
  final String id;
  final String title;
  final String? description;
  final int amountOre;
  final Recurrence recurrence;

  /// Mandatory ("must be done") rather than optional ("can be done").
  final bool mandatory;

  /// Which weekdays the task is active on (1=Monday...7=Sunday). `null` means
  /// "every day". Only applies to recurring tasks (not [Recurrence.once]).
  final List<int>? activeWeekdays;

  /// Which children the task is assigned to. `null` means "all children" -
  /// dynamically, so children added later get it too.
  final List<String>? assignedChildIds;

  /// When the task should be done at the earliest (`"HH:MM"`). Informative.
  final String? startTime;

  /// The task's deadline (`"HH:MM"`). Without one, mandatory tasks use the
  /// family's default deadline (`FamilySettings.defaultDueTime`).
  final String? dueTime;

  /// Whether the task is shown as an event in the family calendar.
  final bool showInCalendar;

  Task({
    required this.id,
    required this.title,
    this.description,
    required this.amountOre,
    required this.recurrence,
    this.mandatory = false,
    List<int>? activeWeekdays,
    List<String>? assignedChildIds,
    String? startTime,
    String? dueTime,
    this.showInCalendar = false,
  })  : activeWeekdays = _normalizeWeekdays(activeWeekdays),
        assignedChildIds = _normalizeChildIds(assignedChildIds),
        startTime = normalizeTimeOfDay(startTime),
        dueTime = normalizeTimeOfDay(dueTime);

  /// The payload of `create_task`/`update_task` (see docs/app-api.md).
  /// Explicit `null`s clear a value; 'once' has no week plan.
  Map<String, Object?> toPayload() => {
        'id': id,
        'title': title,
        'description': description,
        'amountOre': amountOre,
        'recurrence': recurrence.value,
        'mandatory': mandatory,
        'activeWeekdays': recurrence == Recurrence.once ? null : activeWeekdays,
        'assignedChildIds': assignedChildIds,
        'startTime': startTime,
        'dueTime': dueTime,
        'showInCalendar': showInCalendar,
      };

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      description: json['description'] as String?,
      amountOre: (json['amountOre'] as num?)?.toInt() ?? 0,
      recurrence: Recurrence.fromValue(json['recurrence'] as String? ?? ''),
      mandatory: json['mandatory'] as bool? ?? false,
      activeWeekdays: (json['activeWeekdays'] as List?)
          ?.map((d) => (d as num).toInt())
          .toList(),
      assignedChildIds: (json['assignedChildIds'] as List?)?.cast<String>(),
      startTime: json['startTime'] as String?,
      dueTime: json['dueTime'] as String?,
      showInCalendar: json['showInCalendar'] as bool? ?? false,
    );
  }
}

/// Normalizes a time of day to `"HH:MM"` (e.g. `"7:5"` -> `"07:05"`), or
/// `null` if the value is empty or invalid.
String? normalizeTimeOfDay(String? value) {
  final minutes = minutesOfDay(value);
  if (minutes == null) return null;
  final h = (minutes ~/ 60).toString().padLeft(2, '0');
  final m = (minutes % 60).toString().padLeft(2, '0');
  return '$h:$m';
}

/// `"HH:MM"` -> minutes after midnight, or `null` if invalid.
int? minutesOfDay(String? value) {
  if (value == null) return null;
  final parts = value.trim().split(':');
  if (parts.length != 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
    return null;
  }
  return h * 60 + m;
}
