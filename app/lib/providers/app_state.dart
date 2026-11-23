import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../l10n/l10n.dart';
import '../logic/follow_up.dart';
import '../logic/recurrence.dart';
import '../models/balance_adjustment.dart';
import '../models/child.dart';
import '../models/completion.dart';
import '../models/family_settings.dart';
import '../models/task.dart';
import '../repositories/task_repository.dart';
import '../services/crypto_service.dart';
import '../services/ha_client.dart';
import '../services/native_bridge.dart';
import '../services/settings_service.dart';

/// Sync status shown discreetly in the UI (e.g. as a small icon/text).
enum SyncStatus { unknown, connected, offline, syncing }

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

/// Central app state. Keeps the UI deliberately simple: one
/// [ChangeNotifier] that gathers the settings, the local copy of the family's
/// data (via [TaskRepository]) and the connection to Home Assistant.
///
/// Home Assistant is the "source of truth": all devices - the family screen,
/// the parents' phones and the children's tablets - fetch the family's data
/// from there and send their actions there. Actions are also applied locally
/// right away, so the app feels fast and works briefly without a connection.
class AppState extends ChangeNotifier {
  final SettingsService settings;
  final TaskRepository repository;
  final HaClient _client;
  final NativeBridge _native;

  /// Fetches news from HA and recalculates the follow-up (deadlines pass
  /// without the data changing).
  Timer? _syncTimer;
  static const _syncInterval = Duration(seconds: 30);
  StreamSubscription<String>? _linkSubscription;
  StreamSubscription<String?>? _installFailureSubscription;

  /// Follow-up status per child: overdue tasks, restriction, next deadline.
  Map<String, ChildFollowUp> followUps = {};

  ChildFollowUp? followUpFor(String childId) => followUps[childId];

  FamilySettings get familySettings => settings.familySettings;

