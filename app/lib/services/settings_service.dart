import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/family_settings.dart';
import 'ha_client.dart';

/// The currency until Home Assistant has said otherwise.
const defaultCurrency = 'DKK';

/// The device's role in the family. Decided in Home Assistant when the device
/// is added ("Add device"), and cannot be changed on the device itself.
enum DeviceRole {
  /// The family screen (e.g. on the fridge): all children together, the
  /// parent part locked with the PIN.
  screen,

  /// A parent's phone: shared task list, the parent part locked with the PIN.
  phone,

  /// A child's own tablet, bound to exactly one child. Only shows that child's
  /// tasks and has NO parent mode - HA also refuses anything other than "mark
  /// as done" for the child itself. The role can only be removed by
  /// reinstalling the app (AndroidManifest: allowBackup="false").
  childTablet;

  /// The role's name in the Home Assistant integration.
  static DeviceRole? fromHa(String? value) {
    switch (value) {
      case 'screen':
        return DeviceRole.screen;
      case 'parent':
        return DeviceRole.phone;
      case 'child':
        return DeviceRole.childTablet;
    }
    return null;
  }
}

/// Simple wrapper around [SharedPreferences] for all local settings: the
/// language, the connection to Home Assistant, role, PIN hash and a local
/// copy of the family's settings/balance info (from HA).
class SettingsService {
  static const _keyLanguage = 'language';
  static const _keyCurrency = 'currency';
  static const _keyRole = 'role';
  static const _keyPinHash = 'pin_hash';
  static const _keyPinSalt = 'pin_salt';
  static const _keyDeviceName = 'device_name';
  static const _keyFamilyName = 'family_name';

  // The connection to Home Assistant (from pairing).
  static const _keyHaUrl = 'ha_url';
  static const _keyHaDeviceId = 'ha_device_id';
  static const _keyHaDeviceKey = 'ha_device_key';

  // Child's tablet: which child the tablet is bound to.
  static const _keyBoundChildId = 'bound_child_id';

  // The family's times/limits (JSON, see FamilySettings) and parents'
  // suspension of the restriction for today (JSON: child id -> "YYYY-MM-DD").
  static const _keyFamilySettings = 'family_settings';
  static const _keyRestrictionSuspensions = 'restriction_suspensions';

  // The latest app version that has been notified about (so the notification
  // only comes once per version).
  static const _keyNotifiedUpdateCode = 'notified_update_code';

  static const _keyTotalPaidOutOre = 'total_paid_out_ore';
  static const _keyPaidOutByChild = 'paid_out_by_child';
  static const _keyOfflineQueue = 'offline_action_queue';

  final SharedPreferences _prefs;
  SettingsService(this._prefs);

  static Future<SettingsService> create() async {
    final prefs = await SharedPreferences.getInstance();
    return SettingsService(prefs);
  }

  // ---- Language -----------------------------------------------------------

  /// The app's language code (`en`, `da`, `de`, `es`, `fr`), or `null` until
  /// it has been chosen on first start. Kept when the connection is
  /// forgotten.
  String? get language => _prefs.getString(_keyLanguage);

  Future<void> setLanguage(String language) =>
      _prefs.setString(_keyLanguage, language);

  // ---- Currency -------------------------------------------------------------

  /// The currency the family's amounts are shown in. Chosen in Home Assistant
  /// (free text, e.g. "DKK", "kr" or "€") and synced from there.
  String get currency => _prefs.getString(_keyCurrency) ?? defaultCurrency;

  Future<void> setCurrency(String currency) =>
      _prefs.setString(_keyCurrency, currency);

  // ---- Role and connection -------------------------------------------------

  DeviceRole? get role {
    final v = _prefs.getString(_keyRole);
    if (v == 'screen') return DeviceRole.screen;
    if (v == 'phone') return DeviceRole.phone;
    if (v == 'child_tablet') return DeviceRole.childTablet;
    return null;
  }

  Future<void> setRole(DeviceRole role) {
    switch (role) {
      case DeviceRole.screen:
        return _prefs.setString(_keyRole, 'screen');
      case DeviceRole.phone:
        return _prefs.setString(_keyRole, 'phone');
      case DeviceRole.childTablet:
        return _prefs.setString(_keyRole, 'child_tablet');
    }
  }

  HaConnection? get connection {
    final url = Uri.tryParse(_prefs.getString(_keyHaUrl) ?? '');
    final id = _prefs.getString(_keyHaDeviceId);
    final key = _prefs.getString(_keyHaDeviceKey);
    if (url == null || !url.hasScheme || id == null || key == null) {
      return null;
    }
    return HaConnection(baseUrl: url, deviceId: id, key: key);
  }

  Future<void> setConnection(HaConnection connection) async {
    await _prefs.setString(_keyHaUrl, connection.baseUrl.toString());
    await _prefs.setString(_keyHaDeviceId, connection.deviceId);
    await _prefs.setString(_keyHaDeviceKey, connection.key);
  }

