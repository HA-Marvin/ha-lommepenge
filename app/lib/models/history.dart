/// The kinds of history items HA sends (and the values of the `types`
/// filter). Unknown types (e.g. `lock`, coming later) are still shown, with
/// a neutral look.
const historyTypes = ['approved', 'rejected', 'adjustment', 'missed'];

/// One item in the history (`GET /history`, `items[]`).
class HistoryItem {
  final String id;
  final String type;

  /// When it happened (HA's local time), see docs/app-api.md.
  final DateTime at;
  final String childId;

  /// The current name (empty if the child no longer exists).
  final String childName;
  final String? taskId;
  final String? taskTitle;

  /// Signed for adjustments.
  final int amountOre;
  final DateTime? completedAt;
  final bool late;
  final String? note;

  const HistoryItem({
    required this.id,
    required this.type,
    required this.at,
    required this.childId,
    this.childName = '',
    this.taskId,
    this.taskTitle,
    this.amountOre = 0,
    this.completedAt,
    this.late = false,
    this.note,
  });

  static HistoryItem? tryParse(Map<String, dynamic> json) {
    final at = DateTime.tryParse('${json['at']}');
    final type = json['type'];
    if (at == null || type is! String) return null;
    final completedAt = json['completedAt'];
    return HistoryItem(
      id: '${json['id']}',
      type: type,
      at: at,
      childId: json['childId'] as String? ?? '',
      childName: json['childName'] as String? ?? '',
      taskId: json['taskId'] as String?,
      taskTitle: json['taskTitle'] as String?,
      amountOre: (json['amountOre'] as num?)?.toInt() ?? 0,
      completedAt: completedAt is String ? DateTime.tryParse(completedAt) : null,
      late: json['late'] as bool? ?? false,
      note: json['note'] as String?,
    );
  }
}

/// One page of history: the 30 days `from` <= day < `before`, newest first.
/// [nextBefore] is the `before` of the next (older) page, or `null` when
/// nothing older exists.
class HistoryPage {
  final String from;
  final String before;
  final List<HistoryItem> items;
  final String? nextBefore;

  const HistoryPage({
    required this.from,
    required this.before,
    required this.items,
    this.nextBefore,
  });

  factory HistoryPage.fromJson(Map<String, dynamic> json) {
    final items = <HistoryItem>[];
    for (final raw in (json['items'] as List?) ?? const []) {
      if (raw is! Map<String, dynamic>) continue;
      final item = HistoryItem.tryParse(raw);
      if (item != null) items.add(item);
    }
    return HistoryPage(
      from: json['from'] as String? ?? '',
      before: json['before'] as String? ?? '',
      items: items,
      nextBefore: json['nextBefore'] as String?,
    );
  }
}
