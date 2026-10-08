import 'dart:async';
import 'dart:io';

import 'package:chess_srs/src/persistence/canonical_rekey_migration.dart';
import 'package:chess_srs/src/persistence/opening_name_repair_migration.dart';
import 'package:chess_srs/src/persistence/srs_schema.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const kLichessDatabaseName = 'chess_srs.db';

const puzzleTTL = Duration(days: 60);
const corresGameTTL = Duration(days: 60);
const gameTTL = Duration(days: 90);
const chatReadMessagesTTL = Duration(days: 180);
const httpLogTTL = Duration(days: 7);
const appLogTTL = Duration(days: 7);

const kStorageAnonId = '**anonymous**';

final _logger = Logger('Database');

/// A provider for the app [Database].
final databaseProvider = FutureProvider<Database>((Ref ref) async {
  if (Platform.isLinux) {
    databaseFactory = databaseFactoryFfi;
  }
  final dbPath = await _databasePath;
  return await openAppDatabase(databaseFactory, dbPath);
}, name: 'DatabaseProvider');

/// Returns the database path including filename.
Future<String> get _databasePath async {
  if (Platform.isLinux) {
    final directory = await getApplicationSupportDirectory();
    return join(directory.path, kLichessDatabaseName);
  }

  return join(await getDatabasesPath(), kLichessDatabaseName);
}

Future<int?> _getDatabaseVersion(Database db) async {
  try {
    final versionStr = (await db.rawQuery('SELECT sqlite_version()')).first.values.first.toString();
    final versionCells = versionStr.split('.').map((i) => int.parse(i)).toList();
    return versionCells[0] * 100000 + versionCells[1] * 1000 + versionCells[2];
  } catch (e, st) {
    _logger.warning('Error occurred while fetching SQLite version:', e, st);
    return null;
  }
}

/// A provider that returns the size of the database file in bytes.
final getDbSizeInBytesProvider = FutureProvider<int>((Ref ref) async {
  final dbPath = await _databasePath;
  final dbFile = File(dbPath);

  if (!await dbFile.exists()) {
    return 0;
  }
  return await dbFile.length();
}, name: 'GetDbSizeInBytesProvider');

