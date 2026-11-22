import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/family_settings.dart';
import 'ha_client.dart';

/// Enhedens rolle i familien. Bestemmes i Home Assistant, når enheden
/// tilføjes ("Tilføj enhed"), og kan ikke ændres på enheden selv.
enum DeviceRole {
  /// Den fælles skærm (fx på køleskabet): alle børn samlet, forælder-delen
  /// låst med PIN.
  screen,

  /// En forælders telefon: fælles opgaveliste, forælder-delen låst med PIN.
  phone,

  /// Et barns egen tablet, bundet til præcis ét barn. Viser kun det barns
  /// opgaver og har INGEN forælder-tilstand - HA afviser i øvrigt alt andet
  /// end "markér udført" for barnet selv. Rollen kan kun fjernes ved at
  /// geninstallere appen (AndroidManifest: allowBackup="false").
  childTablet;

  /// Rollens navn i Home Assistant-integrationen.
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

/// Simpel wrapper omkring [SharedPreferences] til alle lokale
/// indstillinger: forbindelsen til Home Assistant, rolle, PIN-hash og en
/// lokal kopi af familiens indstillinger/saldo-info (fra HA).
class SettingsService {
  static const _keyRole = 'role';
  static const _keyPinHash = 'pin_hash';
  static const _keyPinSalt = 'pin_salt';
  static const _keyDeviceName = 'device_name';
  static const _keyFamilyName = 'family_name';

  // Forbindelsen til Home Assistant (fra parringen).
  static const _keyHaUrl = 'ha_url';
  static const _keyHaDeviceId = 'ha_device_id';
  static const _keyHaDeviceKey = 'ha_device_key';

  // Barne-tablet: hvilket barn tabletten er bundet til.
  static const _keyBoundChildId = 'bound_child_id';

  // Familiens tider/grænser (JSON, se FamilySettings) og forældres
  // ophævelse af spærring for i dag (JSON: barn-id -> "YYYY-MM-DD").
  static const _keyFamilySettings = 'family_settings';
  static const _keyRestrictionSuspensions = 'restriction_suspensions';

  // Seneste app-version der er givet besked om (så notifikationen kun
  // kommer én gang pr. version).
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

  // ---- Rolle og forbindelse ---------------------------------------------

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

  /// Glemmer forbindelsen, rollen og PIN'en (fx når enheden er fjernet i
  /// Home Assistant). Enheden skal derefter forbindes igen med en ny
  /// QR-kode fra HA.
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

  // ---- Barne-tablet -----------------------------------------------------

  String? get boundChildId => _prefs.getString(_keyBoundChildId);

  Future<void> setBoundChildId(String? childId) => childId == null
      ? _prefs.remove(_keyBoundChildId)
      : _prefs.setString(_keyBoundChildId, childId);

  // ---- Familiens tider og grænser -----------------------------------------

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

  /// Barn-id -> dato (`YYYY-MM-DD`) hvor en forælder har ophævet barnets
  /// spærring for resten af dagen.
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

  // ---- PIN (familiens forælder-PIN, sat i Home Assistant) -----------------

  bool get hasPin =>
      _prefs.containsKey(_keyPinHash) && _prefs.containsKey(_keyPinSalt);

  String? get pinHash => _prefs.getString(_keyPinHash);
  String? get pinSalt => _prefs.getString(_keyPinSalt);

  Future<void> setPin(String hash, String salt) async {
    await _prefs.setString(_keyPinHash, hash);
    await _prefs.setString(_keyPinSalt, salt);
  }

  // ---- Saldo ---------------------------------------------------------------
  //
  // [totalPaidOutOre] var ét globalt udbetalt-beløb fra dengang appen kun
  // understøttede ét barn; det bruges kun af engangs-migrationen i
  // TaskRepository.migrateLegacyPaidOutIfNeeded. Udbetalt er nu pr. barn.

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
      // Defensivt: en ugyldig/korrupt gemt værdi må ikke crashe appen -
      // behandles blot som "intet udbetalt endnu for nogen".
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

  // ---- Simpel offline-kø ------------------------------------------------
  // Handlinger der ikke kunne sendes til Home Assistant med det samme, gemt
  // som JSON-strenge og sendt igen senere i samme rækkefølge.

  List<String> get offlineQueueRaw =>
      _prefs.getStringList(_keyOfflineQueue) ?? const [];

  Future<void> setOfflineQueueRaw(List<String> items) =>
      _prefs.setStringList(_keyOfflineQueue, items);
}
