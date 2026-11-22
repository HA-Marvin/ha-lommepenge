/// How often a task can be done.
///
/// [weekly] is no longer offered in the create/edit task UI (30 Aug 2026) - a
/// "week plan" (Task.activeWeekdays) on a [daily] task covers the same need
/// (e.g. "only Tuesday and Thursday") more flexibly. The value is kept in the
/// enum for backwards compatibility, so a task that was already created as
/// weekly keeps working and syncing correctly.
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
/// actually means "every day" (empty, or contains all 7), so DB/JSON always
/// has one unambiguous representation of "no filter".
List<int>? _normalizeWeekdays(List<int>? weekdays) {
  if (weekdays == null || weekdays.isEmpty) return null;
  final unique = weekdays.toSet();
  if (unique.length >= 7) return null;
  final sorted = unique.toList()..sort();
  return sorted;
}

/// Normalizes a list of child ids to `null` when the list is empty, so DB/JSON
/// always has one unambiguous representation of "no specific children chosen"
/// (= "all children", see [Task.assignedChildIds]). Deliberately NOT a
/// corresponding "all ids chosen -> null" rule like for [_normalizeWeekdays]:
/// the Task model does not know the family's full list of children, so only
/// the UI/repository layer (which actually knows the list) can decide whether
/// "all chosen individually" should really be stored as the dynamic "all
/// children" value (null) instead.
List<String>? _normalizeChildIds(List<String>? childIds) {
  if (childIds == null || childIds.isEmpty) return null;
  final unique = <String>[];
  for (final id in childIds) {
    if (!unique.contains(id)) unique.add(id);
  }
  return unique;
}

/// A task created by a parent.
///
/// [amountOre] is the amount in 1/100 of the family's currency (øre, cents
/// ...; the name is historic) to avoid rounding errors with double values.
class Task {
  final String id;
  final String title;
  final String? description;
  final int amountOre;
  final Recurrence recurrence;
  final DateTime createdAt;
  final bool active;

  /// Whether the task is marked as mandatory ("must be done") rather than
  /// optional ("can be done"). Default false, so existing tasks from before
  /// this field stay optional. Mandatory tasks are followed up (deadline,
  /// restriction) - see `logic/follow_up.dart`.
  final bool mandatory;

  /// Which weekdays the task is active on (`DateTime.weekday` convention:
  /// 1=Monday...7=Sunday). `null` or an empty list means "every day" - the
  /// backwards-compatible default for existing tasks and for one-off tasks.
  /// Only applies to recurring tasks (not [Recurrence.once]).
  final List<int>? activeWeekdays;

  /// Which children the task is assigned to. `null` or an empty list means
  /// "all children" - and it is DYNAMIC: if a new child is added to the family
  /// later, the task automatically applies to it too, without this task
  /// having to be edited. Exactly the same pattern as [activeWeekdays] uses
  /// for "every day" - see `TaskRepository.resolvedChildIdsForTask` for how
  /// "all children" is looked up dynamically.
  final List<String>? assignedChildIds;

  /// When the task should be done at the earliest (`"HH:MM"`), e.g. 06:45 for
  /// "Pack the school bag". Informative only (shown on the card and used as
  /// the start of a calendar event) - the task can still be done earlier.
  final String? startTime;

  /// The task's deadline (`"HH:MM"`). For mandatory tasks without their own
  /// deadline the family's default deadline is used (see
  /// `FamilySettings.defaultDueTime`). After the deadline an undone mandatory
  /// task counts as overdue (restriction/notification), but can still be
  /// marked as done.
  final String? dueTime;

  /// Whether the task is shown as an event in the family calendar. Off by default.
  final bool showInCalendar;

