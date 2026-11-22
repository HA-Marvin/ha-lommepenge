import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/task.dart';
import '../providers/app_state.dart';
import '../widgets/child_task_list.dart';
import '../widgets/sync_indicator.dart';
import '../widgets/task_card.dart';
import '../widgets/update_banner.dart';
import 'parent_home_screen.dart';
import 'pin_entry_screen.dart';

/// Asks for the parent PIN and opens parent mode. Shared by the parent
/// phone's and the family screen's views; deliberately does not exist on the
/// child's tablet.
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

/// The parent phone's view: ONE shared list of tasks (regardless of which
/// child/children they apply to), with each child's own balance and weekly
/// progress at the top. The family screen uses `ScreenOverviewScreen` (one
/// column per child) instead, and the child's tablet `ChildTabletHomeScreen`.
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

  /// Builds the children's availability status for [task], one entry per
  /// actually assigned child (see the dynamic "all children") - see [TaskCard].
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
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lommepenge'),
        actions: [
          SyncIndicator(appState: appState),
          IconButton(
            icon: const Icon(Icons.lock_outline),
            tooltip: l10n.parentMode,
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
                    l10n.noTasksAskParent,
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
                  onComplete: (childId) => completeTaskWithFeedback(
                    context,
                    appState,
                    task,
                    childId,
                  ),
                ),
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

/// Horizontal, scrollable row with one balance card per child - "typically up
/// to 3 children side by side", but without a hard limit: more children
/// simply scroll horizontally instead of being squeezed in.
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
