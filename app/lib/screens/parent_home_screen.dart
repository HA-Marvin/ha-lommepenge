import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/balance_adjustment.dart';
import '../models/child.dart';
import '../models/completion.dart';
import '../models/task.dart';
import '../providers/app_state.dart';
import '../widgets/amount_text.dart';
import 'children_screen.dart';
import 'settings_screen.dart';
import 'task_edit_screen.dart';

/// Parent mode: tasks, children, approvals, overview/balance, history and
/// settings - gathered in tabs. New devices are added in Home Assistant, and
/// the family's data is part of HA's backups. Requires that the user has
/// already entered the correct PIN (handled by [PinEntryScreen] before this
/// screen is opened).
class ParentHomeScreen extends StatelessWidget {
  const ParentHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.parentMode),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: l10n.switchToChildMode,
            onPressed: () => Navigator.of(context).pop(),
          ),
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: l10n.tabTasks, icon: const Icon(Icons.checklist)),
              Tab(
                text: l10n.tabChildren,
                icon: const Icon(Icons.family_restroom_outlined),
              ),
              Tab(
                text: l10n.tabApprovals,
                icon: const Icon(Icons.fact_check_outlined),
              ),
              Tab(text: l10n.tabOverview, icon: const Icon(Icons.savings_outlined)),
              Tab(text: l10n.tabHistory, icon: const Icon(Icons.history)),
              Tab(text: l10n.tabSettings, icon: const Icon(Icons.tune)),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _TasksTab(),
            ChildrenScreen(),
            _ApprovalsTab(),
            _OverviewTab(),
            _HistoryTab(),
            SettingsTabContent(),
          ],
        ),
      ),
    );
  }
}

class _TasksTab extends StatelessWidget {
  const _TasksTab();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final tasks = appState.tasks;
    final l10n = context.l10n;

    return Scaffold(
      body: tasks.isEmpty
          ? Center(child: Text(l10n.noTasksYet))
          : ListView.builder(
              itemCount: tasks.length,
              itemBuilder: (context, index) {
                final task = tasks[index];
                return ListTile(
                  title: Text(task.title),
                  subtitle: Text([
                    formatAmount(l10n, task.amountOre, appState.currency),
                    task.recurrence.label(l10n),
                    if (task.dueTime != null) l10n.deadlineAt(task.dueTime!),
                    if (task.showInCalendar) l10n.inCalendar,
                  ].join(' · ')),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => TaskEditScreen(task: task),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _confirmDelete(context, task),
                      ),
                    ],
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const TaskEditScreen()),
        ),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, Task task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.deleteTask),
        content: Text(ctx.l10n.confirmDelete(task.title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ctx.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(ctx.l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<AppState>().deleteTask(task.id);
    }
  }
}

class _ApprovalsTab extends StatelessWidget {
  const _ApprovalsTab();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final l10n = context.l10n;
    final pending = appState.completions
        .where((c) => c.status == CompletionStatus.pending)
        .toList()
      ..sort((a, b) => b.completedAt.compareTo(a.completedAt));

    if (pending.isEmpty) {
      return Center(child: Text(l10n.noPendingApprovals));
    }

    final tasksById = {for (final t in appState.tasks) t.id: t};
    final childrenById = appState.childrenById;

    return ListView.builder(
      itemCount: pending.length,
      itemBuilder: (context, index) {
        final completion = pending[index];
        final task = tasksById[completion.taskId];
        final title = task?.title ?? l10n.unknownTask;
        final childName =
            childrenById[completion.childId]?.name ?? l10n.unknownChild;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: ListTile(
            title: Text(title),
            subtitle: Text([
              childName,
              formatAmount(l10n, completion.amountAtCompletionOre, appState.currency),
              formatDateTime(l10n, completion.completedAt),
              if (completion.late) l10n.late,
            ].join(' · ')),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.red),
                  tooltip: l10n.reject,
                  onPressed: () => context
                      .read<AppState>()
                      .rejectCompletion(completion.id),
                ),
                IconButton(
                  icon: const Icon(Icons.check, color: Colors.green),
                  tooltip: l10n.approve,
                  onPressed: () => context
                      .read<AppState>()
                      .approveCompletion(completion.id),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final children = appState.children;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final child in children) ...[
          _ChildOverviewCard(appState: appState, child: child),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.tune),
          label: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(context.l10n.adjustBalance),
          ),
          onPressed: children.isEmpty
              ? null
              : () => _openAdjustBalanceDialog(context, children),
        ),
      ],
    );
  }

  Future<void> _openAdjustBalanceDialog(
    BuildContext context,
    List<Child> children,
  ) async {
    final appState = context.read<AppState>();
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    String selectedChildId = children.first.id;

    int? parseKrToOre(String input) {
      final normalized = input.trim().replaceAll(',', '.');
      final value = double.tryParse(normalized);
      if (value == null) return null;
      return (value * 100).round();
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(ctx.l10n.adjustBalance),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  ctx.l10n.adjustBalanceHelp,
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedChildId,
                  decoration: InputDecoration(
                    labelText: ctx.l10n.child,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    for (final child in children)
                      DropdownMenuItem(
                        value: child.id,
                        child: Text(child.name),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => selectedChildId = value);
                    }
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: amountController,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: ctx.l10n.amountSigned(appState.currency),
                    border: const OutlineInputBorder(),
                    suffixText: appState.currency,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9,.\-]')),
                  ],
                  validator: (value) {
                    final parsed = parseKrToOre(value ?? '');
                    if (parsed == null || parsed == 0) {
                      return ctx.l10n.amountNonZero;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: noteController,
                  decoration: InputDecoration(
                    labelText: ctx.l10n.reason,
                    border: const OutlineInputBorder(),
                  ),
                  maxLines: 2,
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? ctx.l10n.reasonRequired
                      : null,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(ctx.l10n.cancel),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.of(ctx).pop(true);
                }
              },
              child: Text(ctx.l10n.save),
            ),
          ],
        ),
      ),
    );

    if (result == true && context.mounted) {
      final amountOre = parseKrToOre(amountController.text)!;
      final note = noteController.text.trim();
      try {
        await appState.adjustBalance(
          amountOre: amountOre,
          note: note,
          childId: selectedChildId,
        );
        if (context.mounted) {
          final l10n = context.l10n;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                l10n.balanceAdjustedBy(
                  formatAmount(l10n, amountOre, appState.currency),
                ),
              ),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('$e')));
        }
      }
    }
  }
}

