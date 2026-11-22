import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/child.dart';
import '../providers/app_state.dart';
import '../widgets/child_task_list.dart';
import '../widgets/sync_indicator.dart';
import '../widgets/update_banner.dart';
import 'language_screen.dart';

/// The child's tablet: only that child's balance and tasks. There is no
/// lock/parent button - the parent part does not exist on this device, and
/// Home Assistant refuses anything other than "mark as done" for the child
/// itself anyway. The language can be changed from the app bar.
class ChildTabletHomeScreen extends StatefulWidget {
  const ChildTabletHomeScreen({super.key});

  @override
  State<ChildTabletHomeScreen> createState() => _ChildTabletHomeScreenState();
}

class _ChildTabletHomeScreenState extends State<ChildTabletHomeScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _sync();
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
    final tasks = tasksForChild(appState, child.id);
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
            const SizedBox(height: 8),
            FollowUpBanner(
              followUp: appState.followUpFor(child.id),
              settings: appState.familySettings,
            ),
            if (tasks.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  context.l10n.noTasksRightNow,
                  textAlign: TextAlign.center,
                ),
              )
            else
              for (final task in tasks)
                ChildTaskCard(appState: appState, child: child, task: task),
          ],
        ),
      ),
    );
  }
}
