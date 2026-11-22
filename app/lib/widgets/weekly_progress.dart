import 'package:flutter/material.dart';

/// Simpel visuel fremskridtsvisning: et sæt stjerner der viser hvor
/// mange opgaver der er fuldført denne uge, op til [max]. Bevidst
/// enkelt - ingen "gamification" ud over dette.
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
          'Denne uge: $completedCount fuldførte opgaver',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 4),
        Wrap(children: stars),
      ],
    );
  }
}
