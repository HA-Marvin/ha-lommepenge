import 'task.dart';

/// Familiens justerbare tider og grænser for opfølgning og spærring.
///
/// Gemmes på køleskabsskærmen (sandheden) og kan rettes fra
/// forælder-delen af appen eller fra Home Assistant (`set_setting`). Følger
/// med i sync-state, så telefoner og tablets viser de samme værdier.
class FamilySettings {
  /// Frist for obligatoriske opgaver uden egen frist.
  final String defaultDueTime;

  /// Spærre-vinduet: kun i dette tidsrum kan en tablet spærres.
  final String restrictionStart;
  final String restrictionEnd;

  /// Pausetid før tabletten låses op, når en opgave er udført for sent.
  final int latePauseMinutes;

  /// Hvor længe før fristen der advares.
  final int warningMinutes;

  /// Vinter-perioden i ISO-uger (kan gå hen over nytår, fx 43 -> 13).
  final int winterFromWeek;
  final int winterToWeek;

  const FamilySettings({
    this.defaultDueTime = '18:00',
    this.restrictionStart = '15:00',
    this.restrictionEnd = '21:00',
    this.latePauseMinutes = 10,
    this.warningMinutes = 60,
    this.winterFromWeek = 43,
    this.winterToWeek = 13,
  });

  static const defaults = FamilySettings();

  /// Nøglerne der kan sættes enkeltvis med [withValue] (fx fra HA).
  static const keys = {
    'defaultDueTime',
    'restrictionStart',
    'restrictionEnd',
    'latePauseMinutes',
    'warningMinutes',
    'winterFromWeek',
    'winterToWeek',
  };

  Map<String, Object> toJson() => {
        'defaultDueTime': defaultDueTime,
        'restrictionStart': restrictionStart,
        'restrictionEnd': restrictionEnd,
        'latePauseMinutes': latePauseMinutes,
        'warningMinutes': warningMinutes,
        'winterFromWeek': winterFromWeek,
        'winterToWeek': winterToWeek,
      };

  /// Læser indstillinger defensivt: manglende eller ugyldige værdier
  /// falder tilbage til standarden, så en gammel/korrupt værdi aldrig kan
  /// crashe appen eller slå opfølgningen fra.
  factory FamilySettings.fromJson(Map<String, dynamic>? json) {
    var settings = defaults;
    if (json == null) return settings;
    for (final key in keys) {
      if (!json.containsKey(key)) continue;
      try {
        settings = settings.withValue(key, json[key]);
      } on ArgumentError {
        // behold standarden for denne nøgle
      }
    }
    return settings;
  }

  /// Returnerer en kopi med én værdi ændret. Kaster [ArgumentError] ved
  /// ukendt nøgle eller ugyldig værdi.
  FamilySettings withValue(String key, Object? value) {
    String time() {
      final t = normalizeTimeOfDay(value?.toString());
      if (t == null) throw ArgumentError('Ugyldigt klokkeslæt for $key: $value');
      return t;
    }

    int intIn(int min, int max) {
      final v = value is int ? value : int.tryParse('$value');
      if (v == null || v < min || v > max) {
        throw ArgumentError('$key skal være mellem $min og $max: $value');
      }
      return v;
    }

    switch (key) {
      case 'defaultDueTime':
        return _copy(defaultDueTime: time());
      case 'restrictionStart':
        return _copy(restrictionStart: time());
      case 'restrictionEnd':
        return _copy(restrictionEnd: time());
      case 'latePauseMinutes':
        return _copy(latePauseMinutes: intIn(0, 240));
      case 'warningMinutes':
        return _copy(warningMinutes: intIn(0, 600));
      case 'winterFromWeek':
        return _copy(winterFromWeek: intIn(1, 53));
      case 'winterToWeek':
        return _copy(winterToWeek: intIn(1, 53));
      default:
        throw ArgumentError('Ukendt indstilling: $key');
    }
  }

  FamilySettings _copy({
    String? defaultDueTime,
    String? restrictionStart,
    String? restrictionEnd,
    int? latePauseMinutes,
    int? warningMinutes,
    int? winterFromWeek,
    int? winterToWeek,
  }) {
    return FamilySettings(
      defaultDueTime: defaultDueTime ?? this.defaultDueTime,
      restrictionStart: restrictionStart ?? this.restrictionStart,
      restrictionEnd: restrictionEnd ?? this.restrictionEnd,
      latePauseMinutes: latePauseMinutes ?? this.latePauseMinutes,
      warningMinutes: warningMinutes ?? this.warningMinutes,
      winterFromWeek: winterFromWeek ?? this.winterFromWeek,
      winterToWeek: winterToWeek ?? this.winterToWeek,
    );
  }
}
