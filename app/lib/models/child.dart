/// A child in the family.
///
/// The family is a list of named children. There is deliberately no hard-coded
/// limit on the number of children anywhere in the model, the database or the
/// business logic (the UI is designed for typically 1-3, but supports more).
class Child {
  final String id;
  final String name;

  /// Used to show the children in a stable, user-chosen order (e.g. creation
  /// order by default) rather than alphabetical/random.
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

  /// JSON form used over the sync protocol (camelCase keys), separate from
  /// [toMap]/[fromMap] which use the database's snake_case column names.
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
