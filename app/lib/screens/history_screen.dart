import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/history.dart';
import '../providers/app_state.dart';
import '../widgets/amount_text.dart';

/// The history, fetched from Home Assistant when the screen opens - 30 days
/// at a time, with "Show older" for the next 30 - and dropped again when it
/// closes (Del H2: the device never stores history).
///
/// With [childId] (the child's tablet) only that child's history is shown,
/// without filters - HA refuses other children for a tablet anyway. Without
/// it (parent mode) all children are shown, with an optional filter by child
/// and by type. [embedded] leaves out the app bar (a tab in parent mode).
class HistoryScreen extends StatefulWidget {
  final String? childId;
  final bool embedded;

  const HistoryScreen({super.key, this.childId, this.embedded = false});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final List<HistoryItem> _items = [];
  String? _from;
  String? _before;
  String? _nextBefore;
  bool _loading = false;
  String? _error;

  /// Parent mode's filters: `null` = all children; empty = all types.
  String? _childFilter;
  final Set<String> _typeFilter = {};

  /// Increased on every new (first-page) request, so an answer to an older
  /// request (e.g. before the filter was changed) is dropped.
  int _generation = 0;

  bool get _forOneChild => widget.childId != null;

  @override
  void initState() {
    super.initState();
    _loading = true;
    _load(null, first: true);
  }

  void _reload() {
    _generation++;
    setState(() {
      _items.clear();
      _from = null;
      _before = null;
      _nextBefore = null;
      _error = null;
    });
    _load(null);
  }

  Future<void> _load(String? before, {bool first = false}) async {
    final generation = _generation;
    if (!first) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final page = await context.read<AppState>().fetchHistory(
            before: before,
            childId: _forOneChild ? widget.childId : _childFilter,
            types: _typeFilter.isEmpty
                ? null
                : [
                    for (final type in historyTypes)
                      if (_typeFilter.contains(type)) type,
                  ],
          );
      if (!mounted || generation != _generation) return;
      setState(() {
        _items.addAll(page.items);
        _from = page.from;
        _before ??= page.before;
        _nextBefore = page.nextBefore;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final list = RefreshIndicator(
      onRefresh: () async => _reload(),
      child: ListView(
        children: [
          if (!_forOneChild) _filters(context),
          if (_from != null && _before != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                l10n.historyPeriod(
                  formatDate(l10n, DateTime.parse(_from!)),
                  formatDate(
                    l10n,
                    DateTime.parse(_before!).subtract(const Duration(days: 1)),
                  ),
                ),
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          if (_items.isEmpty && !_loading && _error == null)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(l10n.historyEmpty, textAlign: TextAlign.center),
            ),
          for (final item in _items)
            _HistoryTile(item: item, showChild: !_forOneChild),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () =>
                        _items.isEmpty ? _reload() : _load(_nextBefore),
                    child: Text(l10n.tryAgain),
                  ),
                ],
              ),
            ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_nextBefore != null && _error == null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.expand_more),
                label: Text(l10n.showOlder),
                onPressed: () => _load(_nextBefore),
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
    if (widget.embedded) return list;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.history)),
      body: list,
    );
  }

  Widget _filters(BuildContext context) {
    final l10n = context.l10n;
    final children = context.watch<AppState>().children;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButton<String?>(
            value: children.any((c) => c.id == _childFilter)
                ? _childFilter
                : null,
            isExpanded: true,
            items: [
              DropdownMenuItem(value: null, child: Text(l10n.allChildren)),
              for (final child in children)
                DropdownMenuItem(value: child.id, child: Text(child.name)),
            ],
            onChanged: (value) {
              _childFilter = value;
              _reload();
            },
          ),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final type in historyTypes)
                FilterChip(
                  label: Text(historyTypeLabel(l10n, type)),
                  selected: _typeFilter.contains(type),
                  onSelected: (selected) {
                    if (selected) {
                      _typeFilter.add(type);
                    } else {
                      _typeFilter.remove(type);
                    }
                    _reload();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The display name of a history type (the raw type for unknown ones).
String historyTypeLabel(AppLocalizations l10n, String type) {
  switch (type) {
    case 'approved':
      return l10n.historyApproved;
    case 'rejected':
      return l10n.historyRejected;
    case 'missed':
      return l10n.historyMissed;
    case 'adjustment':
      return l10n.historyAdjustment;
  }
  return type;
}

class _HistoryTile extends StatelessWidget {
  final HistoryItem item;
  final bool showChild;

  const _HistoryTile({required this.item, required this.showChild});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final currency = context.select<AppState, String>((s) => s.currency);
    final IconData icon;
    final Color color;
    switch (item.type) {
      case 'approved':
        icon = Icons.check_circle;
        color = Colors.green[700]!;
      case 'rejected':
        icon = Icons.cancel;
        color = Colors.red[700]!;
      case 'missed':
        icon = Icons.event_busy;
        color = Colors.orange[800]!;
      case 'adjustment':
        icon = Icons.tune;
        color = Colors.blueGrey;
      default:
        icon = Icons.info_outline;
        color = Colors.grey[700]!;
    }

    final String title;
    if (item.type == 'adjustment') {
      title = l10n.balanceAdjustment(item.note ?? '');
    } else {
      title = item.taskTitle ?? item.note ?? l10n.unknownTask;
    }
    final childName = item.childName.isEmpty ? l10n.unknownChild : item.childName;
    final completedAt = item.completedAt;
    final subtitle = [
      if (showChild) childName,
      historyTypeLabel(l10n, item.type),
      formatDateTime(l10n, item.at),
      if (completedAt != null) l10n.doneAt(formatDateTime(l10n, completedAt)),
      if (item.late) l10n.late,
    ].join(' · ');

    // Only approved tasks and adjustments changed the balance; rejected and
    // missed ones show what they would have given, struck through.
    final gaveMoney = item.type == 'approved' || item.type == 'adjustment';
    final sign = item.type == 'adjustment' && item.amountOre > 0 ? '+' : '';
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Text(
        '$sign${formatAmount(l10n, item.amountOre, currency)}',
        style: TextStyle(
          fontWeight: gaveMoney ? FontWeight.bold : null,
          color: gaveMoney
              ? (item.amountOre < 0 ? Colors.red[700] : Colors.green[700])
              : Colors.grey[600],
          decoration: gaveMoney ? null : TextDecoration.lineThrough,
        ),
      ),
    );
  }
}
