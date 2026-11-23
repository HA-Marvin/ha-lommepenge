import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../l10n/l10n.dart';
import '../models/approval.dart';
import '../models/child.dart';
import '../models/family_settings.dart';
import '../models/history.dart';
import '../models/lock.dart';
import '../models/task.dart';
import '../services/crypto_service.dart';
import '../services/ha_client.dart';
import '../services/native_bridge.dart';
import '../services/settings_service.dart';

/// Sync status shown discreetly in the UI (e.g. as a small icon/text).
enum SyncStatus { unknown, connected, offline, syncing }

/// An action or a history request that did not go through. [message] is
/// "No connection to Home Assistant - try again" or HA's own error text (in
/// the app's language). Nothing has been changed in the app.
class ActionFailed implements Exception {
  final String message;

  /// No answer from HA (network, timeout, not JSON): HA may or may not have
  /// performed the action, so a retry must be idempotent.
  final bool offline;

  /// HA's stable error code, if it sent one (e.g. `task_not_available`).
  final String? code;

  const ActionFailed(this.message, {this.offline = false, this.code});

  @override
  String toString() => message;
}

/// A newer version of the app that Home Assistant has ready.
class AppUpdate {
  final String version;
  final int versionCode;
  final String sha256;
  final int size;

  const AppUpdate({
    required this.version,
    required this.versionCode,
    required this.sha256,
    required this.size,
  });

