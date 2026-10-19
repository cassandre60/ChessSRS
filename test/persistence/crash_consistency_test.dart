// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC coverage: INV-001, INV-002.
//
// Crash consistency (docs/test-audit/audit-report.md blind spot #1, T0): the
// write paths must be all-or-nothing. A fault injected at a batch boundary
// must leave the database exactly as it was, never half-written, and a retry
// must heal. INV-004 is not cited here: none of these scenarios deletes.
//
// The fault is injected in-process at the repository's own boundary
// (`Batch.commit` / batch statement) rather than by killing the process, so
// what is proven is the claim the audit named: no write path reaches the
// database outside its transaction. Recovery of a WAL journal left by a real
// power loss is SQLite's job, not this file's.

import 'dart:io';

import 'package:chess_srs/src/db/database.dart';
import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/import/pgn_importer.dart';
import 'package:chess_srs/src/persistence/persistence.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'faulty_database.dart';

/// Only the harness's own fault should satisfy `throwsA`; a `DatabaseException`
/// from anywhere else must fail the test instead of passing vacuously.
final Matcher _injectedFault = isA<InjectedFault>();

void main() {
  setUpAll(sqfliteFfiInit);

  group('crash consistency', () {
    late Directory tempDir;
    late String dbPath;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('chess_srs_crash_');
      dbPath = p.join(tempDir.path, 'crash.db');
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } on FileSystemException {
        // Best-effort cleanup; the database file may already be gone.
      }
    });

    test(
      'torn import: a fault at the chapter batch leaves the library untouched (INV-001)',
      () async {
        await _seedImport(dbPath, 'survivor', chapters: 2);

        final db = await _openFaulty(dbPath);
        db.arm(const FaultPlan(throwAtBatchCommit: 1));
        final repo = SqliteStudyRepository(db);
        await expectLater(
          repo.saveImportResult(_importResult('torn', chapters: 3)),
          throwsA(_injectedFault),
        );

        // The study insert, the chapter batch and the decision batch share one
        // transaction: losing the chapter batch must lose the study row too.
        await _expectImportCounts(db, studies: 1, chapters: 2, decisions: 2);
        expect(await _studyIds(db), [
          'survivor',
        ], reason: 'a half-written study survived the fault');
        await _expectNoOrphans(db);

        // The single-shot fault has fired; the retry must heal the library.
        await repo.saveImportResult(_importResult('torn', chapters: 3));
        await _expectImportCounts(db, studies: 2, chapters: 5, decisions: 5);
        expect(await _studyIds(db), ['survivor', 'torn']);
        await _expectNoOrphans(db);

        await db.close();
      },
    );

    test(
      'torn import: a fault at the decision batch rolls the committed chapter batch back (INV-001)',
      () async {
        await _seedImport(dbPath, 'survivor', chapters: 2);

        final db = await _openFaulty(dbPath);
        // Commit #1 is the chapter batch, which executes *before* the decision
        // batch commits. Both live inside one transaction, so the late fault
        // must unwind the earlier batch as well.
        db.arm(const FaultPlan(throwAtBatchCommit: 2));
        final repo = SqliteStudyRepository(db);
        await expectLater(
          repo.saveImportResult(_importResult('torn', chapters: 3)),
          throwsA(_injectedFault),
        );

        await _expectImportCounts(db, studies: 1, chapters: 2, decisions: 2);
        expect(await _studyIds(db), ['survivor']);
        await _expectNoOrphans(db);

        await repo.saveImportResult(_importResult('torn', chapters: 3));
        await _expectImportCounts(db, studies: 2, chapters: 5, decisions: 5);
        await _expectNoOrphans(db);

        await db.close();
      },
    );

    test(
      'torn answer write: a fault at the batch commit leaves no knowledge row without its mirrors (INV-002)',
      () async {
        await _seedAnswerablePosition(dbPath);

        final db = await _openFaulty(dbPath);
        final repo = SqliteStudyRepository(db);
        await _expectCount(db, 'SELECT COUNT(*) FROM $kTablePositionKnowledgeState', 0);
        await _expectCount(db, 'SELECT COUNT(*) FROM $kTableSrsReviewState', 0);

        db.arm(const FaultPlan(throwAtBatchCommit: 1));
        final state = _answeredKnowledgeState();
        await expectLater(repo.saveAnswerBatch(knowledgeStates: [state]), throwsA(_injectedFault));

        // Knowledge row, canonical mirror and per-occurrence mirror are one
        // batch; none of them may survive a failed commit.
        await _expectCount(
          db,
          'SELECT COUNT(*) FROM $kTablePositionKnowledgeState',
          0,
          reason: 'a knowledge row survived a failed answer write',
        );
        await _expectCount(
          db,
          'SELECT COUNT(*) FROM $kTableSrsReviewState',
          0,
          reason: 'a mirror survived a failed answer write (vice versa of the orphan pairing)',
        );
        await _expectNoOrphans(db);

        // Retry heals: one knowledge row and both mirrors it implies.
        await repo.saveAnswerBatch(knowledgeStates: [state]);
        await _expectCount(db, 'SELECT COUNT(*) FROM $kTablePositionKnowledgeState', 1);
        await _expectCount(
          db,
          "SELECT COUNT(*) FROM $kTableSrsReviewState WHERE decisionId = 'canon-crash-1'",
          1,
          reason: 'the canonical mirror is keyed by the canonical id',
        );
        await _expectCount(
          db,
          "SELECT COUNT(*) FROM $kTableSrsReviewState WHERE decisionId = 'dec-b-1'",
          1,
          reason: 'the per-occurrence mirror is keyed by the decision id',
        );
        await _expectNoOrphans(db);

        // Durability: the healed write survives a close and reopen (INV-001).
        await db.close();
        final reopened = await openAppDatabase(databaseFactoryFfi, dbPath);
        await _expectCount(reopened, 'SELECT COUNT(*) FROM $kTableSrsReviewState', 2);
        await _expectCount(reopened, 'SELECT COUNT(*) FROM $kTablePositionKnowledgeState', 1);
        await reopened.close();
      },
    );

    test(
      'torn answer write: a fault between the paired writes leaves nothing behind (INV-002)',
      () async {
        await _seedAnswerablePosition(dbPath);

        final db = await _openFaulty(dbPath);
        final repo = SqliteStudyRepository(db);
        // Statement #1 is the knowledge upsert, #2 the canonical mirror, #3 the
        // per-occurrence mirror. Failing as the third is added is the "fault
        // between the two writes" case: the batch never reaches SQLite.
        db.arm(const FaultPlan(throwAtStatement: 3));
        await expectLater(
          repo.saveAnswerBatch(knowledgeStates: [_answeredKnowledgeState()]),
          throwsA(_injectedFault),
        );

        await _expectCount(db, 'SELECT COUNT(*) FROM $kTablePositionKnowledgeState', 0);
        await _expectCount(db, 'SELECT COUNT(*) FROM $kTableSrsReviewState', 0);
        await _expectNoOrphans(db);

        await repo.saveAnswerBatch(knowledgeStates: [_answeredKnowledgeState()]);
        await _expectCount(db, 'SELECT COUNT(*) FROM $kTablePositionKnowledgeState', 1);
        await _expectCount(db, 'SELECT COUNT(*) FROM $kTableSrsReviewState', 2);
        await _expectNoOrphans(db);

        await db.close();
      },
    );
  });
}

