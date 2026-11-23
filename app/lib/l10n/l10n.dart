import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../models/task.dart';
import 'app_localizations.dart';

export 'app_localizations.dart';

/// The app's languages, each shown by its own name. English is the default;
/// the language is chosen on first start and can be changed later.
const supportedLanguages = {
  'en': 'English',
  'da': 'Dansk',
  'de': 'Deutsch',
  'es': 'Español',
  'fr': 'Français',
};

const defaultLanguage = 'en';

/// The texts in [language] (English if the language is unknown). For code
/// without a [BuildContext], e.g. `AppState`.
AppLocalizations l10nFor(String? language) => lookupAppLocalizations(
      Locale(supportedLanguages.containsKey(language) ? language! : defaultLanguage),
    );

extension L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

extension RecurrenceLabel on Recurrence {
  String label(AppLocalizations l10n) {
    switch (this) {
      case Recurrence.once:
        return l10n.recurrenceOnce;
      case Recurrence.daily:
        return l10n.recurrenceDaily;
      case Recurrence.weekly:
        return l10n.recurrenceWeekly;
      case Recurrence.unlimited:
        return l10n.recurrenceUnlimited;
    }
  }
}

/// Short weekday names, Monday first, paired with their `DateTime.weekday`
/// value (1 = Monday ... 7 = Sunday).
List<MapEntry<int, String>> weekdayLabels(AppLocalizations l10n) => [
      // 1 January 2024 was a Monday.
      for (var day = 1; day <= 7; day++)
        MapEntry(day, DateFormat.E(l10n.localeName).format(DateTime(2024, 1, day))),
    ];

/// A date, e.g. 23/11/2026 or 11/23/2026 depending on the language.
String formatDate(AppLocalizations l10n, DateTime d) =>
    DateFormat.yMd(l10n.localeName).format(d);

/// A date with time of day (24-hour clock).
String formatDateTime(AppLocalizations l10n, DateTime d) =>
    '${formatDate(l10n, d)} ${formatTimeOfDay(d)}';

/// A day and month without the year, e.g. 23/11.
String formatDayMonth(AppLocalizations l10n, DateTime d) =>
    DateFormat.Md(l10n.localeName).format(d);

/// A weekday with day and month, e.g. "Tue, 11/25" or "tir. 25.11.".
String formatWeekdayDayMonth(AppLocalizations l10n, DateTime d) =>
    DateFormat.MEd(l10n.localeName).format(d);

/// A deadline from Home Assistant: only the time when it is [today] (HA's
/// date, `YYYY-MM-DD`), otherwise with the day in front.
String formatDeadline(AppLocalizations l10n, DateTime deadline, String? today) {
  final day = DateTime(deadline.year, deadline.month, deadline.day);
  final isToday = today != null && DateTime.tryParse(today) == day;
  return isToday
      ? formatTimeOfDay(deadline)
      : '${formatWeekdayDayMonth(l10n, deadline)} ${formatTimeOfDay(deadline)}';
}

/// `HH:MM` - the app always uses a 24-hour clock, like Home Assistant.
String formatTimeOfDay(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
