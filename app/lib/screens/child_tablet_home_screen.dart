import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/child.dart';
import '../providers/app_state.dart';
import '../widgets/child_task_list.dart';
import '../widgets/lock_view.dart';
import '../widgets/sync_indicator.dart';
import '../widgets/update_banner.dart';
import 'history_screen.dart';
import 'language_screen.dart';
import 'notifications_screen.dart';

/// The child's tablet: only that child's balance and tasks, as Home
/// Assistant sends them. There is no lock/parent button - the parent part
/// does not exist on this device, and Home Assistant refuses anything other
/// than "mark as done" for the child itself anyway. The child's
/// notifications, own history and the language can be opened from the app
/// bar. A lock is shown above the tasks (a big countdown while it runs, see
/// [LockView]). (HA's state is fetched every 30 seconds and when the app
/// comes to the foreground - see `AppState`.)
class ChildTabletHomeScreen extends StatefulWidget {
  const ChildTabletHomeScreen({super.key});

  @override
  State<ChildTabletHomeScreen> createState() => _ChildTabletHomeScreenState();
}

class _ChildTabletHomeScreenState extends State<ChildTabletHomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  Future<void> _sync() async {
    if (!mounted) return;
    await context.read<AppState>().syncNow();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final child = appState.boundChild;
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(child == null ? 'Lommepenge' : l10n.hiChild(child.name)),
        actions: [
          SyncIndicator(appState: appState),
          IconButton(
            icon: const Icon(Icons.notifications_none),
            tooltip: l10n.notifications,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NotificationsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: l10n.history,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => HistoryScreen(childId: appState.boundChildId),
              ),
            ),
          ),
          const LanguageButton(),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _sync,
        child: child == null
            ? ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      appState.syncMessage ?? l10n.fetchingYourTasks,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              )
            : _buildContent(context, appState, child),
      ),
    );
  }

  Widget _buildContent(BuildContext context, AppState appState, Child child) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          children: [
            UpdateBanner(appState: appState),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ChildSummaryCard(
                appState: appState,
                child: child,
                large: true,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: LockView(child: child),
            ),
            const SizedBox(height: 8),
            if (child.tasks.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  context.l10n.noTasksRightNow,
                  textAlign: TextAlign.center,
                ),
              )
            else
              ...childTaskCards(context, appState, child),
          ],
        ),
      ),
    );
  }
}