/// Opens the app database.
Future<Database> openAppDatabase(DatabaseFactory dbFactory, String path) {
  return dbFactory.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 16,
      onConfigure: (db) async {
        final version = await _getDatabaseVersion(db);
        _logger.info('SQLite version: $version');
        if (version != null && version >= 307000) {
          _logger.info('Enabling WAL journal mode');
          await db.rawQuery('PRAGMA journal_mode=WAL');
        }
      },
      onOpen: (db) async {
        await db.transaction((txn) async {
          await Future.wait([
            _deleteOldEntries(txn, 'puzzle', puzzleTTL),
            _deleteOldEntries(txn, 'correspondence_game', corresGameTTL),
            _deleteOldEntries(txn, 'game', gameTTL),
            _deleteOldEntries(txn, 'chat_read_messages', chatReadMessagesTTL),
            _deleteOldEntries(txn, 'http_log', httpLogTTL),
            _deleteOldEntries(txn, 'app_log', appLogTTL),
          ]);
        });
      },
      onCreate: (db, version) async {
        final batch = db.batch();
        _createPuzzleBatchTableV3(batch);
        _createPuzzleTableV1(batch);
        _createCorrespondenceGameTableV1(batch);
        _createChatReadMessagesTableV1(batch);
        _createGameTableV2(batch);
        _createHttpLogTableV4(batch);
        _createAppLogTableV5(batch);
        createSrsTables(batch);
        await batch.commit();
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        _logger.info('Upgrading database schema from v$oldVersion to v$newVersion');
        final batch = db.batch();
        if (oldVersion == 1) {
          _createGameTableV2(batch);
        }
        if (oldVersion < 3) {
          _updatePuzzleBatchTableToV3(batch);
        }
        if (oldVersion < 4) {
          _createHttpLogTableV4(batch);
        }
        if (oldVersion < 5) {
          _createAppLogTableV5(batch);
        }
        if (oldVersion < 6) {
          createSrsTables(batch);
        } else {
          if (oldVersion < 7) {
            batch.execute(
              'ALTER TABLE $kTableSrsStudy ADD COLUMN isActive INTEGER NOT NULL DEFAULT 1',
            );
          }
          if (oldVersion < 8) {
            batch.execute('ALTER TABLE $kTableSrsChapter ADD COLUMN opening TEXT');
          }
          if (oldVersion < 9) {
            batch.execute('ALTER TABLE $kTableSrsStudy ADD COLUMN pgnHash TEXT');
            batch.execute(
              'CREATE INDEX IF NOT EXISTS idx_srs_study_pgnHash ON $kTableSrsStudy(pgnHash)',
            );
          }
          if (oldVersion < 10) {
            batch.execute('ALTER TABLE $kTableSrsDecision ADD COLUMN canonicalStateId TEXT');
            batch.execute(
              'CREATE INDEX IF NOT EXISTS idx_srs_decision_canonicalStateId ON $kTableSrsDecision(canonicalStateId)',
            );
            batch.execute('''
              CREATE TABLE IF NOT EXISTS $kTablePositionKnowledgeState (
                canonicalId TEXT PRIMARY KEY,
                firstReviewedAt TEXT,
                lastReviewedAt TEXT,
                nextDueAt TEXT,
                repetitionCount INTEGER NOT NULL DEFAULT 0,
                lapseCount INTEGER NOT NULL DEFAULT 0,
                stability REAL NOT NULL DEFAULT 0.0,
                difficulty REAL NOT NULL DEFAULT 0.0,
                latencyEmaMs REAL,
                latencySampleCount INTEGER NOT NULL DEFAULT 0
              );
            ''');
            batch.execute(
              'CREATE INDEX IF NOT EXISTS idx_position_knowledge_state_nextDueAt ON $kTablePositionKnowledgeState(nextDueAt)',
            );
          }
          if (oldVersion < 11) {
            batch.execute(
              'ALTER TABLE $kTableSrsChapter ADD COLUMN orientation TEXT NOT NULL DEFAULT "white"',
            );
          }
          if (oldVersion < 12) {
            batch.execute(
              'CREATE INDEX IF NOT EXISTS idx_srs_review_event_whenTimestamp ON $kTableSrsReviewEvent(whenTimestamp)',
            );
          }
          if (oldVersion < 13) {
            batch.execute(
              'ALTER TABLE $kTableSrsReviewState ADD COLUMN difficulty REAL NOT NULL DEFAULT 5.0',
            );
          }
        }

        // Not a schema change: v14 redefines the canonical review id and backfills history that
        // v10 never copied. Both read before they write, so they cannot be folded into the DDL
        // batch.
        // The data migrations read and write the open database, and a batch is only applied on
        // commit — so the schema has to land before they run, or they read the pre-upgrade tables.
        await batch.commit();

        // v16 scopes the canonical key by repertoire side. This recomputes the v15
        // canonical IDs in place, so a same position in White and Black gets separate
        // canonical states instead of sharing one. It is a no-op once every row is
        // side-scoped, so it runs unconditionally once the legacy migrations settle the
        // pre-v14 IDs they depend on.
        if (oldVersion < 16) {
          final sideScoped = await rekeyCanonicalReviewState(db);
          _logger.info(
            'Side-scoped canonical rekey: ${sideScoped.decisionsRemapped} decisions, '
            '${sideScoped.statesRemapped} states (${sideScoped.statesMerged} merged), '
            '${sideScoped.skipped} skipped',
          );

          // Keep any per-occurrence review history reachable under the new canonical rows.
          final backfill = await backfillCanonicalStatesFromLegacy(db);
          _logger.info(
            'Canonical backfill: ${backfill.statesCreated} states created '
            '(${backfill.collisionsMerged} from collisions)',
          );
        }

        if (oldVersion < 14) {
          final rekey = await rekeyCanonicalReviewState(db);
          _logger.info(
            'Canonical rekey: ${rekey.decisionsRemapped} decisions, '
            '${rekey.statesRemapped} states (${rekey.statesMerged} merged), '
            '${rekey.skipped} skipped',
          );

          // v10 created the canonical table and the column that points at it without ever copying
          // the existing history into them. After the rekey has settled the keys, give every
          // canonical position a state derived from the legacy rows, so a position reached by
          // transposition stops being scheduled from two different sets of numbers.
          final backfill = await backfillCanonicalStatesFromLegacy(db);
          _logger.info(
            'Canonical backfill: ${backfill.statesCreated} states created '
            '(${backfill.collisionsMerged} from collisions)',
          );
        }

        // Also not a schema change: v15 clears opening names that P-OPENNAME's
        // classifier now rejects, on chapters imported before that fix. Runs
        // after the batch commit for the same reason as the v14 block above — it
        // reads and writes the upgraded table.
        if (oldVersion < 15) {
          final repaired = await repairSpuriousOpeningNames(db);
          _logger.info(
            'Opening name repair: ${repaired.cleared} spurious names cleared, '
            '${repaired.kept} kept',
          );
        }

        _logger.info('Database schema upgraded successfully to v$newVersion');
      },
      onDowngrade: onDatabaseDowngradeDelete,
    ),
  );
}