  AppState({
    required this.settings,
    required this.repository,
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
    // Texts calculated in this class follow the new language at the next sync.
    syncMessage = null;
    notifyListeners();
  }

  void _applyLanguage() {
    _client.l10n = l10n;
    repository.l10n = l10n;
  }

  /// The currency chosen in Home Assistant (DKK until the first sync).
  String get currency => settings.currency;

  bool parentModeUnlocked = false;

  List<Task> tasks = [];
  List<Completion> completions = [];
  List<BalanceAdjustment> balanceAdjustments = [];
  List<Child> children = [];

  /// Balance/earnings etc. are per child - see [currentBalanceOreFor] etc.
  Map<String, int> currentBalanceOreByChild = {};
  Map<String, int> totalEarnedOreByChild = {};
  Map<String, int> earnedThisWeekOreByChild = {};
  Map<String, int> completedCountThisWeekByChild = {};

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

  int currentBalanceOreFor(String childId) =>
      currentBalanceOreByChild[childId] ?? 0;
  int totalEarnedOreFor(String childId) => totalEarnedOreByChild[childId] ?? 0;
  int earnedThisWeekOreFor(String childId) =>
      earnedThisWeekOreByChild[childId] ?? 0;
  int completedCountThisWeekFor(String childId) =>
      completedCountThisWeekByChild[childId] ?? 0;

  Map<String, TaskAvailability> _availability = {};
  Map<String, List<String>> _resolvedChildIds = {};

  /// Availability of [task] for one specific child - see
  /// `TaskRepository.availabilityFor`.
  TaskAvailability availabilityOf(Task task, String childId) =>
      _availability['${task.id}::$childId'] ?? TaskAvailability.available;

  /// Which children's ids [task] is actually assigned to right now (dynamic
  /// lookup of "all children") - see `TaskRepository.resolvedChildIdsForTask`.
  List<String> resolvedChildIdsFor(Task task) =>
      _resolvedChildIds[task.id] ?? const [];

  DateTime? nextAvailableFor(Task task, String childId) {
    final forTaskAndChild = completions
        .where((c) => c.taskId == task.id && c.childId == childId)
        .toList();
    return nextAvailableDate(task, forTaskAndChild);
  }

  // ---- Sorting the task list ("what needs doing now?") ---------------------
  //
  // The rule (confirmed with the user on 30 Aug 2026): the outermost sorting
  // (mandatory before optional) is left alone - it still happens in
  // refreshFromLocal. WITHIN each of the two groups the tasks are sorted by
  // how "urgent" they are right now, calculated from the task's ACTUALLY
  // assigned children (resolvedChildIdsFor) - see _taskSortTuple and
  // _childSortTuple below for the rule itself.

  /// Sorts [tasksToSort] by the "what needs to happen now" rule (see
  /// [_taskSortTuple]), and uses [originalIndex] - the task's place in the
  /// original, created_at-sorted list from the repository - as the
  /// tiebreak.
  ///
  /// Dart's `List.sort` is NOT guaranteed to be stable, so the tiebreak must
  /// be explicit in the comparison function so two tasks with exactly the
  /// same (tier, dayOffset) do not "flicker" between two updates of the list.
  List<Task> _sortByUrgency(
    List<Task> tasksToSort,
    Map<String, int> originalIndex,
  ) {
    final withKeys = [
      for (final task in tasksToSort) MapEntry(task, _taskSortTuple(task)),
    ];
    withKeys.sort((a, b) {
      final tierCompare = a.value.$1.compareTo(b.value.$1);
      if (tierCompare != 0) return tierCompare;
      final offsetCompare = a.value.$2.compareTo(b.value.$2);
      if (offsetCompare != 0) return offsetCompare;
      final aIndex = originalIndex[a.key.id] ?? 0;
      final bIndex = originalIndex[b.key.id] ?? 0;
      return aIndex.compareTo(bIndex);
    });
    return [for (final entry in withKeys) entry.key];
  }

  /// Calculates [task]'s sort key as a (tier, dayOffset) pair, from its
  /// ACTUALLY assigned children ([resolvedChildIdsFor]) - see
  /// [_childSortTuple] for how each child's tuple is calculated.
  ///
  /// The task's overall tuple is the BEST (smallest) of all assigned
  /// children's tuples, compared first on tier (0 < 1 < 2), then on
  /// dayOffset: as long as just ONE assigned child can/should still do the
  /// task today, the task stays at the top of the list - it only moves down
  /// once ALL assigned children are in the same or a worse state.
  ///
  /// Edge case: if the task is not actually assigned to any (still existing)
  /// children - e.g. all assigned children have been deleted since - (1, 0)
  /// is used as fallback: the same "place" as "can never become available
  /// again", so the task ends up somewhere sensible instead of at the top,
  /// and the sorting does not crash on an empty set of child tuples.
  (int, int) _taskSortTuple(Task task) {
    final childIds = resolvedChildIdsFor(task);
    if (childIds.isEmpty) return (1, 0);

    (int, int)? best;
    for (final childId in childIds) {
      final tuple = _childSortTuple(task, childId);
      final isBetter = best == null ||
          tuple.$1 < best.$1 ||
          (tuple.$1 == best.$1 && tuple.$2 < best.$2);
      if (isBetter) {
        best = tuple;
      }
    }
    return best!;
  }

  /// Calculates one assigned child's (tier, dayOffset) tuple for [task]. The
  /// smaller the tuple (tier compared first, then dayOffset), the more
  /// urgent/relevant the task is for this child right now:
  ///
  /// - tier 0: the task is actually untouched and ready to be done today (the
  ///   top group) - dayOffset always 0.
  /// - tier 1: the task can NEVER become available again for this child (e.g.
  ///   a one-off task that has already been approved, or an impossible week
  ///   plan where no weekday is chosen) - the middle group, dayOffset always 0.
  /// - tier 2: the task has either already been touched/is awaiting approval
  ///   today (dayOffset 0), or is only available again on a coming day
  ///   (dayOffset = number of calendar days from today to that date).
  ///
  /// Special case (the only exception to using [availabilityOf] directly): a
  /// task with status [TaskAvailability.available] STILL counts as "already
  /// done today" (tier 2, dayOffset 0) if there is an APPROVED completion for
  /// exactly this (task, child) pair with completedAt today. In practice this
  /// only happens for [Recurrence.unlimited] tasks, which deliberately have no
  /// daily cool-down in [computeAvailability] (they are "always available") -
  /// without this check an unlimited task the child has already done 5 times
  /// today would stay at the top of the list for the rest of the day. The
  /// check is deliberately written generically (looks at the completions
  /// list, not at task.recurrence), so it does not need updating if a future
  /// recurrence type gets the same property.
  (int, int) _childSortTuple(Task task, String childId) {
    final availability = availabilityOf(task, childId);

    if (availability == TaskAvailability.pendingApproval) {
      return (2, 0);
    }

    if (availability == TaskAvailability.available) {
      final alreadyApprovedToday = completions.any((c) =>
          c.taskId == task.id &&
          c.childId == childId &&
          c.status == CompletionStatus.approved &&
          _isSameCalendarDate(c.completedAt, DateTime.now()));
      return alreadyApprovedToday ? (2, 0) : (0, 0);
    }

    // doneToday / doneThisWeek / notScheduledToday / completedOnce: find the
    // next date on which the task becomes available again for this child.
    final next = nextAvailableFor(task, childId);
    if (next == null) {
      // Can never become available again (e.g. completedOnce, or a week plan
      // without any active weekdays).
      return (1, 0);
    }
    final dayOffset = _calendarDateOnly(next)
        .difference(_calendarDateOnly(DateTime.now()))
        .inDays;
    return (2, dayOffset);
  }

  /// Compares two [DateTime]s at calendar-day level (year/month/day),
  /// ignoring the time of day.
  bool _isSameCalendarDate(DateTime a, DateTime b) =>
      _calendarDateOnly(a) == _calendarDateOnly(b);

  /// Date without time of day - the same pattern as the private `_dateOnly`
  /// in `logic/recurrence.dart` (duplicated here as it is not exported).
  DateTime _calendarDateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  // ---- Startup ---------------------------------------------------------------

  Future<void> initialize() async {
    // Installations from before the language choice were Danish-only, so a
    // device that is already connected keeps Danish. A new installation
    // chooses on first start (English by default).
    if (!languageChosen && isConnected) {
      await settings.setLanguage('da');
      _applyLanguage();
    }

    // One-time migration of the old global paid-out amount to the one child -
    // see the doc on the method. Must happen BEFORE refreshFromLocal starts
    // reading per-child balances.
    await repository.migrateLegacyPaidOutIfNeeded();
    await refreshFromLocal();

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
    final initialLink = await _native.takeInitialLink();
    if (initialLink != null) {
      unawaited(connectWithLink(initialLink));
    } else if (isConnected) {
      unawaited(syncNow());
    }
    _syncTimer = Timer.periodic(_syncInterval, (_) => _onTick());
  }

  Future<void> _onTick() async {
    try {
      if (isConnected) {
        await syncNow();
      } else {
        await _recomputeFollowUps();
        notifyListeners();
      }
    } catch (_) {
      // A failed background update must never bring the app down - the next
      // tick tries again.
    }
  }

  Future<void> _recomputeFollowUps() async {
    followUps = await repository.followUpForAll();
  }

  Future<void> refreshFromLocal() async {
    final activeTasks = await repository.getActiveTasks();
    // Mandatory tasks are always shown first, so they do not drown among
    // optional tasks - this is the outermost sorting level and is not touched
    // by the "what needs doing now" sorting within each group (see
    // _sortByUrgency below). These two temporary lists are used right away to
    // calculate _availability/_resolvedChildIds, BEFORE they are finally
    // sorted and combined into `tasks`.
    final mandatoryTasks = activeTasks.where((t) => t.mandatory).toList();
    final optionalTasks = activeTasks.where((t) => !t.mandatory).toList();
    final tasksForAvailability = [...mandatoryTasks, ...optionalTasks];
    completions = await repository.getAllCompletions();
    balanceAdjustments = await repository.getAllBalanceAdjustments();
    children = await repository.getAllChildren();

    final balanceMap = <String, int>{};
    final earnedMap = <String, int>{};
    final weekEarnedMap = <String, int>{};
    final weekCountMap = <String, int>{};
    for (final child in children) {
      balanceMap[child.id] =
          await repository.currentBalanceOre(childId: child.id);
      earnedMap[child.id] =
          await repository.totalEarnedOre(childId: child.id);
      weekEarnedMap[child.id] =
          await repository.earnedThisWeekOre(childId: child.id);
      weekCountMap[child.id] =
          await repository.completedCountThisWeek(childId: child.id);
    }
    currentBalanceOreByChild = balanceMap;
    totalEarnedOreByChild = earnedMap;
    earnedThisWeekOreByChild = weekEarnedMap;
    completedCountThisWeekByChild = weekCountMap;

    final avail = <String, TaskAvailability>{};
    final resolved = <String, List<String>>{};
    for (final task in tasksForAvailability) {
      final resolvedChildIds = await repository.resolvedChildIdsForTask(task);
      resolved[task.id] = resolvedChildIds;
      for (final childId in resolvedChildIds) {
        final forTaskAndChild = completions
            .where((c) => c.taskId == task.id && c.childId == childId)
            .toList();
        avail['${task.id}::$childId'] =
            computeAvailability(task, forTaskAndChild);
      }
    }
    _availability = avail;
    _resolvedChildIds = resolved;

    // The order the repository already delivers (created_at ASC, oldest task
    // first) is used as the tiebreak in the sorting - store each task's
    // original place BEFORE re-sorting, so the tiebreak is unambiguous and
    // independent of the order in which the sorting itself visits the tasks
    // (see _sortByUrgency).
    final originalIndex = <String, int>{
      for (var i = 0; i < activeTasks.length; i++) activeTasks[i].id: i,
    };
    tasks = [
      ..._sortByUrgency(mandatoryTasks, originalIndex),
      ..._sortByUrgency(optionalTasks, originalIndex),
    ];

    await _recomputeFollowUps();

    notifyListeners();
  }

  // ---- Parent mode -------------------------------------------------------

  /// Checks the family's parent PIN (set in Home Assistant).
  bool verifyPin(String pin) {
    final hash = settings.pinHash;
    final salt = settings.pinSalt;
    if (hash == null || salt == null) return false;
    return CryptoService.verifyPin(pin, salt, hash);
  }

  void enterParentMode() {
    // A child's tablet has no parent mode - not even if a future UI bug were
    // to try to open it.
    if (isChildTablet) return;
    parentModeUnlocked = true;
    notifyListeners();
  }

  void exitParentMode() {
    parentModeUnlocked = false;
    notifyListeners();
  }

  // ---- Actions (tasks / completions) ---------------------------------------
  //
  // All writes follow the same pattern: apply locally right away (so the UI
  // feels fast and works briefly offline), and then send the action to Home
  // Assistant, whose response replaces the local copy.

  Future<void> _applyLocallyAndSync(Map<String, dynamic> action) async {
    await repository.applyAction(action);
    await refreshFromLocal();

    if (isConnected) {
      await _pushAction(action);
    }
  }

  Future<Task> createTask({
    required String title,
    String? description,
    required int amountOre,
    required Recurrence recurrence,
    bool mandatory = false,
    List<int>? activeWeekdays,
    List<String>? assignedChildIds,
    String? startTime,
    String? dueTime,
    bool showInCalendar = false,
  }) async {
    final task = await repository.createTask(
      title: title,
      description: description,
      amountOre: amountOre,
      recurrence: recurrence,
      mandatory: mandatory,
      activeWeekdays: activeWeekdays,
      assignedChildIds: assignedChildIds,
      startTime: startTime,
      dueTime: dueTime,
      showInCalendar: showInCalendar,
    );
    await refreshFromLocal();
    if (isConnected) {
      await _pushAction({
        'type': 'create_task',
        'payload': {...task.toJson(), 'id': task.id},
      });
    }
    return task;
  }

  Future<void> editTask(
    String id, {
    required String title,
    String? description,
    required int amountOre,
    required Recurrence recurrence,
    bool mandatory = false,
    List<int>? activeWeekdays,
    List<String>? assignedChildIds,
    String? startTime,
    String? dueTime,
    bool showInCalendar = false,
  }) {
    return _applyLocallyAndSync({
      'type': 'update_task',
      'payload': {
        'id': id,
        'title': title,
        'description': description,
        'amountOre': amountOre,
        'recurrence': recurrence.value,
        'mandatory': mandatory,
        // 'null' explicitly means "every day"/"all children" - see
        // TaskRepository.applyAction/editTask, which treats a missing value
        // here as "keep existing", not a full reset.
        'activeWeekdays': recurrence == Recurrence.once ? null : activeWeekdays,
        'assignedChildIds': assignedChildIds,
        // Explicit null = "no time" (reset), the same pattern as above.
        'startTime': startTime,
        'dueTime': dueTime,
        'showInCalendar': showInCalendar,
      },
    });
  }

  /// A parent lifts the child's restriction for the rest of today.
  Future<void> suspendRestriction(String childId) {
    return _applyLocallyAndSync({
      'type': 'suspend_restriction',
      'payload': {'childId': childId},
    });
  }

  /// Changes one family setting (see [FamilySettings.keys]). Throws
  /// [RepositoryException] for an invalid value.
  Future<void> setFamilySetting(String key, Object value) {
    return _applyLocallyAndSync({
      'type': 'set_setting',
      'payload': {'key': key, 'value': value},
    });
  }

  Future<void> deleteTask(String id) {
    return _applyLocallyAndSync({
      'type': 'delete_task',
      'payload': {'id': id},
    });
  }

  Future<void> completeTask(Task task, {required String childId}) {
    return _applyLocallyAndSync({
      'type': 'complete_task',
      'payload': {
        'taskId': task.id,
        'childId': childId,
        'completionId': null,
        'completedAt': DateTime.now().toIso8601String(),
      },
    });
  }

  Future<void> approveCompletion(String completionId) {
    return _applyLocallyAndSync({
      'type': 'approve_completion',
      'payload': {
        'completionId': completionId,
        'approvedAt': DateTime.now().toIso8601String(),
      },
    });
  }

  Future<void> rejectCompletion(String completionId) {
    return _applyLocallyAndSync({
      'type': 'reject_completion',
      'payload': {'completionId': completionId},
    });
  }

  Future<void> markPaidOut({required String childId}) {
    return _applyLocallyAndSync({
      'type': 'mark_paid_out',
      'payload': {'childId': childId},
    });
  }

  /// Adds a manual, signed (+/-) balance adjustment for one child, with a
  /// mandatory reason. Throws [RepositoryException] (from the repository) if
  /// the note is empty.
  Future<void> adjustBalance({
    required int amountOre,
    required String note,
    required String childId,
  }) {
    return _applyLocallyAndSync({
      'type': 'adjust_balance',
      'payload': {
        'id': const Uuid().v4(),
        'amountOre': amountOre,
        'note': note,
        'childId': childId,
        'createdAt': DateTime.now().toIso8601String(),
      },
    });
  }

  // ---- Actions (children) --------------------------------------------------

  Future<void> addChild(String name) {
    return _applyLocallyAndSync({
      'type': 'add_child',
      'payload': {'id': const Uuid().v4(), 'name': name},
    });
  }

  Future<void> renameChild(String id, String newName) {
    return _applyLocallyAndSync({
      'type': 'rename_child',
      'payload': {'id': id, 'name': newName},
    });
  }

  Future<void> deleteChild(String id) {
    return _applyLocallyAndSync({
      'type': 'delete_child',
      'payload': {'id': id},
    });
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
    await settings.setOfflineQueueRaw(const []);
    connectionMessage = null;
    notifyListeners();
    await syncNow();
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
    parentModeUnlocked = false;
    notifyListeners();
  }

  /// Fetches fresh data from HA and sends any actions from the offline queue.
  /// Called every 30 seconds, when the app opens and on "pull to refresh".
  Future<void> syncNow() async {
    final current = connection;
    if (current == null) {
      syncStatus = SyncStatus.unknown;
      syncMessage = l10n.notConnectedYet;
      notifyListeners();
      return;
    }

    syncStatus = SyncStatus.syncing;
    notifyListeners();

    await _flushOfflineQueue(current);
    await _handleResult(await _client.fetchState(current));
  }

  Future<void> _pushAction(Map<String, dynamic> action) async {
    final current = connection;
    if (current == null) return;
    final result = await _client.sendAction(current, action);
    if (!result.success && !result.unauthorized) {
      if (result.offline) {
        await _enqueueOffline(action);
      } else {
        // HA rejected the action (e.g. already approved by the other parent):
        // fetch the real state and show the error.
        await syncNow();
        throw RepositoryException(result.errorMessage!);
      }
    }
    await _handleResult(result);
  }

  Future<void> _handleResult(HaResult result) async {
    if (result.unauthorized) {
      await disconnect(message: l10n.deviceRemoved);
      return;
    }
    if (result.success && result.state != null) {
      await _applyState(result.state!);
      syncStatus = SyncStatus.connected;
      syncMessage = null;
      lastSyncAt = DateTime.now();
    } else {
      syncStatus = SyncStatus.offline;
      syncMessage = result.errorMessage ?? l10n.noConnectionRetryLater;
    }
    notifyListeners();
  }

  Future<void> _applyState(Map<String, dynamic> state) async {
    await repository.replaceAllFromState(state);
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
    await _checkForUpdate(AppUpdate.fromJson(state['appUpdate']));
    await refreshFromLocal();
  }

  Future<void> _enqueueOffline(Map<String, dynamic> action) async {
    final queue = List<String>.from(settings.offlineQueueRaw);
    queue.add(jsonEncode(action));
    await settings.setOfflineQueueRaw(queue);
  }

  Future<void> _flushOfflineQueue(HaConnection current) async {
    final queue = List<String>.from(settings.offlineQueueRaw);
    if (queue.isEmpty) return;

    final remaining = <String>[];
    for (var i = 0; i < queue.length; i++) {
      final action = jsonDecode(queue[i]) as Map<String, dynamic>;
      final result = await _client.sendAction(current, action);
      if (result.offline) {
        // Still no connection: keep this one and the rest, in order.
        remaining.addAll(queue.skip(i));
        break;
      }
      // Rejected by HA (e.g. already handled): the action is dropped - HA's
      // state is fetched right after and shows the right thing.
    }
    await settings.setOfflineQueueRaw(remaining);
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
    _linkSubscription?.cancel();
    _installFailureSubscription?.cancel();
    super.dispose();
  }
}
