import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/child.dart';
import '../models/task.dart';
import '../providers/app_state.dart';
import '../widgets/action_feedback.dart';
import '../widgets/amount_text.dart';
import '../widgets/lock_view.dart';
import 'children_screen.dart';
import 'history_screen.dart';
import 'settings_screen.dart';
import 'task_edit_screen.dart';

/// Parent mode: tasks, children, approvals, overview/balance, history and
/// settings - gathered in tabs. Everything shown comes from Home Assistant's
/// latest state (the parent part of it), and every change is an action HA
/// confirms (see `AppState`). New devices are added in Home Assistant.
/// Opened by `openParentMode`: on the family screen only after the correct
/// PIN, on a parent's phone directly (Del H5).
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
            // Fetched from HA when the tab is shown, dropped when it is left.
            HistoryScreen(embedded: true),
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
                final busy = appState.isBusy(AppState.taskKey(task.id));
                return ListTile(
                  title: Text(task.title),
                  subtitle: Text([
                    formatAmount(l10n, task.amountOre, appState.currency),
                    task.recurrence.label(l10n),
                    if (task.mandatory) l10n.mustBeDone,
                    if (task.dueTime != null) l10n.deadlineAt(task.dueTime!),
                    if (task.showInCalendar) l10n.inCalendar,
                  ].join(' · ')),
                  trailing: busy
                      ? const BusyIndicator()
                      : Row(
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
      final appState = context.read<AppState>();
      await runAction(context, () => appState.deleteTask(task.id));
    }
  }
}

class _ApprovalsTab extends StatelessWidget {
  const _ApprovalsTab();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final l10n = context.l10n;
    final pending = appState.approvals;
    final approvingAll = appState.isBusy(AppState.approveAllKey);

    if (pending.isEmpty) {
      return Center(child: Text(l10n.noPendingApprovals));
    }

    return ListView.builder(
      itemCount: pending.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: FilledButton.icon(
              icon: approvingAll
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.done_all),
              label: Text(l10n.approveAll),
              onPressed: approvingAll
                  ? null
                  : () => _approveAll(
                        context,
                        [for (final a in pending) a.completionId],
                      ),
            ),
          );
        }
        final approval = pending[index - 1];
        final title =
            approval.taskTitle.isEmpty ? l10n.unknownTask : approval.taskTitle;
        final childName =
            approval.childName.isEmpty ? l10n.unknownChild : approval.childName;
        final completedAt = approval.completedAt;
        final busy = approvingAll ||
            appState.isBusy(AppState.completionKey(approval.completionId));

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: ListTile(
            title: Text(title),
            subtitle: Text([
              childName,
              formatAmount(l10n, approval.amountOre, appState.currency),
              if (completedAt != null) formatDateTime(l10n, completedAt),
              if (approval.late) l10n.late,
            ].join(' · ')),
            trailing: busy
                ? const BusyIndicator()
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.red),
                        tooltip: l10n.reject,
                        onPressed: () => _reject(context, approval.completionId),
                      ),
                      IconButton(
                        icon: const Icon(Icons.check, color: Colors.green),
                        tooltip: l10n.approve,
                        onPressed: () => runAction(
                          context,
                          () => appState
                              .approveCompletion(approval.completionId),
                        ),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

/// "Approve all" (Del H5): after one confirmation approves exactly the
/// [completionIds] shown. Tasks the parent does not want to approve must be
/// rejected first - there is no selection.
Future<void> _approveAll(
  BuildContext context,
  List<String> completionIds,
) async {
  final appState = context.read<AppState>();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(ctx.l10n.approveAllTitle(completionIds.length)),
      content: Text(ctx.l10n.approveAllHelp),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(ctx.l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(ctx.l10n.approveAll),
        ),
      ],
    ),
  );
  if (confirmed == true && context.mounted) {
    await runAction(context, () => appState.approveCompletions(completionIds));
  }
}

/// Asks for an optional reason (the child sees it in the notification) and
/// rejects the completion.
Future<void> _reject(BuildContext context, String completionId) async {
  final appState = context.read<AppState>();
  final reason = await showDialog<String>(
    context: context,
    builder: (_) => const _RejectDialog(),
  );
  if (reason == null || !context.mounted) return;
  await runAction(
    context,
    () => appState.rejectCompletion(completionId, reason: reason),
  );
}

