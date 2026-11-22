import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

/// Simple visual progress display: a set of stars showing how many tasks have
/// been completed this week, up to [max]. Deliberately simple - no
/// "gamification" beyond this.
class WeeklyProgress extends StatelessWidget {
  final int completedCount;
  final int max;

  const WeeklyProgress({
    super.key,
    required this.completedCount,
    this.max = 7,
  });

  @override
  Widget build(BuildContext context) {
    final shown = completedCount > max ? max : completedCount;
    final stars = List<Widget>.generate(max, (i) {
      final filled = i < shown;
      return Icon(
        filled ? Icons.star_rounded : Icons.star_border_rounded,
        color: filled ? Colors.amber[700] : Colors.grey[400],
        size: 28,
      );
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.completedThisWeek(completedCount),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 4),
        Wrap(children: stars),
      ],
    );
  }
}
