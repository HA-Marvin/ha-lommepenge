import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

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

/// Sync-status som vises diskret i UI'et (fx som et lille ikon/tekst).
enum SyncStatus { ukendt, forbundet, offline, synkroniserer }

/// En nyere version af appen, som Home Assistant har klar.
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

/// Central app-tilstand. Holder UI'et bevidst simpelt: én
/// [ChangeNotifier] der samler indstillinger, den lokale kopi af familiens
/// data (via [TaskRepository]) og forbindelsen til Home Assistant.
///
/// Home Assistant er "sandheden": alle enheder - den fælles skærm,
/// forældrenes telefoner og børnenes tablets - henter familiens data derfra
/// og sender deres handlinger dertil. Handlinger udføres også lokalt med det
/// samme, så appen føles hurtig og virker kortvarigt uden forbindelse.
class AppState extends ChangeNotifier {
  final SettingsService settings;
  final TaskRepository repository;
  final HaClient _client;
  final NativeBridge _native;

  /// Henter nyt fra HA og genberegner opfølgning (frister passerer jo uden
  /// at data ændrer sig).
  Timer? _syncTimer;
  static const _syncInterval = Duration(seconds: 30);
  StreamSubscription<String>? _linkSubscription;
  StreamSubscription<String>? _installFailureSubscription;

  /// Opfølgnings-status pr. barn: forsinkede opgaver, spærring, næste frist.
  Map<String, ChildFollowUp> followUps = {};

  ChildFollowUp? followUpFor(String childId) => followUps[childId];

  FamilySettings get familySettings => settings.familySettings;

  AppState({
    required this.settings,
    required this.repository,
    HaClient? client,
    NativeBridge? native,
  })  : _client = client ?? HaClient(),
        _native = native ?? NativeBridge();

  bool parentModeUnlocked = false;

  List<Task> tasks = [];
  List<Completion> completions = [];
  List<BalanceAdjustment> balanceAdjustments = [];
  List<Child> children = [];

  /// Saldo/optjening m.m. er pr. barn - se [currentBalanceOreFor] m.fl.
  Map<String, int> currentBalanceOreByChild = {};
  Map<String, int> totalEarnedOreByChild = {};
  Map<String, int> earnedThisWeekOreByChild = {};
  Map<String, int> completedCountThisWeekByChild = {};

  SyncStatus syncStatus = SyncStatus.ukendt;
  String? syncMessage;
  DateTime? lastSyncAt;

  /// Besked på forbind-skærmen, fx når enheden er fjernet i HA.
  String? connectionMessage;

  /// Appens egen version (fra Android).
  String appVersion = '';
  int appVersionCode = 0;

  /// Nyere version fra Home Assistant, hvis der er en.
  AppUpdate? availableUpdate;

  /// Mens en opdatering hentes: 0.0-1.0, ellers `null`.
  double? updateProgress;
  String? updateMessage;

  DeviceRole? get role => settings.role;
  bool get hasPin => settings.hasPin;
  bool get isScreen => role == DeviceRole.screen;
  bool get isPhone => role == DeviceRole.phone;
  bool get isChildTablet => role == DeviceRole.childTablet;

  /// Om enheden er forbundet til Home Assistant (og dermed har en rolle).
  bool get isConnected => settings.connection != null && role != null;

  HaConnection? get connection => settings.connection;

  /// Barne-tablet: det barn tabletten er bundet til.
  String? get boundChildId => settings.boundChildId;
  Child? get boundChild =>
      boundChildId == null ? null : childrenById[boundChildId];

  /// Hurtigt opslag barn-id -> [Child], til navnevisning i UI'et.
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

  /// Tilgængelighed af [task] for ét bestemt barn - se
  /// `TaskRepository.availabilityFor`.
  TaskAvailability availabilityOf(Task task, String childId) =>
      _availability['${task.id}::$childId'] ?? TaskAvailability.available;

