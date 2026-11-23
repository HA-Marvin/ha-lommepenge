import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/lock.dart';
import '../providers/app_state.dart';

/// The child's notifications from the last 7 days, newest first, exactly as
/// Home Assistant sends them in the state (child's tablet only). There is no
/// read/unread - HA deletes them after 7 days. The same notifications are
/// shown by Android when they arrive (see `LockService.kt`).
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final l10n = context.l10n;
    final notifications = appState.boundChild?.notifications ?? const [];

    return Scaffold(
      appBar: AppBar(title: Text(l10n.notifications)),
      body: RefreshIndicator(
        onRefresh: appState.syncNow,
        child: ListView(
          children: [
            if (notifications.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Text(l10n.notificationsEmpty, textAlign: TextAlign.center),
              ),
            for (final notification in notifications)
              _NotificationTile(notification: notification),
          ],
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final ChildNotification notification;

  const _NotificationTile({required this.notification});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final (icon, color) = switch (notification.type) {
      'deadlineWarning' => (Icons.alarm, Colors.orange[800]!),
      'overdue' => (Icons.event_busy, Colors.red[700]!),
      'rejected' => (Icons.cancel_outlined, Colors.red[700]!),
      'lockStarted' => (Icons.lock_clock, Colors.purple[700]!),
      'forgotten' => (Icons.money_off, Colors.grey[700]!),
      _ => (Icons.notifications_none, Colors.grey[700]!),
    };
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(notification.message),
      subtitle: Text(formatDateTime(l10n, notification.at)),
    );
  }
}