class _ChildOverviewCard extends StatelessWidget {
  final AppState appState;
  final Child child;
  const _ChildOverviewCard({required this.appState, required this.child});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final balance = appState.currentBalanceOreFor(child.id);
    final paidOut = appState.settings.paidOutOreFor(child.id);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              child.name,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            Text(l10n.earnedNotPaidOut,
                style: Theme.of(context).textTheme.titleSmall),
            Text(
              formatAmount(l10n, balance, appState.currency),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(l10n.paidOutTotal,
                style: Theme.of(context).textTheme.titleSmall),
            Text(
              formatAmount(l10n, paidOut, appState.currency),
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.payments_outlined),
              label: Text(l10n.markAsPaidOut),
              onPressed: balance <= 0
                  ? null
                  : () => _confirmPayout(context, child),
            ),
          ],
        ),
      ),
    );
  }
}

/// Confirms and performs a payout for one specific child. A top-level
/// function (not an instance method) as it uses no instance state, and is
/// used from `_ChildOverviewCard`'s button per child.
Future<void> _confirmPayout(BuildContext context, Child child) async {
  final appState = context.read<AppState>();
  final balance = appState.currentBalanceOreFor(child.id);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(ctx.l10n.markAsPaidOut),
      content: Text(
        ctx.l10n.confirmPayout(
          formatAmount(ctx.l10n, balance, appState.currency),
          child.name,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(ctx.l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(ctx.l10n.yesPayOut),
        ),
      ],
    ),
  );
  if (confirmed == true) {
    await appState.markPaidOut(childId: child.id);
  }
}

/// Common type to be able to sort completions and balance adjustments
/// interleaved by date in the history tab.
class _HistoryEntry {
  final DateTime date;
  final Widget tile;
  const _HistoryEntry({required this.date, required this.tile});
}

class _HistoryTab extends StatelessWidget {
  const _HistoryTab();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final l10n = context.l10n;
    final approved = appState.completions
        .where((c) => c.status == CompletionStatus.approved)
        .toList();
    final adjustments = appState.balanceAdjustments;

    if (approved.isEmpty && adjustments.isEmpty) {
      return Center(child: Text(l10n.noCompletedTasksYet));
    }

    final tasksById = {for (final t in appState.tasks) t.id: t};
    final childrenById = appState.childrenById;

    final entries = <_HistoryEntry>[
      for (final completion in approved)
        _HistoryEntry(
          date: completion.completedAt,
          tile: ListTile(
            leading: const Icon(Icons.check_circle, color: Colors.green),
            title: Text(tasksById[completion.taskId]?.title ?? l10n.unknownTask),
            subtitle: Text(
              '${childrenById[completion.childId]?.name ?? l10n.unknownChild} · '
              '${formatDate(l10n, completion.completedAt)}',
            ),
            trailing: Text(
              formatAmount(
                l10n,
                completion.amountAtCompletionOre,
                appState.currency,
              ),
            ),
          ),
        ),
      for (final adjustment in adjustments)
        _HistoryEntry(
          date: adjustment.createdAt,
          tile: _AdjustmentTile(
            adjustment: adjustment,
            childName:
                childrenById[adjustment.childId]?.name ?? l10n.unknownChild,
          ),
        ),
    ]..sort((a, b) => b.date.compareTo(a.date));

    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, index) => entries[index].tile,
    );
  }
}

class _AdjustmentTile extends StatelessWidget {
  final BalanceAdjustment adjustment;
  final String childName;
  const _AdjustmentTile({required this.adjustment, required this.childName});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final currency = context.watch<AppState>().currency;
    final isPositive = adjustment.amountOre >= 0;
    final sign = isPositive ? '+' : '';
    final color = isPositive ? Colors.green[700] : Colors.red[700];
    return ListTile(
      leading: const Icon(Icons.tune, color: Colors.blueGrey),
      title: Text(l10n.balanceAdjustment(adjustment.note)),
      subtitle: Text('$childName · ${formatDate(l10n, adjustment.createdAt)}'),
      trailing: Text(
        '$sign${formatAmount(l10n, adjustment.amountOre, currency)}',
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
    );
  }
}
