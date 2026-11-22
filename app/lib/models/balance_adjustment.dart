/// A manual, signed (+/-) adjustment of the balance, created by a parent -
/// e.g. to correct a wrong balance after a reinstall that reset it.
/// [amountOre] can be negative. [note] is a mandatory reason, so the
/// adjustment can always be explained in the history.
class BalanceAdjustment {
  final String id;
  final int amountOre;
  final String note;

  /// Which child the adjustment applies to - every child has its own
  /// balance, see `TaskRepository.currentBalanceOre`.
  final String childId;
  final DateTime createdAt;

  const BalanceAdjustment({
    required this.id,
    required this.amountOre,
    required this.note,
    required this.childId,
    required this.createdAt,
  });

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'amount_ore': amountOre,
      'note': note,
      'child_id': childId,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory BalanceAdjustment.fromMap(Map<String, Object?> map) {
    return BalanceAdjustment(
      id: map['id'] as String,
      amountOre: map['amount_ore'] as int,
      note: map['note'] as String,
      // Defensive fallback to '' if an old row still lacks the value - see
      // the same comment in Completion.fromMap.
      childId: map['child_id'] as String? ?? '',
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  /// JSON form used over the sync protocol (camelCase keys), separate from
  /// [toMap]/[fromMap] which use the database's snake_case column names.
  Map<String, Object?> toJson() {
    return {
      'id': id,
      'amountOre': amountOre,
      'note': note,
      'childId': childId,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory BalanceAdjustment.fromJson(Map<String, Object?> json) {
    return BalanceAdjustment(
      id: json['id'] as String,
      amountOre: json['amountOre'] as int,
      note: json['note'] as String,
      childId: json['childId'] as String? ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
