import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/child.dart';
import '../providers/app_state.dart';
import 'amount_text.dart';

/// One entry of a child's task list, exactly as Home Assistant sent it:
/// amount, status, date and deadline, with a "Done" button that is only
/// enabled when HA says the task can be done now ([TaskEntry.canComplete]).
/// While the tap is waiting for HA the button shows a spinner ([busy]).
class TaskCard extends StatelessWidget {
  final TaskEntry entry;

  /// Shown on the card when several children's lists are mixed (the
  /// parent's phone); `null` otherwise.
  final String? childName;
  final bool busy;
  final VoidCallback onComplete;

  const TaskCard({
    super.key,
    required this.entry,
    this.childName,
    this.busy = false,
    required this.onComplete,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final currency = context.watch<AppState>().currency;
    final theme = Theme.of(context);
    final upcoming = entry.status == TaskEntryStatus.upcoming;

    final card = Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      // Mandatory tasks ("must be done") are marked with a red border/tint,
      // so they stand out from optional tasks.
      color: entry.mandatory ? Colors.red[50] : null,
      shape: entry.mandatory
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.red[400]!, width: 1.5),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              entry.title,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (entry.description != null &&
                entry.description!.trim().isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(entry.description!, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  formatAmount(l10n, entry.amountOre, currency),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.green[700],
                    fontWeight: FontWeight.bold,
                  ),
                ),
                _chip(Text(entry.recurrence.label(l10n))),
                if (entry.mandatory)
                  _chip(
                    Text(l10n.mustBeDone),
                    avatar: Icon(
                      Icons.priority_high,
                      size: 16,
                      color: Colors.red[800],
                    ),
                    color: Colors.red[100],
                  ),
                if (entry.startTime != null)
                  _chip(
                    Text(l10n.fromTime(entry.startTime!)),
                    avatar: const Icon(Icons.schedule, size: 16),
                  ),
                if (childName != null)
                  _chip(
                    Text(childName!),
                    avatar: const Icon(Icons.person, size: 16),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _StatusLabel(entry: entry)),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: entry.canComplete && !busy ? onComplete : null,
                  child: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.done),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    // Later days are shown faded, so today's tasks stand out.
    return upcoming ? Opacity(opacity: 0.6, child: card) : card;
  }

  static Widget _chip(Widget label, {Widget? avatar, Color? color}) => Chip(
        avatar: avatar,
        label: label,
        backgroundColor: color,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );
}

/// The entry's status, and its deadline when it has one.
class _StatusLabel extends StatelessWidget {
  final TaskEntry entry;

  const _StatusLabel({required this.entry});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final today = context.select<AppState, String?>((s) => s.today);
    late final String text;
    late final Color color;
    late final IconData icon;

    switch (entry.status) {
      case TaskEntryStatus.available:
        text = l10n.statusAvailable;
        color = Colors.blue[700]!;
        icon = Icons.play_circle_outline;
      case TaskEntryStatus.overdue:
        text = l10n.statusOverdue;
        color = Colors.red[700]!;
        icon = Icons.warning_amber;
      case TaskEntryStatus.awaitingApproval:
        text = entry.late
            ? '${l10n.statusPending} · ${l10n.late}'
            : l10n.statusPending;
        color = Colors.orange[800]!;
        icon = Icons.hourglass_top;
      case TaskEntryStatus.upcoming:
        text = l10n.statusUpcomingOn(formatWeekdayDayMonth(l10n, entry.date));
        color = Colors.grey[700]!;
        icon = Icons.event;
    }
    final deadline = entry.deadline;
    final showDeadline =
        deadline != null && entry.status != TaskEntryStatus.awaitingApproval;

    final style = Theme.of(context).textTheme.bodySmall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Flexible(
              child: Text(text, style: style?.copyWith(color: color)),
            ),
          ],
        ),
        if (showDeadline)
          Padding(
            padding: const EdgeInsets.only(top: 2, left: 20),
            child: Text(
              l10n.deadlineLabel(formatDeadline(l10n, deadline, today)),
              style: style,
            ),
          ),
      ],
    );
  }
}
