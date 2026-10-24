// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// SPEC coverage: INV-005.
//
// On-disk fixtures for the shipped schema versions the inline tests do not
// cover: v6-v11 (schema additions only) and v14-v15 (the canonical rekey and
// the side split, entered through the real open path). v12->v13 and v13->v14
// have inline fixtures in sqlite_study_repository_test.dart, and v16->v17 plus
// the v18 foreign-key rebuild live in test/db/srs_upgrade_test.dart.
//
// Each fixture is built as "the current schema minus everything added after N"
// rather than from historical DDL. Every migration step is additive (ADD
// COLUMN / CREATE TABLE IF NOT EXISTS), so a strip that misses something makes
// the open fail loudly with "duplicate column name" — the fixtures check their
// own premise. The database is then reopened through [openAppDatabase] and
// checked against what INV-005 promises: every row survives, and the derived
// identities (canonicalStateId, difficulty, orientation, pgnHash) land on the
// current contract.

import 'dart:convert';
import 'dart:io';

import 'package:chess_srs/src/db/database.dart';
import 'package:chess_srs/src/domain/position_knowledge_state.dart';
import 'package:chess_srs/src/domain/repertoire_move.dart';
import 'package:chess_srs/src/domain/repertoire_node.dart';
import 'package:chess_srs/src/persistence/json_adapters.dart';
import 'package:chess_srs/src/persistence/srs_schema.dart';
import 'package:crypto/crypto.dart';
import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _fenKey = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -';

/// The answer set the fixture decision offers. The first-child key and the
/// complete-contract key differ only when more than one move is accepted, so
/// the fixtures need both moves to exercise a real rekey.
const _acceptedMoves = [
  RepertoireMove(from: 'e2', to: 'e4', san: 'e4'),
  RepertoireMove(from: 'd2', to: 'd4', san: 'd4'),
];

/// The pre-v14 canonical key: `sha1("<fenKey>|<first accepted move>")`.
final _firstChildKey = canonicalKey(_fenKey, 'e2e4');

/// The v14/v15-era canonical key: `sha1("<fenKey>|<sorted uci>|<sorted uci>")`.
/// v16 scoped this key by repertoire side; that is the rewrite under test.
String _unscopedCompleteKey(String fenKey) {
  final sortedMoves = _acceptedMoves.map((move) => move.uci).toList()..sort();
  return sha1.convert(utf8.encode([fenKey, ...sortedMoves].join('|'))).toString();
}

