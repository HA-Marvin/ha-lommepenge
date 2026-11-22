import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/balance_adjustment.dart';
import '../models/child.dart';
import '../models/completion.dart';
import '../models/task.dart';
import '../providers/app_state.dart';
import '../widgets/amount_text.dart';
import 'children_screen.dart';
import 'settings_screen.dart';
import 'task_edit_screen.dart';

/// Forælder-tilstand: opgaver, børn, godkendelser, overblik/saldo,
/// historik og indstillinger - samlet i faner. Nye enheder tilføjes i
/// Home Assistant, og familiens data er med i HA's backups. Kræver at brugeren allerede har
/// tastet korrekt PIN (håndteret af [PinEntryScreen] før denne skærm
/// åbnes).
class ParentHomeScreen extends StatelessWidget {
  const ParentHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Forælder-tilstand'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Skift til barne-tilstand',
            onPressed: () => Navigator.of(context).pop(),
          ),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Opgaver', icon: Icon(Icons.checklist)),
              Tab(text: 'Børn', icon: Icon(Icons.family_restroom_outlined)),
              Tab(text: 'Godkendelser', icon: Icon(Icons.fact_check_outlined)),
              Tab(text: 'Overblik', icon: Icon(Icons.savings_outlined)),
              Tab(text: 'Historik', icon: Icon(Icons.history)),
              Tab(text: 'Indstillinger', icon: Icon(Icons.tune)),
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

    return Scaffold(
      body: tasks.isEmpty
          ? const Center(child: Text('Ingen opgaver oprettet endnu.'))
          : ListView.builder(
              itemCount: tasks.length,
              itemBuilder: (context, index) {
                final task = tasks[index];
                return ListTile(
                  title: Text(task.title),
                  subtitle: Text(
                    '${formatKr(task.amountOre)} · ${task.recurrence.label}'
                    '${task.dueTime != null ? ' · frist ${task.dueTime}' : ''}'
                    '${task.showInCalendar ? ' · i kalender' : ''}',
                  ),
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
        title: const Text('Slet opgave'),
        content: Text('Er du sikker på at du vil slette "${task.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annullér'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Slet'),
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
    final pending = appState.completions
        .where((c) => c.status == CompletionStatus.pending)
        .toList()
      ..sort((a, b) => b.completedAt.compareTo(a.completedAt));

    if (pending.isEmpty) {
      return const Center(child: Text('Ingen opgaver venter på godkendelse.'));
    }

    final tasksById = {for (final t in appState.tasks) t.id: t};
    final childrenById = appState.childrenById;

    return ListView.builder(
      itemCount: pending.length,
      itemBuilder: (context, index) {
        final completion = pending[index];
        final task = tasksById[completion.taskId];
        final title = task?.title ?? 'Ukendt opgave';
        final childName = childrenById[completion.childId]?.name ?? 'Ukendt barn';

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: ListTile(
            title: Text(title),
            subtitle: Text(
              '$childName · ${formatKr(completion.amountAtCompletionOre)} · '
              '${_formatDateTime(completion.completedAt)}'
              '${completion.late ? ' · for sent' : ''}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.red),
                  tooltip: 'Afvis',
                  onPressed: () => context
                      .read<AppState>()
                      .rejectCompletion(completion.id),
                ),
                IconButton(
                  icon: const Icon(Icons.check, color: Colors.green),
                  tooltip: 'Godkend',
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

  String _formatDateTime(DateTime d) {
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${d.day}/${d.month}/${d.year} kl. $hh:$mm';
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
          label: const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Justér saldo'),
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
          title: const Text('Justér saldo'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Brug dette til at rette en forkert saldo, fx efter en '
                  'geninstallation. Beløbet kan være negativt.',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedChildId,
                  decoration: const InputDecoration(
                    labelText: 'Barn',
                    border: OutlineInputBorder(),
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
                  decoration: const InputDecoration(
                    labelText: 'Beløb (kr, +/-)',
                    border: OutlineInputBorder(),
                    suffixText: 'kr',
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
                      return 'Angiv et beløb forskelligt fra 0.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: noteController,
                  decoration: const InputDecoration(
                    labelText: 'Begrundelse',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'Begrundelse er påkrævet.'
                      : null,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Annullér'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.of(ctx).pop(true);
                }
              },
              child: const Text('Gem'),
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Saldo justeret med ${formatKr(amountOre)}.')),
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
            Text('Optjent, ikke udbetalt',
                style: Theme.of(context).textTheme.titleSmall),
            Text(
              formatKr(balance),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text('Udbetalt i alt',
                style: Theme.of(context).textTheme.titleSmall),
            Text(
              formatKr(paidOut),
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.payments_outlined),
              label: const Text('Marker som udbetalt'),
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

/// Bekræfter og udfører en udbetaling for ét bestemt barn. Et top-level
/// funktion (ikke en instans-metode) da den ikke bruger nogen
/// instans-tilstand, og bruges fra `_ChildOverviewCard`'s knap pr. barn.
Future<void> _confirmPayout(BuildContext context, Child child) async {
  final appState = context.read<AppState>();
  final balance = appState.currentBalanceOreFor(child.id);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Marker som udbetalt'),
      content: Text(
        'Du er ved at markere ${formatKr(balance)} som udbetalt til '
        '${child.name}. Denne saldo nulstilles herefter til 0 kr. '
        'Fortsæt?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Annullér'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Ja, udbetal'),
        ),
      ],
    ),
  );
  if (confirmed == true) {
    await appState.markPaidOut(childId: child.id);
  }
}

/// Fælles type til at kunne sortere completions og saldo-justeringer
/// interleaved efter dato i historik-fanen.
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
    final approved = appState.completions
        .where((c) => c.status == CompletionStatus.approved)
        .toList();
    final adjustments = appState.balanceAdjustments;

    if (approved.isEmpty && adjustments.isEmpty) {
      return const Center(child: Text('Ingen fuldførte opgaver endnu.'));
    }

    final tasksById = {for (final t in appState.tasks) t.id: t};
    final childrenById = appState.childrenById;

    final entries = <_HistoryEntry>[
      for (final completion in approved)
        _HistoryEntry(
          date: completion.completedAt,
          tile: ListTile(
            leading: const Icon(Icons.check_circle, color: Colors.green),
            title: Text(tasksById[completion.taskId]?.title ?? 'Ukendt opgave'),
            subtitle: Text(
              '${childrenById[completion.childId]?.name ?? 'Ukendt barn'} · '
              '${_formatDate(completion.completedAt)}',
            ),
            trailing: Text(formatKr(completion.amountAtCompletionOre)),
          ),
        ),
      for (final adjustment in adjustments)
        _HistoryEntry(
          date: adjustment.createdAt,
          tile: _AdjustmentTile(
            adjustment: adjustment,
            childName: childrenById[adjustment.childId]?.name ?? 'Ukendt barn',
          ),
        ),
    ]..sort((a, b) => b.date.compareTo(a.date));

    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, index) => entries[index].tile,
    );
  }

  String _formatDate(DateTime d) => '${d.day}/${d.month}/${d.year}';
}

class _AdjustmentTile extends StatelessWidget {
  final BalanceAdjustment adjustment;
  final String childName;
  const _AdjustmentTile({required this.adjustment, required this.childName});

  @override
  Widget build(BuildContext context) {
    final isPositive = adjustment.amountOre >= 0;
    final sign = isPositive ? '+' : '';
    final color = isPositive ? Colors.green[700] : Colors.red[700];
    final d = adjustment.createdAt;
    return ListTile(
      leading: const Icon(Icons.tune, color: Colors.blueGrey),
      title: Text('Saldo-justering: ${adjustment.note}'),
      subtitle: Text('$childName · ${d.day}/${d.month}/${d.year}'),
      trailing: Text(
        '$sign${formatKr(adjustment.amountOre)}',
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
    );
  }
}