  /// Hvilke børns id'er [task] reelt er tildelt lige nu (dynamisk
  /// opslag af "alle børn") - se `TaskRepository.resolvedChildIdsForTask`.
  List<String> resolvedChildIdsFor(Task task) =>
      _resolvedChildIds[task.id] ?? const [];

  DateTime? nextAvailableFor(Task task, String childId) {
    final forTaskAndChild = completions
        .where((c) => c.taskId == task.id && c.childId == childId)
        .toList();
    return nextAvailableDate(task, forTaskAndChild);
  }

  // ---- Sortering af opgavelisten ("hvad skal gøres nu?") -------------------
  //
  // Reglen (bekræftet med brugeren 30. aug. 2026, se samtalen der indførte
  // denne sortering hvis en fremtidig session har brug for baggrunden):
  // den yderste sortering (obligatorisk før valgfri) rører vi ikke ved -
  // den sker stadig i refreshFromLocal. INDEN i hver af de to grupper
  // sorteres opgaverne efter hvor "presserende" de er lige nu, beregnet ud
  // fra opgavens REELT tildelte børn (resolvedChildIdsFor) - se
  // _taskSortTuple og _childSortTuple nedenfor for selve reglen.

  /// Sorterer [tasksToSort] efter "hvad skal der ske nu"-reglen (se
  /// [_taskSortTuple]), og bruger [originalIndex] - opgavens plads i den
  /// oprindelige, created_at-sorterede liste fra repository - som
  /// uafgjort-tiebreak.
  ///
  /// Dart's `List.sort` er IKKE garanteret stabil, så tiebreaket skal
  /// være eksplicit i sammenligningsfunktionen for at to opgaver med
  /// nøjagtig samme (tier, dayOffset) ikke "flimrer" indbyrdes mellem to
  /// opdateringer af listen.
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

  /// Beregner [task]s sorterings-nøgle som et (tier, dayOffset)-par, ud
  /// fra dens REELT tildelte børn ([resolvedChildIdsFor]) - se
  /// [_childSortTuple] for hvordan hvert enkelt barns tuple beregnes.
  ///
  /// Opgavens samlede tuple er det BEDSTE (mindste) af alle tildelte
  /// børns tuples, sammenlignet først på tier (0 < 1 < 2), derefter på
  /// dayOffset: så længe bare ÉT tildelt barn stadig kan/skal udføre
  /// opgaven i dag, skal opgaven blive i toppen af listen - den falder
  /// først længere ned når ALLE tildelte børn er i samme eller ringere
  /// tilstand.
  ///
  /// Edge case: hvis opgaven ikke reelt er tildelt nogen (længere
  /// eksisterende) børn - fx alle tildelte børn er slettet siden -
  /// bruges (1, 0) som fallback: samme "plads" som "kan aldrig blive
  /// tilgængelig igen", så opgaven havner et fornuftigt sted i stedet
  /// for øverst, og sorteringen ikke crasher på et tomt børne-tuple-sæt.
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

