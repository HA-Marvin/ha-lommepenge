import 'package:uuid/uuid.dart';

import '../db/database_helper.dart';
import '../logic/follow_up.dart';
import '../logic/recurrence.dart';
import '../models/balance_adjustment.dart';
import '../models/child.dart';
import '../models/completion.dart';
import '../models/family_settings.dart';
import '../models/task.dart';
import '../services/settings_service.dart';

/// Kastes når en handling ikke er gyldig i den nuværende tilstand, fx
/// at markere en opgave udført mens den allerede venter på godkendelse.
class RepositoryException implements Exception {
  final String message;
  RepositoryException(this.message);
  @override
  String toString() => message;
}

/// Samler al forretningslogik for opgaver/completions/saldo/børn ét
/// sted, så både UI'et og sync-laget (server og klient) bruger præcis
/// den samme logik og dermed ikke kan komme ud af trit med hinanden.
///
/// På skærm-enheden ER denne repository's database "sandheden". På
/// telefonen er den en lokal cache, der bliver overskrevet af
/// [replaceAllFromState] hver gang der er kontakt til skærmen.
class TaskRepository {
  final DatabaseHelper _db;
  final SettingsService settings;
  final Uuid _uuid = const Uuid();

  TaskRepository({
    DatabaseHelper? databaseHelper,
    required this.settings,
  }) : _db = databaseHelper ?? DatabaseHelper.instance;

  // ---- Læsning -----------------------------------------------------------

  Future<List<Task>> getActiveTasks() => _db.getAllTasks(onlyActive: true);
  Future<List<Task>> getAllTasks() => _db.getAllTasks();
  Future<List<Completion>> getAllCompletions() => _db.getAllCompletions();
  Future<List<BalanceAdjustment>> getAllBalanceAdjustments() =>
      _db.getAllBalanceAdjustments();

  Future<List<Completion>> getPendingCompletions() async {
    final all = await _db.getAllCompletions();
    return all.where((c) => c.status == CompletionStatus.pending).toList();
  }

  Future<List<Completion>> getApprovedCompletions() async {
    final all = await _db.getAllCompletions();
    return all.where((c) => c.status == CompletionStatus.approved).toList()
      ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
  }

  /// Opgavens tilgængelighed for ét bestemt barn. Kun completions for
  /// DETTE barn tælles med - ved en opgave delt mellem flere børn må
  /// barn A's udførelse/godkendelse ikke blokere barn B's egen,
  /// uafhængige udførelse af samme opgave.
  Future<TaskAvailability> availabilityFor(Task task, String childId) async {
    final completions = await _db.getCompletionsForTask(task.id);
    final forChild = completions.where((c) => c.childId == childId).toList();
    return computeAvailability(task, forChild);
  }

  // ---- Børn ----------------------------------------------------------------

  Future<List<Child>> getAllChildren() => _db.getAllChildren();