  Task({
    required this.id,
    required this.title,
    this.description,
    required this.amountOre,
    required this.recurrence,
    required this.createdAt,
    this.active = true,
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

  /// Whether the task is active (can be done) on [date], based on
  /// [activeWeekdays]. `null`/empty list/all 7 days means always active.
  bool isActiveOn(DateTime date) {
    final weekdays = activeWeekdays;
    if (weekdays == null || weekdays.isEmpty) return true;
    return weekdays.contains(date.weekday);
  }

  Task copyWith({
    String? title,
    String? description,
    bool clearDescription = false,
    int? amountOre,
    Recurrence? recurrence,
    bool? active,
    bool? mandatory,
    List<int>? activeWeekdays,
    bool clearActiveWeekdays = false,
    List<String>? assignedChildIds,
    bool clearAssignedChildIds = false,
    String? startTime,
    bool clearStartTime = false,
    String? dueTime,
    bool clearDueTime = false,
    bool? showInCalendar,
  }) {
    return Task(
      id: id,
      title: title ?? this.title,
      description:
          clearDescription ? null : (description ?? this.description),
      amountOre: amountOre ?? this.amountOre,
      recurrence: recurrence ?? this.recurrence,
      createdAt: createdAt,
      active: active ?? this.active,
      mandatory: mandatory ?? this.mandatory,
      activeWeekdays: clearActiveWeekdays
          ? null
          : (activeWeekdays ?? this.activeWeekdays),
      assignedChildIds: clearAssignedChildIds
          ? null
          : (assignedChildIds ?? this.assignedChildIds),
      startTime: clearStartTime ? null : (startTime ?? this.startTime),
      dueTime: clearDueTime ? null : (dueTime ?? this.dueTime),
      showInCalendar: showInCalendar ?? this.showInCalendar,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'amount_ore': amountOre,
      'recurrence': recurrence.value,
      'created_at': createdAt.toIso8601String(),
      'active': active ? 1 : 0,
      'mandatory': mandatory ? 1 : 0,
      'active_weekdays': activeWeekdays?.join(','),
      'assigned_child_ids': assignedChildIds?.join(','),
      'start_time': startTime,
      'due_time': dueTime,
      'show_in_calendar': showInCalendar ? 1 : 0,
    };
  }

  factory Task.fromMap(Map<String, Object?> map) {
    final rawWeekdays = map['active_weekdays'] as String?;
    final rawChildIds = map['assigned_child_ids'] as String?;
    return Task(
      id: map['id'] as String,
      title: map['title'] as String,
      description: map['description'] as String?,
      amountOre: map['amount_ore'] as int,
      recurrence: Recurrence.fromValue(map['recurrence'] as String),
      createdAt: DateTime.parse(map['created_at'] as String),
      active: (map['active'] as int) == 1,
      // Defensive fallback to 0/optional if an old row/DB version lacks the
      // column (should not happen after the migration in DatabaseHelper, but
      // being robust costs nothing).
      mandatory: (map['mandatory'] as int? ?? 0) == 1,
      activeWeekdays: (rawWeekdays == null || rawWeekdays.isEmpty)
          ? null
          : rawWeekdays.split(',').map(int.parse).toList(),
      // 'null'/missing column means "all children" - correct for ALL tasks
      // created before this feature, no backfill needed.
      assignedChildIds: (rawChildIds == null || rawChildIds.isEmpty)
          ? null
          : rawChildIds.split(','),
      startTime: map['start_time'] as String?,
      dueTime: map['due_time'] as String?,
      showInCalendar: (map['show_in_calendar'] as int? ?? 0) == 1,
    );
  }

  /// JSON form used over the sync protocol (camelCase keys), separate from
  /// [toMap]/[fromMap] which use the database's snake_case column names.
  Map<String, Object?> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'amountOre': amountOre,
      'recurrence': recurrence.value,
      'createdAt': createdAt.toIso8601String(),
      'active': active,
      'mandatory': mandatory,
      'activeWeekdays': activeWeekdays,
      'assignedChildIds': assignedChildIds,
      'startTime': startTime,
      'dueTime': dueTime,
      'showInCalendar': showInCalendar,
    };
  }

  factory Task.fromJson(Map<String, Object?> json) {
    return Task(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      amountOre: json['amountOre'] as int,
      recurrence: Recurrence.fromValue(json['recurrence'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      active: json['active'] as bool? ?? true,
      // '?? false'/'?? null' keep sync backwards compatible if the sender
      // does not know the field yet.
      mandatory: json['mandatory'] as bool? ?? false,
      activeWeekdays:
          (json['activeWeekdays'] as List?)?.cast<int>(),
      // The same backwards-compatible '?? null' (the key is missing entirely
      // if the sender does not know the "several children" feature) -> "all
      // children", which is correct for all tasks from before it existed.
      assignedChildIds:
          (json['assignedChildIds'] as List?)?.cast<String>(),
      // The same backwards-compatible pattern: an older sender does not send
      // times/calendar choice -> no times, not in the calendar.
      startTime: json['startTime'] as String?,
      dueTime: json['dueTime'] as String?,
      showInCalendar: json['showInCalendar'] as bool? ?? false,
    );
  }
}

/// Normalizes a time of day to `"HH:MM"` (e.g. `"7:5"` -> `"07:05"`), or
/// `null` if the value is empty or invalid. One unambiguous representation in
/// DB/JSON, so comparisons and display always work.
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
