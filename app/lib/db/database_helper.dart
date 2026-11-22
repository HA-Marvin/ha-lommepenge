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

/// Ansvarlig for at åbne og oprette den lokale SQLite-database, samt
/// lave rå CRUD-operationer på tasks/completions/balance_adjustments/
/// children.
///
/// Bruger den globale `sqflite.databaseFactory`, så unit-tests kan
/// erstatte den med `sqflite_common_ffi`s `databaseFactoryFfi` (se
/// test/task_balance_test.dart) uden nogen særlig test-flag i denne
/// klasse.
class DatabaseHelper {
  DatabaseHelper._internal();
  static final DatabaseHelper instance = DatabaseHelper._internal();

  /// Skal kaldes ÉN gang, tidligt i `main()`, før noget som helst rører
  /// databasen. Den almindelige `sqflite`-plugin har ingen native
  /// implementering på Windows/Linux desktop (kun Android/iOS/macOS), så
  /// der skiftes til `sqflite_common_ffi`'s rene Dart-implementering på
  /// de platforme. Uden dette hænger appen uendeligt på opstartsskærmen
  /// på Windows, fordi database-kaldet fejler stille i baggrunden.
  static void initializeFactory() {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
  }

  Database? _db;

  /// Sti der bruges til databasen. Overstyres i tests (fx ':memory:').
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
        // En frisk installation starter uden børn: forældrene opretter
        // selv familiens børn, så der ikke dukker et generisk "Barn 1" op
        // (fx som enhed i Home Assistant).
        await _createChildrenTableIfMissing(db);
      },
      // v1 -> v2: tilføjede 'mandatory'-kolonnen (obligatorisk/valgfri
      // opgave).
      // v2 -> v3: tilføjede 'active_weekdays'-kolonnen på tasks
      // (ugeplan-filter) og 'balance_adjustments'-tabellen (manuel
      // saldo-justering). Kører automatisk på begge enheders
      // eksisterende database - bevarer alle nuværende
      // opgaver/completions, nye kolonner/tabeller starter tomme/null.
      // v3 -> v4: "flere børn"-featuren. Tilføjede 'children'-tabellen,
      // 'assigned_child_ids' på tasks (null = "alle børn", jf.
      // Task.assignedChildIds) og 'child_id' på completions/
      // balance_adjustments (hvilket barn der optjener/justeres).
      // Databevarende: en opgradering fra en version uden børn-support
      // opretter automatisk ét standard-barn og overfører AL eksisterende
      // completions-/saldo-historik til det, så intet forsvinder eller
      // ender "forældreløst" - se backfill-blokken nedenfor.
      // v4 -> v5: tidspunkter og opfølgning. 'start_time'/'due_time'/
      // 'show_in_calendar' på tasks og 'late' på completions. Eksisterende
      // opgaver får ingen tider og er ikke i kalenderen; eksisterende
      // completions tæller som rettidige.
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

          // Databevarende backfill: kør KUN hvis der endnu ikke findes
          // nogen børn (dvs. dette er reelt en opgradering fra en
          // version uden børn-support). Al eksisterende completions-/
          // saldo-historik (som hidtil ikke havde nogen barn-tilknytning,
          // fordi appen kun understøttede ét barn) tilhører herefter
          // automatisk dette ene barn, i stedet for at gå tabt eller
          // pege på et barn der ikke findes.
          final existingChildren = await db.query('children');
          if (existingChildren.isEmpty) {
            final defaultChildId = const Uuid().v4();
            await db.insert('children', {
              'id': defaultChildId,
              'name': 'Barn 1',
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

  /// Lukker databasen. Bruges primært i tests mellem kørsler.
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

  /// Soft-delete: markerer opgaven inaktiv i stedet for at slette rækken,
  /// så historikken for tidligere completions bevares.
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

  /// Sletter alle tasks. Bruges kun når en telefon overskriver sin lokale
  /// cache med den fulde state fra skærmens database.
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

  // ---- Balance-justeringer ------------------------------------------------

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

  // ---- Børn ---------------------------------------------------------------

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

  /// Sletter alle børn. Bruges kun når en telefon overskriver sin lokale
  /// cache med den fulde state fra skærmens database (se
  /// TaskRepository.replaceAllFromState).
  Future<void> clearChildren() async {
    final db = await database;
    await db.delete('children');
  }
}
