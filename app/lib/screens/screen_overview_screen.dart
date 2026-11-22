import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/child.dart';
import '../providers/app_state.dart';
import '../widgets/child_task_list.dart';
import '../widgets/sync_indicator.dart';
import '../widgets/update_banner.dart';
import 'child_home_screen.dart';

/// Køleskabsskærmens visning: alle børn samlet, med én kolonne pr. barn
/// (navn, saldo, ugens fremskridt og barnets egne opgaver), så hvert barn
/// hurtigt kan finde sin egen del. Forælder-tilstand åbnes med låsen.
///
/// Er skærmen for smal til at alle kolonner kan være der (fx en tablet på
/// højkant), scroller kolonnerne vandret i stedet for at klemmes.
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
            tooltip: 'Forælder-tilstand',
            onPressed: () => openParentMode(context),
          ),
        ],
      ),
      body: Column(
        children: [
          UpdateBanner(appState: appState),
          Expanded(child: _body(appState, children)),
        ],
      ),
    );
  }

  Widget _body(AppState appState, List<Child> children) {
    return children.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Der er ingen børn endnu. Opret dem i forælder-tilstand.',
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
    final tasks = tasksForChild(appState, child.id);
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
          FollowUpBanner(
            followUp: appState.followUpFor(child.id),
            settings: appState.familySettings,
          ),
          if (tasks.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Ingen opgaver.', textAlign: TextAlign.center),
            )
          else
            for (final task in tasks)
              ChildTaskCard(appState: appState, child: child, task: task),
        ],
      ),
    );
  }
}
