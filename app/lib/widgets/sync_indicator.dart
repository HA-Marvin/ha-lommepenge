import 'package:flutter/material.dart';

import '../providers/app_state.dart';

/// Lille ikon i app-baren med forbindelsen til Home Assistant. Tryk
/// viser seneste sync-besked.
class SyncIndicator extends StatelessWidget {
  final AppState appState;
  const SyncIndicator({super.key, required this.appState});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color? color;
    switch (appState.syncStatus) {
      case SyncStatus.forbundet:
        icon = Icons.wifi;
        color = Colors.green;
        break;
      case SyncStatus.offline:
        icon = Icons.wifi_off;
        color = Colors.red;
        break;
      case SyncStatus.synkroniserer:
        icon = Icons.sync;
        color = Colors.orange;
        break;
      case SyncStatus.ukendt:
        icon = Icons.wifi_off;
        color = Colors.grey;
        break;
    }
    return IconButton(
      icon: Icon(icon, color: color),
      tooltip: appState.syncMessage ?? 'Sync-status',
      onPressed: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              appState.syncMessage ?? 'Forbundet til Home Assistant.',
            ),
          ),
        );
      },
    );
  }
}
