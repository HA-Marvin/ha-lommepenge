import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/child.dart';
import '../models/lock.dart';
import '../providers/app_state.dart';

/// Builds how a lock of one [LockType] is shown on the child's tablet.
typedef LockViewBuilder = Widget Function(BuildContext context, Child child);

/// One view per lock type. Only the in-app countdown exists today; a new
/// type (e.g. an overlay on other apps) gets its own entry here.
final Map<LockType, LockViewBuilder> lockViews = {
  LockType.inApp: (context, child) => InAppLockView(lock: child.lock),
};

/// The child's lock on the tablet, shown by the view for its type - nothing
/// when there is no lock.
class LockView extends StatelessWidget {
  final Child child;

  const LockView({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final lock = child.lock;
    if (!lock.isRunning && !lock.isPending) return const SizedBox.shrink();
    final builder = lockViews[lock.type];
    return builder == null ? const SizedBox.shrink() : builder(context, child);
  }
}

/// The in-app lock: while it runs a big countdown with the reason below;
/// while it waits for the child to use the tablet a calm notice.
class InAppLockView extends StatelessWidget {
  final ChildLock lock;

  const InAppLockView({super.key, required this.lock});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final reason = lock.reason;

    if (lock.isRunning) {
      return Card(
        key: const ValueKey('lock-running'),
        color: colors.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(Icons.lock_clock, size: 48, color: colors.onErrorContainer),
              const SizedBox(height: 8),
              Text(
                l10n.lockRunningTitle,
                style: text.titleLarge?.copyWith(color: colors.onErrorContainer),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              LockCountdown(
                lock: lock,
                builder: (context, remaining) => Text(
                  formatCountdown(remaining),
                  key: const ValueKey('lock-countdown'),
                  style: text.displayLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colors.onErrorContainer,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Text(
                l10n.lockEndsAt(formatTimeOfDay(lock.endsAt!)),
                style: text.bodyMedium?.copyWith(color: colors.onErrorContainer),
              ),
              if (reason != null && reason.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  reason,
                  style: text.titleMedium?.copyWith(color: colors.onErrorContainer),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Card(
      key: const ValueKey('lock-pending'),
      color: colors.surfaceContainerHighest,
      child: ListTile(
        leading: const Icon(Icons.hourglass_empty),
        title: Text(l10n.lockPendingTitle),
        subtitle: Text([
          if (lock.minutes != null) l10n.lockPendingBody(lock.minutes!),
          if (reason != null && reason.isNotEmpty) reason,
        ].join('\n')),
      ),
    );
  }
}

/// Rebuilds every second with how long a running lock has left, counted
/// down locally from HA's time in the latest state (see
/// [AppState.lockRemainingFor]). When it reaches zero, HA's state is fetched
/// once, so the screen shows that the lock has ended.
class LockCountdown extends StatefulWidget {
  final ChildLock lock;
  final Widget Function(BuildContext context, Duration remaining) builder;

  const LockCountdown({super.key, required this.lock, required this.builder});

  @override
  State<LockCountdown> createState() => _LockCountdownState();
}

class _LockCountdownState extends State<LockCountdown> {
  Timer? _timer;
  bool _askedForState = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void didUpdateWidget(LockCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lock.endsAt != widget.lock.endsAt) _askedForState = false;
  }

  void _tick() {
    if (!mounted) return;
    setState(() {});
    final appState = context.read<AppState>();
    final remaining = appState.lockRemainingFor(widget.lock);
    if (remaining == Duration.zero && !_askedForState) {
      _askedForState = true;
      unawaited(appState.syncNow());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining =
        context.read<AppState>().lockRemainingFor(widget.lock) ?? Duration.zero;
    return widget.builder(context, remaining);
  }
}

/// A short line about a child's lock and pause, for the family screen, the
/// parent's phone and parent mode: "Locked · 42:10 left", "Lock waiting",
/// "Paused until 1/12/2026". Nothing when there is neither. Without
/// [showLock] only the pause is shown (the child's tablet has [LockView]).
class LockStatusLine extends StatelessWidget {
  final Child child;
  final bool showLock;

  const LockStatusLine({super.key, required this.child, this.showLock = true});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lock = child.lock;
    final colors = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.bodyMedium;
    final lines = <Widget>[];

    if (!showLock) {
      // The lock is shown elsewhere.
    } else if (lock.isRunning) {
      lines.add(_line(
        Icons.lock_clock,
        colors.error,
        LockCountdown(
          lock: lock,
          builder: (context, remaining) => Text(
            l10n.lockStatusRunning(formatCountdown(remaining)),
            style: style?.copyWith(color: colors.error),
          ),
        ),
      ));
    } else if (lock.isPending) {
      lines.add(_line(
        Icons.hourglass_empty,
        colors.onSurfaceVariant,
        Text(l10n.lockStatusPending, style: style),
      ));
    }
    if (child.paused) {
      final until = DateTime.tryParse(child.pausedUntil ?? '');
      lines.add(_line(
        Icons.pause_circle_outline,
        colors.onSurfaceVariant,
        Text(
          until == null
              ? l10n.pausedStatus
              : l10n.pausedUntilStatus(formatDate(l10n, until)),
          style: style,
        ),
      ));
    }
    if (lines.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: lines,
    );
  }

  Widget _line(IconData icon, Color color, Widget text) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Flexible(child: text),
          ],
        ),
      );
}
