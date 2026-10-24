import 'dart:async';
import 'dart:io';

import 'package:chess_srs/src/persistence/canonical_rekey_migration.dart';
import 'package:chess_srs/src/persistence/fen_key_backfill_migration.dart';
import 'package:chess_srs/src/persistence/opening_name_repair_migration.dart';
import 'package:chess_srs/src/persistence/orphaned_review_state_sweep.dart';
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

/// Adds SRS columns introduced after a database was first created, if they are missing.
///
/// Architecture §B.2 caps auto-traversal exposure credit to once per calendar day per decision.
/// Until `lastExposedAt` was stored, the only record of the last grant lived in the coordinator's
/// memory, so the cap reset on every app restart and passive stability compounded once per session
/// rather than once per day.
///
/// This is a top-up rather than a versioned migration, on purpose: it reads the table first, so it
/// is idempotent, it leaves `version` and `onUpgrade` untouched, and it converges for any database
/// whether or not it was created before the column existed. The column is nullable TEXT, so it
/// reads back as null, which the coordinator treats as "never exposed" — the permissive reading,
/// and the correct one for a row written before the column existed.
Future<void> _ensureLateSrsColumns(Database db) async {
  final columns = await db.rawQuery('PRAGMA table_info($kTablePositionKnowledgeState)');
  if (columns.isEmpty) return; // table not created yet; onCreate will include the column
  final hasLastExposedAt = columns.any((row) => row['name'] == 'lastExposedAt');
  if (!hasLastExposedAt) {
    await db.execute('ALTER TABLE $kTablePositionKnowledgeState ADD COLUMN lastExposedAt TEXT');
  }
}

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
      version: 21,
      onConfigure: (db) async {
        final version = await _getDatabaseVersion(db);
        _logger.info('SQLite version: $version');
        if (version != null && version >= 307000) {
          _logger.info('Enabling WAL journal mode');
          await db.rawQuery('PRAGMA journal_mode=WAL');
        }
        // SQLite ignores declared foreign keys unless the connection asks for them, and the
        // setting is per-connection rather than persisted. srs_chapter and srs_decision declare
        // ON DELETE CASCADE against srs_study; without this those clauses are decorative, and an
        // orphan survives any path that does not cascade by hand. deleteStudy and deleteChapter do
        // cascade in Dart, which is why nothing had gone wrong yet — the database was simply not
        // holding up its end for anything else.
        //
        // Set unconditionally: older SQLite ignores it rather than failing, and foreign-key
        // support predates every version this app opens a database on.
        await db.rawQuery('PRAGMA foreign_keys = ON');

        // Memory-mapped I/O: allow SQLite to map up to 256 MiB directly into virtual memory.
        // When mmap_size is set, page reads bypass read() system calls and access the kernel
        // page cache directly. Supported since SQLite 3.7.17.
        if (version != null && version >= 307017) {
          await db.rawQuery('PRAGMA mmap_size = 268435456'); // 256 MiB
        }

        // 64 MiB user-space page cache (negative number indicates size in kibibytes).
        await db.rawQuery('PRAGMA cache_size = -64000');

        // Store temporary tables and indices in memory rather than on disk.
        await db.rawQuery('PRAGMA temp_store = MEMORY');
      },
      onOpen: (db) async {
        await _ensureLateSrsColumns(db);
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
          if (oldVersion < 17) {
            // CREATE IF NOT EXISTS: idempotent by construction, so a resumed
            // upgrade or a fixture built from the current schema cannot fail
            // the open with "already exists".
            batch.execute('''
              CREATE TABLE IF NOT EXISTS $kTableSrsStudyRemote (
                studyId TEXT PRIMARY KEY,
                remoteStudyId TEXT NOT NULL,
                remoteUpdatedAt TEXT NOT NULL,
                FOREIGN KEY (studyId) REFERENCES $kTableSrsStudy(id) ON DELETE CASCADE
              );
            ''');
            batch.execute(
              'CREATE INDEX IF NOT EXISTS idx_srs_study_remote_remoteStudyId ON $kTableSrsStudyRemote(remoteStudyId)',
            );
          }

          if (oldVersion < 18) {
            // Ghost FK removal: V3 created srs_review_state and
            // srs_review_event with FOREIGN KEY (decisionId) REFERENCES
            // srs_decision(id); later schemas dropped the clauses but SQLite
            // keeps enforcing them on old tables — and since enforcement was
            // switched on per connection, every canonical-mirror write (whose
            // id is a position key, never a decision row) fails on long-lived
            // databases while fresh installs work. Rebuild both tables
            // without the clauses, preserving every row and index. Only
            // tables that exist are rebuilt, so fixtures lacking them pass
            // through untouched.
            final legacyTables = await db.rawQuery(
              "SELECT name FROM sqlite_master WHERE type='table' AND name IN "
              "('$kTableSrsReviewState','$kTableSrsReviewEvent')",
            );
            final legacyNames = legacyTables.map((r) => r['name']! as String).toSet();
            if (legacyNames.contains(kTableSrsReviewState)) {
              batch.execute('DROP TABLE IF EXISTS ${kTableSrsReviewState}_new');
              batch.execute('''
                CREATE TABLE ${kTableSrsReviewState}_new (
                  decisionId TEXT PRIMARY KEY,
                  firstReviewedAt TEXT,
                  lastReviewedAt TEXT,
                  nextDueAt TEXT,
                  repetitionCount INTEGER NOT NULL DEFAULT 0,
                  lapseCount INTEGER NOT NULL DEFAULT 0,
                  stability REAL NOT NULL DEFAULT 0.0,
                  difficulty REAL NOT NULL DEFAULT 5.0
                );
              ''');
              batch.execute(
                'INSERT INTO ${kTableSrsReviewState}_new SELECT * FROM $kTableSrsReviewState',
              );
              batch.execute('DROP TABLE $kTableSrsReviewState');
              batch.execute(
                'ALTER TABLE ${kTableSrsReviewState}_new RENAME TO $kTableSrsReviewState',
              );
              batch.execute(
                'CREATE INDEX IF NOT EXISTS idx_srs_review_state_nextDueAt ON $kTableSrsReviewState(nextDueAt)',
              );
            }
            if (legacyNames.contains(kTableSrsReviewEvent)) {
              batch.execute('DROP TABLE IF EXISTS ${kTableSrsReviewEvent}_new');
              batch.execute('''
                CREATE TABLE ${kTableSrsReviewEvent}_new (
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  decisionId TEXT NOT NULL,
                  whenTimestamp TEXT NOT NULL,
                  result TEXT NOT NULL,
                  oldStateJson TEXT NOT NULL,
                  newStateJson TEXT NOT NULL
                );
              ''');
              batch.execute(
                'INSERT INTO ${kTableSrsReviewEvent}_new SELECT * FROM $kTableSrsReviewEvent',
              );
              batch.execute('DROP TABLE $kTableSrsReviewEvent');
              batch.execute(
                'ALTER TABLE ${kTableSrsReviewEvent}_new RENAME TO $kTableSrsReviewEvent',
              );
              batch.execute(
                'CREATE INDEX IF NOT EXISTS idx_srs_review_event_decisionId ON $kTableSrsReviewEvent(decisionId)',
              );
              batch.execute(
                'CREATE INDEX IF NOT EXISTS idx_srs_review_event_whenTimestamp ON $kTableSrsReviewEvent(whenTimestamp)',
              );
            }
          }

          if (oldVersion < 19) {
            batch.execute('''
              CREATE TABLE IF NOT EXISTS $kTableSrsUnlockedDecision (
                decisionId TEXT PRIMARY KEY,
                unlockedAt TEXT NOT NULL,
                FOREIGN KEY (decisionId) REFERENCES $kTableSrsDecision(id) ON DELETE CASCADE
              );
            ''');
            batch.execute(
              'CREATE INDEX IF NOT EXISTS idx_srs_unlocked_decision_decisionId ON $kTableSrsUnlockedDecision(decisionId)',
            );
          }

          if (oldVersion < 21) {
            // The decision's position identity on its own row, so session
            // construction can build the transposition and canonical indexes
            // without decoding chapter trees (PERF-FIX-49). Nullable: the v21
            // data migration backfills it from the trees, and a row it cannot
            // fill stays null and falls back to the tree path at session time.
            batch.execute('ALTER TABLE $kTableSrsDecision ADD COLUMN fenKey TEXT');
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

        // Also not a schema change: v20 clears the review-state mirrors the v14/v16 rekeys
        // stranded under superseded canonical keys. The rekey now carries each mirror along
        // with its knowledge row, so this only removes what the earlier passes already left
        // behind — rows that neither a decision nor a knowledge row names any more.
        if (oldVersion < 20) {
          final swept = await sweepOrphanedReviewStates(db);
          _logger.info('Orphaned review-state sweep: $swept rows removed');
        }

        // Also not a schema change: v21 copies each decision's position
        // identity (its node's fen key) onto its row, reading the stored
        // chapter trees once. Runs after the batch commit for the same reason
        // as the v14/v16 blocks above — it reads the upgraded table.
        if (oldVersion < 21) {
          final fenKeys = await backfillDecisionFenKeys(db);
          _logger.info(
            'Fen key backfill: ${fenKeys.decisionsFilled} decisions filled, '
            '${fenKeys.skipped} skipped',
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
    "SELECT name FROM sqlite_master WHERE type='table' AND name = ?",
    [table],
  );

  return tableExists.isNotEmpty;
}
