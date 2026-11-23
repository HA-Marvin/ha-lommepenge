import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

/// Runs a confirmed action (see `AppState`): on success shows [success] (if
/// given); on an error shows the message - "No connection to Home Assistant
/// – try again" or HA's own error - with a "Try again" button that runs the
/// same action again. Returns whether the action went through.
///
/// Nothing is changed in the app when an action fails, so there is nothing
/// to undo here.
Future<bool> runAction(
  BuildContext context,
  Future<void> Function() action, {
  String? success,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final tryAgain = context.l10n.tryAgain;
  try {
    await action();
    if (success != null) {
      messenger?.showSnackBar(SnackBar(content: Text(success)));
    }
    return true;
  } catch (e) {
    messenger?.showSnackBar(
      SnackBar(
        content: Text('$e'),
        action: SnackBarAction(
          label: tryAgain,
          onPressed: () async {
            try {
              await action();
              if (success != null) {
                messenger.showSnackBar(SnackBar(content: Text(success)));
              }
            } catch (e) {
              messenger.showSnackBar(SnackBar(content: Text('$e')));
            }
          },
        ),
      ),
    );
    return false;
  }
}

/// A small spinner in place of an icon button while its action is waiting
/// for Home Assistant.
class BusyIndicator extends StatelessWidget {
  const BusyIndicator({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
}
