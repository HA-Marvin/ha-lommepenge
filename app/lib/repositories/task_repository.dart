import 'package:uuid/uuid.dart';

import '../db/database_helper.dart';
import '../l10n/l10n.dart';
import '../logic/follow_up.dart';
import '../logic/recurrence.dart';
import '../models/balance_adjustment.dart';
import '../models/child.dart';
import '../models/completion.dart';
import '../models/family_settings.dart';
import '../models/task.dart';
import '../services/settings_service.dart';

/// Thrown when an action is not valid in the current state, e.g. marking a
/// task as done while it is already waiting for approval. [message] is in
/// the app's language and is shown to the user as it is.
class RepositoryException implements Exception {
  final String message;
  RepositoryException(this.message);
  @override
  String toString() => message;
}

/// Gathers all business logic for tasks/completions/balance/children in one
/// place, so the UI and the sync with Home Assistant use exactly the same
/// logic and cannot get out of step with each other.
///
/// The database is a local copy: actions are applied here right away (so the
/// app feels fast and works briefly offline) and the copy is overwritten by
/// [replaceAllFromState] every time Home Assistant answers. HA's integration
/// has the same rules in `family.py`/`logic.py`.
class TaskRepository {
  final DatabaseHelper _db;
  final SettingsService settings;
  final Uuid _uuid = const Uuid();

  /// The texts for error messages; set by `AppState` when the language changes.
  AppLocalizations l10n = l10nFor(defaultLanguage);

  TaskRepository({
    DatabaseHelper? databaseHelper,
    required this.settings,
  }) : _db = databaseHelper ?? DatabaseHelper.instance;

  // ---- Reading -----------------------------------------------------------

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

  /// The task's availability for one specific child. Only completions for
  /// THIS child count - for a task shared between several children, child A's
  /// completion/approval must not block child B's own, independent
  /// completion of the same task.
  Future<TaskAvailability> availabilityFor(Task task, String childId) async {
    final completions = await _db.getCompletionsForTask(task.id);
    final forChild = completions.where((c) => c.childId == childId).toList();
    return computeAvailability(task, forChild);
  }

  // ---- Children ------------------------------------------------------------

  Future<List<Child>> getAllChildren() => _db.getAllChildren();