  /// Opretter et nyt barn. [id] kan angives eksplicit (bruges af
  /// [applyAction], så samme id genbruges på tværs af skærm/telefon -
  /// samme mønster som `create_task`).
  Future<Child> addChild(String name, {String? id}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw RepositoryException('Barnets navn må ikke være tomt.');
    }
    final existing = await _db.getAllChildren();
    final child = Child(
      id: id ?? _uuid.v4(),
      name: trimmed,
      sortOrder: existing.length,
      createdAt: DateTime.now(),
    );
    await _db.insertChild(child);
    return child;
  }

  Future<void> renameChild(String id, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) {
      throw RepositoryException('Barnets navn må ikke være tomt.');
    }
    final children = await _db.getAllChildren();
    final matches = children.where((c) => c.id == id);
    if (matches.isEmpty) {
      throw RepositoryException('Barnet findes ikke længere.');
    }
    await _db.updateChild(matches.first.copyWith(name: trimmed));
  }

  /// Sletter et barn. Det sidste barn kan også slettes - familien kan
  /// godt stå uden børn, indtil forældrene opretter nye.
  Future<void> deleteChild(String id) async {
    final children = await _db.getAllChildren();
    if (!children.any((c) => c.id == id)) {
      throw RepositoryException('Barnet findes ikke længere.');
    }
    await _db.deleteChild(id);
  }

  /// Hvilke børns id'er en opgave reelt gælder for lige nu.
  /// `null`/tom [Task.assignedChildIds] betyder "alle børn" - løses her
  /// DYNAMISK op mod familiens aktuelle børneliste, så et barn tilføjet
  /// EFTER opgaven blev oprettet automatisk er inkluderet. Eksplicit
  /// angivne id'er filtreres til kun dem der stadig findes (et barn kan
  /// være slettet siden opgaven blev tildelt) - døde id'er smides stille
  /// væk i stedet for at crashe.
  Future<List<String>> resolvedChildIdsForTask(Task task) async {
    final children = await _db.getAllChildren();
    final assigned = task.assignedChildIds;
    if (assigned == null || assigned.isEmpty) {
      return children.map((c) => c.id).toList();
    }
    final existingIds = children.map((c) => c.id).toSet();
    return assigned.where(existingIds.contains).toList();
  }

  // ---- Saldo (pr. barn) -----------------------------------------------------

  /// Sum af alle godkendte completions nogensinde (øre) for ét barn.
  Future<int> totalEarnedOre({required String childId}) async {
    final approved = await getApprovedCompletions();
    return approved
        .where((c) => c.childId == childId)
        .fold<int>(0, (sum, c) => sum + c.amountAtCompletionOre);
  }

  /// Sum af alle manuelle saldo-justeringer nogensinde (øre, kan være
  /// negativ) for ét barn.
  Future<int> totalAdjustmentsOre({required String childId}) async {
    final adjustments = await getAllBalanceAdjustments();
    return adjustments
        .where((a) => a.childId == childId)
        .fold<int>(0, (sum, a) => sum + a.amountOre);
  }

  /// Nuværende optjent, ikke-udbetalt saldo (øre) for ét barn, inkl.
  /// manuelle justeringer.
  Future<int> currentBalanceOre({required String childId}) async {
    final earned = await totalEarnedOre(childId: childId);
    final paidOut = settings.paidOutOreFor(childId);
    final adjustments = await totalAdjustmentsOre(childId: childId);
    final balance = earned - paidOut + adjustments;
    return balance < 0 ? 0 : balance;
  }

  /// Sum af godkendte completions de sidste 7 dage (øre) for ét barn.
  Future<int> earnedThisWeekOre({
    required String childId,
    DateTime? now,
  }) async {
    final today = now ?? DateTime.now();
    final cutoff = today.subtract(const Duration(days: 7));
    final approved = await getApprovedCompletions();
    return approved
        .where((c) => c.childId == childId && c.completedAt.isAfter(cutoff))
        .fold<int>(0, (sum, c) => sum + c.amountAtCompletionOre);
  }

  /// Antal opgaver godkendt de sidste 7 dage for ét barn - bruges til den
  /// simple fremskridtsvisning i barne-tilstand.
  Future<int> completedCountThisWeek({
    required String childId,
    DateTime? now,
  }) async {
    final today = now ?? DateTime.now();
    final cutoff = today.subtract(const Duration(days: 7));
    final approved = await getApprovedCompletions();
    return approved
        .where((c) => c.childId == childId && c.completedAt.isAfter(cutoff))
        .length;
  }

  /// Opretter og gemmer en manuel saldo-justering for ét barn.
  /// [amountOre] kan være negativ; [note] er en obligatorisk begrundelse.
  Future<BalanceAdjustment> addBalanceAdjustment({
    required int amountOre,
    required String note,
    required String childId,
    String? id,
    DateTime? createdAt,
  }) async {
    if (note.trim().isEmpty) {
      throw RepositoryException('En saldo-justering skal have en note.');
    }
    final adjustment = BalanceAdjustment(
      id: id ?? _uuid.v4(),
      amountOre: amountOre,
      note: note.trim(),
      childId: childId,
      createdAt: createdAt ?? DateTime.now(),
    );
    await _db.insertBalanceAdjustment(adjustment);
    return adjustment;
  }

  // ---- Skrivning (høj-niveau, bruges direkte af UI) -----------------------

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
    final task = Task(
      id: _uuid.v4(),
      title: title,
      description: description,
      amountOre: amountOre,
      recurrence: recurrence,
      createdAt: DateTime.now(),
      active: true,
      mandatory: mandatory,
      activeWeekdays: recurrence == Recurrence.once ? null : activeWeekdays,
      assignedChildIds: assignedChildIds,
      startTime: startTime,
      dueTime: dueTime,
      showInCalendar: showInCalendar,
    );
    await _db.insertTask(task);
    return task;
  }

  Future<void> editTask(
    String id, {
    required String title,
    String? description,
    required int amountOre,
    required Recurrence recurrence,
    bool? mandatory,
    List<int>? activeWeekdays,
    bool clearActiveWeekdays = false,
    List<String>? assignedChildIds,
    bool clearAssignedChildIds = false,
    String? startTime,
    bool clearStartTime = false,
    String? dueTime,
    bool clearDueTime = false,
    bool? showInCalendar,
  }) async {
    final existing = await _db.getTask(id);
    if (existing == null) {
      throw RepositoryException('Opgaven findes ikke længere.');
    }
    final updated = existing.copyWith(
      title: title,
      description: description,
      clearDescription: description == null,
      amountOre: amountOre,
      recurrence: recurrence,
      mandatory: mandatory,
      activeWeekdays: recurrence == Recurrence.once ? null : activeWeekdays,
      // 'Engang' skal altid ende med activeWeekdays == null, uanset hvad
      // der evt. var valgt tidligere, eller hvad kaldet ellers beder om.
      clearActiveWeekdays:
          recurrence == Recurrence.once ? true : clearActiveWeekdays,
      assignedChildIds: assignedChildIds,
      clearAssignedChildIds: clearAssignedChildIds,
      startTime: startTime,
      clearStartTime: clearStartTime,
      dueTime: dueTime,
      clearDueTime: clearDueTime,
      showInCalendar: showInCalendar,
    );
    await _db.updateTask(updated);
  }

  Future<void> deleteTask(String id) => _db.deactivateTask(id);

  /// Barnet markerer en opgave udført. Opretter en 'pending' completion.
  /// Kaster [RepositoryException] hvis opgaven ikke er tilgængelig lige
  /// nu, eller hvis opgaven slet ikke er tildelt dette barn.
  Future<Completion> completeTask(
    String taskId, {
    required String childId,
    String? completionId,
    DateTime? completedAt,
  }) async {
    final task = await _db.getTask(taskId);
    if (task == null || !task.active) {
      throw RepositoryException('Opgaven findes ikke længere.');
    }
    final resolvedChildIds = await resolvedChildIdsForTask(task);
    if (!resolvedChildIds.contains(childId)) {
      throw RepositoryException('Opgaven er ikke tildelt dette barn.');
    }
    final existingForTask = await _db.getCompletionsForTask(taskId);
    // Kun completions for DETTE barn må påvirke tilgængeligheden - se
    // [availabilityFor].
    final existingForChild =
        existingForTask.where((c) => c.childId == childId).toList();
    final availability =
        computeAvailability(task, existingForChild, now: completedAt);
    if (availability != TaskAvailability.available) {
      throw RepositoryException(
        'Opgaven kan ikke markeres udført lige nu.',
      );
    }
    final at = completedAt ?? DateTime.now();
    final completion = Completion(
      id: completionId ?? _uuid.v4(),
      taskId: taskId,
      childId: childId,
      completedAt: at,
      status: CompletionStatus.pending,
      amountAtCompletionOre: task.amountOre,
      late: isLateCompletion(task, settings.familySettings, at),
    );
    await _db.insertCompletion(completion);
    return completion;
  }

  /// Forælder godkender en 'pending' completion - tæller nu med i saldoen.
  Future<void> approveCompletion(String completionId, {DateTime? approvedAt}) async {
    final completion = await _db.getCompletion(completionId);
    if (completion == null) {
      throw RepositoryException('Udførelsen findes ikke.');
    }
    if (completion.status != CompletionStatus.pending) {
      throw RepositoryException('Udførelsen er allerede behandlet.');
    }
    await _db.updateCompletion(
      completion.copyWith(
        status: CompletionStatus.approved,
        approvedAt: approvedAt ?? DateTime.now(),
      ),
    );
  }

  /// Forælder afviser en 'pending' completion - tæller ikke med.
  Future<void> rejectCompletion(String completionId) async {
    final completion = await _db.getCompletion(completionId);
    if (completion == null) {
      throw RepositoryException('Udførelsen findes ikke.');
    }
    if (completion.status != CompletionStatus.pending) {
      throw RepositoryException('Udførelsen er allerede behandlet.');
    }
    await _db.updateCompletion(
      completion.copyWith(status: CompletionStatus.rejected),
    );
  }

  /// Flytter hele det ene barns aktuelle saldo til "udbetalt" og
  /// nulstiller dets optjente (ikke-udbetalte) saldo til 0. Påvirker
  /// ikke de øvrige børns saldi.
  Future<void> markPaidOut({required String childId}) async {
    final earned = await totalEarnedOre(childId: childId);
    final adjustments = await totalAdjustmentsOre(childId: childId);
    await settings.setPaidOutOreFor(childId, earned + adjustments);
  }

  // ---- Opfølgning og indstillinger -----------------------------------------

  /// Opfølgnings-status (forsinket/spærret) for hvert barn på [now].
  Future<Map<String, ChildFollowUp>> followUpForAll({DateTime? now}) async {
    final at = now ?? DateTime.now();
    final tasks = await getActiveTasks();
    final completions = await getAllCompletions();
    final children = await getAllChildren();
    final suspensions = settings.restrictionSuspensions;
    final familySettings = settings.familySettings;
    final result = <String, ChildFollowUp>{};
    for (final child in children) {
      final childTasks = <Task>[];
      for (final task in tasks) {
        if ((await resolvedChildIdsForTask(task)).contains(child.id)) {
          childTasks.add(task);
        }
      }
      result[child.id] = computeFollowUp(
        childId: child.id,
        tasks: childTasks,
        completions: completions.where((c) => c.childId == child.id).toList(),
        settings: familySettings,
        now: at,
        suspendedOn: suspensions[child.id],
      );
    }
    return result;
  }

  /// Forælder ophæver barnets spærring for resten af [day].
  Future<void> suspendRestriction(String childId, {DateTime? day}) async {
    final children = await getAllChildren();
    if (!children.any((c) => c.id == childId)) {
      throw RepositoryException('Barnet findes ikke længere.');
    }
    final suspensions = Map<String, String>.from(
      settings.restrictionSuspensions,
    );
    suspensions[childId] = dateKey(day ?? DateTime.now());
    await settings.setRestrictionSuspensions(suspensions);
  }

  /// Sætter én familie-indstilling (se [FamilySettings.keys]).
  Future<void> setFamilySetting(String key, Object? value) async {
    try {
      await settings.setFamilySettings(
        settings.familySettings.withValue(key, value),
      );
    } on ArgumentError catch (e) {
      throw RepositoryException('${e.message}');
    }
  }

  // ---- Engangs-migration (Feature: flere børn) -----------------------------

  /// Engangs-migration: indtil nu var [SettingsService.totalPaidOutOre]
  /// ét globalt udbetalt-beløb for hele familien (dengang appen kun
  /// understøttede ét barn). Nu er udbetalt-beløb pr. barn (se
  /// [SettingsService.paidOutOreFor]). Denne migration overfører den
  /// gamle globale værdi til det ene barn, PRÆCIS én gang, og kun når
  /// det giver mening: det nye per-barn-kort er stadig helt tomt, den
  /// gamle værdi er > 0, og der findes præcis ét barn (dvs. dette er
  /// reelt en opgradering fra "kun ét barn"-versionen af appen - findes
  /// der allerede flere børn, er der intet entydigt barn at overføre
  /// den gamle værdi til, og migrationen springes over).
  ///
  /// Skal kaldes tidligt i AppState.initialize() - FØR resten af appen
  /// begynder at læse/skrive per-barn-saldi.
  Future<void> migrateLegacyPaidOutIfNeeded() async {
    final legacy = settings.totalPaidOutOre;
    if (legacy <= 0) return;
    if (settings.paidOutOreByChild.isNotEmpty) return;
    final children = await _db.getAllChildren();
    if (children.length != 1) return;
    await settings.setPaidOutOreFor(children.first.id, legacy);
  }

  // ---- Samlet handlings-API (bruges af sync: både server og klient) ------

  /// Anvender én sync-handling på den lokale database. Bruges både
  /// direkte af UI'et (så al skrivning går ét sted igennem) og af
  /// [SyncServer] når skærmen modtager en handling fra telefonen.
  Future<void> applyAction(Map<String, dynamic> action) async {
    final type = action['type'] as String?;
    final payload = (action['payload'] as Map?)?.cast<String, dynamic>() ?? {};

    switch (type) {
      case 'create_task':
        final task = Task(
          id: payload['id'] as String? ?? _uuid.v4(),
          title: payload['title'] as String,
          description: payload['description'] as String?,
          amountOre: payload['amountOre'] as int,
          recurrence: Recurrence.fromValue(payload['recurrence'] as String),
          createdAt: payload['createdAt'] != null
              ? DateTime.parse(payload['createdAt'] as String)
              : DateTime.now(),
          active: true,
          mandatory: payload['mandatory'] as bool? ?? false,
          activeWeekdays:
              (payload['activeWeekdays'] as List?)?.cast<int>(),
          assignedChildIds:
              (payload['assignedChildIds'] as List?)?.cast<String>(),
          startTime: payload['startTime'] as String?,
          dueTime: payload['dueTime'] as String?,
          showInCalendar: payload['showInCalendar'] as bool? ?? false,
        );
        await _db.insertTask(task);
        return;

      case 'update_task':
        // Skelner bevidst mellem "nøglen mangler helt" (en gammel
        // enhed uden denne opdatering, der aldrig har hørt om
        // activeWeekdays/assignedChildIds - behold den eksisterende
        // ugeplan/tildeling uændret, samme bagudkompatible mønster som
        // 'mandatory') og "nøglen er eksplicit sat til null" (en
        // opdateret enhed der aktivt beder om at nulstille til "alle
        // dage"/"alle børn").
        final hasWeekdaysKey = payload.containsKey('activeWeekdays');
        final hasChildIdsKey = payload.containsKey('assignedChildIds');
        final hasStartKey = payload.containsKey('startTime');
        final hasDueKey = payload.containsKey('dueTime');
        await editTask(
          payload['id'] as String,
          title: payload['title'] as String,
          description: payload['description'] as String?,
          amountOre: payload['amountOre'] as int,
          recurrence: Recurrence.fromValue(payload['recurrence'] as String),
          mandatory: payload['mandatory'] as bool?,
          activeWeekdays:
              (payload['activeWeekdays'] as List?)?.cast<int>(),
          clearActiveWeekdays:
              hasWeekdaysKey && payload['activeWeekdays'] == null,
          assignedChildIds:
              (payload['assignedChildIds'] as List?)?.cast<String>(),
          clearAssignedChildIds:
              hasChildIdsKey && payload['assignedChildIds'] == null,
          startTime: payload['startTime'] as String?,
          clearStartTime: hasStartKey && payload['startTime'] == null,
          dueTime: payload['dueTime'] as String?,
          clearDueTime: hasDueKey && payload['dueTime'] == null,
          showInCalendar: payload['showInCalendar'] as bool?,
        );
        return;

      case 'delete_task':
        await deleteTask(payload['id'] as String);
        return;

      case 'complete_task':
        final completeChildId = payload['childId'] as String?;
        if (completeChildId == null || completeChildId.isEmpty) {
          throw RepositoryException(
            'Handlingen mangler oplysning om hvilket barn (childId).',
          );
        }
        await completeTask(
          payload['taskId'] as String,
          childId: completeChildId,
          completionId: payload['completionId'] as String?,
          completedAt: payload['completedAt'] != null
              ? DateTime.parse(payload['completedAt'] as String)
              : null,
        );
        return;

      case 'approve_completion':
        await approveCompletion(
          payload['completionId'] as String,
          approvedAt: payload['approvedAt'] != null
              ? DateTime.parse(payload['approvedAt'] as String)
              : null,
        );
        return;

      case 'reject_completion':
        await rejectCompletion(payload['completionId'] as String);
        return;

      case 'mark_paid_out':
        final payoutChildId = payload['childId'] as String?;
        if (payoutChildId == null || payoutChildId.isEmpty) {
          throw RepositoryException(
            'Handlingen mangler oplysning om hvilket barn (childId).',
          );
        }
        await markPaidOut(childId: payoutChildId);
        return;

      case 'adjust_balance':
        final adjustChildId = payload['childId'] as String?;
        if (adjustChildId == null || adjustChildId.isEmpty) {
          throw RepositoryException(
            'Handlingen mangler oplysning om hvilket barn (childId).',
          );
        }
        await addBalanceAdjustment(
          id: payload['id'] as String?,
          amountOre: payload['amountOre'] as int,
          note: payload['note'] as String,
          childId: adjustChildId,
          createdAt: payload['createdAt'] != null
              ? DateTime.parse(payload['createdAt'] as String)
              : null,
        );
        return;

      case 'add_child':
        final name = payload['name'] as String?;
        if (name == null || name.trim().isEmpty) {
          throw RepositoryException('Handlingen mangler et navn.');
        }
        await addChild(name, id: payload['id'] as String?);
        return;

      case 'rename_child':
        final renameId = payload['id'] as String?;
        final newName = payload['name'] as String?;
        if (renameId == null || newName == null || newName.trim().isEmpty) {
          throw RepositoryException('Handlingen mangler id eller navn.');
        }
        await renameChild(renameId, newName);
        return;

      case 'delete_child':
        final deleteId = payload['id'] as String?;
        if (deleteId == null || deleteId.isEmpty) {
          throw RepositoryException('Handlingen mangler et id.');
        }
        await deleteChild(deleteId);
        return;

      case 'suspend_restriction':
        final suspendChildId = payload['childId'] as String?;
        if (suspendChildId == null || suspendChildId.isEmpty) {
          throw RepositoryException(
            'Handlingen mangler oplysning om hvilket barn (childId).',
          );
        }
        await suspendRestriction(suspendChildId);
        return;

      case 'set_setting':
        final key = payload['key'] as String?;
        if (key == null) {
          throw RepositoryException('Handlingen mangler en indstilling.');
        }
        await setFamilySetting(key, payload['value']);
        return;

      default:
        throw RepositoryException('Ukendt handling: $type');
    }
  }

  // ---- Fuld state (bruges af sync) ----------------------------------------

  /// Bygger den fulde state-dump som skærmen svarer med på GET /state og
  /// efter hver POST /action.
  Future<Map<String, dynamic>> getStateJson() async {
    final tasks = await _db.getAllTasks();
    final completions = await _db.getAllCompletions();
    final adjustments = await _db.getAllBalanceAdjustments();
    final children = await _db.getAllChildren();
    return {
      'deviceName': settings.deviceName,
      'familyName': settings.familyName,
      'children': children.map((c) => c.toJson()).toList(),
      'tasks': tasks.map((t) => t.toJson()).toList(),
      'completions': completions.map((c) => c.toJson()).toList(),
      'balanceAdjustments': adjustments.map((a) => a.toJson()).toList(),
      'totalPaidOutOre': settings.totalPaidOutOre,
      'paidOutOreByChild': settings.paidOutOreByChild,
      'familySettings': settings.familySettings.toJson(),
      'restrictionSuspensions': settings.restrictionSuspensions,
      'updatedAt': DateTime.now().toIso8601String(),
    };
  }

  /// Overskriver hele den lokale database med state modtaget fra skærmen.
  /// Bruges kun på telefonen - en simpel og robust "full replace"-strategi
  /// frem for finkornet konflikthåndtering, jf. MVP-scope.
  Future<void> replaceAllFromState(Map<String, dynamic> state) async {
    final tasksJson = (state['tasks'] as List).cast<Map>();
    final completionsJson = (state['completions'] as List).cast<Map>();

    await _db.clearCompletions();
    await _db.clearTasks();

    // Bagudkompatibelt, samme mønster som 'balanceAdjustments' nedenfor:
    // en gammel enhed uden denne opdatering sender ikke 'children' med i
    // sin state - spring da over og lad de(t) eksisterende barn/børn på
    // denne enhed stå urørt, i stedet for at slette dem uden mulighed
    // for at genskabe dem.
    //
    // Børnene genskabes FØR tasks/completions/balance-justeringer
    // nedenfor, så fremmednøglerne (assignedChildIds/childId) i den data
    // der genindlæses rent faktisk peger på børn der findes.
    if (state['children'] != null) {
      final childrenJson = (state['children'] as List).cast<Map>();
      await _db.clearChildren();
      for (final c in childrenJson) {
        await _db.insertChild(Child.fromJson(c.cast<String, Object?>()));
      }
    }

    for (final t in tasksJson) {
      await _db.insertTask(Task.fromJson(t.cast<String, Object?>()));
    }
    for (final c in completionsJson) {
      await _db.insertCompletion(
        Completion.fromJson(c.cast<String, Object?>()),
      );
    }

    // Bagudkompatibelt: en gammel enhed uden denne opdatering sender
    // ikke 'balanceAdjustments' med i sin state - spring da blot over i
    // stedet for at fejle, og lad de eksisterende justeringer (hvis
    // nogen) stå urørt.
    if (state['balanceAdjustments'] != null) {
      final adjustmentsJson =
          (state['balanceAdjustments'] as List).cast<Map>();
      await _db.clearBalanceAdjustments();
      for (final a in adjustmentsJson) {
        await _db.insertBalanceAdjustment(
          BalanceAdjustment.fromJson(a.cast<String, Object?>()),
        );
      }
    }

    if (state['totalPaidOutOre'] != null) {
      await settings.setTotalPaidOutOre(state['totalPaidOutOre'] as int);
    }

    // Bagudkompatibelt, samme mønster som ovenfor: en gammel enhed
    // sender ikke 'paidOutOreByChild' med endnu.
    if (state['paidOutOreByChild'] != null) {
      final raw = (state['paidOutOreByChild'] as Map).cast<String, dynamic>();
      await settings.setPaidOutOreByChild(
        raw.map((key, value) => MapEntry(key, value as int)),
      );
    }

    // Samme bagudkompatible mønster: en ældre skærm sender ikke disse.
    if (state['familySettings'] != null) {
      await settings.setFamilySettings(FamilySettings.fromJson(
        (state['familySettings'] as Map).cast<String, dynamic>(),
      ));
    }
    if (state['restrictionSuspensions'] != null) {
      await settings.setRestrictionSuspensions(
        (state['restrictionSuspensions'] as Map)
            .map((k, v) => MapEntry(k as String, v as String)),
      );
    }
  }
}
