import 'task.dart';

/// An unknown setting or an invalid value. The repository turns it into a
/// message in the app's language.
class InvalidSetting extends ArgumentError {
  final String key;
  final Object? value;
  final int? min;
  final int? max;

  InvalidSetting.time(this.key, this.value)
      : min = null,
        max = null,
        super('Invalid time for $key: $value');

  InvalidSetting.range(this.key, this.value, int this.min, int this.max)
      : super('$key must be between $min and $max: $value');

  InvalidSetting.unknown(this.key)
      : value = null,
        min = null,
        max = null,
        super('Unknown setting: $key');
}

/// The family's adjustable times and limits for follow-up and restriction.
///
/// Stored in Home Assistant (the source of truth) and can be changed from the
/// parent part of the app or from Home Assistant (`set_setting`). Included in
/// the synced state, so phones and tablets show the same values.
class FamilySettings {
  /// Deadline for mandatory tasks without their own deadline.
  final String defaultDueTime;

  /// The restriction window: a tablet can only be restricted in this period.
  final String restrictionStart;
  final String restrictionEnd;

  /// Pause before the tablet is unlocked when a task was done late.
  final int latePauseMinutes;

  /// How long before the deadline a warning is shown.
  final int warningMinutes;

  /// The winter period in ISO weeks (can span New Year, e.g. 43 -> 13).
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

  /// The keys that can be set one at a time with [withValue] (e.g. from HA).
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

  /// Reads settings defensively: missing or invalid values fall back to the
  /// default, so an old/corrupt value can never crash the app or turn the
  /// follow-up off.
  factory FamilySettings.fromJson(Map<String, dynamic>? json) {
    var settings = defaults;
    if (json == null) return settings;
    for (final key in keys) {
      if (!json.containsKey(key)) continue;
      try {
        settings = settings.withValue(key, json[key]);
      } on ArgumentError {
        // keep the default for this key
      }
    }
    return settings;
  }

  /// Returns a copy with one value changed. Throws [InvalidSetting] for an
  /// unknown key or an invalid value.
  FamilySettings withValue(String key, Object? value) {
    String time() {
      final t = normalizeTimeOfDay(value?.toString());
      if (t == null) throw InvalidSetting.time(key, value);
      return t;
    }

    int intIn(int min, int max) {
      final v = value is int ? value : int.tryParse('$value');
      if (v == null || v < min || v > max) {
        throw InvalidSetting.range(key, value, min, max);
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
        throw InvalidSetting.unknown(key);
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
