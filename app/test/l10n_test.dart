// The translations: every language has every text with the same
// placeholders, and amounts follow the language.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lommepenge_app/l10n/l10n.dart';
import 'package:lommepenge_app/widgets/amount_text.dart';

Map<String, String> _messages(String language) {
  final json = jsonDecode(File('lib/l10n/app_$language.arb').readAsStringSync())
      as Map<String, dynamic>;
  return {
    for (final entry in json.entries)
      if (!entry.key.startsWith('@')) entry.key: entry.value as String,
  };
}

/// Top-level placeholder names, e.g. `{name}` or `{count, plural, ...}`.
Set<String> _placeholders(String message) {
  final names = <String>{};
  var depth = 0;
  for (var i = 0; i < message.length; i++) {
    if (message[i] == '{') {
      if (depth == 0) {
        final match = RegExp(r'\{(\w+)').matchAsPrefix(message, i);
        if (match != null) names.add(match.group(1)!);
      }
      depth++;
    } else if (message[i] == '}') {
      depth--;
    }
  }
  return names;
}

void main() {
  test('every language has every text with the same placeholders', () {
    final english = _messages('en');
    for (final language in supportedLanguages.keys) {
      final messages = _messages(language);
      expect(messages.keys.toSet(), english.keys.toSet(), reason: language);
      for (final key in english.keys) {
        expect(
          _placeholders(messages[key]!),
          _placeholders(english[key]!),
          reason: '$language/$key',
        );
      }
    }
  });

  test('every supported language has generated texts', () {
    expect(
      AppLocalizations.supportedLocales.map((l) => l.languageCode).toSet(),
      supportedLanguages.keys.toSet(),
    );
    for (final language in supportedLanguages.keys) {
      expect(l10nFor(language).localeName, language);
    }
    expect(l10nFor('xx').localeName, defaultLanguage);
    expect(l10nFor(null).localeName, defaultLanguage);
  });

  test('plurals', () {
    expect(l10nFor('en').completedThisWeek(1), 'This week: 1 completed task');
    expect(l10nFor('en').completedThisWeek(3), 'This week: 3 completed tasks');
    expect(l10nFor('da').completedThisWeek(3), 'Denne uge: 3 fuldførte opgaver');
    expect(
      l10nFor('en').lockPendingBody(1),
      'It lasts 1 minute and starts the next time the tablet is used.',
    );
    expect(l10nFor('da').lockPendingBody(60), startsWith('Den varer 60 minutter'));
  });

  test('texts with several values keep the order of the values', () {
    // Undeclared placeholders are ordered alphabetically by gen-l10n, so
    // these are declared in app_en.arb.
    expect(
      l10nFor('en').errSettingRange('latePauseMinutes', '0', '240', '999'),
      'latePauseMinutes must be between 0 and 240: 999',
    );
  });

  test('amounts use the currency and the decimal separator of the language', () {
    expect(formatAmount(l10nFor('en'), 2000, 'DKK'), '20 DKK');
    expect(formatAmount(l10nFor('en'), 1250, 'USD'), '12.50 USD');
    expect(formatAmount(l10nFor('da'), 1250, 'kr'), '12,50 kr');
    expect(formatAmount(l10nFor('de'), -5, '€'), '-0,05 €');
    expect(l10nFor('fr').amountLabel('€'), 'Montant (€)');
  });
}