  /// Creates a new child. [id] can be given explicitly (used by
  /// [applyAction], so the same id is reused across devices - the same
  /// pattern as `create_task`).
  Future<Child> addChild(String name, {String? id}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw RepositoryException(l10n.errChildNameEmpty);
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
      throw RepositoryException(l10n.errChildNameEmpty);
    }
    final children = await _db.getAllChildren();
    final matches = children.where((c) => c.id == id);
    if (matches.isEmpty) {
      throw RepositoryException(l10n.errChildNotFound);
    }
    await _db.updateChild(matches.first.copyWith(name: trimmed));
  }

  /// Deletes a child. The last child can also be deleted - the family can
  /// be without children until the parents create new ones.
  Future<void> deleteChild(String id) async {
    final children = await _db.getAllChildren();
    if (!children.any((c) => c.id == id)) {
      throw RepositoryException(l10n.errChildNotFound);
    }
    await _db.deleteChild(id);
  }

  /// Which children's ids a task actually applies to right now.
  /// `null`/empty [Task.assignedChildIds] means "all children" - resolved
  /// here DYNAMICALLY against the family's current list of children, so a
  /// child added AFTER the task was created is automatically included.
  /// Explicitly given ids are filtered to only those that still exist (a
  /// child may have been deleted since the task was assigned) - dead ids are
  /// silently dropped instead of crashing.
  Future<List<String>> resolvedChildIdsForTask(Task task) async {
    final children = await _db.getAllChildren();
    final assigned = task.assignedChildIds;
    if (assigned == null || assigned.isEmpty) {
      return children.map((c) => c.id).toList();
    }
    final existingIds = children.map((c) => c.id).toSet();
    return assigned.where(existingIds.contains).toList();
  }

  // ---- Balance (per child) ---------------------------------------------------

  /// Sum of all approved completions ever (øre) for one child.
  Future<int> totalEarnedOre({required String childId}) async {
    final approved = await getApprovedCompletions();
    return approved
        .where((c) => c.childId == childId)
        .fold<int>(0, (sum, c) => sum + c.amountAtCompletionOre);
  }

  /// Sum of all manual balance adjustments ever (øre, can be negative) for
  /// one child.
  Future<int> totalAdjustmentsOre({required String childId}) async {
    final adjustments = await getAllBalanceAdjustments();
    return adjustments
        .where((a) => a.childId == childId)
        .fold<int>(0, (sum, a) => sum + a.amountOre);
  }

  /// Current earned, not paid out balance (øre) for one child, including
  /// manual adjustments.
  Future<int> currentBalanceOre({required String childId}) async {
    final earned = await totalEarnedOre(childId: childId);
    final paidOut = settings.paidOutOreFor(childId);
    final adjustments = await totalAdjustmentsOre(childId: childId);
    final balance = earned - paidOut + adjustments;
    return balance < 0 ? 0 : balance;
  }

  /// Sum of approved completions in the last 7 days (øre) for one child.
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

  /// Number of tasks approved in the last 7 days for one child - used for
  /// the simple progress display in child mode.
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

  /// Creates and stores a manual balance adjustment for one child.
  /// [amountOre] can be negative; [note] is a mandatory reason.
  Future<BalanceAdjustment> addBalanceAdjustment({
    required int amountOre,
    required String note,
    required String childId,
    String? id,
    DateTime? createdAt,
  }) async {
    if (note.trim().isEmpty) {
      throw RepositoryException(l10n.errAdjustmentNote);
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

  // ---- Writing (high level, used directly by the UI) -----------------------

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
      throw RepositoryException(l10n.errTaskNotFound);
    }
    final updated = existing.copyWith(
      title: title,
      description: description,
      clearDescription: description == null,
      amountOre: amountOre,
      recurrence: recurrence,
      mandatory: mandatory,
      activeWeekdays: recurrence == Recurrence.once ? null : activeWeekdays,
      // 'Once' must always end with activeWeekdays == null, regardless of
      // what may have been chosen before, or what the call otherwise asks for.
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

  /// The child marks a task as done. Creates a 'pending' completion.
  /// Throws [RepositoryException] if the task is not available right now, or
  /// if the task is not assigned to this child at all.
  Future<Completion> completeTask(
    String taskId, {
    required String childId,
    String? completionId,
    DateTime? completedAt,
  }) async {
    final task = await _db.getTask(taskId);
    if (task == null || !task.active) {
      throw RepositoryException(l10n.errTaskNotFound);
    }
    final resolvedChildIds = await resolvedChildIdsForTask(task);
    if (!resolvedChildIds.contains(childId)) {
      throw RepositoryException(l10n.errTaskNotAssigned);
    }
    final existingForTask = await _db.getCompletionsForTask(taskId);
    // Only completions for THIS child may affect the availability - see
    // [availabilityFor].
    final existingForChild =
        existingForTask.where((c) => c.childId == childId).toList();
    final availability =
        computeAvailability(task, existingForChild, now: completedAt);
    if (availability != TaskAvailability.available) {
      throw RepositoryException(l10n.errTaskNotAvailable);
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

  /// A parent approves a 'pending' completion - it now counts in the balance.
  Future<void> approveCompletion(String completionId, {DateTime? approvedAt}) async {
    final completion = await _db.getCompletion(completionId);
    if (completion == null) {
      throw RepositoryException(l10n.errCompletionNotFound);
    }
    if (completion.status != CompletionStatus.pending) {
      throw RepositoryException(l10n.errCompletionHandled);
    }
    await _db.updateCompletion(
      completion.copyWith(
        status: CompletionStatus.approved,
        approvedAt: approvedAt ?? DateTime.now(),
      ),
    );
  }

  /// A parent rejects a 'pending' completion - it does not count.
  Future<void> rejectCompletion(String completionId) async {
    final completion = await _db.getCompletion(completionId);
    if (completion == null) {
      throw RepositoryException(l10n.errCompletionNotFound);
    }
    if (completion.status != CompletionStatus.pending) {
      throw RepositoryException(l10n.errCompletionHandled);
    }
    await _db.updateCompletion(
      completion.copyWith(status: CompletionStatus.rejected),
    );
  }

  /// Moves the one child's entire current balance to "paid out" and resets
  /// its earned (not paid out) balance to 0. Does not affect the other
  /// children's balances.
  Future<void> markPaidOut({required String childId}) async {
    final earned = await totalEarnedOre(childId: childId);
    final adjustments = await totalAdjustmentsOre(childId: childId);
    await settings.setPaidOutOreFor(childId, earned + adjustments);
  }

  // ---- Follow-up and settings -------------------------------------------------

  /// Follow-up status (overdue/restricted) for every child at [now].
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

  /// A parent lifts the child's restriction for the rest of [day].
  Future<void> suspendRestriction(String childId, {DateTime? day}) async {
    final children = await getAllChildren();
    if (!children.any((c) => c.id == childId)) {
      throw RepositoryException(l10n.errChildNotFound);
    }
    final suspensions = Map<String, String>.from(
      settings.restrictionSuspensions,
    );
    suspensions[childId] = dateKey(day ?? DateTime.now());
    await settings.setRestrictionSuspensions(suspensions);
  }

  /// Sets one family setting (see [FamilySettings.keys]).
  Future<void> setFamilySetting(String key, Object? value) async {
    try {
      await settings.setFamilySettings(
        settings.familySettings.withValue(key, value),
      );
    } on InvalidSetting catch (e) {
      final min = e.min;
      final max = e.max;
      throw RepositoryException(
        min != null && max != null
            ? l10n.errSettingRange(e.key, '$min', '$max', '${e.value}')
            : FamilySettings.keys.contains(e.key)
                ? l10n.errInvalidTime(e.key, '${e.value}')
                : l10n.errUnknownSetting(e.key),
      );
    }
  }

  // ---- One-time migration (feature: several children) -------------------------

  /// One-time migration: until then [SettingsService.totalPaidOutOre] was one
  /// global paid-out amount for the whole family (when the app only supported
  /// one child). Paid-out amounts are now per child (see
  /// [SettingsService.paidOutOreFor]). This migration moves the old global
  /// value to the one child, EXACTLY once, and only when it makes sense: the
  /// new per-child map is still completely empty, the old value is > 0, and
  /// there is exactly one child (i.e. this really is an upgrade from the "one
  /// child only" version of the app - if there are already several children,
  /// there is no unambiguous child to move the old value to, and the migration
  /// is skipped).
  ///
  /// Must be called early in AppState.initialize() - BEFORE the rest of the
  /// app starts reading/writing per-child balances.
  Future<void> migrateLegacyPaidOutIfNeeded() async {
    final legacy = settings.totalPaidOutOre;
    if (legacy <= 0) return;
    if (settings.paidOutOreByChild.isNotEmpty) return;
    final children = await _db.getAllChildren();
    if (children.length != 1) return;
    await settings.setPaidOutOreFor(children.first.id, legacy);
  }

  // ---- The common action API (the same actions as HA's integration) ---------

  /// Applies one action to the local database. All writing from the UI goes
  /// through here (and is then sent to Home Assistant, which applies the same
  /// action with the same rules).
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
        // Deliberately distinguishes between "the key is missing entirely"
        // (an old sender that has never heard of activeWeekdays/
        // assignedChildIds - keep the existing week plan/assignment
        // unchanged, the same backwards-compatible pattern as 'mandatory')
        // and "the key is explicitly set to null" (an updated sender that
        // actively asks to reset to "every day"/"all children").
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
          throw RepositoryException(l10n.errMissingChildId);
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
          throw RepositoryException(l10n.errMissingChildId);
        }
        await markPaidOut(childId: payoutChildId);
        return;

      case 'adjust_balance':
        final adjustChildId = payload['childId'] as String?;
        if (adjustChildId == null || adjustChildId.isEmpty) {
          throw RepositoryException(l10n.errMissingChildId);
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
          throw RepositoryException(l10n.errMissingName);
        }
        await addChild(name, id: payload['id'] as String?);
        return;

      case 'rename_child':
        final renameId = payload['id'] as String?;
        final newName = payload['name'] as String?;
        if (renameId == null || newName == null || newName.trim().isEmpty) {
          throw RepositoryException(l10n.errMissingIdOrName);
        }
        await renameChild(renameId, newName);
        return;

      case 'delete_child':
        final deleteId = payload['id'] as String?;
        if (deleteId == null || deleteId.isEmpty) {
          throw RepositoryException(l10n.errMissingId);
        }
        await deleteChild(deleteId);
        return;

      case 'suspend_restriction':
        final suspendChildId = payload['childId'] as String?;
        if (suspendChildId == null || suspendChildId.isEmpty) {
          throw RepositoryException(l10n.errMissingChildId);
        }
        await suspendRestriction(suspendChildId);
        return;

      case 'set_setting':
        final key = payload['key'] as String?;
        if (key == null) {
          throw RepositoryException(l10n.errMissingSetting);
        }
        await setFamilySetting(key, payload['value']);
        return;

      default:
        throw RepositoryException(l10n.errUnknownAction('$type'));
    }
  }

  // ---- Full state ---------------------------------------------------------------

  /// The full local state in the sync format (the same shape as HA's
  /// `state_json`).
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

  /// Overwrites the whole local database with the state received from Home
  /// Assistant - a simple and robust "full replace" strategy rather than
  /// fine-grained conflict handling.
  Future<void> replaceAllFromState(Map<String, dynamic> state) async {
    final tasksJson = (state['tasks'] as List).cast<Map>();
    final completionsJson = (state['completions'] as List).cast<Map>();

    await _db.clearCompletions();
    await _db.clearTasks();

    // Backwards compatible, the same pattern as 'balanceAdjustments' below:
    // an old sender without this update does not send 'children' in its state
    // - then skip it and leave the existing child/children on this device
    // untouched, instead of deleting them with no way to recreate them.
    //
    // The children are recreated BEFORE tasks/completions/balance adjustments
    // below, so the foreign keys (assignedChildIds/childId) in the reloaded
    // data actually point to children that exist.
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

    // Backwards compatible: an old sender without this update does not send
    // 'balanceAdjustments' in its state - then simply skip it instead of
    // failing, and leave the existing adjustments (if any) untouched.
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

    // Backwards compatible, the same pattern as above: an old sender does not
    // send 'paidOutOreByChild' yet.
    if (state['paidOutOreByChild'] != null) {
      final raw = (state['paidOutOreByChild'] as Map).cast<String, dynamic>();
      await settings.setPaidOutOreByChild(
        raw.map((key, value) => MapEntry(key, value as int)),
      );
    }

    // The same backwards-compatible pattern: an older sender does not send these.
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
