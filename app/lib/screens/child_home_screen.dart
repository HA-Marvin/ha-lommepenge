import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/task.dart';
import '../providers/app_state.dart';
import '../widgets/child_task_list.dart';
import '../widgets/sync_indicator.dart';
import '../widgets/task_card.dart';
import '../widgets/update_banner.dart';
import 'parent_home_screen.dart';
import 'pin_entry_screen.dart';

/// Beder om forælder-PIN og åbner forælder-tilstand. Fælles for
/// forælder-telefonens og køleskabsskærmens visning; findes bevidst ikke
/// på barnets tablet.
Future<void> openParentMode(BuildContext context) async {
  final navigator = Navigator.of(context);
  final appState = context.read<AppState>();
  final unlocked = await navigator.push<bool>(
    MaterialPageRoute(builder: (_) => const PinEntryScreen()),
  );
  if (unlocked != true) return;
  appState.enterParentMode();
  await navigator.push(
    MaterialPageRoute(builder: (_) => const ParentHomeScreen()),
  );
  appState.exitParentMode();
}

/// Forælder-telefonens visning: ÉN fælles liste over opgaver (uanset
/// hvilket/hvilke børn de gælder for), samt hvert barns egen saldo og
/// ugentlige fremskridtsvisning øverst. Køleskabsskærmen bruger i stedet
/// `ScreenOverviewScreen` (én kolonne pr. barn), og barnets tablet
/// `ChildTabletHomeScreen`.
class ChildHomeScreen extends StatefulWidget {
  const ChildHomeScreen({super.key});

  @override
  State<ChildHomeScreen> createState() => _ChildHomeScreenState();
}

class _ChildHomeScreenState extends State<ChildHomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _trySync());
  }

  Future<void> _trySync() async {
    await context.read<AppState>().syncNow();
  }

  Future<void> _openParentMode() async {
    await openParentMode(context);
    if (mounted) await _trySync();
  }

  Future<void> _completeTask(
    AppState appState,
    Task task,
    String childId,
  ) async {
    try {
      await appState.completeTask(task, childId: childId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sendt til godkendelse!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  /// Bygger børnenes tilgængeligheds-status for [task], ét indgang pr.
  /// reelt tildelt barn (jf. den dynamiske "alle børn") - se [TaskCard].
  List<ChildTaskStatus> _childStatusesFor(AppState appState, Task task) {
    final childIds = appState.resolvedChildIdsFor(task);
    final childrenById = appState.childrenById;
    return childIds
        .map((childId) {
          final child = childrenById[childId];
          if (child == null) return null;
          return ChildTaskStatus(
            childId: childId,
            childName: child.name,
            availability: appState.availabilityOf(task, childId),
            nextAvailableAt: appState.nextAvailableFor(task, childId),
          );
        })
        .whereType<ChildTaskStatus>()
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lommepenge'),
        actions: [
          SyncIndicator(appState: appState),
          IconButton(
            icon: const Icon(Icons.lock_outline),
            tooltip: 'Forælder-tilstand',
            onPressed: _openParentMode,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _trySync,
        child: ListView(
          children: [
            UpdateBanner(appState: appState),
            const SizedBox(height: 16),
            _ChildBalanceRow(appState: appState),
            const SizedBox(height: 8),
            if (appState.tasks.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    'Der er ingen opgaver endnu. Bed en forælder om at '
                    'oprette nogle i forælder-tilstand.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              )
            else
              ...appState.tasks.map(
                (task) => TaskCard(
                  task: task,
                  childStatuses: _childStatusesFor(appState, task),
                  onComplete: (childId) =>
                      _completeTask(appState, task, childId),
                ),
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

/// Vandret, scrollbar række med ét saldo-kort pr. barn - "op til typisk
/// 3 børn ved siden af hinanden", men uden noget hårdt loft: flere børn
/// scroller blot vandret i stedet for at klemmes ind.
class _ChildBalanceRow extends StatelessWidget {
  final AppState appState;
  const _ChildBalanceRow({required this.appState});

  @override
  Widget build(BuildContext context) {
    final children = appState.children;
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      height: 230,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: children.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final child = children[index];
          return SizedBox(
            width: 240,
            child: ChildSummaryCard(appState: appState, child: child),
          );
        },
      ),
    );
  }
}