/// A study whose import never touches the fault plan: seed on a plain database
/// first, so the torn write under test starts from a known-complete library.
Future<void> _seedImport(String dbPath, String studyId, {required int chapters}) async {
  final db = await openAppDatabase(databaseFactoryFfi, dbPath);
  await SqliteStudyRepository(db).saveImportResult(_importResult(studyId, chapters: chapters));
  await db.close();
}

/// A minimal answerable position: one decision whose canonical id is
/// `canon-crash-1`, which is what the per-occurrence mirror SELECT matches.
Future<void> _seedAnswerablePosition(String dbPath) async {
  final db = await openAppDatabase(databaseFactoryFfi, dbPath);
  final repo = SqliteStudyRepository(db);
  const studyId = 'b-study';
  final chapter = Chapter.create(studyId: studyId, sourceOrder: 0, title: 'Main');
  await repo.saveStudy(const Study(id: studyId, title: 'Answer Write'));
  await repo.saveChapter(chapter);
  await repo.saveDecision(
    RepertoireDecision(
      id: 'dec-b-1',
      studyId: studyId,
      chapterId: chapter.id,
      nodeId: 'node-b-1',
      expectedMoves: const [RepertoireMove(from: 'e2', to: 'e4', san: 'e4')],
      canonicalStateId: 'canon-crash-1',
    ),
  );
  await db.close();
}