  /// Beregner ét tildelt barns (tier, dayOffset)-tuple for [task]. Jo
  /// mindre tuple (tier sammenlignet først, så dayOffset), jo mere
  /// presserende/relevant er opgaven for dette barn lige nu:
  ///
  /// - tier 0: opgaven er reelt uberørt og klar til at blive udført i
  ///   dag (topgruppen) - dayOffset altid 0.
  /// - tier 1: opgaven kan ALDRIG blive tilgængelig igen for dette barn
  ///   (fx en engangsopgave der allerede er godkendt, eller en umulig
  ///   ugeplan hvor ingen ugedag er valgt) - mellemgruppen, dayOffset
  ///   altid 0.
  /// - tier 2: opgaven er enten allerede rørt/afventer godkendelse i dag
  ///   (dayOffset 0), eller først tilgængelig igen en kommende dag
  ///   (dayOffset = antal kalenderdage fra i dag og frem til den dato).
  ///
  /// Særtilfælde (den eneste undtagelse fra at bruge [availabilityOf]
  /// direkte): en opgave med status [TaskAvailability.available] tæller
  /// ALLIGEVEL som "allerede udført i dag" (tier 2, dayOffset 0) hvis der
  /// findes en GODKENDT completion for netop dette (opgave, barn)-par
  /// med completedAt på dags dato. Dette sker i praksis kun for
  /// [Recurrence.unlimited]-opgaver, som bevidst ikke har nogen
  /// dags-nedkøling i [computeAvailability] (de er "altid tilgængelige")
  /// - uden dette tjek ville en unlimited-opgave, barnet allerede har
  /// lavet 5 gange i dag, forblive øverst i listen resten af dagen.
  /// Tjekket er bevidst skrevet generisk (kigger på completions-listen,
  /// ikke på task.recurrence), så det ikke skal opdateres hvis en
  /// fremtidig recurrence-type får samme egenskab.
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

