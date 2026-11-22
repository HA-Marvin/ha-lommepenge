import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../logic/follow_up.dart';
import '../models/child.dart';
import '../models/family_settings.dart';
import '../models/task.dart';
import '../providers/app_state.dart';
import 'amount_text.dart';
import 'task_card.dart';
import 'weekly_progress.dart';

/// The tasks for ONE child, in the app's usual "what needs doing now" order.
/// Used by the child's tablet (the whole screen) and by the family screen's
/// column per child.
List<Task> tasksForChild(AppState appState, String childId) => appState.tasks
    .where((t) => appState.resolvedChildIdsFor(t).contains(childId))
    .toList();

/// Marks [task] as done for [childId] and shows the result as a SnackBar.
Future<void> completeTaskWithFeedback(
  BuildContext context,
  AppState appState,
  Task task,
  String childId,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final sent = context.l10n.sentForApproval;
  try {
    await appState.completeTask(task, childId: childId);
    messenger.showSnackBar(SnackBar(content: Text(sent)));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('$e')));
  }
}

/// Task card for one child - only the child's own status and button, also
/// for tasks shared between several children.
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

/// Message to the child about a restriction or an approaching deadline. Shown
/// at the top of the child's tablet and in the child's column on the family
/// screen. Empty when there is nothing to say.
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
    final l10n = context.l10n;

    if (f.restricted) {
      final pauseUntil = f.latePauseUntil;
      final String detail;
      if (f.overdue.isNotEmpty) {
        final list = f.overdue.map((d) => d.task.title).join(', ');
        detail = l10n.restrictedDoFirst(list);
      } else if (pauseUntil != null) {
        final left = pauseUntil.difference(DateTime.now()).inMinutes + 1;
        detail = l10n.restrictedLatePause(left);
      } else {
        detail = f.reason(l10n) ?? '';
      }
      return _Banner(
        color: Colors.red,
        icon: Icons.block,
        title: l10n.restrictedTitle,
        text: detail,
      );
    }

    if (f.overdue.isNotEmpty) {
      final list = f.overdue.map((d) => d.task.title).join(', ');
      return _Banner(
        color: Colors.orange,
        icon: Icons.warning_amber,
        title: l10n.behindTitle,
        text: l10n.behindBody(list, settings.restrictionStart),
      );
    }

    final next = f.nextDue;
    if (next != null) {
      final minutesLeft = next.due.difference(DateTime.now()).inMinutes;
      if (minutesLeft <= settings.warningMinutes) {
        return _Banner(
          color: Colors.orange,
          icon: Icons.alarm,
          title: l10n.reminderTitle(next.task.title),
          text: l10n.reminderBody(next.dueLabel),
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

/// The child's name, balance and the week's progress.
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
    final l10n = context.l10n;
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
              formatAmount(
                l10n,
                appState.currentBalanceOreFor(child.id),
                appState.currency,
              ),
              style: (large ? text.displaySmall : text.headlineSmall)
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.thisWeekAmount(
                formatAmount(
                  l10n,
                  appState.earnedThisWeekOreFor(child.id),
                  appState.currency,
                ),
              ),
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