  static AppUpdate? fromJson(Object? json) {
    if (json is! Map) return null;
    final version = json['version'];
    final code = json['versionCode'];
    final sha = json['sha256'];
    if (version is! String || code is! int || sha is! String) return null;
    return AppUpdate(
      version: version,
      versionCode: code,
      sha256: sha,
      size: (json['size'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Central app state: one [ChangeNotifier] with the device's settings, Home
/// Assistant's latest answer and the connection to HA.
///
/// The app is a pure view of Home Assistant (Del H1): it keeps only HA's
/// latest state in memory, stores no history and calculates nothing itself.
/// Every action is confirmed: it is sent to HA, the UI shows a spinner
/// ([isBusy]) meanwhile, and the screen changes only from the state HA sends
/// back. On an error nothing changes and [ActionFailed] is thrown. There is
/// no offline queue. The state is fetched every 30 seconds and when the app
/// comes to the foreground.
class AppState extends ChangeNotifier with WidgetsBindingObserver {
  final SettingsService settings;
  final HaClient _client;
  final NativeBridge _native;

  /// Fetches HA's state every [_syncInterval].
  Timer? _syncTimer;
  static const _syncInterval = Duration(seconds: 30);
  StreamSubscription<String>? _linkSubscription;
  StreamSubscription<String?>? _installFailureSubscription;
  StreamSubscription<void>? _refreshSubscription;
  bool _observingLifecycle = false;

  AppState({
    required this.settings,
    HaClient? client,
    NativeBridge? native,
  })  : _client = client ?? HaClient(),
        _native = native ?? NativeBridge() {
    _applyLanguage();
    // A wrong clock on the device is corrected with HA's time instead of
    // forcing a new pairing; the correction survives restarts.
    _client.clockOffset = Duration(milliseconds: settings.clockOffsetMs);
    _client.onClockOffsetChanged =
        (offset) => settings.setClockOffsetMs(offset.inMilliseconds);
  }

  // ---- Language ------------------------------------------------------------

  /// The app's language (English until another is chosen).
  String get language {
    final chosen = settings.language;
    return supportedLanguages.containsKey(chosen) ? chosen! : defaultLanguage;
  }

  /// Whether the language has been chosen (on first start the app asks).
  bool get languageChosen => settings.language != null;

  /// The texts in the app's language, for code without a `BuildContext`.
  AppLocalizations get l10n => l10nFor(language);

  Future<void> setLanguage(String language) async {
    await settings.setLanguage(language);
    _applyLanguage();
    await _updateChildService();
    // Texts calculated in this class follow the new language at the next sync.
    syncMessage = null;
    notifyListeners();
  }

  void _applyLanguage() {
    _client.l10n = l10n;
  }

  /// The currency chosen in Home Assistant (DKK until the first sync).
  String get currency => settings.currency;

  bool parentModeUnlocked = false;

  // ---- Home Assistant's latest state (in memory only) ----------------------

  /// Whether a state has been received from HA since the app started.
  bool hasState = false;

  /// The children with balance, earnings this week and task list - a child's
  /// tablet only gets its own child.
  List<Child> children = const [];

  /// Parent part: completions waiting for approval, oldest first.
  List<Approval> approvals = const [];

  /// Parent part: the active tasks with all fields, for the edit screens.
  List<Task> tasks = const [];

  /// Parent part: the family's times and limits.
  FamilySettings familySettings = FamilySettings.defaults;

  /// HA's local date (`YYYY-MM-DD`) at the latest state, so "today" is HA's
  /// today even if the device's clock is wrong.
  String? today;

  /// HA's time (`state.now`) in the latest state, and when (by the device's
  /// clock) that state arrived. A lock's countdown is `endsAt - serverNow`
  /// minus the time since [stateReceivedAt], see [lockRemainingFor].
  DateTime? serverNow;
  DateTime stateReceivedAt = DateTime.now();

  SyncStatus syncStatus = SyncStatus.unknown;
  String? syncMessage;
  DateTime? lastSyncAt;

  /// Message on the connect screen, e.g. when the device was removed in HA.
  String? connectionMessage;

  /// The app's own version (from Android).
  String appVersion = '';
  int appVersionCode = 0;

  /// A newer version from Home Assistant, if there is one.
  AppUpdate? availableUpdate;

  /// While an update is downloading: 0.0-1.0, otherwise `null`.
  double? updateProgress;
  String? updateMessage;

  DeviceRole? get role => settings.role;
  bool get hasPin => settings.hasPin;
  bool get isScreen => role == DeviceRole.screen;
  bool get isPhone => role == DeviceRole.phone;
  bool get isChildTablet => role == DeviceRole.childTablet;

  /// Whether the device is connected to Home Assistant (and thereby has a role).
  bool get isConnected => settings.connection != null && role != null;

  HaConnection? get connection => settings.connection;

  /// Child's tablet: the child the tablet is bound to.
  String? get boundChildId => settings.boundChildId;
  Child? get boundChild =>
      boundChildId == null ? null : childrenById[boundChildId];

  /// Quick lookup child id -> [Child], for showing names in the UI.
  Map<String, Child> get childrenById => {for (final c in children) c.id: c};

  /// How long [lock] has left now, counted down locally from HA's time in
  /// the latest state (`null` when it is not running).
  Duration? lockRemainingFor(ChildLock lock, {DateTime? deviceNow}) =>
      lockRemaining(
        lock,
        serverNow: serverNow,
        receivedAt: stateReceivedAt,
        deviceNow: deviceNow ?? DateTime.now(),
      );

  // ---- Startup ---------------------------------------------------------------

  Future<void> initialize() async {
    // Installations from before the language choice were Danish-only, so a
    // device that is already connected keeps Danish. A new installation
    // chooses on first start (English by default).
    if (!languageChosen && isConnected) {
      await settings.setLanguage('da');
      _applyLanguage();
    }
    await _removeDataFromOlderVersions();

    final version = await _native.appVersion();
    appVersion = version.name;
    appVersionCode = version.code;
    _client.appVersion = appVersion;
    _client.appVersionCode = appVersionCode;

    _linkSubscription = _native.links.listen(connectWithLink);
    _installFailureSubscription = _native.installFailures.listen((message) {
      updateProgress = null;
      updateMessage = message ?? l10n.installationFailed;
      notifyListeners();
    });
    // The child's tablet's background service reported use to HA (which may
    // have started a lock): show HA's new state at once.
    _refreshSubscription = _native.refreshRequests.listen((_) {
      if (isConnected) unawaited(syncNow());
    });
    await _updateChildService();
    WidgetsBinding.instance.addObserver(this);
    _observingLifecycle = true;
    final initialLink = await _native.takeInitialLink();
    if (initialLink != null) {
      unawaited(connectWithLink(initialLink));
    } else if (isConnected) {
      unawaited(syncNow());
    }
    _syncTimer = Timer.periodic(_syncInterval, (_) => _onTick());
  }

  /// Versions before Del H1 kept a copy of the family's data in SQLite and
  /// in the settings. It is no longer used, so it is deleted.
  Future<void> _removeDataFromOlderVersions() async {
    await settings.removeObsoleteData();
    try {
      final dir = await getApplicationDocumentsDirectory();
      for (final suffix in ['', '-journal', '-wal', '-shm']) {
        final file = File('${dir.path}/lommepenge.db$suffix');
        if (await file.exists()) await file.delete();
      }
    } catch (_) {
      // Best effort: no documents directory (tests) or the file is busy.
    }
  }

  Future<void> _onTick() async {
    try {
      if (isConnected) await syncNow();
    } catch (_) {
      // A failed background update must never bring the app down - the next
      // tick tries again.
    }
  }

  /// The app came to the foreground: fetch HA's state right away instead of
  /// waiting for the next 30-second tick.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && isConnected) {
      unawaited(syncNow());
    }
  }

  // ---- Parent mode -------------------------------------------------------

  /// Checks the family's parent PIN (set in Home Assistant).
  bool verifyPin(String pin) {
    final hash = settings.pinHash;
    final salt = settings.pinSalt;
    if (hash == null || salt == null) return false;
    return CryptoService.verifyPin(pin, salt, hash);
  }

  /// On the family screen (shared by everyone, e.g. on the fridge) parent
  /// mode closes by itself after this long without a tap, so a parent who
  /// walks away does not leave it open to the children. Phones are not
  /// timed out.
  static const parentModeTimeout = Duration(minutes: 2);
  Timer? _parentModeTimer;

  /// Called when parent mode has closed because of inactivity, so the UI can
  /// leave the parent screens (see `ParentModeTimeout` in main.dart).
  VoidCallback? onParentModeTimedOut;

  void enterParentMode() {
    // A child's tablet has no parent mode - not even if a future UI bug were
    // to try to open it.
    if (isChildTablet) return;
    parentModeUnlocked = true;
    _restartParentModeTimer();
    notifyListeners();
  }

  void exitParentMode() {
    _parentModeTimer?.cancel();
    _parentModeTimer = null;
    if (!parentModeUnlocked) return;
    parentModeUnlocked = false;
    notifyListeners();
  }

  /// The user touched the screen: parent mode stays open another
  /// [parentModeTimeout].
  void registerActivity() {
    if (parentModeUnlocked) _restartParentModeTimer();
  }

  void _restartParentModeTimer() {
    _parentModeTimer?.cancel();
    _parentModeTimer = null;
    if (!isScreen) return;
    _parentModeTimer = Timer(parentModeTimeout, () {
      exitParentMode();
      onParentModeTimedOut?.call();
    });
  }

  // ---- Actions (confirmed by Home Assistant) --------------------------------
  //
  // Every action follows the same pattern (Del H1): mark it as busy (the UI
  // shows a spinner), send it to HA, and show the state HA sends back. On
  // an error nothing changes locally and [ActionFailed] is thrown, so the UI
  // can show "No connection to Home Assistant - try again" or HA's error.

  /// Actions in progress, by key (see [completeKey] etc.).
  final Set<String> _busy = {};

  /// Whether the action with [key] is waiting for HA (show a spinner).
  bool isBusy(String key) => _busy.contains(key);

  static String completeKey(String childId, String taskId) =>
      'complete:$childId:$taskId';
  static String completionKey(String completionId) =>
      'completion:$completionId';
  static String taskKey(String taskId) => 'task:$taskId';
  static String childKey(String childId) => 'child:$childId';
  static String payoutKey(String childId) => 'payout:$childId';
  static String settingKey(String key) => 'setting:$key';
  static String lockKey(String childId) => 'lock:$childId';
  static String pauseKey(String childId) => 'pause:$childId';
  static const adjustKey = 'adjust';

  /// Counts the states applied from actions, so a poll that was started
  /// before an action and answers after it does not show the older state.
  int _actionStates = 0;

  Future<void> _sendAction(String busyKey, Map<String, dynamic> action) async {
    final current = connection;
    if (current == null) {
      throw ActionFailed(l10n.noConnectionTryAgain, offline: true);
    }
    _busy.add(busyKey);
    notifyListeners();
    try {
      final result = await _client.sendAction(current, action);
      if (result.unauthorized) {
        await disconnect(message: l10n.deviceRemoved);
        throw ActionFailed(l10n.deviceRemoved, code: result.code);
      }
      final state = result.data;
      if (!result.success || state == null) {
        if (result.offline) {
          syncStatus = SyncStatus.offline;
          syncMessage = result.errorMessage;
        } else {
          // HA refused (e.g. already handled by the other parent): the view
          // may be out of date, so fetch HA's state.
          unawaited(syncNow());
        }
        throw ActionFailed(
          result.errorMessage ?? l10n.noConnectionTryAgain,
          offline: result.offline,
          code: result.code,
        );
      }
      _actionStates++;
      await _applyState(state);
      _markConnected();
    } finally {
      _busy.remove(busyKey);
      notifyListeners();
    }
  }

  /// The completion id of a tap on "Done" per child and task entry, kept
  /// until HA has answered, so a retry after a timeout or a lost answer sends
  /// the same id and HA does not count the task twice.
  final Map<String, String> _completionIds = {};

  String _completionSlot(String childId, TaskEntry entry) =>
      '${completeKey(childId, entry.taskId)}:${entry.date.toIso8601String()}';

  /// The completion id a retry of "Done" for [entry] will send, if a tap is
  /// still unanswered.
  @visibleForTesting
  String? pendingCompletionId(String childId, TaskEntry entry) =>
      _completionIds[_completionSlot(childId, entry)];

  /// Marks [entry] as done for [childId]. The completion id is created by
  /// the app once per tap and reused when the same tap is retried after
  /// "No connection".
  Future<void> completeTask(TaskEntry entry, {required String childId}) async {
    final key = completeKey(childId, entry.taskId);
    if (isBusy(key)) return;
    final slot = _completionSlot(childId, entry);
    final completionId =
        _completionIds.putIfAbsent(slot, () => const Uuid().v4());
    try {
      await _sendAction(key, {
        'type': 'complete_task',
        'payload': {
          'taskId': entry.taskId,
          'childId': childId,
          'completionId': completionId,
        },
      });
      _completionIds.remove(slot);
    } on ActionFailed catch (e) {
      // HA answered (with an error): the id is used up. Without an answer
      // HA may have registered it, so the next try sends the same id.
      if (!e.offline) _completionIds.remove(slot);
      rethrow;
    }
  }

  /// Forgets kept completion ids whose task entry HA no longer shows as
  /// doable (it is awaiting approval or gone): a later tap is a new one.
  void _forgetHandledCompletionIds() {
    if (_completionIds.isEmpty) return;
    final doable = {
      for (final child in children)
        for (final entry in child.tasks)
          if (entry.canComplete) _completionSlot(child.id, entry),
    };
    _completionIds.removeWhere((slot, _) => !doable.contains(slot));
  }

  /// Creates [task]. Its id is made by the app: the edit screen sends the
  /// same id when it saves again after an error, so HA does not create the
  /// task twice.
  Future<void> createTask(Task task) => _sendAction(taskKey(task.id), {
        'type': 'create_task',
        'payload': task.toPayload(),
      });

  Future<void> editTask(Task task) => _sendAction(taskKey(task.id), {
        'type': 'update_task',
        'payload': task.toPayload(),
      });

  Future<void> deleteTask(String id) => _sendAction(taskKey(id), {
        'type': 'delete_task',
        'payload': {'id': id},
      });

  /// Changes one family setting (see [FamilySettings.keys]); HA validates it.
  Future<void> setFamilySetting(String key, Object value) =>
      _sendAction(settingKey(key), {
        'type': 'set_setting',
        'payload': {'key': key, 'value': value},
      });

  Future<void> approveCompletion(String completionId) =>
      _sendAction(completionKey(completionId), {
        'type': 'approve_completion',
        'payload': {'completionId': completionId},
      });

  /// Rejects a completion, with the parent's optional [reason] (shown to
  /// the child in the notification; HA allows at most 500 characters).
  Future<void> rejectCompletion(String completionId, {String? reason}) {
    final text = reason?.trim() ?? '';
    return _sendAction(completionKey(completionId), {
      'type': 'reject_completion',
      'payload': {
        'completionId': completionId,
        if (text.isNotEmpty) 'reason': text,
      },
    });
  }

  /// Clears the child's pending or running lock (new causes can lock again).
  Future<void> liftLock(String childId) => _sendAction(lockKey(childId), {
        'type': 'lift_lock',
        'payload': {'childId': childId},
      });

  /// Pauses the child (no task is mandatory, no lock) until [until] (HA's
  /// date `YYYY-MM-DD`, after today) or, without it, until resumed; pausing
  /// also lifts the lock. `paused: false` resumes now.
  Future<void> setPause(String childId, {required bool paused, String? until}) =>
      _sendAction(pauseKey(childId), {
        'type': 'set_pause',
        'payload': {
          'childId': childId,
          'paused': paused,
          if (paused) 'until': until,
        },
      });

  Future<void> markPaidOut({required String childId}) =>
      _sendAction(payoutKey(childId), {
        'type': 'mark_paid_out',
        'payload': {'childId': childId},
      });

  /// Adds a manual, signed (+/-) balance adjustment for one child, with a
  /// mandatory reason.
  Future<void> adjustBalance({
    required int amountOre,
    required String note,
    required String childId,
  }) =>
      _sendAction(adjustKey, {
        'type': 'adjust_balance',
        'payload': {
          'id': const Uuid().v4(),
          'childId': childId,
          'amountOre': amountOre,
          'note': note,
        },
      });

  Future<void> addChild(String name) {
    final id = const Uuid().v4();
    return _sendAction(childKey(id), {
      'type': 'add_child',
      'payload': {'id': id, 'name': name},
    });
  }

  Future<void> renameChild(String id, String newName) =>
      _sendAction(childKey(id), {
        'type': 'rename_child',
        'payload': {'id': id, 'name': newName},
      });

  Future<void> deleteChild(String id) => _sendAction(childKey(id), {
        'type': 'delete_child',
        'payload': {'id': id},
      });

  // ---- History (fetched on request, never stored) ----------------------------

  /// One page of history from HA (30 days before [before], newest first). A
  /// child's tablet always asks for its own child only. The page is not kept
  /// here - the history screen holds it while it is open.
  Future<HistoryPage> fetchHistory({
    String? before,
    String? childId,
    List<String>? types,
  }) async {
    final current = connection;
    if (current == null) {
      throw ActionFailed(l10n.noConnectionTryAgain, offline: true);
    }
    final result = await _client.fetchHistory(
      current,
      before: before,
      childId: isChildTablet ? boundChildId : childId,
      types: types,
    );
    if (result.unauthorized) {
      await disconnect(message: l10n.deviceRemoved);
      throw ActionFailed(l10n.deviceRemoved, code: result.code);
    }
    final page = result.data;
    if (!result.success || page == null) {
      throw ActionFailed(
        result.errorMessage ?? l10n.noConnectionTryAgain,
        offline: result.offline,
        code: result.code,
      );
    }
    return HistoryPage.fromJson(page);
  }

  // ---- Connection to Home Assistant ----------------------------------------

  /// Connects the device with a link from "Add device" in Home Assistant (the
  /// QR code or "Open the app and connect"). The role is decided by HA.
  /// Returns an error message, or `null` on success.
  Future<String?> connectWithLink(String text) async {
    final link = parseConnectLink(text);
    if (link == null) {
      return _connectionFailed(l10n.notLommepengeLink);
    }
    return _connect(link);
  }

  /// Connects with HA's address and the code from "Add device" - for devices
  /// without a camera.
  Future<String?> connectWithCode(String address, String code) async {
    final link = connectLinkFromCode(address, code);
    if (link == null) {
      return _connectionFailed(l10n.enterAddressAndCode);
    }
    return _connect(link);
  }

  /// Home Assistant on the home network, to fill in the address.
  Future<List<({String name, String url})>> discoverHa() => _native.discoverHa();

  Future<String?> _connect(ConnectLink link) async {
    if (isChildTablet && isConnected) {
      // A child's tablet cannot be switched to another role by scanning a new
      // code - only by reinstalling.
      return _connectionFailed(l10n.tabletAlreadyConnected);
    }
    final result = await _client.pair(link);
    if (!result.success) return _connectionFailed(result.errorMessage!);
    final role = DeviceRole.fromHa(result.role);
    if (role == null || result.deviceId == null || result.deviceKey == null) {
      return _connectionFailed(l10n.unexpectedResponse);
    }

    await settings.setConnection(HaConnection(
      baseUrl: link.baseUrl,
      deviceId: result.deviceId!,
      key: result.deviceKey!,
    ));
    await settings.setRole(role);
    await settings.setBoundChildId(
      role == DeviceRole.childTablet ? result.childId : null,
    );
    await settings.setDeviceName(result.deviceName ?? 'Lommepenge');
    await settings.setFamilyName(result.familyName ?? 'Lommepenge');
    connectionMessage = null;
    notifyListeners();
    await syncNow();
    await _updateChildService();
    return null;
  }

  String _connectionFailed(String message) {
    connectionMessage = message;
    notifyListeners();
    return message;
  }

  /// Forgets the connection on this device (the device should also be removed
  /// under "Devices" in Home Assistant). The language is kept.
  Future<void> disconnect({String? message}) async {
    await settings.clearConnection();
    connectionMessage = message;
    syncStatus = SyncStatus.unknown;
    syncMessage = null;
    availableUpdate = null;
    _clearState();
    _parentModeTimer?.cancel();
    parentModeUnlocked = false;
    notifyListeners();
    await _updateChildService();
  }

  void _clearState() {
    hasState = false;
    children = const [];
    approvals = const [];
    tasks = const [];
    familySettings = FamilySettings.defaults;
    today = null;
    serverNow = null;
    _completionIds.clear();
  }

  Future<void>? _syncing;

  /// Fetches HA's current state. Called every 30 seconds, when the app comes
  /// to the foreground, when it opens and on "pull to refresh". Calls while
  /// a fetch is running share it.
  Future<void> syncNow() => _syncing ??= _sync().whenComplete(() {
        _syncing = null;
      });

  Future<void> _sync() async {
    final current = connection;
    if (current == null) {
      syncStatus = SyncStatus.unknown;
      syncMessage = l10n.notConnectedYet;
      notifyListeners();
      return;
    }

    syncStatus = SyncStatus.syncing;
    notifyListeners();

    final actionStatesBefore = _actionStates;
    final result = await _client.fetchState(current);
    if (result.unauthorized) {
      await disconnect(message: l10n.deviceRemoved);
      return;
    }
    final state = result.data;
    if (result.success && state != null) {
      // An action answered while this fetch was under way: its state is
      // newer, so this one is dropped (the next poll fetches again).
      if (_actionStates == actionStatesBefore) await _applyState(state);
      _markConnected();
    } else {
      // Keep showing HA's latest state; only the status changes.
      syncStatus = SyncStatus.offline;
      syncMessage = result.errorMessage ?? l10n.noConnectionTryAgain;
    }
    notifyListeners();
  }

  void _markConnected() {
    syncStatus = SyncStatus.connected;
    syncMessage = null;
    lastSyncAt = DateTime.now();
  }

  /// Shows HA's state (from `GET /state` or an action) - see docs/app-api.md.
  Future<void> _applyState(Map<String, dynamic> state) async {
    final device = state['device'];
    if (device is Map) {
      final role = DeviceRole.fromHa(device['role'] as String?);
      if (role != null && role != settings.role) await settings.setRole(role);
      if (role == DeviceRole.childTablet) {
        await settings.setBoundChildId(device['childId'] as String?);
      }
      if (device['name'] is String) {
        await settings.setDeviceName(device['name'] as String);
      }
    }
    if (state['familyName'] is String) {
      await settings.setFamilyName(state['familyName'] as String);
    }
    final currency = state['currency'];
    if (currency is String && currency.trim().isNotEmpty) {
      await settings.setCurrency(currency.trim());
    }
    final pinHash = state['pinHash'];
    final pinSalt = state['pinSalt'];
    if (pinHash is String && pinSalt is String) {
      await settings.setPin(pinHash, pinSalt);
    }

    children = _parseList(state['children'], Child.fromJson);
    approvals = _parseList(state['approvals'], Approval.fromJson);
    tasks = _parseList(state['tasks'], Task.fromJson);
    final familySettingsJson = state['settings'];
    familySettings = FamilySettings.fromJson(
      familySettingsJson is Map<String, dynamic> ? familySettingsJson : null,
    );
    today = state['today'] as String?;
    final now = state['now'];
    serverNow = now is String ? DateTime.tryParse(now) : null;
    stateReceivedAt = DateTime.now();
    hasState = true;
    _forgetHandledCompletionIds();

    await _checkForUpdate(AppUpdate.fromJson(state['appUpdate']));
  }

  /// Reads a list from the state; an item the app cannot read is skipped.
  static List<T> _parseList<T>(
    Object? raw,
    T Function(Map<String, dynamic>) parse,
  ) {
    final items = <T>[];
    if (raw is! List) return items;
    for (final item in raw) {
      if (item is! Map<String, dynamic>) continue;
      try {
        items.add(parse(item));
      } catch (_) {
        // A malformed item from a newer/older HA: skipped.
      }
    }
    return items;
  }

  // ---- The child's tablet's background service -------------------------------

  /// Starts the foreground service on a connected child's tablet (it polls
  /// HA, reports use and shows the child's notifications - see
  /// `LockService.kt`) and stops it everywhere else. Its texts follow the
  /// app's language.
  Future<void> _updateChildService() async {
    final enabled = isConnected && isChildTablet;
    await _native.configureChildService(
      enabled: enabled,
      texts: enabled
          ? {
              'statusChannel': l10n.serviceStatusChannel,
              'messagesChannel': l10n.serviceMessagesChannel,
              'active': l10n.serviceActive,
              'lockedUntil': l10n.serviceLockedUntil('{time}'),
            }
          : const {},
    );
  }

  // ---- Updating the app from Home Assistant ---------------------------------

  Future<void> _checkForUpdate(AppUpdate? update) async {
    final newer = update != null &&
        appVersionCode > 0 &&
        update.versionCode > appVersionCode;
    availableUpdate = newer ? update : null;
    if (newer && settings.notifiedUpdateCode < update.versionCode) {
      await settings.setNotifiedUpdateCode(update.versionCode);
      await _native.notify(
        l10n.updateNotificationTitle,
        l10n.updateNotificationBody(update.version),
        channelName: l10n.updatesChannel,
      );
    }
  }

  /// Downloads the new version from HA, checks it and asks Android to install it.
  Future<void> installUpdate() async {
    final update = availableUpdate;
    final current = connection;
    if (update == null || current == null || updateProgress != null) return;

    if (!await _native.canInstall()) {
      updateMessage = l10n.allowUnknownApps;
      notifyListeners();
      await _native.openInstallSettings();
      return;
    }

    updateProgress = 0;
    updateMessage = null;
    notifyListeners();
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/lommepenge-${update.version}.apk');
    final error = await _client.downloadApk(
      current,
      file,
      onProgress: (received, total) {
        final size = total ?? update.size;
        updateProgress = size > 0 ? received / size : null;
        notifyListeners();
      },
    );
    if (error != null) {
      updateProgress = null;
      updateMessage = error;
      notifyListeners();
      return;
    }
    final digest = await sha256.bind(file.openRead()).first;
    if (digest.toString() != update.sha256) {
      await file.delete();
      updateProgress = null;
      updateMessage = l10n.downloadCorrupt;
      notifyListeners();
      return;
    }
    try {
      await _native.installApk(file.path);
      updateMessage = l10n.installing(update.version);
    } catch (e) {
      updateMessage = l10n.installFailed('$e');
    }
    updateProgress = null;
    notifyListeners();
  }

  bool _disposed = false;

  /// A sync that was started before [dispose] may finish afterwards; its
  /// result is then simply dropped.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _syncTimer?.cancel();
    _parentModeTimer?.cancel();
    if (_observingLifecycle) WidgetsBinding.instance.removeObserver(this);
    _linkSubscription?.cancel();
    _installFailureSubscription?.cancel();
    _refreshSubscription?.cancel();
    super.dispose();
  }
}