Future<FaultyDatabase> _openFaulty(String dbPath) async =>
    FaultyDatabase(await openAppDatabase(databaseFactoryFfi, dbPath));

/// A chapter count per chapter, not per game: the import writes one chapter
/// row per [Chapter] and one decision row per decision.
ImportResult _importResult(String studyId, {required int chapters}) {
  final built = [
    for (var i = 0; i < chapters; i++)
      Chapter.create(studyId: studyId, sourceOrder: i, title: 'Chapter ${i + 1}'),
  ];
  return ImportResult(
    study: Study(id: studyId, title: 'Crash Study $studyId'),
    chapters: built,
    decisions: [
      for (var i = 0; i < built.length; i++)
        RepertoireDecision(
          id: 'dec-$studyId-$i',
          studyId: studyId,
          chapterId: built[i].id,
          nodeId: 'node-$studyId-$i',
          expectedMoves: const [RepertoireMove(from: 'e2', to: 'e4', san: 'e4')],
        ),
    ],
    errors: const [],
  );
}

/// A graded answer's canonical knowledge state: the shape `saveAnswerBatch`
/// receives from the review service.
PositionKnowledgeState _answeredKnowledgeState() => PositionKnowledgeState(
  canonicalId: 'canon-crash-1',
  firstReviewedAt: DateTime.utc(2026, 10, 19, 12),
  lastReviewedAt: DateTime.utc(2026, 10, 19, 12),
  nextDueAt: DateTime.utc(2026, 10, 20, 12),
  repetitionCount: 1,
  stability: 1.0,
  difficulty: 5.0,
);

Future<int> _scalar(DatabaseExecutor db, String sql) async {
  final rows = await db.rawQuery(sql);
  return (rows.single.values.single! as num).toInt();
}

Future<void> _expectCount(DatabaseExecutor db, String sql, int expected, {String? reason}) async {
  expect(await _scalar(db, sql), expected, reason: reason);
}

Future<void> _expectImportCounts(
  DatabaseExecutor db, {
  required int studies,
  required int chapters,
  required int decisions,
}) async {
  await _expectCount(db, 'SELECT COUNT(*) FROM $kTableSrsStudy', studies);
  await _expectCount(db, 'SELECT COUNT(*) FROM $kTableSrsChapter', chapters);
  await _expectCount(db, 'SELECT COUNT(*) FROM $kTableSrsDecision', decisions);
}

/// The audit's "no orphan row" claim, checked structurally rather than by
/// counting the rows the test happens to remember: a chapter without its
/// study, a decision without its chapter, or a knowledge row without the
/// canonical mirror that a whole-batch write always emits with it.
Future<void> _expectNoOrphans(DatabaseExecutor db) async {
  await _expectCount(
    db,
    'SELECT COUNT(*) FROM $kTableSrsChapter c '
    'LEFT JOIN $kTableSrsStudy s ON s.id = c.studyId WHERE s.id IS NULL',
    0,
    reason: 'a chapter without its study survived',
  );
  await _expectCount(
    db,
    'SELECT COUNT(*) FROM $kTableSrsDecision d '
    'LEFT JOIN $kTableSrsChapter c ON c.id = d.chapterId WHERE c.id IS NULL',
    0,
    reason: 'a decision without its chapter survived',
  );
  await _expectCount(
    db,
    'SELECT COUNT(*) FROM $kTablePositionKnowledgeState k '
    'LEFT JOIN $kTableSrsReviewState r ON r.decisionId = k.canonicalId '
    'WHERE r.decisionId IS NULL',
    0,
    reason: 'a knowledge row without its canonical mirror survived',
  );
}

Future<List<String>> _studyIds(DatabaseExecutor db) async {
  final rows = await db.rawQuery('SELECT id FROM $kTableSrsStudy ORDER BY id');
  return [for (final row in rows) row['id']! as String];
}
