import 'package:flutter/material.dart';

import '../logic/follow_up.dart';
import '../models/child.dart';
import '../models/family_settings.dart';
import '../models/task.dart';
import '../providers/app_state.dart';
import 'amount_text.dart';
import 'task_card.dart';
import 'weekly_progress.dart';

/// Opgaverne for ÉT barn, i appens almindelige "hvad skal gøres nu"-
/// rækkefølge. Bruges af barnets tablet (hele skærmen) og af
/// køleskabsskærmens kolonne pr. barn.
List<Task> tasksForChild(AppState appState, String childId) => appState.tasks
    .where((t) => appState.resolvedChildIdsFor(t).contains(childId))
    .toList();

/// Markerer [task] udført for [childId] og viser resultatet som SnackBar.
Future<void> completeTaskWithFeedback(
  BuildContext context,
  AppState appState,
  Task task,
  String childId,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await appState.completeTask(task, childId: childId);
    messenger.showSnackBar(
      const SnackBar(content: Text('Sendt til godkendelse!')),
    );
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('$e')));
  }
}

/// Opgavekort for ét barn - kun barnets egen status og knap, også for
/// opgaver der er delt mellem flere børn.
class ChildTaskCard extends StatelessWidget {
  final AppState appState;
  final Child child;
  final Task task;

  const ChildTaskCard({
    super.key,
    required this.appState,
    required this.child,
    required this.task,
  });

  @override
  Widget build(BuildContext context) {
    return TaskCard(
      task: task,
      childStatuses: [
        ChildTaskStatus(
          childId: child.id,
          childName: child.name,
          availability: appState.availabilityOf(task, child.id),
          nextAvailableAt: appState.nextAvailableFor(task, child.id),
        ),
      ],
      onComplete: (childId) =>
          completeTaskWithFeedback(context, appState, task, childId),
    );
  }
}

/// Besked til barnet om spærring eller en frist der nærmer sig. Vises
/// øverst på barnets tablet og i barnets kolonne på køleskabet. Tom, når
/// der intet er at sige.
class FollowUpBanner extends StatelessWidget {
  final ChildFollowUp? followUp;
  final FamilySettings settings;

  const FollowUpBanner({
    super.key,
    required this.followUp,
    required this.settings,
  });

  @override
  Widget build(BuildContext context) {
    final f = followUp;
    if (f == null || f.suspended) return const SizedBox.shrink();

    if (f.restricted) {
      final pauseUntil = f.latePauseUntil;
      final String detail;
      if (f.overdue.isNotEmpty) {
        final list = f.overdue.map((d) => d.task.title).join(', ');
        detail = 'Lav først: $list. Så låses de op igen.';
      } else if (pauseUntil != null) {
        final left = pauseUntil.difference(DateTime.now()).inMinutes + 1;
        detail = 'Opgaven er udført for sent, så der går $left '
            'minut${left == 1 ? '' : 'ter'}, før din tablet bliver låst op igen.';
      } else {
        detail = f.reason ?? '';
      }
      return _Banner(
        color: Colors.red,
        icon: Icons.block,
        title: 'Spil og YouTube er spærret',
        text: detail,
      );
    }

    if (f.overdue.isNotEmpty) {
      final list = f.overdue.map((d) => d.task.title).join(', ');
      return _Banner(
        color: Colors.orange,
        icon: Icons.warning_amber,
        title: 'Du er bagud',
        text: '$list skulle være lavet. Spil og YouTube spærres fra kl. '
            '${settings.restrictionStart}, hvis det ikke er gjort.',
      );
    }

    final next = f.nextDue;
    if (next != null) {
      final minutesLeft = next.due.difference(DateTime.now()).inMinutes;
      if (minutesLeft <= settings.warningMinutes) {
        return _Banner(
          color: Colors.orange,
          icon: Icons.alarm,
          title: 'Husk: ${next.task.title}',
          text: 'Skal være lavet kl. ${next.dueLabel}, ellers spærres spil og '
              'YouTube.',
        );
      }
    }
    return const SizedBox.shrink();
  }
}

class _Banner extends StatelessWidget {
  final MaterialColor color;
  final IconData icon;
  final String title;
  final String text;

  const _Banner({
    required this.color,
    required this.icon,
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color[50],
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color[400]!, width: 1.5),
      ),
      child: ListTile(
        leading: Icon(icon, color: color[800], size: 32),
        title: Text(
          title,
          style: TextStyle(fontWeight: FontWeight.bold, color: color[900]),
        ),
        subtitle: Text(text, style: TextStyle(color: color[900])),
      ),
    );
  }
}

/// Barnets navn, saldo og ugens fremskridt.
class ChildSummaryCard extends StatelessWidget {
  final AppState appState;
  final Child child;
  final bool large;

  const ChildSummaryCard({
    super.key,
    required this.appState,
    required this.child,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: EdgeInsets.all(large ? 24 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              child.name,
              style: (large ? text.headlineSmall : text.titleMedium)
                  ?.copyWith(fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              formatKr(appState.currentBalanceOreFor(child.id)),
              style: (large ? text.displaySmall : text.headlineSmall)
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Denne uge: ${formatKr(appState.earnedThisWeekOreFor(child.id))}',
              style: text.bodySmall,
            ),
            const SizedBox(height: 8),
            WeeklyProgress(
              completedCount: appState.completedCountThisWeekFor(child.id),
            ),
          ],
        ),
      ),
    );
  }
}
