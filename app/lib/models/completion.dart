/// Status for en udført opgave, indtil forælder har taget stilling.
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

/// En registrering af at et barn har markeret en opgave som udført.
///
/// [amountAtCompletionOre] er en kopi af opgavens beløb på
/// udførelsestidspunktet, så en senere prisændring på opgaven ikke
/// ændrer historikken.
class Completion {
  final String id;
  final String taskId;

  /// Hvilket barn der har udført/optjener denne completion. Ved en
  /// opgave tildelt flere børn optjener hvert barn sin egen completion
  /// for samme opgave, helt uafhængigt af de andre - se
  /// `TaskRepository.completeTask`.
  final String childId;
  final DateTime completedAt;
  final CompletionStatus status;
  final DateTime? approvedAt;
  final int amountAtCompletionOre;

  /// Om opgaven blev markeret udført efter sin frist (kun obligatoriske
  /// opgaver). Beregnes ved udførelsen og gemmes, så en senere ændring af
  /// fristen ikke ændrer historikken. Udløser pausetiden før tabletten
  /// låses op (se `logic/follow_up.dart`) og vises ved godkendelse.
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
      // Defensivt fallback til '' hvis en gammel række alligevel mangler
      // værdien - bør ikke ske, da DatabaseHelper-migrationen backfiller
      // alle gamle rækker med et standard-barn, men appen må under ingen
      // omstændigheder crashe på en uventet gammel/korrupt række.
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

  /// JSON-form brugt over sync-protokollen (camelCase-nøgler), adskilt
  /// fra [toMap]/[fromMap] der bruger databasens snake_case kolonnenavne.
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
      // Samme defensive fallback som fromMap - se kommentaren der.
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
