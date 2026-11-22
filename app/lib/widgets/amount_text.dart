import '../l10n/l10n.dart';

/// Formats an amount in 1/100 of the currency (e.g. øre or cents) with the
/// family's [currency] from Home Assistant, e.g. "12.50 DKK" in English or
/// "12,50 €" in Danish, German, Spanish and French - without superfluous
/// decimals when the amount is whole ("20 DKK").
String formatAmount(AppLocalizations l10n, int ore, String currency) {
  final isNegative = ore < 0;
  final absOre = ore.abs();
  final whole = absOre ~/ 100;
  final rest = absOre % 100;
  final sign = isNegative ? '-' : '';
  if (rest == 0) {
    return '$sign$whole $currency';
  }
  final separator = l10n.localeName == 'en' ? '.' : ',';
  final restText = rest.toString().padLeft(2, '0');
  return '$sign$whole$separator$restText $currency';
}
