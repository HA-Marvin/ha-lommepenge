import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/child.dart';
import '../providers/app_state.dart';
import 'action_feedback.dart';
import 'amount_text.dart';
import 'task_card.dart';

/// Marks [entry] as done for [childId] and shows the result as a SnackBar
/// ("Try again" on an error sends the same completion id again).
Future<void> completeTaskWithFeedback(
  BuildContext context,
  AppState appState,
  TaskEntry entry,
  String childId,
) =>
    runAction(
      context,
      () => appState.completeTask(entry, childId: childId),
      success: context.l10n.sentForApproval,
    );

/// The cards for one child's task list, exactly in Home Assistant's order.
/// Used by the child's tablet, the family screen's column per child and the
/// parent's phone. [showChildName] puts the child's name on every card.
List<Widget> childTaskCards(
  BuildContext context,
  AppState appState,
  Child child, {
  bool showChildName = false,
}) =>
    [
      for (final entry in child.tasks)
        TaskCard(
          key: ValueKey('${child.id}/${entry.taskId}'),
          entry: entry,
          childName: showChildName ? child.name : null,
          busy: appState.isBusy(AppState.completeKey(child.id, entry.taskId)),
          onComplete: () =>
              completeTaskWithFeedback(context, appState, entry, child.id),
        ),
    ];

/// The child's name, balance and what was earned this week - all from HA.
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
              formatAmount(l10n, child.balanceOre, appState.currency),
              style: (large ? text.displaySmall : text.headlineSmall)
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.thisWeekAmount(
                formatAmount(l10n, child.earnedThisWeekOre, appState.currency),
              ),
              style: text.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
