import 'package:flutter/material.dart';

import '../logic/recurrence.dart';
import '../models/task.dart';
import 'amount_text.dart';

/// Ét barns tilgængeligheds-status for én bestemt opgave - bruges af
/// [TaskCard] til at vise/håndtere hvert tildelt barn uafhængigt af de
/// andre (en opgave delt mellem flere børn optjenes pr. barn, jf.
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

/// Viser én opgave i barne-tilstand med tydeligt beløb, status og en
/// "Udført"-knap der kun er aktiv når opgaven kan udføres.
///
/// [childStatuses] er statussen for hvert barn opgaven reelt er tildelt
/// lige nu (jf. [Task.assignedChildIds] og den dynamiske "alle børn").
/// Er der kun ét barn tildelt, vises den simple ét-knap-UI som hidtil
/// (med barnets navn vist direkte på kortet); er der flere, vises én
/// række pr. barn med sit eget navn og sin egen knap/status, så børnene
/// kan markere/godkendes helt uafhængigt af hinanden.
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

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      // Obligatoriske opgaver ("skal udføres") markeres tydeligt med rød
      // kant/tint, så de visuelt skiller sig ud fra valgfri opgaver
      // (som beholder kortets almindelige udseende).
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
                  formatKr(task.amountOre),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.green[700],
                        fontWeight: FontWeight.bold,
                      ),
                ),
                Chip(
                  label: Text(task.recurrence.label),
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
                    label: const Text('Skal udføres'),
                    backgroundColor: Colors.red[100],
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                if (task.startTime != null || task.dueTime != null)
                  Chip(
                    avatar: const Icon(Icons.schedule, size: 16),
                    label: Text([
                      if (task.startTime != null) 'fra ${task.startTime}',
                      if (task.dueTime != null) 'senest ${task.dueTime}',
                    ].join(' · ')),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                // Ved kun ét tildelt barn vises navnet direkte her som en
                // ekstra chip - ved flere børn vises navnene i stedet i
                // hver sin række nedenfor, så de ikke gentages to steder.
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
                'Ikke tildelt noget barn i familien.',
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

/// Den simple ét-knap-UI, uændret fra før "flere børn"-featuren - bruges
/// når opgaven reelt kun er tildelt ét barn.
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
          child: const Text('Udført'),
        ),
      ],
    );
  }
}

/// Én række for ét barn på en opgave der er delt mellem flere børn -
/// eget navn, egen status og egen knap, helt uafhængigt af de andre
/// børns rækker på samme kort.
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
            child: const Text('Udført'),
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
    late final String text;
    late final Color color;
    late final IconData icon;

    switch (availability) {
      case TaskAvailability.available:
        text = 'Klar til at blive udført';
        color = Colors.blue[700]!;
        icon = Icons.play_circle_outline;
        break;
      case TaskAvailability.pendingApproval:
        text = 'Venter på godkendelse';
        color = Colors.orange[800]!;
        icon = Icons.hourglass_top;
        break;
      case TaskAvailability.doneToday:
        text = 'Udført i dag - tilgængelig igen i morgen';
        color = Colors.grey[600]!;
        icon = Icons.check_circle_outline;
        break;
      case TaskAvailability.doneThisWeek:
        final dateText = nextAvailableAt != null
            ? ' (${_formatDate(nextAvailableAt!)})'
            : '';
        text = 'Udført denne uge - tilgængelig igen$dateText';
        color = Colors.grey[600]!;
        icon = Icons.check_circle_outline;
        break;
      case TaskAvailability.completedOnce:
        text = 'Fuldført';
        color = Colors.grey[600]!;
        icon = Icons.check_circle;
        break;
      case TaskAvailability.notScheduledToday:
        final dateText = nextAvailableAt != null
            ? ' (${_formatDate(nextAvailableAt!)})'
            : '';
        text = 'Ikke på ugeplanen i dag$dateText';
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

  String _formatDate(DateTime d) {
    return '${d.day}/${d.month}';
  }
}
