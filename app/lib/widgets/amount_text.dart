/// Formaterer et beløb i øre som en dansk kronetekst, fx "12,50 kr" eller
/// "20 kr" (uden overflødige decimaler når beløbet er helt).
String formatKr(int ore) {
  final isNegative = ore < 0;
  final absOre = ore.abs();
  final kr = absOre ~/ 100;
  final rest = absOre % 100;
  final sign = isNegative ? '-' : '';
  if (rest == 0) {
    return '$sign$kr kr';
  }
  final restText = rest.toString().padLeft(2, '0');
  return '$sign$kr,$restText kr';
}
