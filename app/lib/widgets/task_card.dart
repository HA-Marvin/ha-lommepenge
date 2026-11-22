import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../logic/recurrence.dart';
import '../models/task.dart';
import '../providers/app_state.dart';
import 'amount_text.dart';

/// One child's availability status for one specific task - used by
/// [TaskCard] to show/handle each assigned child independently of the others
/// (a task shared between several children is earned per child, see
/// `TaskRepository.completeTask`/`availabilityFor`).
class ChildTaskStatus {
  final String childId;
  final String childName;
  final TaskAvailability availability;
  final DateTime? nextAvailableAt;

  const ChildTaskStatus({
    required this.childId,
    required this.childName,
    required this.availability,
    this.nextAvailableAt,
  });
}

/// Shows one task in child mode with a clear amount, status and a "Done"
/// button that is only active when the task can be done.
///
/// [childStatuses] is the status for each child the task is actually
/// assigned to right now (see [Task.assignedChildIds] and the dynamic "all
/// children"). With only one child assigned, the simple one-button UI is shown
/// (with the child's name shown directly on the card); with several, one row
/// per child is shown with its own name and its own button/status, so the
/// children can mark/be approved completely independently of each other.
class TaskCard extends StatelessWidget {
  final Task task;
  final List<ChildTaskStatus> childStatuses;
  final void Function(String childId) onComplete;

  const TaskCard({
    super.key,
    required this.task,
    required this.childStatuses,
    required this.onComplete,
  });

  @override
  Widget build(BuildContext context) {
    final isShared = childStatuses.length > 1;
    final l10n = context.l10n;
    final currency = context.watch<AppState>().currency;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      // Mandatory tasks ("must be done") are marked clearly with a red
      // border/tint, so they stand out visually from optional tasks (which
      // keep the card's normal look).
      color: task.mandatory ? Colors.red[50] : null,
      shape: task.mandatory
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
              task.title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (task.description != null &&
                task.description!.trim().isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                task.description!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  formatAmount(l10n, task.amountOre, currency),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.green[700],
                        fontWeight: FontWeight.bold,
                      ),
                ),
                Chip(
                  label: Text(task.recurrence.label(l10n)),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                if (task.mandatory)
                  Chip(
                    avatar: Icon(
                      Icons.priority_high,
                      size: 16,
                      color: Colors.red[800],
                    ),
                    label: Text(l10n.mustBeDone),
                    backgroundColor: Colors.red[100],
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                if (task.startTime != null || task.dueTime != null)
                  Chip(
                    avatar: const Icon(Icons.schedule, size: 16),
                    label: Text([
                      if (task.startTime != null) l10n.fromTime(task.startTime!),
                      if (task.dueTime != null) l10n.byTime(task.dueTime!),
                    ].join(' · ')),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                // With only one assigned child the name is shown directly
                // here as an extra chip - with several children the names are
                // shown in a row each below instead, so they are not repeated
                // in two places.
                if (!isShared && childStatuses.isNotEmpty)
                  Chip(
                    avatar: const Icon(Icons.person, size: 16),
                    label: Text(childStatuses.first.childName),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (childStatuses.isEmpty)
              Text(
                l10n.notAssigned,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.grey[600]),
              )
            else if (!isShared)
              _SingleChildRow(
                status: childStatuses.first,
                onComplete: () => onComplete(childStatuses.first.childId),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < childStatuses.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    _ChildRow(
                      status: childStatuses[i],
                      onComplete: () => onComplete(childStatuses[i].childId),
                    ),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// The simple one-button UI - used when the task is actually only assigned to
/// one child.
class _SingleChildRow extends StatelessWidget {
  final ChildTaskStatus status;
  final VoidCallback onComplete;

  const _SingleChildRow({required this.status, required this.onComplete});

  @override
  Widget build(BuildContext context) {
    final isAvailable = status.availability == TaskAvailability.available;
    return Row(
      children: [
        Expanded(
          child: _StatusLabel(
            availability: status.availability,
            nextAvailableAt: status.nextAvailableAt,
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: isAvailable ? onComplete : null,
          child: Text(context.l10n.done),
        ),
      ],
    );
  }
}

/// One row for one child on a task shared between several children - its own
/// name, its own status and its own button, completely independent of the
/// other children's rows on the same card.
class _ChildRow extends StatelessWidget {
  final ChildTaskStatus status;
  final VoidCallback onComplete;

  const _ChildRow({required this.status, required this.onComplete});

  @override
  Widget build(BuildContext context) {
    final isAvailable = status.availability == TaskAvailability.available;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status.childName,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                _StatusLabel(
                  availability: status.availability,
                  nextAvailableAt: status.nextAvailableAt,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: isAvailable ? onComplete : null,
            child: Text(context.l10n.done),
          ),
        ],
      ),
    );
  }
}

class _StatusLabel extends StatelessWidget {
  final TaskAvailability availability;
  final DateTime? nextAvailableAt;

  const _StatusLabel({required this.availability, this.nextAvailableAt});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final next = nextAvailableAt;
    late final String text;
    late final Color color;
    late final IconData icon;

    switch (availability) {
      case TaskAvailability.available:
        text = l10n.statusAvailable;
        color = Colors.blue[700]!;
        icon = Icons.play_circle_outline;
        break;
      case TaskAvailability.pendingApproval:
        text = l10n.statusPending;
        color = Colors.orange[800]!;
        icon = Icons.hourglass_top;
        break;
      case TaskAvailability.doneToday:
        text = l10n.statusDoneToday;
        color = Colors.grey[600]!;
        icon = Icons.check_circle_outline;
        break;
      case TaskAvailability.doneThisWeek:
        text = next != null
            ? l10n.statusDoneThisWeekUntil(formatDayMonth(l10n, next))
            : l10n.statusDoneThisWeek;
        color = Colors.grey[600]!;
        icon = Icons.check_circle_outline;
        break;
      case TaskAvailability.completedOnce:
        text = l10n.statusCompleted;
        color = Colors.grey[600]!;
        icon = Icons.check_circle;
        break;
      case TaskAvailability.notScheduledToday:
        text = next != null
            ? l10n.statusNotScheduledUntil(formatDayMonth(l10n, next))
            : l10n.statusNotScheduled;
        color = Colors.grey[600]!;
        icon = Icons.event_busy;
        break;
    }

    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}
