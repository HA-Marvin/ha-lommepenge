import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../providers/app_state.dart';

/// Shown at the top when Home Assistant has a newer version of the app ready.
/// "Update" fetches it from HA and asks Android to install it.
class UpdateBanner extends StatelessWidget {
  final AppState appState;
  const UpdateBanner({super.key, required this.appState});

  @override
  Widget build(BuildContext context) {
    final update = appState.availableUpdate;
    final message = appState.updateMessage;
    if (update == null && message == null) return const SizedBox.shrink();
    final progress = appState.updateProgress;
    final busy = progress != null;
    final l10n = context.l10n;

    return MaterialBanner(
      leading: const Icon(Icons.system_update),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(update == null ? message! : l10n.newVersionReady(update.version)),
          if (update != null && message != null) ...[
            const SizedBox(height: 4),
            Text(message, style: Theme.of(context).textTheme.bodySmall),
          ],
          if (busy) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(value: progress > 0 ? progress : null),
          ],
        ],
      ),
      actions: [
        if (update != null)
          FilledButton(
            onPressed: busy ? null : appState.installUpdate,
            child: Text(l10n.update),
          )
        else
          const SizedBox.shrink(),
      ],
    );
  }
}
