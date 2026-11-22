/// En manuel, signeret (+/-) justering af saldoen, oprettet af en
/// forælder - fx for at rette en forkert saldo efter en geninstallation
/// der nulstillede den. [amountOre] kan være negativ. [note] er en
/// obligatorisk begrundelse, så justeringen altid kan forklares i
/// historikken.
class BalanceAdjustment {
  final String id;
  final int amountOre;
  final String note;

  /// Hvilket barn justeringen gælder for - hvert barn har sin egen
  /// saldo, se `TaskRepository.currentBalanceOre`.
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
      // Defensivt fallback til '' hvis en gammel række alligevel mangler
      // værdien - se samme kommentar i Completion.fromMap.
      childId: map['child_id'] as String? ?? '',
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  /// JSON-form brugt over sync-protokollen (camelCase-nøgler), adskilt
  /// fra [toMap]/[fromMap] der bruger databasens snake_case kolonnenavne.
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
