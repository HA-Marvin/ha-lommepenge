import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../models/balance_adjustment.dart';
import '../models/child.dart';
import '../models/completion.dart';
import '../models/task.dart';

/// Responsible for opening and creating the local SQLite database, and for
/// raw CRUD operations on tasks/completions/balance_adjustments/children.
///
/// Uses the global `sqflite.databaseFactory`, so unit tests can replace it
/// with `sqflite_common_ffi`'s `databaseFactoryFfi` (see
/// test/task_balance_test.dart) without any special test flag in this class.
class DatabaseHelper {
  DatabaseHelper._internal();
  static final DatabaseHelper instance = DatabaseHelper._internal();

  /// Must be called ONCE, early in `main()`, before anything touches the
  /// database. The regular `sqflite` plugin has no native implementation on
  /// Windows/Linux desktop (only Android/iOS/macOS), so on those platforms we
  /// switch to `sqflite_common_ffi`'s pure Dart implementation. Without this
  /// the app hangs forever on the start screen on Windows, because the
  /// database call fails silently in the background.
  static void initializeFactory() {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
  }

  Database? _db;

  /// Path used for the database. Overridden in tests (e.g. ':memory:').
  String? overridePath;

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<void> _createBalanceAdjustmentsTableIfMissing(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS balance_adjustments (
        id TEXT PRIMARY KEY,
        amount_ore INTEGER NOT NULL,
        note TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createChildrenTableIfMissing(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS children (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');
  }

  Future<Database> _open() async {
    String path;
    if (overridePath != null) {
      path = overridePath!;
    } else {
      final dir = await getApplicationDocumentsDirectory();
      path = p.join(dir.path, 'lommepenge.db');
    }

    return openDatabase(
      path,
      version: 5,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE tasks (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            description TEXT,
            amount_ore INTEGER NOT NULL,
            recurrence TEXT NOT NULL,
            created_at TEXT NOT NULL,
            active INTEGER NOT NULL DEFAULT 1,
            mandatory INTEGER NOT NULL DEFAULT 0,
            active_weekdays TEXT,
            assigned_child_ids TEXT,
            start_time TEXT,
            due_time TEXT,
            show_in_calendar INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE completions (
            id TEXT PRIMARY KEY,
            task_id TEXT NOT NULL,
            child_id TEXT NOT NULL DEFAULT '',
            completed_at TEXT NOT NULL,
            status TEXT NOT NULL,
            approved_at TEXT,
            amount_at_completion_ore INTEGER NOT NULL,
            late INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_completions_task_id ON completions (task_id)',
        );
        await db.execute('''
          CREATE TABLE balance_adjustments (
            id TEXT PRIMARY KEY,
            amount_ore INTEGER NOT NULL,
            note TEXT NOT NULL,
            child_id TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL
          )
        ''');
        // A fresh installation starts without children: the parents create
        // the family's children themselves, so no generic "Child 1" shows up
        // (e.g. as a device in Home Assistant).
        await _createChildrenTableIfMissing(db);
      },
      // v1 -> v2: added the 'mandatory' column (mandatory/optional task).
      // v2 -> v3: added the 'active_weekdays' column on tasks (week plan
      // filter) and the 'balance_adjustments' table (manual balance
      // adjustment). Runs automatically on existing databases - keeps all
      // current tasks/completions, new columns/tables start empty/null.
      // v3 -> v4: the "several children" feature. Added the 'children' table,
      // 'assigned_child_ids' on tasks (null = "all children", see
      // Task.assignedChildIds) and 'child_id' on completions/
      // balance_adjustments (which child earns/is adjusted). Data-preserving:
      // an upgrade from a version without children support automatically
      // creates one default child and moves ALL existing completion/balance
      // history to it, so nothing disappears or ends up "orphaned" - see the
      // backfill block below.
      // v4 -> v5: times and follow-up. 'start_time'/'due_time'/
      // 'show_in_calendar' on tasks and 'late' on completions. Existing tasks
      // get no times and are not in the calendar; existing completions count
      // as on time.
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE tasks ADD COLUMN mandatory INTEGER NOT NULL DEFAULT 0',
          );
        }
        if (oldVersion < 3) {
          await db.execute(
            'ALTER TABLE tasks ADD COLUMN active_weekdays TEXT',
          );
          await _createBalanceAdjustmentsTableIfMissing(db);
        }
        if (oldVersion < 4) {
          await _createChildrenTableIfMissing(db);
          await db.execute(
            'ALTER TABLE tasks ADD COLUMN assigned_child_ids TEXT',
          );
          await db.execute(
            'ALTER TABLE completions ADD COLUMN child_id TEXT',
          );
          await db.execute(
            'ALTER TABLE balance_adjustments ADD COLUMN child_id TEXT',
          );

          // Data-preserving backfill: ONLY runs if no children exist yet
          // (i.e. this really is an upgrade from a version without children
          // support). All existing completion/balance history (which until
          // now had no child link, because the app only supported one child)
          // then automatically belongs to this one child, instead of being
          // lost or pointing to a child that does not exist.
          final existingChildren = await db.query('children');
          if (existingChildren.isEmpty) {
            final defaultChildId = const Uuid().v4();
            await db.insert('children', {
              'id': defaultChildId,
              'name': 'Child 1',
              'sort_order': 0,
              'created_at': DateTime.now().toIso8601String(),
            });
            await db.update(
              'completions',
              {'child_id': defaultChildId},
              where: 'child_id IS NULL',
            );
            await db.update(
              'balance_adjustments',
              {'child_id': defaultChildId},
              where: 'child_id IS NULL',
            );
          }
        }
        if (oldVersion < 5) {
          await db.execute('ALTER TABLE tasks ADD COLUMN start_time TEXT');
          await db.execute('ALTER TABLE tasks ADD COLUMN due_time TEXT');
          await db.execute(
            'ALTER TABLE tasks ADD COLUMN show_in_calendar INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute(
            'ALTER TABLE completions ADD COLUMN late INTEGER NOT NULL DEFAULT 0',
          );
        }
      },
    );
  }