void _createPuzzleBatchTableV3(Batch batch) {
  batch.execute('DROP TABLE IF EXISTS puzzle_batchs');
  batch.execute('''
    CREATE TABLE puzzle_batchs(
      userId TEXT NOT NULL,
      angle TEXT NOT NULL,
      lastModified TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      data TEXT NOT NULL,
      PRIMARY KEY (userId, angle)
    )
    ''');
}

void _updatePuzzleBatchTableToV3(Batch batch) {
  batch.execute('''
    CREATE TABLE puzzle_batchs_new(
      userId TEXT NOT NULL,
      angle TEXT NOT NULL,
      lastModified TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      data TEXT NOT NULL,
      PRIMARY KEY (userId, angle)
    )
    ''');
  batch.execute('''
    INSERT INTO puzzle_batchs_new(userId, angle, data)
    SELECT userId, angle, data FROM puzzle_batchs
    ''');
  batch.execute('DROP TABLE puzzle_batchs');
  batch.execute('ALTER TABLE puzzle_batchs_new RENAME TO puzzle_batchs');
}

void _createPuzzleTableV1(Batch batch) {
  batch.execute('DROP TABLE IF EXISTS puzzle');
  batch.execute('''
    CREATE TABLE puzzle(
    puzzleId TEXT NOT NULL,
    lastModified TEXT NOT NULL,
    data TEXT NOT NULL,
    PRIMARY KEY (puzzleId)
  )
    ''');
}

void _createCorrespondenceGameTableV1(Batch batch) {
  batch.execute('DROP TABLE IF EXISTS correspondence_game');
  batch.execute('''
    CREATE TABLE correspondence_game(
    gameId TEXT NOT NULL,
    userId TEXT NOT NULL,
    lastModified TEXT NOT NULL,
    data TEXT NOT NULL,
    PRIMARY KEY (gameId)
  )
    ''');
}

void _createGameTableV2(Batch batch) {
  batch.execute('DROP TABLE IF EXISTS game');
  batch.execute('''
    CREATE TABLE game(
    gameId TEXT NOT NULL,
    userId TEXT NOT NULL,
    lastModified TEXT NOT NULL,
    data TEXT NOT NULL,
    PRIMARY KEY (gameId)
  )
    ''');
}

void _createChatReadMessagesTableV1(Batch batch) {
  batch.execute('DROP TABLE IF EXISTS chat_read_messages');
  batch.execute('''
    CREATE TABLE chat_read_messages(
    id TEXT NOT NULL,
    lastModified TEXT NOT NULL,
    nbRead INTEGER NOT NULL,
    PRIMARY KEY (id)
  )
    ''');
}

void _createHttpLogTableV4(Batch batch) {
  batch.execute('DROP TABLE IF EXISTS http_log');
  batch.execute('''
    CREATE TABLE http_log(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    httpLogId TEXT NOT NULL UNIQUE,
    requestDateTime TEXT NOT NULL,
    requestMethod TEXT NOT NULL,
    requestUrl TEXT NOT NULL,
    responseCode INTEGER,
    responseDateTime TEXT,
    lastModified TEXT NOT NULL,
    errorMessage TEXT
  )
    ''');
}

void _createAppLogTableV5(Batch batch) {
  batch.execute('DROP TABLE IF EXISTS app_log');
  batch.execute('''
    CREATE TABLE app_log(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    logTime TEXT NOT NULL,
    loggerName TEXT NOT NULL,
    levelValue INTEGER NOT NULL,
    levelName TEXT NOT NULL,
    message TEXT NOT NULL,
    error TEXT,
    stackTrace TEXT,
    lastModified TEXT NOT NULL
  )
    ''');
}

Future<void> _deleteOldEntries(DatabaseExecutor db, String table, Duration ttl) async {
  final date = DateTime.now().subtract(ttl);

  if (!await _doesTableExist(db, table)) {
    return;
  }

  await db.delete(table, where: 'lastModified < ?', whereArgs: [date.toIso8601String()]);
}

Future<bool> _doesTableExist(DatabaseExecutor db, String table) async {
  final tableExists = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' AND name='$table'",
  );

  return tableExists.isNotEmpty;
}
