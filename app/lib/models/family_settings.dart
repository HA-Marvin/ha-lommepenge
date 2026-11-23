import 'task.dart';

/// An unknown setting or an invalid value (see [FamilySettings.withValue]).
class InvalidSetting extends ArgumentError {
  final String key;
  final Object? value;

  InvalidSetting(this.key, this.value) : super('Invalid value for $key: $value');
}

/// The family's adjustable times and limits, from `state.settings` (parent
/// mode). Stored and validated in Home Assistant; changed with the
/// `set_setting` action. The app only shows them.
class FamilySettings {
  /// Deadline for mandatory tasks without their own deadline.
  final String defaultDueTime;

  /// Pause before the tablet is unlocked when a task was done late.
  final int latePauseMinutes;

  /// How long before the deadline a warning is shown.
  final int warningMinutes;

  /// The winter period in ISO weeks (can span New Year, e.g. 43 -> 13).
  final int winterFromWeek;
  final int winterToWeek;

  const FamilySettings({
    this.defaultDueTime = '18:00',
    this.latePauseMinutes = 10,
    this.warningMinutes = 60,
    this.winterFromWeek = 43,
    this.winterToWeek = 13,
  });

  static const defaults = FamilySettings();

  /// The keys `set_setting` accepts (see docs/app-api.md).
  static const keys = {
    'defaultDueTime',
    'latePauseMinutes',
    'warningMinutes',
    'winterFromWeek',
    'winterToWeek',
  };

  Map<String, Object> toJson() => {
        'defaultDueTime': defaultDueTime,
        'latePauseMinutes': latePauseMinutes,
        'warningMinutes': warningMinutes,
        'winterFromWeek': winterFromWeek,
        'winterToWeek': winterToWeek,
      };

  /// Reads settings defensively: missing or invalid values fall back to the
  /// default, and unknown keys (e.g. the old restriction window) are ignored.
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
      if (t == null) throw InvalidSetting(key, value);
      return t;
    }

    int intIn(int min, int max) {
      final v = value is int ? value : int.tryParse('$value');
      if (v == null || v < min || v > max) throw InvalidSetting(key, value);
      return v;
    }

    switch (key) {
      case 'defaultDueTime':
        return _copy(defaultDueTime: time());
      case 'latePauseMinutes':
        return _copy(latePauseMinutes: intIn(0, 240));
      case 'warningMinutes':
        return _copy(warningMinutes: intIn(0, 600));
      case 'winterFromWeek':
        return _copy(winterFromWeek: intIn(1, 53));
      case 'winterToWeek':
        return _copy(winterToWeek: intIn(1, 53));
      default:
        throw InvalidSetting(key, value);
    }
  }

  FamilySettings _copy({
    String? defaultDueTime,
    int? latePauseMinutes,
    int? warningMinutes,
    int? winterFromWeek,
    int? winterToWeek,
  }) {
    return FamilySettings(
      defaultDueTime: defaultDueTime ?? this.defaultDueTime,
      latePauseMinutes: latePauseMinutes ?? this.latePauseMinutes,
      warningMinutes: warningMinutes ?? this.warningMinutes,
      winterFromWeek: winterFromWeek ?? this.winterFromWeek,
      winterToWeek: winterToWeek ?? this.winterToWeek,
    );
  }
}