/// Returns the (possibly empty) reason, or `null` when cancelled. Owns its
/// text controller, so it lives as long as the dialog's closing animation.
class _RejectDialog extends StatefulWidget {
  const _RejectDialog();

  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.rejectTitle),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 500,
        maxLines: 3,
        minLines: 1,
        decoration: InputDecoration(
          labelText: l10n.rejectReasonLabel,
          helperText: l10n.rejectReasonHelp,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(l10n.reject),
        ),
      ],
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final children = appState.children;
    final adjusting = appState.isBusy(AppState.adjustKey);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final child in children) ...[
          _ChildOverviewCard(appState: appState, child: child),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: adjusting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.tune),
          label: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(context.l10n.adjustBalance),
          ),
          onPressed: children.isEmpty || adjusting
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
      final l10n = context.l10n;
      await runAction(
        context,
        () => appState.adjustBalance(
          amountOre: amountOre,
          note: note,
          childId: selectedChildId,
        ),
        success: l10n.balanceAdjustedBy(
          formatAmount(l10n, amountOre, appState.currency),
        ),
      );
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
    final balance = child.balanceOre;
    final busy = appState.isBusy(AppState.payoutKey(child.id));
    final lock = child.lock;
    final lifting = appState.isBusy(AppState.lockKey(child.id));
    final pausing = appState.isBusy(AppState.pauseKey(child.id));

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
            const SizedBox(height: 4),
            Text(
              l10n.thisWeekAmount(
                formatAmount(l10n, child.earnedThisWeekOre, appState.currency),
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.payments_outlined),
              label: Text(l10n.markAsPaidOut),
              onPressed: balance <= 0 || busy
                  ? null
                  : () => _confirmPayout(context, child),
            ),
            const Divider(height: 32),
            LockStatusLine(child: child),
            if (lock.isPending || lock.isRunning) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: lifting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.lock_open),
                label: Text(l10n.liftLock),
                onPressed: lifting
                    ? null
                    : () => runAction(
                          context,
                          () => appState.liftLock(child.id),
                          success: l10n.lockLifted,
                        ),
              ),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.pauseChild),
              subtitle: Text(l10n.pauseHelp),
              secondary: pausing ? const BusyIndicator() : null,
              value: child.paused,
              onChanged: pausing
                  ? null
                  : (value) => value
                      ? _pause(context, child)
                      : runAction(
                          context,
                          () => appState.setPause(child.id, paused: false),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pauses [child], with an optional end date chosen in a dialog (the first
/// day the tasks are mandatory again; after HA's today).
Future<void> _pause(BuildContext context, Child child) async {
  final appState = context.read<AppState>();
  final today = DateTime.tryParse(appState.today ?? '') ?? DateTime.now();
  final firstDay = DateTime(today.year, today.month, today.day + 1);
  final choice = await showDialog<_PauseChoice>(
    context: context,
    builder: (ctx) => _PauseDialog(childName: child.name, firstDay: firstDay),
  );
  if (choice == null || !context.mounted) return;
  await runAction(
    context,
    () => appState.setPause(child.id, paused: true, until: choice.until),
  );
}

/// The parent's choice in [_PauseDialog]: [until] is `YYYY-MM-DD` or `null`
/// (no end date).
class _PauseChoice {
  final String? until;
  const _PauseChoice(this.until);
}

class _PauseDialog extends StatefulWidget {
  final String childName;
  final DateTime firstDay;

  const _PauseDialog({required this.childName, required this.firstDay});

  @override
  State<_PauseDialog> createState() => _PauseDialogState();
}

class _PauseDialogState extends State<_PauseDialog> {
  DateTime? _until;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final until = _until;
    return AlertDialog(
      title: Text(l10n.pauseTitle(widget.childName)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.pauseHelp),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event),
            title: Text(l10n.pauseUntilLabel),
            subtitle: Text(
              until == null ? l10n.pauseNoEndDate : formatDate(l10n, until),
            ),
            trailing: until == null
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear),
                    tooltip: l10n.pauseNoEndDate,
                    onPressed: () => setState(() => _until = null),
                  ),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: until ?? widget.firstDay,
                firstDate: widget.firstDay,
                lastDate: widget.firstDay.add(const Duration(days: 365)),
              );
              if (picked != null) setState(() => _until = picked);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            _PauseChoice(until == null ? null : isoDate(until)),
          ),
          child: Text(l10n.pauseConfirm),
        ),
      ],
    );
  }
}

/// `YYYY-MM-DD`, as Home Assistant expects dates.
String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}'
    '-${d.day.toString().padLeft(2, '0')}';

/// Confirms and performs a payout for one specific child.
Future<void> _confirmPayout(BuildContext context, Child child) async {
  final appState = context.read<AppState>();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(ctx.l10n.markAsPaidOut),
      content: Text(
        ctx.l10n.confirmPayout(
          formatAmount(ctx.l10n, child.balanceOre, appState.currency),
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
  if (confirmed == true && context.mounted) {
    await runAction(context, () => appState.markPaidOut(childId: child.id));
  }
}
