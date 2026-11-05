// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC coverage: INV-002, INV-068.

// Library-rotation diagnostics, 2026-11-05. The owner's headline complaint is
// "it serves the same line over and over while all the others are lost". Two
// candidate mechanisms were tested against the code, not inferred from SQL.
//
// 1. NULL canonical mapping (DB-CANON-GAP). 451 of the 33,784 decisions carry
//    no `canonicalStateId`, and a day's answers left no `position_knowledge_state`
//    row. Their scheduling identity is the decision id itself
//    (`RepertoireDecision.canonicalId => canonicalStateId ?? id`). REFUTED:
//    such a decision is scheduled forward like any other — it leaves the due
//    set, returns when its interval elapses, and advances on the next answer —
//    and the current write path does store its canonical knowledge row.
//
// 2. Dynamic mode with nothing unlocked (DB-DYNAMIC-FREEZE). The owner's stored
//    prefs have `dynamicRepertoireMode: true`; `srs_unlocked_decision` is
//    EMPTY. In that mode a position is queueable only if it is already learned
//    or explicitly unlocked, so a never-seen position is unreachable.
//    CONFIRMED: the library outside the learned set cannot be introduced.

import 'dart:io';

import 'package:chess_srs/src/db/database.dart';
import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/persistence/persistence.dart';
import 'package:chess_srs/src/review/review_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory tempDir;
  late String dbPath;
  final day1 = DateTime.utc(2026, 11, 5, 12);

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('chess_srs_null_canonical_due_');
    dbPath = p.join(tempDir.path, 'null_canonical_due.db');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<({Database db, SqliteStudyRepository repo, RepertoireDecision decision, FixedClock clock})>
  seedNullCanonical() async {
    final db = await openAppDatabase(databaseFactoryFfi, dbPath);
    final repo = SqliteStudyRepository(db);
    final study = Study(id: 's1', title: 'S', createdAt: day1, updatedAt: day1);
    const startFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
    const startKey = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -';
    const childFen = 'rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq - 0 1';
    const childKey = 'rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq -';
    const root = RepertoireNode(
      id: 'n1',
      fen: startFen,
      fenKey: startKey,
      children: [
        RepertoireNode(
          id: 'n2',
          fen: childFen,
          fenKey: childKey,
          incomingMove: RepertoireMove(from: 'd2', to: 'd4', san: 'd4'),
        ),
      ],
    );
    final chapter = Chapter(id: 'c1', studyId: 's1', sourceOrder: 0, root: root, createdAt: day1);
    final decision = RepertoireDecision.create(
      studyId: 's1',
      chapterId: 'c1',
      nodeId: 'n1',
      fenKey: startKey,
      expectedMoves: const [RepertoireMove(from: 'd2', to: 'd4', san: 'd4')],
    );
    await repo.saveStudy(study);
    await repo.saveChapter(chapter);
    await repo.saveDecision(decision);
    // The gap under test: the row carries no canonical mapping.
    await db.rawUpdate('UPDATE srs_decision SET canonicalStateId = NULL WHERE id = ?', [
      decision.id,
    ]);
    return (db: db, repo: repo, decision: decision, clock: FixedClock(day1));
  }

  test('a decision with no canonicalStateId is scheduled forward, not left due', () async {
    final seeded = await seedNullCanonical();
    final repo = seeded.repo;
    final decision = seeded.decision;
    final clock = seeded.clock;
    final service = ReviewService(repository: repo, clock: clock);
    // The state may live in either store; the answer writes both from one batch
    // for a mapped decision, and only the mirror carries the decision id when
    // `canonicalStateId` is NULL.
    Future<ReviewState> stateOf(String id) async {
      final mirror = await repo.getReviewState(id);
      if (mirror != null) return mirror;
      final knowledge = await repo.getPositionKnowledgeState(id);
      if (knowledge == null) fail('no review state or knowledge state was stored for $id');
      return knowledge.toReviewState(id);
    }

    try {
      // Fresh: not owed yet, but the session still queues it for introduction.
      expect(await service.getDueCount(), 0);
      final first = await service.startSession();
      expect(first.currentPrompt?.decision.id, decision.id);

      final answered = await service.submitMove(from: 'd2', to: 'd4');
      expect(answered.isCorrect, isTrue);

      // INV-068: answered, so no longer outstanding on the same day.
      expect(await service.getDueCount(), 0, reason: 'a just-answered position is not due');

      // The canonical knowledge store must carry the answer too, not only the
      // legacy mirror: the owner's library showed a day's answers with no
      // position_knowledge_state row.
      expect(
        await repo.getPositionKnowledgeState(decision.id),
        isNotNull,
        reason: 'a NULL-canonical answer must still write the canonical knowledge store',
      );

      final scheduled = await stateOf(decision.id);
      final nextDue = scheduled.nextDueAt;
      expect(nextDue, isNotNull);
      expect(
        nextDue!.isAfter(day1),
        isTrue,
        reason: 'scheduled into the future, not left at the answer instant',
      );

      // The interval elapses: the position returns, and answering advances it.
      clock.value = nextDue.add(const Duration(minutes: 1));
      expect(
        await service.getDueCount(),
        greaterThanOrEqualTo(1),
        reason: 'a position whose interval elapsed is due again',
      );

      final second = await service.startSession();
      expect(second.currentPrompt?.decision.id, decision.id);
      await service.submitMove(from: 'd2', to: 'd4');

      final advanced = await stateOf(decision.id);
      expect(
        advanced.repetitionCount,
        greaterThan(scheduled.repetitionCount),
        reason: 'a second answer advances the repetition count instead of re-serving the same step',
      );
      expect(advanced.nextDueAt!.isAfter(nextDue), isTrue);
    } finally {
      await seeded.db.close();
    }
  });

  test('dynamic mode with nothing unlocked introduces no fresh position', () async {
    final seeded = await seedNullCanonical();
    final repo = seeded.repo;
    try {
      // The owner's stored prefs: dynamicRepertoireMode true, and an empty
      // srs_unlocked_decision table. In dynamic mode a position is queueable
      // only if it is already learned or explicitly unlocked, so a never-seen
      // position is unreachable — the library outside the learned set is lost.
      final dynamic = ReviewService(
        repository: repo,
        clock: seeded.clock,
        dynamicRepertoireMode: true,
      );
      final dynamicSession = await dynamic.startSession();
      expect(
        dynamicSession.currentPrompt,
        isNull,
        reason: 'with nothing unlocked, dynamic mode has no fresh position to introduce',
      );
      expect(dynamicSession.initialQueueCount, 0);
      expect(
        dynamicSession.dynamicModeWithoutUnlocks,
        isTrue,
        reason: 'the review screen keys its freeze banner off this',
      );

      // One unlock is enough to introduce it again.
      final unlocked = ReviewService(
        repository: repo,
        clock: seeded.clock,
        dynamicRepertoireMode: true,
      );
      final unlockedSession = await unlocked.startSession(
        preloadedUnlockedDecisionIds: {seeded.decision.id},
      );
      expect(unlockedSession.currentPrompt?.decision.id, seeded.decision.id);
      expect(unlockedSession.dynamicModeWithoutUnlocks, isFalse);

      // Without dynamic mode the same position is introduced normally.
      final normal = ReviewService(repository: repo, clock: seeded.clock);
      final normalSession = await normal.startSession();
      expect(normalSession.currentPrompt?.decision.id, seeded.decision.id);
      expect(normalSession.dynamicModeWithoutUnlocks, isFalse);
    } finally {
      await seeded.db.close();
    }
  });
}