  /// Closes the database. Mainly used in tests between runs.
  Future<void> close() async {
    final db = _db;
    _db = null;
    await db?.close();
  }

  // ---- Tasks ----------------------------------------------------------

  Future<void> insertTask(Task task) async {
    final db = await database;
    await db.insert(
      'tasks',
      task.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateTask(Task task) async {
    final db = await database;
    await db.update(
      'tasks',
      task.toMap(),
      where: 'id = ?',
      whereArgs: [task.id],
    );
  }

  /// Soft delete: marks the task inactive instead of deleting the row, so
  /// the history of previous completions is kept.
  Future<void> deactivateTask(String taskId) async {
    final db = await database;
    await db.update(
      'tasks',
      {'active': 0},
      where: 'id = ?',
      whereArgs: [taskId],
    );
  }

  Future<List<Task>> getAllTasks({bool onlyActive = false}) async {
    final db = await database;
    final rows = await db.query(
      'tasks',
      where: onlyActive ? 'active = 1' : null,
      orderBy: 'created_at ASC',
    );
    return rows.map(Task.fromMap).toList();
  }

  Future<Task?> getTask(String id) async {
    final db = await database;
    final rows = await db.query('tasks', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Task.fromMap(rows.first);
  }

  /// Deletes all tasks. Only used when the local copy is overwritten with
  /// the full state from Home Assistant.
  Future<void> clearTasks() async {
    final db = await database;
    await db.delete('tasks');
  }

  // ---- Completions ------------------------------------------------------

  Future<void> insertCompletion(Completion completion) async {
    final db = await database;
    await db.insert(
      'completions',
      completion.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateCompletion(Completion completion) async {
    final db = await database;
    await db.update(
      'completions',
      completion.toMap(),
      where: 'id = ?',
      whereArgs: [completion.id],
    );
  }

  Future<Completion?> getCompletion(String id) async {
    final db = await database;
    final rows =
        await db.query('completions', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Completion.fromMap(rows.first);
  }

  Future<List<Completion>> getAllCompletions() async {
    final db = await database;
    final rows = await db.query('completions', orderBy: 'completed_at DESC');
    return rows.map(Completion.fromMap).toList();
  }

  Future<List<Completion>> getCompletionsForTask(String taskId) async {
    final db = await database;
    final rows = await db.query(
      'completions',
      where: 'task_id = ?',
      whereArgs: [taskId],
      orderBy: 'completed_at DESC',
    );
    return rows.map(Completion.fromMap).toList();
  }

  Future<void> clearCompletions() async {
    final db = await database;
    await db.delete('completions');
  }

  // ---- Balance adjustments ------------------------------------------------

  Future<void> insertBalanceAdjustment(BalanceAdjustment adjustment) async {
    final db = await database;
    await db.insert(
      'balance_adjustments',
      adjustment.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<BalanceAdjustment>> getAllBalanceAdjustments() async {
    final db = await database;
    final rows =
        await db.query('balance_adjustments', orderBy: 'created_at DESC');
    return rows.map(BalanceAdjustment.fromMap).toList();
  }

  Future<void> clearBalanceAdjustments() async {
    final db = await database;
    await db.delete('balance_adjustments');
  }

  // ---- Children -----------------------------------------------------------

  Future<void> insertChild(Child child) async {
    final db = await database;
    await db.insert(
      'children',
      child.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateChild(Child child) async {
    final db = await database;
    await db.update(
      'children',
      child.toMap(),
      where: 'id = ?',
      whereArgs: [child.id],
    );
  }

  Future<void> deleteChild(String id) async {
    final db = await database;
    await db.delete('children', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Child>> getAllChildren() async {
    final db = await database;
    final rows =
        await db.query('children', orderBy: 'sort_order ASC, created_at ASC');
    return rows.map(Child.fromMap).toList();
  }

  /// Deletes all children. Only used when the local copy is overwritten with
  /// the full state from Home Assistant (see
  /// TaskRepository.replaceAllFromState).
  Future<void> clearChildren() async {
    final db = await database;
    await db.delete('children');
  }
}
