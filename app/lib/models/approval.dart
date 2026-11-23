/// A completion waiting for a parent (`state.approvals[]`, parent mode),
/// oldest first as HA sends them.
class Approval {
  final String completionId;
  final String childId;
  final String childName;
  final String taskId;
  final String taskTitle;
  final int amountOre;

  /// When the child marked it as done (HA's local time).
  final DateTime? completedAt;

  /// Done after the deadline.
  final bool late;

  const Approval({
    required this.completionId,
    required this.childId,
    required this.childName,
    required this.taskId,
    required this.taskTitle,
    required this.amountOre,
    this.completedAt,
    this.late = false,
  });

  factory Approval.fromJson(Map<String, dynamic> json) {
    return Approval(
      completionId: json['completionId'] as String,
      childId: json['childId'] as String? ?? '',
      childName: json['childName'] as String? ?? '',
      taskId: json['taskId'] as String? ?? '',
      taskTitle: json['taskTitle'] as String? ?? '',
      amountOre: (json['amountOre'] as num?)?.toInt() ?? 0,
      completedAt: DateTime.tryParse('${json['completedAt']}'),
      late: json['late'] as bool? ?? false,
    );
  }
}
