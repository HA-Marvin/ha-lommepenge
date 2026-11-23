import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/child.dart';
import '../providers/app_state.dart';
import '../widgets/child_task_list.dart';
import '../widgets/sync_indicator.dart';
import '../widgets/update_banner.dart';
import 'child_home_screen.dart';

/// The family screen's view: all children together, with one column per
/// child (name, balance, earned this week and the child's own tasks), so
/// each child can quickly find their own part. Parent mode is opened with the
/// lock.
///
/// If the screen is too narrow for all columns (e.g. a tablet in portrait),
/// the columns scroll horizontally instead of being squeezed.
class ScreenOverviewScreen extends StatelessWidget {
  const ScreenOverviewScreen({super.key});

  static const double _minColumnWidth = 320;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final children = appState.children;

    return Scaffold(
      appBar: AppBar(
        title: Text(appState.settings.familyName),
        actions: [
          SyncIndicator(appState: appState),
          IconButton(
            icon: const Icon(Icons.lock_outline),
            tooltip: context.l10n.parentMode,
            onPressed: () => openParentMode(context),
          ),
        ],
      ),
      body: Column(
        children: [
          UpdateBanner(appState: appState),
          Expanded(child: _body(context, appState, children)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, AppState appState, List<Child> children) {
    return children.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  context.l10n.noChildrenCreateInParentMode,
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final fits =
                    constraints.maxWidth / children.length >= _minColumnWidth;
                final columns = [
                  for (final child in children)
                    _ChildColumn(appState: appState, child: child),
                ];
                if (fits) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final column in columns) Expanded(child: column),
                    ],
                  );
                }
                return ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final column in columns)
                      SizedBox(width: _minColumnWidth, child: column),
                  ],
                );
              },
            );
  }
}

class _ChildColumn extends StatelessWidget {
  final AppState appState;
  final Child child;

  const _ChildColumn({required this.appState, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ChildSummaryCard(appState: appState, child: child),
          ),
          if (child.tasks.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(context.l10n.noTasks, textAlign: TextAlign.center),
            )
          else
            ...childTaskCards(context, appState, child),
        ],
      ),
    );
  }
}