String _sideScopedKey(Side side) =>
    canonicalKeyForPosition(_fenKey, _acceptedMoves.map((move) => move.uci), repertoireSide: side);

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory tempDir;
  late String dbPath;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('chess_srs_migration_fixture_');
    dbPath = p.join(tempDir.path, 'fixture.db');
  });

  tearDown(() {
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('installs from v6 to v11 open at the current schema without data loss', () {
    for (final version in const [6, 7, 8, 9, 10, 11]) {
      test(
        'a v$version database lands on the current schema with its rows and identities intact',
        () async {
          await _writeFixture(dbPath, version, _seedVersionedInstall);

          final db = await openAppDatabase(databaseFactoryFfi, dbPath);
          try {
            await _expectCurrentSchema(db);

            final study = await _singleRow(
              db,
              kTableSrsStudy,
              where: 'id = ?',
              whereArgs: ['st-1'],
            );
            expect(study['title'], 'Old library');
            expect(study['isActive'], 1);
            expect(study['pgnHash'], version < 9 ? isNull : 'st-1-pgn-hash');

            final chapter = await _singleRow(
              db,
              kTableSrsChapter,
              where: 'id = ?',
              whereArgs: ['ch-1'],
            );
            expect(chapter['startingFen'], _fenKey);
            expect(chapter['opening'], version < 8 ? isNull : 'Sicilian Defense');
            // v11 seeded "black"; older fixtures gain the column with its
            // default, which is also what the rekey then reads back.
            expect(chapter['orientation'], version < 11 ? 'white' : 'black');

            final event = await _singleRow(
              db,
              kTableSrsReviewEvent,
              where: 'decisionId = ?',
              whereArgs: ['occ-1'],
            );
            expect(event['result'], 'good');

            // The legacy per-occurrence row stays exactly where it was; the
            // canonical table is an addition, not a replacement.
            final legacy = await _singleRow(
              db,
              kTableSrsReviewState,
              where: 'decisionId = ?',
              whereArgs: ['occ-1'],
            );
            expect(legacy['repetitionCount'], 8);
            expect(legacy['stability'], 42.5);
            // v13's ADD COLUMN backfills the default over existing rows; this
            // fixture predates v13, so the default is the correct value.
            expect(legacy['difficulty'], 5.0);

            final decision = await _singleRow(
              db,
              kTableSrsDecision,
              where: 'id = ?',
              whereArgs: ['occ-1'],
            );
            if (version < 10) {
              // The canonical column and table arrived at v10. A pre-v10
              // install has no identity to migrate, and none is invented for
              // it: the legacy row remains the only record of its history.
              expect(decision['canonicalStateId'], isNull);
              expect(await db.query(kTablePositionKnowledgeState), isEmpty);
              return;
            }

            // v10 pointed the decision and its knowledge row at the
            // first-child key; the rekey rewrites both onto the side-scoped
            // complete-contract key, honouring the chapter's orientation.
            final expectedKey = _sideScopedKey(version < 11 ? Side.white : Side.black);
            expect(decision['canonicalStateId'], expectedKey);

            final states = await db.query(kTablePositionKnowledgeState);
            expect(states, hasLength(1));
            expect(states.single['canonicalId'], expectedKey);
            expect(states.single['repetitionCount'], 8);
            expect(states.single['lapseCount'], 1);
            expect(states.single['stability'], 42.5);
            expect(states.single['lastExposedAt'], isNull);
            expect(
              await db.query(
                kTablePositionKnowledgeState,
                where: 'canonicalId = ?',
                whereArgs: [_firstChildKey],
              ),
              isEmpty,
              reason: 'the old key must not survive as an orphaned row',
            );
          } finally {
            await db.close();
          }
        },
      );
    }
  });

  group('shared white/black review memory written before v16 is split, not lost', () {
    for (final version in const [14, 15]) {
      test(
        'a v$version database splits the shared state per side and both sides keep their history',
        () async {
          await _writeFixture(dbPath, version, (db, _) => _seedSharedSideInstall(db));

          final db = await openAppDatabase(databaseFactoryFfi, dbPath);
          try {
            await _expectCurrentSchema(db);

            final whiteKey = _sideScopedKey(Side.white);
            final blackKey = _sideScopedKey(Side.black);
            expect(whiteKey, isNot(blackKey), reason: 'side scoping must distinguish the two');

            // Both decisions carried the one shared key; after the split each
            // points at its own side's key.
            final decisions = await db.query(kTableSrsDecision, orderBy: 'id');
            expect(decisions, hasLength(2));
            expect(
              {
                for (final decision in decisions)
                  decision['id']! as String: decision['canonicalStateId'],
              },
              {'occ-black': blackKey, 'occ-white': whiteKey},
            );

            // The single shared knowledge row was copied to both side-scoped
            // keys: neither side's scheduling memory was reset by the split.
            final states = await db.query(kTablePositionKnowledgeState);
            expect(states, hasLength(2));
            expect(states.map((state) => state['canonicalId']! as String).toSet(), {
              whiteKey,
              blackKey,
            });
            for (final state in states) {
              expect(state['repetitionCount'], 7);
              expect(state['stability'], 12.5);
              expect(state['difficulty'], 6.0);
              expect(state['lastExposedAt'], isNull);
            }
            expect(
              await db.query(
                kTablePositionKnowledgeState,
                where: 'canonicalId = ?',
                whereArgs: [_unscopedCompleteKey(_fenKey)],
              ),
              isEmpty,
              reason: 'the shared key must not survive as an orphan once it is split',
            );

            // The legacy rows stay per occurrence, each with its own numbers.
            final legacyWhite = await _singleRow(
              db,
              kTableSrsReviewState,
              where: 'decisionId = ?',
              whereArgs: ['occ-white'],
            );
            expect(legacyWhite['repetitionCount'], 7);
            final legacyBlack = await _singleRow(
              db,
              kTableSrsReviewState,
              where: 'decisionId = ?',
              whereArgs: ['occ-black'],
            );
            expect(legacyBlack['repetitionCount'], 3);

            final study = await _singleRow(
              db,
              kTableSrsStudy,
              where: 'id = ?',
              whereArgs: ['st-1'],
            );
            expect(study['title'], 'Both sides');
            final event = await _singleRow(
              db,
              kTableSrsReviewEvent,
              where: 'decisionId = ?',
              whereArgs: ['occ-white'],
            );
            expect(event['result'], 'good');

            // The opening-name repair is gated on oldVersion < 15: a v14
            // install predates it and loses its spurious name, while a v15
            // install shipped with the fix and its column is left untouched.
            final white = await _singleRow(
              db,
              kTableSrsChapter,
              where: 'id = ?',
              whereArgs: ['ch-white'],
            );
            final black = await _singleRow(
              db,
              kTableSrsChapter,
              where: 'id = ?',
              whereArgs: ['ch-black'],
            );
            expect(white['opening'], version < 15 ? isNull : 'White vs French');
            expect(black['opening'], 'Sicilian Defense');
          } finally {
            await db.close();
          }
        },
      );
    }
  });
}

/// Writes a database at [version] to [dbPath] and closes it again, so the test
/// can reopen it through the current application.
Future<void> _writeFixture(
  String dbPath,
  int version,
  Future<void> Function(Database db, int version) seed,
) async {
  final db = await databaseFactoryFfi.openDatabase(
    dbPath,
    options: OpenDatabaseOptions(
      version: version,
      onCreate: (db, version) async {
        final batch = db.batch();
        createSrsTables(batch);
        await batch.commit();
        await _stripToVersion(db, version);
        await seed(db, version);
      },
    ),
  );
  await db.close();
}

/// Removes everything the shipped schema gained after [version], leaving the
/// shape an install of that version carried.
///
/// Runs in reverse order of introduction. Indexes are dropped before the
/// columns they reference, because SQLite refuses to drop an indexed column.
Future<void> _stripToVersion(Database db, int version) async {
  if (version < 21) {
    await db.execute('ALTER TABLE $kTableSrsDecision DROP COLUMN fenKey');
  }
  if (version < 19) {
    await db.execute('DROP TABLE IF EXISTS $kTableSrsUnlockedDecision');
  }
  // v18 rebuilds the review tables into the same shape createSrsTables
  // already writes, so nothing can be stripped for it.
  if (version < 17) {
    await db.execute('DROP TABLE IF EXISTS $kTableSrsStudyRemote');
  }
  if (version < 13) {
    await db.execute('ALTER TABLE $kTableSrsReviewState DROP COLUMN difficulty');
  }
  if (version < 12) {
    await db.execute('DROP INDEX IF EXISTS idx_srs_review_event_whenTimestamp');
  }
  if (version < 11) {
    await db.execute('ALTER TABLE $kTableSrsChapter DROP COLUMN orientation');
  }
  if (version < 10) {
    await db.execute('DROP INDEX IF EXISTS idx_srs_decision_canonicalStateId');
    await db.execute('ALTER TABLE $kTableSrsDecision DROP COLUMN canonicalStateId');
    await db.execute('DROP TABLE IF EXISTS $kTablePositionKnowledgeState');
  } else {
    // lastExposedAt arrived as an unversioned top-up rather than a migration
    // step, so an install of any version up to v18 may still lack it.
    await db.execute('ALTER TABLE $kTablePositionKnowledgeState DROP COLUMN lastExposedAt');
  }
  if (version < 9) {
    await db.execute('DROP INDEX IF EXISTS idx_srs_study_pgnHash');
    await db.execute('ALTER TABLE $kTableSrsStudy DROP COLUMN pgnHash');
  }
  if (version < 8) {
    await db.execute('ALTER TABLE $kTableSrsChapter DROP COLUMN opening');
  }
  if (version < 7) {
    await db.execute('ALTER TABLE $kTableSrsStudy DROP COLUMN isActive');
  }
}

/// The rows an install of [version] carries: one study, one chapter, one
/// decision offering two accepted moves, and the decision's legacy review
/// state and event. [version] gates the columns that existed at the time.
Future<void> _seedVersionedInstall(Database db, int version) async {
  await db.insert(kTableSrsStudy, {
    'id': 'st-1',
    'title': 'Old library',
    'createdAt': '2026-01-01T00:00:00.000Z',
    'updatedAt': '2026-01-02T00:00:00.000Z',
    if (version >= 7) 'isActive': 1,
    if (version >= 9) 'pgnHash': 'st-1-pgn-hash',
  });
  await db.insert(kTableSrsChapter, {
    'id': 'ch-1',
    'studyId': 'st-1',
    'sourceOrder': 0,
    'title': 'Chapter',
    'startingFen': _fenKey,
    'createdAt': '2026-01-01T00:00:00.000Z',
    'treeJson': jsonEncode(
      repertoireNodeToJson(const RepertoireNode(id: 'node-1', fen: _fenKey, fenKey: _fenKey)),
    ),
    if (version >= 8) 'opening': 'Sicilian Defense',
    if (version >= 11) 'orientation': 'black',
  });
  await db.insert(kTableSrsDecision, {
    'id': 'occ-1',
    'studyId': 'st-1',
    'chapterId': 'ch-1',
    'nodeId': 'node-1',
    'expectedMoves': encodeExpectedMoves(_acceptedMoves),
    if (version >= 10) 'canonicalStateId': _firstChildKey,
  });
  if (version >= 10) {
    // v10 pointed the decision at the canonical table and moved on; an install
    // that had already reviewed carries one knowledge row, under the
    // first-child key that was current at the time.
    await db.insert(kTablePositionKnowledgeState, {
      'canonicalId': _firstChildKey,
      'firstReviewedAt': '2026-01-02T00:00:00.000Z',
      'lastReviewedAt': '2026-01-20T00:00:00.000Z',
      'nextDueAt': '2026-02-20T00:00:00.000Z',
      'repetitionCount': 8,
      'lapseCount': 1,
      'stability': 42.5,
      'difficulty': 6.0,
      'latencySampleCount': 0,
    });
  }
  await db.insert(kTableSrsReviewState, {
    'decisionId': 'occ-1',
    'firstReviewedAt': '2026-01-02T00:00:00.000Z',
    'lastReviewedAt': '2026-01-20T00:00:00.000Z',
    'nextDueAt': '2026-02-20T00:00:00.000Z',
    'repetitionCount': 8,
    'lapseCount': 1,
    'stability': 42.5,
    if (version >= 13) 'difficulty': 6.0,
  });
  await db.insert(kTableSrsReviewEvent, {
    'decisionId': 'occ-1',
    'whenTimestamp': '2026-01-20T00:00:00.000Z',
    'result': 'good',
    'oldStateJson': '{}',
    'newStateJson': '{}',
  });
}

/// The rows a v14/v15 install carries once the same position has been trained
/// from both sides: two chapters — one White, one Black — share a single
/// canonical key and a single knowledge row, because side scoping arrived in
/// v16. The White chapter's opening name is one the v15 repair exists to clear.
Future<void> _seedSharedSideInstall(Database db) async {
  final sharedKey = _unscopedCompleteKey(_fenKey);
  await db.insert(kTableSrsStudy, {
    'id': 'st-1',
    'title': 'Both sides',
    'createdAt': '2026-01-01T00:00:00.000Z',
    'updatedAt': '2026-01-02T00:00:00.000Z',
    'isActive': 1,
    'pgnHash': 'st-1-pgn-hash',
  });
  for (final (index, side) in const ['white', 'black'].indexed) {
    await db.insert(kTableSrsChapter, {
      'id': 'ch-$side',
      'studyId': 'st-1',
      'sourceOrder': index,
      'title': 'Chapter $side',
      'startingFen': _fenKey,
      'createdAt': '2026-01-01T00:00:00.000Z',
      'treeJson': jsonEncode(
        repertoireNodeToJson(RepertoireNode(id: 'node-$side', fen: _fenKey, fenKey: _fenKey)),
      ),
      'opening': side == 'white' ? 'White vs French' : 'Sicilian Defense',
      'orientation': side,
    });
    await db.insert(kTableSrsDecision, {
      'id': 'occ-$side',
      'studyId': 'st-1',
      'chapterId': 'ch-$side',
      'nodeId': 'node-$side',
      'expectedMoves': encodeExpectedMoves(_acceptedMoves),
      'canonicalStateId': sharedKey,
    });
    await db.insert(kTableSrsReviewState, {
      'decisionId': 'occ-$side',
      'firstReviewedAt': '2026-01-02T00:00:00.000Z',
      'lastReviewedAt': '2026-01-20T00:00:00.000Z',
      'nextDueAt': '2026-02-20T00:00:00.000Z',
      'repetitionCount': side == 'white' ? 7 : 3,
      'lapseCount': side == 'white' ? 1 : 0,
      'stability': side == 'white' ? 12.5 : 4.5,
      'difficulty': 6.0,
    });
  }
  await db.insert(kTablePositionKnowledgeState, {
    'canonicalId': sharedKey,
    'firstReviewedAt': '2026-01-02T00:00:00.000Z',
    'lastReviewedAt': '2026-01-20T00:00:00.000Z',
    'nextDueAt': '2026-02-20T00:00:00.000Z',
    'repetitionCount': 7,
    'lapseCount': 1,
    'stability': 12.5,
    'difficulty': 6.0,
    'latencySampleCount': 0,
  });
  await db.insert(kTableSrsReviewEvent, {
    'decisionId': 'occ-white',
    'whenTimestamp': '2026-01-20T00:00:00.000Z',
    'result': 'good',
    'oldStateJson': '{}',
    'newStateJson': '{}',
  });
}

/// Asserts the database landed on the schema the current application writes:
/// every later column, table and index is present, the version is persisted,
/// and the review tables carry no foreign keys (v18 removed the ghosts).
Future<void> _expectCurrentSchema(Database db) async {
  expect(
    (await db.rawQuery('PRAGMA user_version')).single['user_version'],
    21,
    reason: 'the upgrade must persist the new schema version',
  );

  Future<Set<String>> columnsOf(String table) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return {for (final row in rows) row['name']! as String};
  }

  Future<Set<String>> namesOf(String type) async {
    final rows = await db.rawQuery('SELECT name FROM sqlite_master WHERE type = ?', [type]);
    return {for (final row in rows) row['name']! as String};
  }

  expect(await columnsOf(kTableSrsStudy), containsAll(<String>['isActive', 'pgnHash']));
  expect(await columnsOf(kTableSrsChapter), containsAll(<String>['opening', 'orientation']));
  expect(await columnsOf(kTableSrsDecision), containsAll(<String>['canonicalStateId', 'fenKey']));
  expect(await columnsOf(kTableSrsReviewState), containsAll(<String>['difficulty']));
  expect(await columnsOf(kTablePositionKnowledgeState), containsAll(<String>['lastExposedAt']));
  expect(
    await namesOf('table'),
    containsAll(<String>[
      kTablePositionKnowledgeState,
      kTableSrsStudyRemote,
      kTableSrsUnlockedDecision,
    ]),
  );
  expect(
    await namesOf('index'),
    containsAll(<String>[
      'idx_srs_study_pgnHash',
      'idx_srs_decision_canonicalStateId',
      'idx_srs_review_event_whenTimestamp',
      'idx_position_knowledge_state_nextDueAt',
      'idx_srs_study_remote_remoteStudyId',
      'idx_srs_unlocked_decision_decisionId',
      'idx_srs_review_state_nextDueAt',
    ]),
  );
  expect(await db.rawQuery('PRAGMA foreign_key_list($kTableSrsReviewState)'), isEmpty);
  expect(await db.rawQuery('PRAGMA foreign_key_list($kTableSrsReviewEvent)'), isEmpty);
}

Future<Map<String, Object?>> _singleRow(
  Database db,
  String table, {
  required String where,
  required List<Object?> whereArgs,
}) async {
  final rows = await db.query(table, where: where, whereArgs: whereArgs);
  expect(rows, hasLength(1));
  return rows.single;
}
