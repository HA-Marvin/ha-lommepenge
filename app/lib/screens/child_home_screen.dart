import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../providers/app_state.dart';
import '../widgets/child_task_list.dart';
import '../widgets/sync_indicator.dart';
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

/// The parent phone's view: each child's balance at the top, then each
/// child's task list as Home Assistant sends it. The family screen uses
/// `ScreenOverviewScreen` (one column per child) instead, and the child's
/// tablet `ChildTabletHomeScreen`.
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

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final l10n = context.l10n;
    final children = appState.children;
    final noTasks = children.every((c) => c.tasks.isEmpty);

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
            if (noTasks)
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
              for (final child in children)
                if (child.tasks.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text(
                      child.name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  ...childTaskCards(context, appState, child),
                ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

/// Horizontal, scrollable row with one balance card per child - more children
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
      height: 140,
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
