import 'package:flutter/material.dart';

import '../providers/app_state.dart';

/// Vises øverst, når Home Assistant har en nyere version af appen klar.
/// "Opdater" henter den fra HA og beder Android installere den.
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

    return MaterialBanner(
      leading: const Icon(Icons.system_update),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            update == null
                ? message!
                : 'Ny version ${update.version} er klar.',
          ),
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
            child: const Text('Opdater'),
          )
        else
          const SizedBox.shrink(),
      ],
    );
  }
}