  /// Forgets the connection, the role and the PIN (e.g. when the device has
  /// been removed in Home Assistant). The device must then be connected again
  /// with a new code from HA.
  Future<void> clearConnection() async {
    for (final key in [
      _keyHaUrl,
      _keyHaDeviceId,
      _keyHaDeviceKey,
      _keyRole,
      _keyBoundChildId,
      _keyPinHash,
      _keyPinSalt,
      _keyOfflineQueue,
    ]) {
      await _prefs.remove(key);
    }
  }

  // ---- Child's tablet ---------------------------------------------------

  String? get boundChildId => _prefs.getString(_keyBoundChildId);

  Future<void> setBoundChildId(String? childId) => childId == null
      ? _prefs.remove(_keyBoundChildId)
      : _prefs.setString(_keyBoundChildId, childId);

  // ---- The family's times and limits -----------------------------------------

  FamilySettings get familySettings {
    final raw = _prefs.getString(_keyFamilySettings);
    if (raw == null || raw.isEmpty) return FamilySettings.defaults;
    try {
      return FamilySettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return FamilySettings.defaults;
    }
  }

  Future<void> setFamilySettings(FamilySettings value) =>
      _prefs.setString(_keyFamilySettings, jsonEncode(value.toJson()));

  /// Child id -> date (`YYYY-MM-DD`) on which a parent has lifted the child's
  /// restriction for the rest of the day.
  Map<String, String> get restrictionSuspensions {
    final raw = _prefs.getString(_keyRestrictionSuspensions);
    if (raw == null || raw.isEmpty) return {};
    try {
      return (jsonDecode(raw) as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, v as String));
    } catch (_) {
      return {};
    }
  }

  Future<void> setRestrictionSuspensions(Map<String, String> value) =>
      _prefs.setString(_keyRestrictionSuspensions, jsonEncode(value));

  String get deviceName => _prefs.getString(_keyDeviceName) ?? 'Lommepenge';
  Future<void> setDeviceName(String name) =>
      _prefs.setString(_keyDeviceName, name);

  String get familyName => _prefs.getString(_keyFamilyName) ?? 'Lommepenge';
  Future<void> setFamilyName(String name) =>
      _prefs.setString(_keyFamilyName, name);

  int get notifiedUpdateCode => _prefs.getInt(_keyNotifiedUpdateCode) ?? 0;
  Future<void> setNotifiedUpdateCode(int code) =>
      _prefs.setInt(_keyNotifiedUpdateCode, code);

  // ---- PIN (the family's parent PIN, set in Home Assistant) -----------------

  bool get hasPin =>
      _prefs.containsKey(_keyPinHash) && _prefs.containsKey(_keyPinSalt);

  String? get pinHash => _prefs.getString(_keyPinHash);
  String? get pinSalt => _prefs.getString(_keyPinSalt);

  Future<void> setPin(String hash, String salt) async {
    await _prefs.setString(_keyPinHash, hash);
    await _prefs.setString(_keyPinSalt, salt);
  }

  // ---- Balance ---------------------------------------------------------------
  //
  // [totalPaidOutOre] was one global paid-out amount from when the app only
  // supported one child; it is only used by the one-time migration in
  // TaskRepository.migrateLegacyPaidOutIfNeeded. Paid out is now per child.

  int get totalPaidOutOre => _prefs.getInt(_keyTotalPaidOutOre) ?? 0;

  Future<void> setTotalPaidOutOre(int value) =>
      _prefs.setInt(_keyTotalPaidOutOre, value);

  Map<String, int> get paidOutOreByChild {
    final raw = _prefs.getString(_keyPaidOutByChild);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((key, value) => MapEntry(key, value as int));
    } catch (_) {
      // Defensive: an invalid/corrupt stored value must not crash the app -
      // it is simply treated as "nothing paid out yet for anyone".
      return {};
    }
  }

  Future<void> setPaidOutOreByChild(Map<String, int> value) =>
      _prefs.setString(_keyPaidOutByChild, jsonEncode(value));

  int paidOutOreFor(String childId) => paidOutOreByChild[childId] ?? 0;

  Future<void> setPaidOutOreFor(String childId, int amountOre) async {
    final current = Map<String, int>.from(paidOutOreByChild);
    current[childId] = amountOre;
    await setPaidOutOreByChild(current);
  }

  // ---- Simple offline queue ------------------------------------------------
  // Actions that could not be sent to Home Assistant right away, stored as
  // JSON strings and sent again later in the same order.

  List<String> get offlineQueueRaw =>
      _prefs.getStringList(_keyOfflineQueue) ?? const [];

  Future<void> setOfflineQueueRaw(List<String> items) =>
      _prefs.setStringList(_keyOfflineQueue, items);
}