    // doneToday / doneThisWeek / notScheduledToday / completedOnce: find
    // næste dato hvor opgaven bliver tilgængelig igen for dette barn.
    final next = nextAvailableFor(task, childId);
    if (next == null) {
      // Kan aldrig blive tilgængelig igen (fx completedOnce, eller en
      // ugeplan uden nogen aktive ugedage).
      return (1, 0);
    }
    final dayOffset = _calendarDateOnly(next)
        .difference(_calendarDateOnly(DateTime.now()))
        .inDays;
    return (2, dayOffset);
  }

  /// Sammenligner to [DateTime] på kalenderdag-niveau (år/måned/dag),
  /// uden hensyn til klokkeslæt.
  bool _isSameCalendarDate(DateTime a, DateTime b) =>
      _calendarDateOnly(a) == _calendarDateOnly(b);

  /// Dato uden klokkeslæt - samme mønster som den private `_dateOnly` i
  /// `logic/recurrence.dart` (duplikeret her da den ikke eksporteres).
  DateTime _calendarDateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  // ---- Opstart -------------------------------------------------------------

  Future<void> initialize() async {
    // Engangs-migration af det gamle globale udbetalt-beløb til det ene
    // barn - se doc på metoden. Skal ske FØR refreshFromLocal begynder
    // at læse per-barn-saldi.
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
      updateMessage = message;
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
      // En fejlet baggrundsopdatering må aldrig vælte appen - næste tick
      // prøver igen.
    }
  }

  Future<void> _recomputeFollowUps() async {
    followUps = await repository.followUpForAll();
  }

  Future<void> refreshFromLocal() async {
    final activeTasks = await repository.getActiveTasks();
    // Obligatoriske opgaver vises altid først, så de ikke drukner blandt
    // valgfri opgaver - dette er det yderste sorteringsniveau og røres
    // ikke af den nye "hvad skal gøres nu"-sortering inden i hver gruppe
    // (se _sortByUrgency nedenfor).
    // Disse to midlertidige lister bruges lige om lidt til at beregne
    // _availability/_resolvedChildIds (som før), FØR de sorteres endeligt
    // og samles til `tasks`.
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

    // Den rækkefølge repository allerede leverer (created_at ASC, ældste
    // opgave først) bruges som uafgjort-tiebreak i den nye sortering - gem
    // hver opgaves oprindelige plads FØR omsorteringen, så tiebreaket er
    // entydigt og uafhængigt af hvilken rækkefølge sorteringen selv
    // besøger opgaverne i (se _sortByUrgency).
    final originalIndex = <String, int>{
      for (var i = 0; i < activeTasks.length; i++) activeTasks[i].id: i,
    };
    tasks = [
      ..._sortByUrgency(mandatoryTasks, originalIndex),
      ..._sortByUrgency(optionalTasks, originalIndex),
    ];

    await _recomputeFollowUps();

    notifyListeners();

    notifyListeners();
  }

  // ---- Forælder-tilstand -------------------------------------------------

  /// Tjekker familiens forælder-PIN (sat i Home Assistant).
  bool verifyPin(String pin) {
    final hash = settings.pinHash;
    final salt = settings.pinSalt;
    if (hash == null || salt == null) return false;
    return CryptoService.verifyPin(pin, salt, hash);
  }

  void enterParentMode() {
    // En barne-tablet har ingen forælder-tilstand - heller ikke hvis en
    // fremtidig UI-fejl skulle forsøge at åbne den.
    if (isChildTablet) return;
    parentModeUnlocked = true;
    notifyListeners();
  }

  void exitParentMode() {
    parentModeUnlocked = false;
    notifyListeners();
  }

  // ---- Handlinger (opgaver / completions) -------------------------------
  //
  // Alle skrivninger går igennem samme mønster: anvend lokalt med det
  // samme (så UI'et føles hurtigt og virker kortvarigt offline), og send
  // derefter handlingen til Home Assistant, hvis svar erstatter den lokale
  // kopi.

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
        // 'null' betyder eksplicit "alle dage"/"alle børn" - jf.
        // TaskRepository.applyAction/editTask, der behandler en
        // manglende værdi her som en fuld nulstilling, ikke "behold
        // eksisterende".
        'activeWeekdays': recurrence == Recurrence.once ? null : activeWeekdays,
        'assignedChildIds': assignedChildIds,
        // Eksplicit null = "ingen tid" (nulstil), samme mønster som ovenfor.
        'startTime': startTime,
        'dueTime': dueTime,
        'showInCalendar': showInCalendar,
      },
    });
  }

  /// Forælder ophæver barnets spærring for resten af i dag.
  Future<void> suspendRestriction(String childId) {
    return _applyLocallyAndSync({
      'type': 'suspend_restriction',
      'payload': {'childId': childId},
    });
  }

  /// Ændrer én familie-indstilling (se [FamilySettings.keys]). Kaster
  /// [RepositoryException] ved ugyldig værdi.
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

  /// Tilføjer en manuel, signeret (+/-) saldo-justering for ét barn, med
  /// en obligatorisk begrundelse. Kaster [RepositoryException] (fra
  /// repositoriet) hvis noten er tom.
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

  // ---- Handlinger (børn) --------------------------------------------------

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

  // ---- Forbindelse til Home Assistant ------------------------------------

  /// Forbinder enheden med et link fra "Tilføj enhed" i Home Assistant
  /// (QR-koden eller "Åbn appen og forbind"). Rollen bestemmes af HA.
  /// Returnerer en fejlbesked, eller `null` ved succes.
  Future<String?> connectWithLink(String text) async {
    final link = parseConnectLink(text);
    if (link == null) {
      return _connectionFailed(
        'Det er ikke et Lommepenge-link fra Home Assistant.',
      );
    }
    return _connect(link);
  }

  /// Forbinder med HA's adresse og koden fra "Tilføj enhed" - til enheder
  /// uden kamera.
  Future<String?> connectWithCode(String address, String code) async {
    final link = connectLinkFromCode(address, code);
    if (link == null) {
      return _connectionFailed('Skriv Home Assistants adresse og koden.');
    }
    return _connect(link);
  }

  /// Home Assistant på hjemmenettet, til at udfylde adressen.
  Future<List<({String name, String url})>> discoverHa() => _native.discoverHa();

  Future<String?> _connect(ConnectLink link) async {
    if (isChildTablet && isConnected) {
      // En barne-tablet kan ikke skiftes til en anden rolle ved at scanne en
      // ny kode - kun ved geninstallation.
      return _connectionFailed(
        'Denne tablet er allerede forbundet. Geninstallér appen for at '
        'forbinde den igen.',
      );
    }
    final result = await _client.pair(link);
    if (!result.success) return _connectionFailed(result.errorMessage!);
    final role = DeviceRole.fromHa(result.role);
    if (role == null || result.deviceId == null || result.deviceKey == null) {
      return _connectionFailed('Uventet svar fra Home Assistant.');
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

  /// Glemmer forbindelsen på denne enhed (enheden skal også fjernes under
  /// "Enheder" i Home Assistant).
  Future<void> disconnect({String? message}) async {
    await settings.clearConnection();
    connectionMessage = message;
    syncStatus = SyncStatus.ukendt;
    syncMessage = null;
    availableUpdate = null;
    parentModeUnlocked = false;
    notifyListeners();
  }

  /// Henter frisk data fra HA og sender evt. handlinger fra offline-køen.
  /// Kaldes hvert 30. sekund, ved app-åbning og ved "træk-for-at-opdatere".
  Future<void> syncNow() async {
    final current = connection;
    if (current == null) {
      syncStatus = SyncStatus.ukendt;
      syncMessage = 'Ikke forbundet til Home Assistant endnu.';
      notifyListeners();
      return;
    }

    syncStatus = SyncStatus.synkroniserer;
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
        // HA afviste handlingen (fx allerede godkendt af den anden
        // forælder): hent den rigtige tilstand og vis fejlen.
        await syncNow();
        throw RepositoryException(result.errorMessage!);
      }
    }
    await _handleResult(result);
  }

  Future<void> _handleResult(HaResult result) async {
    if (result.unauthorized) {
      await disconnect(
        message: 'Enheden er fjernet i Home Assistant. Forbind den igen med '
            'en ny QR-kode fra Home Assistant (Lommepenge → Tilføj enhed).',
      );
      return;
    }
    if (result.success && result.state != null) {
      await _applyState(result.state!);
      syncStatus = SyncStatus.forbundet;
      syncMessage = null;
      lastSyncAt = DateTime.now();
    } else {
      syncStatus = SyncStatus.offline;
      syncMessage = result.errorMessage ??
          'Ingen forbindelse til Home Assistant. Prøver igen senere.';
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
        // Stadig ingen forbindelse: behold denne og resten i rækkefølge.
        remaining.addAll(queue.skip(i));
        break;
      }
      // Afvist af HA (fx allerede behandlet): handlingen droppes - HA's
      // tilstand hentes lige efter og viser det rigtige.
    }
    await settings.setOfflineQueueRaw(remaining);
  }

  // ---- Opdatering af appen fra Home Assistant -----------------------------

  Future<void> _checkForUpdate(AppUpdate? update) async {
    final newer = update != null &&
        appVersionCode > 0 &&
        update.versionCode > appVersionCode;
    availableUpdate = newer ? update : null;
    if (newer && settings.notifiedUpdateCode < update.versionCode) {
      await settings.setNotifiedUpdateCode(update.versionCode);
      await _native.notify(
        'Ny version af Lommepenge',
        'Version ${update.version} er klar. Åbn appen for at opdatere.',
      );
    }
  }

  /// Henter den nye version fra HA, tjekker den og beder Android installere.
  Future<void> installUpdate() async {
    final update = availableUpdate;
    final current = connection;
    if (update == null || current == null || updateProgress != null) return;

    if (!await _native.canInstall()) {
      updateMessage = 'Tillad "Installér ukendte apps" for Lommepenge, og '
          'tryk Opdater igen.';
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
      updateMessage = 'Den hentede fil var beskadiget. Prøv igen.';
      notifyListeners();
      return;
    }
    try {
      await _native.installApk(file.path);
      updateMessage = 'Installerer version ${update.version}...';
    } catch (e) {
      updateMessage = 'Kunne ikke installere: $e';
    }
    updateProgress = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _linkSubscription?.cancel();
    _installFailureSubscription?.cancel();
    super.dispose();
  }
}
