import 'task.dart';

/// A child in the family, exactly as Home Assistant sends it in the state
/// (`state.children[]`). Everything here is calculated by HA - the app shows
/// it as it is and calculates nothing itself (Del H1).
class Child {
  final String id;
  final String name;

  /// The order the family has chosen (HA already sends the children sorted).
  final int sortOrder;

  /// Earned and not paid out yet.
  final int balanceOre;
  final int earnedThisWeekOre;

  /// The child's task list: one entry per task, at most 5 days ahead, in
  /// HA's order (see [TaskEntry]).
  final List<TaskEntry> tasks;

  const Child({
    required this.id,
    required this.name,
    this.sortOrder = 0,
    this.balanceOre = 0,
    this.earnedThisWeekOre = 0,
    this.tasks = const [],
  });

  /// Reads one child defensively: a task entry the app cannot read is
  /// skipped instead of hiding the whole list.
  factory Child.fromJson(Map<String, dynamic> json) {
    final tasks = <TaskEntry>[];
    for (final raw in (json['tasks'] as List?) ?? const []) {
      if (raw is! Map<String, dynamic>) continue;
      final entry = TaskEntry.tryParse(raw);
      if (entry != null) tasks.add(entry);
    }
    return Child(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      balanceOre: (json['balanceOre'] as num?)?.toInt() ?? 0,
      earnedThisWeekOre: (json['earnedThisWeekOre'] as num?)?.toInt() ?? 0,
      tasks: tasks,
    );
  }
}

/// The status of a task entry, decided by Home Assistant.
enum TaskEntryStatus {
  /// Can be marked as done now.
  available,

  /// The deadline has passed; can still be marked as done (it is then late).
  overdue,

  /// Done, waiting for a parent.
  awaitingApproval,

  /// A later day within the 5-day horizon; cannot be marked as done yet.
  upcoming;

  static TaskEntryStatus? fromValue(String? value) {
    for (final status in values) {
      if (status.name == value) return status;
    }
    return null;
  }
}

/// One entry in a child's task list (`state.children[].tasks[]`): the task's
/// next occurrence for the child, with date, deadline and status - all
/// calculated by HA.
class TaskEntry {
  final String taskId;
  final String title;
  final String? description;

  /// What the task gives (for a pending completion: the amount when it was
  /// done).
  final int amountOre;
  final Recurrence recurrence;
  final bool mandatory;
  final String? startTime;
  final String? dueTime;

  /// The day of this occurrence (HA's local date).
  final DateTime date;

  /// When the occurrence is late (HA's local time), or `null` (optional tasks
  /// have no deadline).
  final DateTime? deadline;
  final TaskEntryStatus status;

  /// The pending completion when [status] is
  /// [TaskEntryStatus.awaitingApproval].
  final String? completionId;

  /// The pending completion was done after the deadline.
  final bool late;

  const TaskEntry({
    required this.taskId,
    required this.title,
    this.description,
    required this.amountOre,
    required this.recurrence,
    this.mandatory = false,
    this.startTime,
    this.dueTime,
    required this.date,
    this.deadline,
    required this.status,
    this.completionId,
    this.late = false,
  });

  /// Whether the "Done" button is enabled.
  bool get canComplete =>
      status == TaskEntryStatus.available || status == TaskEntryStatus.overdue;

  /// `null` when the entry cannot be read (e.g. a status this version of the
  /// app does not know yet) - it is then not shown.
  static TaskEntry? tryParse(Map<String, dynamic> json) {
    final status = TaskEntryStatus.fromValue(json['status'] as String?);
    final taskId = json['taskId'];
    final date = DateTime.tryParse('${json['date']}');
    if (status == null || taskId is! String || date == null) return null;
    final deadline = json['deadline'];
    return TaskEntry(
      taskId: taskId,
      title: json['title'] as String? ?? '',
      description: json['description'] as String?,
      amountOre: (json['amountOre'] as num?)?.toInt() ?? 0,
      recurrence: Recurrence.fromValue(json['recurrence'] as String? ?? ''),
      mandatory: json['mandatory'] as bool? ?? false,
      startTime: json['startTime'] as String?,
      dueTime: json['dueTime'] as String?,
      date: date,
      deadline: deadline is String ? DateTime.tryParse(deadline) : null,
      status: status,
      completionId: json['completionId'] as String?,
      late: json['late'] as bool? ?? false,
    );
  }
}
