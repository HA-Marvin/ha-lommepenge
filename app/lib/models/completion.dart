/// Status of a completed task, until a parent has decided.
enum CompletionStatus {
  pending('pending'),
  approved('approved'),
  rejected('rejected');

  final String value;
  const CompletionStatus(this.value);

  static CompletionStatus fromValue(String value) {
    return CompletionStatus.values.firstWhere(
      (s) => s.value == value,
      orElse: () => CompletionStatus.pending,
    );
  }
}

/// A record that a child has marked a task as done.
///
/// [amountAtCompletionOre] is a copy of the task's amount at the time of
/// completion, so a later price change on the task does not change the
/// history.
class Completion {
  final String id;
  final String taskId;

  /// Which child did/earns this completion. For a task assigned to several
  /// children each child earns its own completion for the same task,
  /// completely independently of the others - see
  /// `TaskRepository.completeTask`.
  final String childId;
  final DateTime completedAt;
  final CompletionStatus status;
  final DateTime? approvedAt;
  final int amountAtCompletionOre;

  /// Whether the task was marked as done after its deadline (mandatory tasks
  /// only). Calculated at completion and stored, so a later change of the
  /// deadline does not change the history. Triggers the pause before the
  /// tablet is unlocked (see `logic/follow_up.dart`) and is shown on approval.
  final bool late;

  const Completion({
    required this.id,
    required this.taskId,
    required this.childId,
    required this.completedAt,
    required this.status,
    this.approvedAt,
    required this.amountAtCompletionOre,
    this.late = false,
  });

  Completion copyWith({
    CompletionStatus? status,
    DateTime? approvedAt,
    bool clearApprovedAt = false,
  }) {
    return Completion(
      id: id,
      taskId: taskId,
      childId: childId,
      completedAt: completedAt,
      status: status ?? this.status,
      approvedAt: clearApprovedAt ? null : (approvedAt ?? this.approvedAt),
      amountAtCompletionOre: amountAtCompletionOre,
      late: late,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'task_id': taskId,
      'child_id': childId,
      'completed_at': completedAt.toIso8601String(),
      'status': status.value,
      'approved_at': approvedAt?.toIso8601String(),
      'amount_at_completion_ore': amountAtCompletionOre,
      'late': late ? 1 : 0,
    };
  }

  factory Completion.fromMap(Map<String, Object?> map) {
    return Completion(
      id: map['id'] as String,
      taskId: map['task_id'] as String,
      // Defensive fallback to '' if an old row still lacks the value - should
      // not happen, as the DatabaseHelper migration backfills all old rows
      // with a default child, but the app must never crash on an unexpected
      // old/corrupt row.
      childId: map['child_id'] as String? ?? '',
      completedAt: DateTime.parse(map['completed_at'] as String),
      status: CompletionStatus.fromValue(map['status'] as String),
      approvedAt: map['approved_at'] == null
          ? null
          : DateTime.parse(map['approved_at'] as String),
      amountAtCompletionOre: map['amount_at_completion_ore'] as int,
      late: (map['late'] as int? ?? 0) == 1,
    );
  }

  /// JSON form used over the sync protocol (camelCase keys), separate from
  /// [toMap]/[fromMap] which use the database's snake_case column names.
  Map<String, Object?> toJson() {
    return {
      'id': id,
      'taskId': taskId,
      'childId': childId,
      'completedAt': completedAt.toIso8601String(),
      'status': status.value,
      'approvedAt': approvedAt?.toIso8601String(),
      'amountAtCompletionOre': amountAtCompletionOre,
      'late': late,
    };
  }

  factory Completion.fromJson(Map<String, Object?> json) {
    return Completion(
      id: json['id'] as String,
      taskId: json['taskId'] as String,
      // The same defensive fallback as fromMap - see the comment there.
      childId: json['childId'] as String? ?? '',
      completedAt: DateTime.parse(json['completedAt'] as String),
      status: CompletionStatus.fromValue(json['status'] as String),
      approvedAt: json['approvedAt'] == null
          ? null
          : DateTime.parse(json['approvedAt'] as String),
      amountAtCompletionOre: json['amountAtCompletionOre'] as int,
      late: json['late'] as bool? ?? false,
    );
  }
}
