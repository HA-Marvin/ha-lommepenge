import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../providers/app_state.dart';

/// Small icon in the app bar with the connection to Home Assistant. Tapping
/// shows the latest sync message.
class SyncIndicator extends StatelessWidget {
  final AppState appState;
  const SyncIndicator({super.key, required this.appState});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color? color;
    switch (appState.syncStatus) {
      case SyncStatus.connected:
        icon = Icons.wifi;
        color = Colors.green;
        break;
      case SyncStatus.offline:
        icon = Icons.wifi_off;
        color = Colors.red;
        break;
      case SyncStatus.syncing:
        icon = Icons.sync;
        color = Colors.orange;
        break;
      case SyncStatus.unknown:
        icon = Icons.wifi_off;
        color = Colors.grey;
        break;
    }
    final l10n = context.l10n;
    return IconButton(
      icon: Icon(icon, color: color),
      tooltip: appState.syncMessage ?? l10n.syncStatus,
      onPressed: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(appState.syncMessage ?? l10n.connectedToHa),
          ),
        );
      },
    );
  }
}
