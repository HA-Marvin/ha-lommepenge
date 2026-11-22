/// Et barn i familien.
///
/// Appen understøttede indtil videre kun ét barn implicit - dette er den
/// nye model der gør familien til en liste af navngivne børn. Der er
/// bevidst intet hårdt kodet loft på antal børn nogen steder i modellen,
/// databasen eller forretningslogikken (UI'et er tænkt/testet mentalt
/// til typisk 1-3, men understøtter flere).
class Child {
  final String id;
  final String name;

  /// Bruges til at vise børnene i en stabil, brugervalgt rækkefølge (fx
  /// oprettelsesrækkefølge som default) frem for alfabetisk/tilfældig.
  final int sortOrder;
  final DateTime createdAt;

  const Child({
    required this.id,
    required this.name,
    required this.sortOrder,
    required this.createdAt,
  });

  Child copyWith({
    String? name,
    int? sortOrder,
  }) {
    return Child(
      id: id,
      name: name ?? this.name,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'sort_order': sortOrder,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Child.fromMap(Map<String, Object?> map) {
    return Child(
      id: map['id'] as String,
      name: map['name'] as String,
      sortOrder: map['sort_order'] as int? ?? 0,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  /// JSON-form brugt over sync-protokollen (camelCase-nøgler), adskilt
  /// fra [toMap]/[fromMap] der bruger databasens snake_case kolonnenavne.
  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'sortOrder': sortOrder,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Child.fromJson(Map<String, Object?> json) {
    return Child(
      id: json['id'] as String,
      name: json['name'] as String,
      sortOrder: json['sortOrder'] as int? ?? 0,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
