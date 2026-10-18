// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC coverage: INV-001, INV-002, INV-004, INV-005, INV-031, INV-051.

import 'dart:convert';
import 'dart:io';

import 'package:chess_srs/src/db/database.dart';
import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/import/pgn_importer.dart';
import 'package:chess_srs/src/persistence/persistence.dart';
import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Counts per-study chapter fetches so the backfill batching test can tell
/// N sequential fetches apart from one batched fetch. The batched backfill
/// reads chapters with a single `IN` query straight from the database, so it
/// never calls this override; the old N+1 loop called it once per study.
class _BackfillCountingRepository extends SqliteStudyRepository {
  _BackfillCountingRepository(super.db);

  int chapterFetches = 0;

  @override
  Future<List<Chapter>> getChaptersByStudy(String studyId, {Side? side}) {
    chapterFetches++;
    return super.getChaptersByStudy(studyId, side: side);
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  group('SqliteStudyRepository', () {
    late Directory tempDir;
    late String dbPath;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('chess_srs_test_');
      dbPath = p.join(tempDir.path, 'test_persistence.db');
    });

    tearDown(() {
      try {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      } catch (_) {}
    });

    test('durability across restart (close and reopen)', () async {
      // 1. Open database and populate data
      var db = await openAppDatabase(databaseFactoryFfi, dbPath);
      var repo = SqliteStudyRepository(db);

      final now = DateTime.utc(2026, 9, 16, 12, 0, 0);
      final study = Study(
        id: 'study-kid-1',
        title: "King's Indian Defence",
        createdAt: now,
        updatedAt: now,
      );

      const rootNode = RepertoireNode(
        id: 'node-root',
        fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
        fenKey: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -',
        children: [
          RepertoireNode(
            id: 'node-d4',
            fen: 'rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq d3 0 1',
            fenKey: 'rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq -',
            incomingMove: RepertoireMove(from: 'd2', to: 'd4', san: 'd4'),
            children: [
              RepertoireNode(
                id: 'node-nf6',
                fen: 'rnbqkb1r/pppppppp/5n2/8/3P4/8/PPP1PPPP/RNBQKBNR w KQkq - 1 2',
                fenKey: 'rnbqkb1r/pppppppp/5n2/8/3P4/8/PPP1PPPP/RNBQKBNR w KQkq -',
                incomingMove: RepertoireMove(from: 'g8', to: 'f6', san: 'Nf6'),
                comment: 'Main reply against 1. d4',
              ),
            ],
          ),
        ],
      );

      final chapter = Chapter(
        id: 'chapter-1',
        studyId: study.id,
        sourceOrder: 0,
        title: 'Main Line',
        startingFen: rootNode.fen,
        root: rootNode,
        createdAt: now,
      );

      const decision = RepertoireDecision(
        id: 'decision-1',
        studyId: 'study-kid-1',
        chapterId: 'chapter-1',
        nodeId: 'node-d4',
        expectedMoves: [RepertoireMove(from: 'g8', to: 'f6', san: 'Nf6')],
      );

      final reviewState = ReviewState(
        decisionId: decision.id,
        firstReviewedAt: now,
        lastReviewedAt: now,
        nextDueAt: now.add(const Duration(days: 1)),
        repetitionCount: 1,
        lapseCount: 0,
        stability: 1.0,
      );

      final reviewEvent = ReviewEvent(
        decisionId: decision.id,
        when: now,
        result: ReviewResult.correct,
        oldState: ReviewState.initial(decisionId: decision.id),
        newState: reviewState,
      );

      await repo.saveStudy(study);
      await repo.saveChapter(chapter);
      await repo.saveDecision(decision);
      await repo.saveReviewState(reviewState);
      await repo.saveReviewEvent(reviewEvent);

      // 2. Close the database
      await db.close();

      // 3. Reopen from disk
      db = await openAppDatabase(databaseFactoryFfi, dbPath);
      repo = SqliteStudyRepository(db);

      try {
        // 4. Verify Study
        final retrievedStudy = await repo.getStudy(study.id);
        expect(retrievedStudy, isNotNull);
        expect(retrievedStudy!.id, study.id);
        expect(retrievedStudy.title, study.title);
        expect(retrievedStudy.createdAt, study.createdAt);

        final allStudies = await repo.getAllStudies();
        expect(allStudies.length, 1);
        expect(allStudies.first.id, study.id);

        // 5. Verify Chapter & Variation Tree
        final retrievedChapter = await repo.getChapter(chapter.id);
        expect(retrievedChapter, isNotNull);
        expect(retrievedChapter!.id, chapter.id);
        expect(retrievedChapter.title, chapter.title);
        expect(retrievedChapter.root, isNotNull);

        final retrievedRoot = retrievedChapter.root!;
        expect(retrievedRoot.id, rootNode.id);
        expect(retrievedRoot.children.length, 1);

        final childD4 = retrievedRoot.children.first;
        expect(childD4.incomingMove?.san, 'd4');
        expect(childD4.children.length, 1);

        final childNf6 = childD4.children.first;
        expect(childNf6.incomingMove?.san, 'Nf6');
        expect(childNf6.comment, 'Main reply against 1. d4');

        // 6. Verify Decision
        final retrievedDecision = await repo.getDecision(decision.id);
        expect(retrievedDecision, isNotNull);
        expect(retrievedDecision!.id, decision.id);
        expect(retrievedDecision.expectedMoves.first.san, 'Nf6');

        final decisionsByStudy = await repo.getDecisionsByStudy(study.id);
        expect(decisionsByStudy.length, 1);
        expect(decisionsByStudy.first.id, decision.id);

        // 7. Verify ReviewState
        final retrievedState = await repo.getReviewState(decision.id);
        expect(retrievedState, isNotNull);
        expect(retrievedState!.decisionId, decision.id);
        expect(retrievedState.repetitionCount, 1);
        expect(retrievedState.lapseCount, 0);
        expect(retrievedState.stability, 1.0);
        expect(retrievedState.nextDueAt, now.add(const Duration(days: 1)));

        // 8. Verify ReviewEvent
        final events = await repo.getReviewEvents(decision.id);
        expect(events.length, 1);
        expect(events.first.decisionId, decision.id);
        expect(events.first.result, ReviewResult.correct);
        expect(events.first.oldState.repetitionCount, 0);
        expect(events.first.newState.repetitionCount, 1);
      } finally {
        await db.close();
      }
    });

    test('getTallyDecisions projects decision identifiers without decoding moves', () async {
      // SPEC INV-051. PERF-FIX-33: slim decision projection for due summary tallies.
      final db = await openAppDatabase(databaseFactoryFfi, inMemoryDatabasePath);
      final repo = SqliteStudyRepository(db);

      try {
        const study = Study(id: 's_tally', title: 'Tally Study');
        await repo.saveStudy(study);
        final ch = Chapter.create(studyId: study.id, sourceOrder: 0, title: 'Chapter 1');
        await repo.saveChapter(ch);
        final decision = RepertoireDecision.create(
          studyId: study.id,
          chapterId: ch.id,
          nodeId: 'n_tally',
          expectedMoves: const [RepertoireMove(from: 'g1', to: 'f3', san: 'Nf3')],
          canonicalStateId: 'canonical_pos_1',
        );
        await repo.saveDecision(decision);

        final tallies = await repo.getTallyDecisions();
        expect(tallies, hasLength(1));
        final tally = tallies.first;
        expect(tally.id, decision.id);
        expect(tally.studyId, study.id);
        expect(tally.chapterId, ch.id);
        expect(tally.canonicalId, 'canonical_pos_1');
      } finally {
        await db.close();
      }
    });

    test(
      'adaptive review and knowledge state loading handles >800 ids with single-pass scan',
      () async {
        // SPEC INV-051. PERF-FIX-34: adaptive state loading when id set exceeds 800 items.
        final db = await openAppDatabase(databaseFactoryFfi, inMemoryDatabasePath);
        final repo = SqliteStudyRepository(db);

        try {
          final now = DateTime.utc(2026, 10, 15, 12);
          final reviewState = ReviewState(
            decisionId: 'dec_42',
            nextDueAt: now,
            firstReviewedAt: now,
            lastReviewedAt: now,
          );
          await repo.saveReviewState(reviewState);

          final kState = PositionKnowledgeState(
            canonicalId: 'can_42',
            nextDueAt: now,
            firstReviewedAt: now,
            lastReviewedAt: now,
          );
          await repo.savePositionKnowledgeState(kState);

          // Build list of 850 query ids including our target
          final queryDecisionIds = List.generate(
            850,
            (i) => i == 42 ? 'dec_42' : 'dummy_dec_$i',
            growable: false,
          );
          final queryCanonicalIds = List.generate(
            850,
            (i) => i == 42 ? 'can_42' : 'dummy_can_$i',
            growable: false,
          );

          final fetchedReviews = await repo.getReviewStatesByIds(queryDecisionIds);
          expect(fetchedReviews, hasLength(1));
          expect(fetchedReviews.single.decisionId, 'dec_42');

          final fetchedKnowledge = await repo.getKnowledgeStatesByCanonicalIds(queryCanonicalIds);
          expect(fetchedKnowledge, hasLength(1));
          expect(fetchedKnowledge.single.canonicalId, 'can_42');
        } finally {
          await db.close();
        }
      },
    );

    test('timestamps are stored as UTC so a timezone change cannot shift due dates', () async {
      // SPEC INV-002. review-4 C2 / QUALITY §3.2: due instants survive a
      // timezone change — stored form is an absolute instant (UTC), not a
      // wall time.
      final db = await openAppDatabase(databaseFactoryFfi, dbPath);
      final repo = SqliteStudyRepository(db);

      try {
        // Local wall time, no UTC flag — what SystemClock produces.
        final localDue = DateTime(2026, 10, 8, 10);
        final kState = PositionKnowledgeState(
          canonicalId: 'k-utc',
          nextDueAt: localDue,
          stability: 3.0,
        );

        await repo.savePositionKnowledgeState(kState);
        final read = await repo.getPositionKnowledgeState('k-utc');

        // The instant is preserved and the read side is marked UTC.
        expect(read, isNotNull);
        expect(read!.nextDueAt, isNotNull);
        expect(read.nextDueAt!.toUtc().toIso8601String(), localDue.toUtc().toIso8601String());
        expect(read.nextDueAt!.isUtc, isTrue);

        // Review state path round-trips UTC too.
        const rState = ReviewState(decisionId: 'r-utc', nextDueAt: null, repetitionCount: 2);
        await repo.saveReviewState(rState.copyWith(nextDueAt: localDue));
        final rRead = await repo.getReviewState('r-utc');
        expect(rRead!.nextDueAt!.toUtc().toIso8601String(), localDue.toUtc().toIso8601String());
        expect(rRead.nextDueAt!.isUtc, isTrue);

        // Review event path round-trips UTC.
        final baseState = ReviewState(decisionId: 'e-utc', nextDueAt: localDue);
        await repo.saveReviewEvent(
          ReviewEvent(
            decisionId: 'e-utc',
            when: localDue,
            result: ReviewResult.correct,
            oldState: const ReviewState(decisionId: 'e-utc'),
            newState: baseState,
          ),
        );
        final events = await repo.getReviewEvents('e-utc');
        expect(events, hasLength(1));
        expect(events.first.when.toUtc().toIso8601String(), localDue.toUtc().toIso8601String());
        expect(events.first.when.isUtc, isTrue);
      } finally {
        await db.close();
      }
    });

    test('latency survives answer persistence (upsert must not REPLACE columns)', () async {
      // SPEC INV-002. review-4 C1: every persisted answer must preserve latency
      // telemetry — INSERT OR REPLACE must not erase columns the caller did not
      // mention (upsert).
      final db = await openAppDatabase(databaseFactoryFfi, dbPath);
      final repo = SqliteStudyRepository(db);

      try {
        final now = DateTime.utc(2026, 9, 16, 12, 0, 0);

        // Seed two canonical rows carrying latency telemetry the answer path
        // does not know about: the answered position and a side-effect
        // position (auto-traversal contagion lands in the same batch).
        Future<void> seedWithLatency(String canonicalId) async {
          await db.insert(kTablePositionKnowledgeState, {
            'canonicalId': canonicalId,
            'firstReviewedAt': now.toIso8601String(),
            'lastReviewedAt': now.toIso8601String(),
            'nextDueAt': now.toIso8601String(),
            'repetitionCount': 3,
            'lapseCount': 1,
            'stability': 10.0,
            'difficulty': 5.0,
            'latencyEmaMs': 1234.5,
            'latencySampleCount': 7,
            'lastExposedAt': now.toIso8601String(),
          });
        }

        await seedWithLatency('k-answered');
        await seedWithLatency('k-side-effect');

        // A normal answer: ReviewState carries no latency fields, so the
        // written rows cannot mention them.
        const answered = ReviewState(decisionId: 'k-answered', repetitionCount: 9, stability: 42.0);
        const sideEffect = ReviewState(decisionId: 'k-side-effect', repetitionCount: 4);

        await repo.saveAnswerBatch(
          knowledgeStates: [
            PositionKnowledgeState.fromReviewState(answered, canonicalId: 'k-answered'),
            PositionKnowledgeState.fromReviewState(
              sideEffect,
              canonicalId: 'k-side-effect',
            ).copyWith(lastExposedAt: now),
          ],
        );

        final readAnswered = await repo.getPositionKnowledgeState('k-answered');
        final readSideEffect = await repo.getPositionKnowledgeState('k-side-effect');

        // Latency columns the caller did not mention survive the write.
        expect(readAnswered?.latencyEmaMs, 1234.5);
        expect(readAnswered?.latencySampleCount, 7);
        expect(readSideEffect?.latencyEmaMs, 1234.5);
        expect(readSideEffect?.latencySampleCount, 7);

        // The columns that were mentioned do update.
        expect(readAnswered?.repetitionCount, 9);
        expect(readAnswered?.stability, 42.0);
        expect(readSideEffect?.lastExposedAt, now);
      } finally {
        await db.close();
      }
    });

    test('deleteStudy cascades and cleans up chapters, decisions, states, and events', () async {
      final db = await openAppDatabase(databaseFactoryFfi, dbPath);
      final repo = SqliteStudyRepository(db);

      try {
        final now = DateTime.utc(2026, 9, 16, 12, 0, 0);
        final study = Study(id: 'study-delete', title: 'To Delete', createdAt: now, updatedAt: now);
        final chapter = Chapter(id: 'ch-del', studyId: study.id, sourceOrder: 0);
        const decision = RepertoireDecision(
          id: 'dec-del',
          studyId: 'study-delete',
          chapterId: 'ch-del',
          nodeId: 'n1',
          expectedMoves: [],
        );
        const state = ReviewState(decisionId: 'dec-del');
        final event = ReviewEvent(
          decisionId: 'dec-del',
          when: now,
          result: ReviewResult.correct,
          oldState: state,
          newState: state,
        );

        await repo.saveStudy(study);
        await repo.saveChapter(chapter);
        await repo.saveDecision(decision);
        await repo.saveReviewState(state);
        await repo.saveReviewEvent(event);

        expect(await repo.getStudy(study.id), isNotNull);
        expect(await repo.getChapter(chapter.id), isNotNull);
        expect(await repo.getDecision(decision.id), isNotNull);
        expect(await repo.getReviewState(decision.id), isNotNull);
        expect((await repo.getReviewEvents(decision.id)).length, 1);

        await repo.deleteStudy(study.id);

        expect(await repo.getStudy(study.id), isNull);
        expect(await repo.getChapter(chapter.id), isNull);
        expect(await repo.getDecision(decision.id), isNull);
        expect(await repo.getReviewState(decision.id), isNull);
        expect(await repo.getReviewEvents(decision.id), isEmpty);
      } finally {
        await db.close();
      }
    });

    test(
      'deleteChapter removes the review events and knowledge state stored under the canonical id',
      () async {
        // The app records a review event against the decision's *canonical* id, so a deletion that
        // only matches the per-occurrence id removes nothing at all.
        final db = await openAppDatabase(databaseFactoryFfi, dbPath);
        final repo = SqliteStudyRepository(db);

        try {
          final now = DateTime.utc(2026, 9, 16, 12);
          final study = Study(id: 's-ch-del', title: 'S', createdAt: now, updatedAt: now);
          final chapter = Chapter(id: 'ch-del-1', studyId: study.id, sourceOrder: 0);
          const decision = RepertoireDecision(
            id: 'occ-1',
            studyId: 's-ch-del',
            chapterId: 'ch-del-1',
            nodeId: 'n1',
            expectedMoves: [],
            canonicalStateId: 'canon-1',
          );
          const state = ReviewState(decisionId: 'canon-1', repetitionCount: 3);
          final event = ReviewEvent(
            decisionId: 'canon-1',
            when: now,
            result: ReviewResult.correct,
            oldState: state,
            newState: state,
          );

          await repo.saveStudy(study);
          await repo.saveChapter(chapter);
          await repo.saveDecision(decision);
          await repo.saveReviewState(state);
          await repo.saveReviewEvent(event);

          expect((await repo.getReviewEvents('canon-1')).length, 1);
          expect(await repo.getReviewState('canon-1'), isNotNull);

          await repo.deleteChapter(chapter.id);

          expect(
            await repo.getReviewEvents('canon-1'),
            isEmpty,
            reason: 'the event was stored under the canonical id and must be found there',
          );
          expect(
            await repo.getReviewState('canon-1'),
            isNull,
            reason: 'nothing references this position any more',
          );
          expect(await repo.getDecision('occ-1'), isNull);
        } finally {
          await db.close();
        }
      },
    );

    test('deleteStudy removes review events stored under the canonical id', () async {
      final db = await openAppDatabase(databaseFactoryFfi, dbPath);
      final repo = SqliteStudyRepository(db);

      try {
        final now = DateTime.utc(2026, 9, 16, 12);
        final study = Study(id: 's-canon-del', title: 'S', createdAt: now, updatedAt: now);
        final chapter = Chapter(id: 'ch-canon-del', studyId: study.id, sourceOrder: 0);
        const decision = RepertoireDecision(
          id: 'occ-2',
          studyId: 's-canon-del',
          chapterId: 'ch-canon-del',
          nodeId: 'n1',
          expectedMoves: [],
          canonicalStateId: 'canon-2',
        );
        const state = ReviewState(decisionId: 'canon-2');
        final event = ReviewEvent(
          decisionId: 'canon-2',
          when: now,
          result: ReviewResult.correct,
          oldState: state,
          newState: state,
        );

        await repo.saveStudy(study);
        await repo.saveChapter(chapter);
        await repo.saveDecision(decision);
        await repo.saveReviewState(state);
        await repo.saveReviewEvent(event);

        expect((await repo.getReviewEvents('canon-2')).length, 1);

        await repo.deleteStudy(study.id);

        expect(
          await repo.getReviewEvents('canon-2'),
          isEmpty,
          reason: 'the event was stored under the canonical id and must be found there',
        );
        expect(await repo.getReviewState('canon-2'), isNull);
      } finally {
        await db.close();
      }
    });

    test('deleteChapter keeps canonical state another chapter still owns', () async {
      final db = await openAppDatabase(databaseFactoryFfi, dbPath);
      final repo = SqliteStudyRepository(db);

      try {
        final now = DateTime.utc(2026, 9, 16, 12);
        final study = Study(id: 's-shared', title: 'S', createdAt: now, updatedAt: now);
        final chapterA = Chapter(id: 'ch-a', studyId: study.id, sourceOrder: 0);
        final chapterB = Chapter(id: 'ch-b', studyId: study.id, sourceOrder: 1);

        // The same position reached twice: a transposition inside one study.
        const decisionA = RepertoireDecision(
          id: 'occ-a',
          studyId: 's-shared',
          chapterId: 'ch-a',
          nodeId: 'n1',
          expectedMoves: [],
          canonicalStateId: 'canon-shared',
        );
        const decisionB = RepertoireDecision(
          id: 'occ-b',
          studyId: 's-shared',
          chapterId: 'ch-b',
          nodeId: 'n9',
          expectedMoves: [],
          canonicalStateId: 'canon-shared',
        );
        const state = ReviewState(decisionId: 'canon-shared', repetitionCount: 5);

        await repo.saveStudy(study);
        await repo.saveChapter(chapterA);
        await repo.saveChapter(chapterB);
        await repo.saveDecision(decisionA);
        await repo.saveDecision(decisionB);
        await repo.saveReviewState(state);

        await repo.deleteChapter(chapterA.id);

        expect(
          await repo.getReviewState('canon-shared'),
          isNotNull,
          reason: 'chapter B still asks this question, so its memory must survive',
        );
        expect(await repo.getDecision('occ-b'), isNotNull);
      } finally {
        await db.close();
      }
    });

    test('deleteStudy keeps canonical rows another study still owns', () async {
      // SPEC INV-031. The shared-canonical guard (studyId != ?) is what keeps a position
      // alive when one of its studies goes away. Deleting study A must not take the
      // canonical row, its mirror, or study B's decision with it.
      final db = await openAppDatabase(databaseFactoryFfi, dbPath);
      final repo = SqliteStudyRepository(db);

      try {
        final now = DateTime.utc(2026, 9, 16, 12);
        final studyA = Study(id: 's-a', title: 'A', createdAt: now, updatedAt: now);
        final studyB = Study(id: 's-b', title: 'B', createdAt: now, updatedAt: now);
        final chapterA = Chapter(id: 'ch-x', studyId: 's-a', sourceOrder: 0);
        final chapterB = Chapter(id: 'ch-y', studyId: 's-b', sourceOrder: 0);

        // The same position learned in two studies: a transposition across libraries.
        const decisionA = RepertoireDecision(
          id: 'occ-x',
          studyId: 's-a',
          chapterId: 'ch-x',
          nodeId: 'n1',
          expectedMoves: [],
          canonicalStateId: 'canon-xshared',
        );
        const decisionB = RepertoireDecision(
          id: 'occ-y',
          studyId: 's-b',
          chapterId: 'ch-y',
          nodeId: 'n9',
          expectedMoves: [],
          canonicalStateId: 'canon-xshared',
        );
        const state = ReviewState(decisionId: 'canon-xshared', repetitionCount: 5);

        await repo.saveStudy(studyA);
        await repo.saveStudy(studyB);
        await repo.saveChapter(chapterA);
        await repo.saveChapter(chapterB);
        await repo.saveDecision(decisionA);
        await repo.saveDecision(decisionB);
        await repo.saveReviewState(state);
        await repo.savePositionKnowledgeState(
          const PositionKnowledgeState(canonicalId: 'canon-xshared', stability: 3.0),
        );

        await repo.deleteStudy(studyA.id);

        expect(
          await repo.getPositionKnowledgeState('canon-xshared'),
          isNotNull,
          reason: 'study B still reaches this position, so the canonical row must survive',
        );
        expect(
          await repo.getReviewState('canon-xshared'),
          isNotNull,
          reason: 'study B still asks this question, so its memory must survive',
        );
        expect(await repo.getDecision('occ-y'), isNotNull);
        expect(await repo.getDecision('occ-x'), isNull);
      } finally {
        await db.close();
      }
    });

    test('concurrent imports of the same PGN do not both land', () async {
      // The duplicate check (getStudyByPgnHash) and the write live in different places: the
      // controller asks "already imported?" and then calls saveImportResult. Two imports that
      // start together both ask before either writes, both see no match, and both write.
      //
      // They do not overwrite each other — chapters and decisions get fresh ids on every import,
      // so ConflictAlgorithm.replace has nothing to match on. They ACCUMULATE: the user ends up
      // with the same repertoire stored twice, under one study, and the duplicate is invisible
      // because there is only one study row.
      final db = await openAppDatabase(databaseFactoryFfi, dbPath);
      final repo = SqliteStudyRepository(db);

      try {
        const hash = 'same-file-twice';
        final now = DateTime.utc(2026, 9, 16, 12, 0, 0);

        ImportResult build(String studyId) {
          // The decision points at the chapter in this import, not a literal id that nothing
          // ever stored — the row was an orphan from the moment it was written.
          final chapter = Chapter.create(studyId: studyId, sourceOrder: 0, title: 'Main');
          return ImportResult(
            study: Study(
              id: studyId,
              title: 'Italian',
              pgnHash: hash,
              createdAt: now,
              updatedAt: now,
            ),
            chapters: [chapter],
            decisions: [
              RepertoireDecision(
                id: 'dec-$studyId-1',
                studyId: studyId,
                chapterId: chapter.id,
                nodeId: 'node-1',
                expectedMoves: const [RepertoireMove(from: 'e2', to: 'e4', san: 'e4')],
              ),
            ],
            errors: const [],
          );
        }

        await Future.wait([
          repo.saveImportResult(build('import-a')),
          repo.saveImportResult(build('import-b')),
        ]);

        final stored = await repo.getAllStudies();
        final withHash = stored.where((s) => s.pgnHash == hash).toList();
        expect(
          withHash,
          hasLength(1),
          reason: 'the same file must end up in the library once, not twice',
        );

        // Whichever import won, its content is intact and the loser's is gone entirely. A torn
        // or half-written copy would show up as one study with the other's decisions inside it.
        final decisions = await repo.getDecisionsByStudy(withHash.single.id);
        expect(
          decisions,
          hasLength(1),
          reason: 'the stored copy must be a whole import, not a mixture of the two',
        );
        expect(decisions.single.id, endsWith('-1'));
      } finally {
        await db.close();
      }
    });

    test('the in-flight dedupe does not collapse the two sides of one tree', () async {
      // The same PGN imported as White and as Black is two studies on purpose: different
      // questions, different SRS memory, and two separate repertoire buttons in the library. They
      // share a pgnHash, so a dedupe check matching on the hash alone drops the second one and the
      // user gets a colour switch that does nothing.
      final db = await openAppDatabase(databaseFactoryFfi, dbPath);
      final repo = SqliteStudyRepository(db);

      try {
        const hash = 'one-tree-both-sides';
        final now = DateTime.utc(2026, 9, 16, 12, 0, 0);

        ImportResult build(String studyId, Side side) {
          final chapter = Chapter.create(
            studyId: studyId,
            sourceOrder: 0,
            title: 'Main',
            orientation: side,
          );
          return ImportResult(
            study: Study(
              id: studyId,
              title: 'Italian',
              pgnHash: hash,
              createdAt: now,
              updatedAt: now,
            ),
            chapters: [chapter],
            decisions: [
              RepertoireDecision(
                id: 'dec-$studyId',
                studyId: studyId,
                chapterId: chapter.id,
                nodeId: 'node-$studyId',
                expectedMoves: const [RepertoireMove(from: 'e2', to: 'e4', san: 'e4')],
              ),
            ],
            errors: const [],
          );
        }

        await repo.saveImportResult(build('study-white', Side.white));
        await repo.saveImportResult(build('study-black', Side.black));

        expect(await repo.getAllStudies(), hasLength(2), reason: 'both sides must be stored');
        expect(await repo.getDecisionsByStudy('study-white'), hasLength(1));
        expect(await repo.getDecisionsByStudy('study-black'), hasLength(1));
      } finally {
        await db.close();
      }
    });

    test('a mixed-side import landing in flight does not duplicate the study (INV-003)', () async {
      // SPEC INV-003. The in-flight re-check filtered on the first chapter's orientation, which
      // no stored mixed-side study can satisfy: importing the same mixed file twice stored it
      // twice. Like getStudyByPgnHash, a mixed import carries no side to filter on.
      final db = await openAppDatabase(databaseFactoryFfi, dbPath);
      final repo = SqliteStudyRepository(db);

      try {
        const hash = 'mixed-file-twice';
        final now = DateTime.utc(2026, 9, 16, 12, 0, 0);

        ImportResult build(String studyId) {
          final white = Chapter.create(
            studyId: studyId,
            sourceOrder: 0,
            title: 'White',
            orientation: Side.white,
          );
          final black = Chapter.create(
            studyId: studyId,
            sourceOrder: 1,
            title: 'Black',
            orientation: Side.black,
          );
          return ImportResult(
            study: Study(
              id: studyId,
              title: 'Both sides',
              pgnHash: hash,
              createdAt: now,
              updatedAt: now,
            ),
            chapters: [white, black],
            decisions: [
              RepertoireDecision(
                id: 'dec-$studyId-1',
                studyId: studyId,
                chapterId: white.id,
                nodeId: 'node-1',
                expectedMoves: const [RepertoireMove(from: 'e2', to: 'e4', san: 'e4')],
              ),
              RepertoireDecision(
                id: 'dec-$studyId-2',
                studyId: studyId,
                chapterId: black.id,
                nodeId: 'node-2',
                expectedMoves: const [RepertoireMove(from: 'e7', to: 'e5', san: 'e5')],
              ),
            ],
            errors: const [],
          );
        }

        await repo.saveImportResult(build('import-a'));
        await repo.saveImportResult(build('import-b'));

        final withHash = (await repo.getAllStudies()).where((s) => s.pgnHash == hash).toList();
        expect(
          withHash,
          hasLength(1),
          reason:
              'a mixed-side file must be stored once; a re-check keyed off the first '
              'chapter alone lets the same file land twice',
        );
      } finally {
        await db.close();
      }
    });

    test(
      'a failed mirror write rolls back the canonical state instead of leaving it torn',
      () async {
        // savePositionKnowledgeState writes the canonical row and then one mirror per decision
        // sharing that canonical id. If those writes are not in a transaction, a failure partway
        // through leaves the canonical row claiming the position was reviewed while some mirrors
        // still say otherwise — which is exactly the mismatch that re-presents or skips positions
        // on the next session.
        //
        // The failure is forced with a trigger on the mirror row rather than by killing the
        // process, so the test is deterministic and asserts the rollback rather than the
        // interruption that would cause it.
        final db = await openAppDatabase(databaseFactoryFfi, dbPath);
        final repo = SqliteStudyRepository(db);

        try {
          final now = DateTime.utc(2026, 9, 16, 12, 0, 0);
          final study = Study(id: 'study-torn', title: 'Torn', createdAt: now, updatedAt: now);
          final chapter = Chapter(id: 'ch-torn', studyId: study.id, sourceOrder: 0);

          const canonicalId = 'torn-pos-canonical';
          const firstDecision = RepertoireDecision(
            id: 'dec-torn-1',
            studyId: 'study-torn',
            chapterId: 'ch-torn',
            nodeId: 'n1',
            expectedMoves: [],
            canonicalStateId: canonicalId,
          );
          const secondDecision = RepertoireDecision(
            id: 'dec-torn-2',
            studyId: 'study-torn',
            chapterId: 'ch-torn',
            nodeId: 'n2',
            expectedMoves: [],
            canonicalStateId: canonicalId,
          );

          await repo.saveStudy(study);
          await repo.saveChapter(chapter);
          await repo.saveDecision(firstDecision);
          await repo.saveDecision(secondDecision);

          // Fail on the second mirror only: the canonical row and the first mirror have
          // already been written by the time this fires.
          await db.execute('''
            CREATE TRIGGER fail_second_mirror BEFORE INSERT ON $kTableSrsReviewState
            WHEN NEW.decisionId = 'dec-torn-2'
            BEGIN SELECT RAISE(ABORT, 'forced mirror failure'); END
          ''');

          await expectLater(
            repo.savePositionKnowledgeState(
              const PositionKnowledgeState(
                canonicalId: canonicalId,
                repetitionCount: 5,
                stability: 100.0,
              ),
            ),
            throwsA(isA<DatabaseException>()),
            reason: 'the forced failure is the point; the write must not silently succeed',
          );

          expect(
            await repo.getPositionKnowledgeState(canonicalId),
            isNull,
            reason:
                'the canonical row survived a write whose mirror failed, so the next session '
                'reads a position as reviewed while its mirrors disagree',
          );
          expect(await repo.getReviewState(canonicalId), isNull);
          expect(await repo.getReviewState(firstDecision.id), isNull);
        } finally {
          await db.close();
        }
      },
    );

    test(
      'deleteStudy preserves shared canonical knowledge states referenced by another study',
      () async {
        final db = await openAppDatabase(databaseFactoryFfi, dbPath);
        final repo = SqliteStudyRepository(db);

        try {
          final now = DateTime.utc(2026, 9, 16, 12, 0, 0);
          final studyA = Study(id: 'study-a', title: 'Study A', createdAt: now, updatedAt: now);
          final chapterA = Chapter(id: 'ch-a', studyId: studyA.id, sourceOrder: 0);
          final studyB = Study(id: 'study-b', title: 'Study B', createdAt: now, updatedAt: now);
          final chapterB = Chapter(id: 'ch-b', studyId: studyB.id, sourceOrder: 0);

          const sharedCanonicalId = 'shared-pos-canonical';
          const unsharedCanonicalId = 'unshared-pos-canonical';

          const decA1 = RepertoireDecision(
            id: 'dec-a1',
            studyId: 'study-a',
            chapterId: 'ch-a',
            nodeId: 'na1',
            expectedMoves: [],
            canonicalStateId: sharedCanonicalId,
          );
          const decA2 = RepertoireDecision(
            id: 'dec-a2',
            studyId: 'study-a',
            chapterId: 'ch-a',
            nodeId: 'na2',
            expectedMoves: [],
            canonicalStateId: unsharedCanonicalId,
          );
          const decB1 = RepertoireDecision(
            id: 'dec-b1',
            studyId: 'study-b',
            chapterId: 'ch-b',
            nodeId: 'nb1',
            expectedMoves: [],
            canonicalStateId: sharedCanonicalId,
          );

          const sharedKState = PositionKnowledgeState(
            canonicalId: sharedCanonicalId,
            repetitionCount: 5,
            stability: 100.0,
          );
          const unsharedKState = PositionKnowledgeState(
            canonicalId: unsharedCanonicalId,
            repetitionCount: 2,
            stability: 40.0,
          );

          await repo.saveStudy(studyA);
          await repo.saveChapter(chapterA);
          await repo.saveDecision(decA1);
          await repo.saveDecision(decA2);

          await repo.saveStudy(studyB);
          await repo.saveChapter(chapterB);
          await repo.saveDecision(decB1);

          await repo.savePositionKnowledgeState(sharedKState);
          await repo.savePositionKnowledgeState(unsharedKState);

          expect(await repo.getPositionKnowledgeState(sharedCanonicalId), isNotNull);
          expect(await repo.getPositionKnowledgeState(unsharedCanonicalId), isNotNull);

          // Delete study A
          await repo.deleteStudy(studyA.id);

          // Study A decisions are deleted
          expect(await repo.getDecision(decA1.id), isNull);
          expect(await repo.getDecision(decA2.id), isNull);

          // Unshared canonical state should be deleted
          expect(await repo.getPositionKnowledgeState(unsharedCanonicalId), isNull);

          // Shared canonical state MUST be preserved because Study B still references it
          final preserved = await repo.getPositionKnowledgeState(sharedCanonicalId);
          expect(preserved, isNotNull);
          expect(preserved!.canonicalId, sharedCanonicalId);
          expect(preserved.repetitionCount, 5);
        } finally {
          await db.close();
        }
      },
    );

    test(
      'deleteStudy preserves shared canonical events and mirrors referenced by another study',
      () async {
        final db = await openAppDatabase(databaseFactoryFfi, dbPath);
        final repo = SqliteStudyRepository(db);

        try {
          final now = DateTime.utc(2026, 9, 16, 12, 0, 0);
          final studyA = Study(id: 'study-a', title: 'Study A', createdAt: now, updatedAt: now);
          final chapterA = Chapter(id: 'ch-a', studyId: studyA.id, sourceOrder: 0);
          final studyB = Study(id: 'study-b', title: 'Study B', createdAt: now, updatedAt: now);
          final chapterB = Chapter(id: 'ch-b', studyId: studyB.id, sourceOrder: 0);

          const sharedCanonicalId = 'shared-pos-canonical';
          const decA = RepertoireDecision(
            id: 'dec-a',
            studyId: 'study-a',
            chapterId: 'ch-a',
            nodeId: 'na',
            expectedMoves: [],
            canonicalStateId: sharedCanonicalId,
          );
          const decB = RepertoireDecision(
            id: 'dec-b',
            studyId: 'study-b',
            chapterId: 'ch-b',
            nodeId: 'nb',
            expectedMoves: [],
            canonicalStateId: sharedCanonicalId,
          );
          const sharedState = ReviewState(decisionId: sharedCanonicalId, repetitionCount: 3);
          final event = ReviewEvent(
            decisionId: sharedCanonicalId,
            when: now,
            result: ReviewResult.correct,
            oldState: const ReviewState(decisionId: sharedCanonicalId),
            newState: sharedState,
          );

          await repo.saveStudy(studyA);
          await repo.saveChapter(chapterA);
          await repo.saveDecision(decA);
          await repo.saveStudy(studyB);
          await repo.saveChapter(chapterB);
          await repo.saveDecision(decB);
          await repo.saveReviewState(sharedState);
          await repo.saveReviewEvent(event);

          await repo.deleteStudy(studyA.id);

          // Study B still owns the position: its history and mirror survive.
          expect(await repo.getDecision(decB.id), isNotNull);
          expect(await repo.getReviewState(sharedCanonicalId), isNotNull);
          expect(await repo.getReviewEvents(sharedCanonicalId), hasLength(1));
        } finally {
          await db.close();
        }
      },
    );

    test('savePositionTree updates tree independently of chapter metadata', () async {
      final db = await openAppDatabase(databaseFactoryFfi, dbPath);
      final repo = SqliteStudyRepository(db);

      try {
        final now = DateTime.utc(2026, 9, 16, 12, 0, 0);
        final study = Study(id: 'study-tree', title: 'Tree Study', createdAt: now, updatedAt: now);
        final chapter = Chapter(
          id: 'ch-tree',
          studyId: study.id,
          sourceOrder: 1,
          title: 'Original Title',
          createdAt: now,
        );

        await repo.saveStudy(study);
        await repo.saveChapter(chapter);

        expect(await repo.getPositionTree(chapter.id), isNull);

        const tree = RepertoireNode(
          id: 'node-root-new',
          fen: 'startpos',
          fenKey: 'startkey',
          comment: 'Root comment',
        );

        await repo.savePositionTree(chapter.id, tree);

        final loadedTree = await repo.getPositionTree(chapter.id);
        expect(loadedTree, isNotNull);
        expect(loadedTree!.id, 'node-root-new');
        expect(loadedTree.comment, 'Root comment');

        // Chapter title and metadata remained intact
        final updatedChapter = await repo.getChapter(chapter.id);
        expect(updatedChapter!.title, 'Original Title');
        expect(updatedChapter.sourceOrder, 1);
      } finally {
        await db.close();
      }
    });

    test('study isActive toggle and persistence', () async {
      final db = await openAppDatabase(databaseFactoryFfi, dbPath);
      final repo = SqliteStudyRepository(db);

      try {
        const study1 = Study(id: 's1', title: 'Active Study', isActive: true);
        const study2 = Study(id: 's2', title: 'Inactive Study', isActive: false);

        await repo.saveStudy(study1);
        await repo.saveStudy(study2);

        expect((await repo.getAllStudies()).length, 2);
        final active = await repo.getActiveStudies();
        expect(active.length, 1);
        expect(active.first.id, 's1');

        // Toggle s1 to inactive and s2 to active
        await repo.updateStudyActive('s1', false);
        await repo.updateStudyActive('s2', true);

        final updatedActive = await repo.getActiveStudies();
        expect(updatedActive.length, 1);
        expect(updatedActive.first.id, 's2');

        // Restart durability: reopen database from disk
        await db.close();
        final reopenedDb = await openAppDatabase(databaseFactoryFfi, dbPath);
        final reopenedRepo = SqliteStudyRepository(reopenedDb);
        try {
          final loadedS1 = await reopenedRepo.getStudy('s1');
          final loadedS2 = await reopenedRepo.getStudy('s2');
          expect(loadedS1!.isActive, isFalse);
          expect(loadedS2!.isActive, isTrue);
        } finally {
          await reopenedDb.close();
        }
      } finally {
        if (db.isOpen) await db.close();
      }
    });

    test('getChapterOpenings retrieves map of chapter IDs to opening families', () async {
      final db = await openAppDatabase(databaseFactoryFfi, dbPath);
      final repo = SqliteStudyRepository(db);

      try {
        const study = Study(id: 's1', title: 'Openings Study');
        await repo.saveStudy(study);

        final ch1 = Chapter.create(studyId: 's1', sourceOrder: 0, opening: 'Ruy Lopez');
        final ch2 = Chapter.create(studyId: 's1', sourceOrder: 1, opening: 'Sicilian Defense');
        final ch3 = Chapter.create(studyId: 's1', sourceOrder: 2, opening: null);

        await repo.saveChapters([ch1, ch2, ch3]);

        final openings = await repo.getChapterOpenings();
        expect(openings[ch1.id], 'Ruy Lopez');
        expect(openings[ch2.id], 'Sicilian Defense');
        expect(openings[ch3.id], isNull);
      } finally {
        await db.close();
      }
    });

    test('getStudyByPgnHash retrieves study by SHA-256 fingerprint', () async {
      final db = await openAppDatabase(databaseFactoryFfi, dbPath);
      final repo = SqliteStudyRepository(db);

      try {
        const hash = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
        const study = Study(id: 's_hashed', title: 'Hashed Study', pgnHash: hash);
        await repo.saveStudy(study);

        final found = await repo.getStudyByPgnHash(hash);
        expect(found, isNotNull);
        expect(found!.id, 's_hashed');
        expect(found.title, 'Hashed Study');
        expect(found.pgnHash, hash);

        final notFound = await repo.getStudyByPgnHash('non_existent_hash');
        expect(notFound, isNull);
      } finally {
        await db.close();
      }
    });

    test('pgnHash backfill is batched, not N+1', () async {
      // SPEC INV-051: bulk lookups stay bounded. Backfilling N studies whose
      // pgnHash predates the column must not issue N sequential chapter
      // fetches plus N sequential updates.
      final db = await openAppDatabase(databaseFactoryFfi, dbPath);
      final repo = _BackfillCountingRepository(db);

      const firstMoves = ['e4', 'd4', 'c4', 'Nf3', 'e3', 'd3', 'c3', 'g3', 'b3', 'a3', 'h3', 'f4'];
      final studyIds = <String>[];
      late final String targetHash;
      late final String targetId;
      try {
        for (var i = 0; i < firstMoves.length; i++) {
          final result = importPgn(
            '[Orientation "white"]\n\n1. ${firstMoves[i]} *',
            studyTitle: 'Book $i',
            repertoireSide: Side.white,
          );
          expect(result.errors, isEmpty);
          await repo.saveStudy(result.study);
          for (final chapter in result.chapters) {
            await repo.saveChapter(chapter);
          }
          studyIds.add(result.study.id);
          if (i == firstMoves.length - 1) {
            targetId = result.study.id;
            targetHash = computeRepertoireTreeHash(result.chapters);
          }
        }

        // Pretend every study was stored before the pgnHash column existed.
        await db.update(kTableSrsStudy, {'pgnHash': null});

        final found = await repo.getStudyByPgnHash(targetHash, forSide: Side.white);

        expect(found?.id, targetId);
        expect(
          repo.chapterFetches,
          0,
          reason:
              'the backfill fetched chapters per study instead of in one batch '
              '(${repo.chapterFetches} fetches for ${firstMoves.length} studies)',
        );
        for (final id in studyIds) {
          expect(
            (await repo.getStudy(id))?.pgnHash,
            isNotNull,
            reason: 'study $id was not backfilled',
          );
        }
        // The side filter survives batching: nothing here trains Black.
        expect(await repo.getStudyByPgnHash(targetHash, forSide: Side.black), isNull);
      } finally {
        await db.close();
      }
    });

    test('getReviewStatesByIds retrieves only review states for specified IDs', () async {
      final db = await openAppDatabase(databaseFactoryFfi, dbPath);
      final repo = SqliteStudyRepository(db);

      try {
        const s1 = ReviewState(decisionId: 'dec-1', repetitionCount: 1);
        const s2 = ReviewState(decisionId: 'dec-2', repetitionCount: 2);
        const s3 = ReviewState(decisionId: 'dec-3', repetitionCount: 3);
        await repo.saveReviewStates([s1, s2, s3]);

        final queried = await repo.getReviewStatesByIds(['dec-1', 'dec-3']);
        expect(queried.length, 2);
        expect(queried.map((s) => s.decisionId).toSet(), equals({'dec-1', 'dec-3'}));

        final emptyQuery = await repo.getReviewStatesByIds([]);
        expect(emptyQuery, isEmpty);
      } finally {
        await db.close();
      }
    });

    test(
      'savePositionKnowledgeState and getPositionKnowledgeState roundtrips canonical state',
      () async {
        final db = await openAppDatabase(databaseFactoryFfi, dbPath);
        final repo = SqliteStudyRepository(db);

        try {
          final now = DateTime.utc(2026, 9, 18, 12);
          final kState = PositionKnowledgeState(
            canonicalId: 'canonical_test_1',
            firstReviewedAt: now,
            lastReviewedAt: now,
            nextDueAt: now.add(const Duration(days: 3)),
            repetitionCount: 4,
            lapseCount: 1,
            stability: 259200000.0,
            difficulty: 4.8,
            latencyEmaMs: 1420.5,
            latencySampleCount: 5,
            lastExposedAt: now.subtract(const Duration(hours: 5)),
          );

          await repo.savePositionKnowledgeState(kState);

          final loaded = await repo.getPositionKnowledgeState('canonical_test_1');
          expect(loaded, isNotNull);
          expect(loaded!.canonicalId, 'canonical_test_1');
          expect(loaded.repetitionCount, 4);
          expect(loaded.lapseCount, 1);
          expect(loaded.stability, 259200000.0);
          expect(loaded.difficulty, 4.8);
          expect(loaded.latencyEmaMs, 1420.5);
          expect(loaded.latencySampleCount, 5);
          expect(loaded.lastExposedAt, now.subtract(const Duration(hours: 5)));

          // Also synchronized to legacy review_state
          final legacy = await repo.getReviewState('canonical_test_1');
          expect(legacy, isNotNull);
          expect(legacy!.repetitionCount, 4);
        } finally {
          await db.close();
        }
      },
    );

    // SPEC INV-028. The once-per-calendar-day exposure cap only holds across an app restart if the
    // last grant is stored. saveAnswerBatch is the write path a real answer takes, and it uses
    // INSERT OR REPLACE, so a column the caller omits is erased rather than preserved.
    test(
      'saveAnswerBatch round-trips lastExposedAt so the daily exposure cap survives a restart',
      () async {
        final db = await openAppDatabase(databaseFactoryFfi, dbPath);
        final repo = SqliteStudyRepository(db);

        try {
          final now = DateTime.utc(2026, 9, 18, 12);
          final exposed = now.subtract(const Duration(hours: 9));
          final firstWrite = <PositionKnowledgeState>[
            PositionKnowledgeState(
              canonicalId: 'canonical_exposed',
              firstReviewedAt: now,
              nextDueAt: now.add(const Duration(days: 4)),
              repetitionCount: 3,
              stability: 345600000.0,
              difficulty: 4.2,
              lastExposedAt: exposed,
            ),
          ];
          await repo.saveAnswerBatch(knowledgeStates: firstWrite);

          final loaded = await repo.getPositionKnowledgeState('canonical_exposed');
          expect(loaded, isNotNull);
          expect(loaded!.lastExposedAt, exposed);

          // A later answer carrying a newer grant updates it.
          final laterExposed = now.add(const Duration(days: 1));
          final secondWrite = <PositionKnowledgeState>[
            PositionKnowledgeState(
              canonicalId: 'canonical_exposed',
              firstReviewedAt: now,
              repetitionCount: 3,
              stability: 345600000.0,
              difficulty: 4.2,
              lastExposedAt: laterExposed,
            ),
          ];
          await repo.saveAnswerBatch(knowledgeStates: secondWrite);

          final updated = await repo.getPositionKnowledgeState('canonical_exposed');
          expect(updated!.lastExposedAt, laterExposed);

          // A state that never earned credit stays null, so the coordinator reads it as "not
          // exposed today" rather than inheriting a stale cap.
          final unexposedWrite = <PositionKnowledgeState>[
            PositionKnowledgeState(
              canonicalId: 'canonical_never_exposed',
              firstReviewedAt: now,
              repetitionCount: 1,
              stability: 86400000.0,
              difficulty: 5.0,
            ),
          ];
          await repo.saveAnswerBatch(knowledgeStates: unexposedWrite);

          final neverExposed = await repo.getPositionKnowledgeState('canonical_never_exposed');
          expect(neverExposed!.lastExposedAt, isNull);
        } finally {
          await db.close();
        }
      },
    );

    test('decision canonicalStateId is persisted and retrieved', () async {
      final db = await openAppDatabase(databaseFactoryFfi, dbPath);
      final repo = SqliteStudyRepository(db);

      try {
        const study = Study(id: 's_canon', title: 'Canonical Study');
        await repo.saveStudy(study);
        final ch = Chapter.create(studyId: 's_canon', sourceOrder: 0);
        await repo.saveChapter(ch);

        // Points at the chapter that was actually stored. The id used to be a literal that no
        // chapter ever carried, which only went unnoticed because nothing enforced the foreign
        // key; the decision was an orphan row from the moment it was written.
        final dec = RepertoireDecision(
          id: 'dec_canon_1',
          studyId: 's_canon',
          chapterId: ch.id,
          nodeId: 'n1',
          expectedMoves: const [RepertoireMove(from: 'e2', to: 'e4', san: 'e4')],
          canonicalStateId: 'sha1_canon_hash_123',
        );
        await repo.saveDecision(dec);

        final loaded = await repo.getDecision('dec_canon_1');
        expect(loaded, isNotNull);
        expect(loaded!.canonicalStateId, 'sha1_canon_hash_123');
        expect(loaded.canonicalId, 'sha1_canon_hash_123');
      } finally {
        await db.close();
      }
    });

    test('chapter orientation round-trips for both White and Black', () async {
      var db = await openAppDatabase(databaseFactoryFfi, dbPath);
      var repo = SqliteStudyRepository(db);

      try {
        const study = Study(id: 'study-orient', title: 'Orientation Test');
        final chWhite = Chapter(
          id: 'ch-w',
          studyId: study.id,
          sourceOrder: 0,
          title: 'White Line',
          orientation: Side.white,
        );
        final chBlack = Chapter(
          id: 'ch-b',
          studyId: study.id,
          sourceOrder: 1,
          title: 'Black Line',
          orientation: Side.black,
        );

        await repo.saveStudy(study);
        await repo.saveChapters([chWhite, chBlack]);

        await db.close();
        db = await openAppDatabase(databaseFactoryFfi, dbPath);
        repo = SqliteStudyRepository(db);

        final loadedW = await repo.getChapter('ch-w');
        final loadedB = await repo.getChapter('ch-b');

        expect(loadedW?.orientation, Side.white);
        expect(loadedB?.orientation, Side.black);
      } finally {
        await db.close();
      }
    });

    test('getTodayReviewedPositionsCount counts distinct decisions reviewed today', () async {
      final db = await openAppDatabase(databaseFactoryFfi, dbPath);
      final repo = SqliteStudyRepository(db);

      try {
        final now = DateTime.utc(2026, 9, 18, 14, 30);
        final yesterday = DateTime.utc(2026, 9, 17, 20, 0);

        final ev1 = ReviewEvent(
          decisionId: 'dec-1',
          when: now.subtract(const Duration(hours: 2)),
          result: ReviewResult.incorrect,
          oldState: const ReviewState(decisionId: 'dec-1'),
          newState: const ReviewState(decisionId: 'dec-1', repetitionCount: 0, lapseCount: 1),
        );
        final ev2 = ReviewEvent(
          decisionId: 'dec-1', // same decision reviewed again today (reguess)
          when: now.subtract(const Duration(hours: 1)),
          result: ReviewResult.correct,
          oldState: const ReviewState(decisionId: 'dec-1', repetitionCount: 0, lapseCount: 1),
          newState: const ReviewState(decisionId: 'dec-1', repetitionCount: 1, lapseCount: 1),
        );
        final ev3 = ReviewEvent(
          decisionId: 'dec-2', // second distinct decision reviewed today
          when: now,
          result: ReviewResult.correct,
          oldState: const ReviewState(decisionId: 'dec-2'),
          newState: const ReviewState(decisionId: 'dec-2', repetitionCount: 1),
        );
        final evYesterday = ReviewEvent(
          decisionId: 'dec-3', // reviewed yesterday
          when: yesterday,
          result: ReviewResult.correct,
          oldState: const ReviewState(decisionId: 'dec-3'),
          newState: const ReviewState(decisionId: 'dec-3', repetitionCount: 1),
        );

        await repo.saveReviewEvent(ev1);
        await repo.saveReviewEvent(ev2);
        await repo.saveReviewEvent(ev3);
        await repo.saveReviewEvent(evYesterday);

        final count = await repo.getTodayReviewedPositionsCount(now);
        expect(count, 2); // exactly 2 distinct positions reviewed today
      } finally {
        await db.close();
      }
    });

    test('getTodayReviewedPositionsCount includes a review at local midnight', () async {
      final db = await openAppDatabase(databaseFactoryFfi, dbPath);
      final repo = SqliteStudyRepository(db);

      try {
        // Local wall time (no UTC suffix): this is what SystemClock produces.
        final now = DateTime(2026, 9, 18, 14, 30);
        final atMidnight = DateTime(2026, 9, 18);
        final beforeMidnight = DateTime(2026, 9, 17, 23, 59, 59);

        Future<void> saveAt(String decisionId, DateTime when) {
          return repo.saveReviewEvent(
            ReviewEvent(
              decisionId: decisionId,
              when: when,
              result: ReviewResult.correct,
              oldState: ReviewState(decisionId: decisionId),
              newState: ReviewState(decisionId: decisionId, repetitionCount: 1),
            ),
          );
        }

        await saveAt('dec-midnight', atMidnight);
        await saveAt('dec-before', beforeMidnight);

        final count = await repo.getTodayReviewedPositionsCount(now);
        // Midnight belongs to today; the minute before does not. The old
        // UTC-midnight bound (with a 'Z' suffix) excluded the midnight row
        // via string comparison against offset-less local timestamps.
        expect(count, 1);
      } finally {
        await db.close();
      }
    });

    test('foreign keys are enforced, so a raw delete cannot leave orphans behind', () async {
      // srs_chapter and srs_decision declare ON DELETE CASCADE, but SQLite ignores foreign
      // keys unless every connection turns them on. deleteStudy cascades by hand, so the gap
      // only shows on paths that do not: a raw DELETE, a future repository method, or a bug that
      // forgets a table. Orphans then accumulate silently and the counts stop agreeing.
      final db = await openAppDatabase(databaseFactoryFfi, dbPath);
      final repo = SqliteStudyRepository(db);

      try {
        final enabled = await db.rawQuery('PRAGMA foreign_keys');
        expect(
          enabled.first.values.first,
          equals(1),
          reason: 'SQLite ignores declared foreign keys unless the connection enables them',
        );

        final now = DateTime.utc(2026, 9, 16, 12, 0, 0);
        final study = Study(id: 's-fk', title: 'Cascade', createdAt: now, updatedAt: now);
        final chapter = Chapter(id: 'c-fk', studyId: study.id, sourceOrder: 0);
        await repo.saveStudy(study);
        await repo.saveChapter(chapter);
        await repo.saveDecision(
          RepertoireDecision(
            id: 'dec-fk',
            studyId: study.id,
            chapterId: chapter.id,
            nodeId: 'node-fk',
            expectedMoves: const [RepertoireMove(from: 'e2', to: 'e4')],
          ),
        );

        // Deliberately not deleteStudy: the point is that the database itself refuses to
        // leave orphans for a caller who forgets to cascade.
        await db.delete(kTableSrsStudy, where: 'id = ?', whereArgs: ['s-fk']);

        expect(
          await repo.getChaptersByStudy('s-fk'),
          isEmpty,
          reason: 'the chapter outlived its study',
        );
        expect(
          await repo.getDecisionsByStudy('s-fk'),
          isEmpty,
          reason: 'the decision outlived its study',
        );
      } finally {
        await db.close();
      }
    });

    test('getChaptersByStudyIds and getAllChapters batch load chapters across studies', () async {
      final db = await openAppDatabase(databaseFactoryFfi, dbPath);
      final repo = SqliteStudyRepository(db);

      try {
        const s1 = Study(id: 's_ch_1', title: 'Study 1');
        const s2 = Study(id: 's_ch_2', title: 'Study 2');
        await repo.saveStudy(s1);
        await repo.saveStudy(s2);

        final c1 = Chapter.create(
          studyId: s1.id,
          sourceOrder: 0,
          title: 'Ch 1',
          orientation: Side.white,
        );
        final c2 = Chapter.create(
          studyId: s1.id,
          sourceOrder: 1,
          title: 'Ch 2',
          orientation: Side.black,
        );
        final c3 = Chapter.create(
          studyId: s2.id,
          sourceOrder: 0,
          title: 'Ch 3',
          orientation: Side.white,
        );
        await repo.saveChapters([c1, c2, c3]);

        final s1Chapters = await repo.getChaptersByStudyIds([s1.id]);
        expect(s1Chapters.map((c) => c.id).toSet(), {c1.id, c2.id});

        final whiteChapters = await repo.getChaptersByStudyIds([s1.id, s2.id], side: Side.white);
        expect(whiteChapters.map((c) => c.id).toSet(), {c1.id, c3.id});

        final blackChapters = await repo.getChaptersByStudyIds([s1.id, s2.id], side: Side.black);
        expect(blackChapters.map((c) => c.id).toSet(), {c2.id});

        final bothChapters = await repo.getChaptersByStudyIds([s1.id, s2.id]);
        expect(bothChapters.map((c) => c.id).toSet(), {c1.id, c2.id, c3.id});

        final all = await repo.getAllChapters();
        expect(all.map((c) => c.id).toSet(), containsAll({c1.id, c2.id, c3.id}));

        final d1 = RepertoireDecision.create(
          studyId: s1.id,
          chapterId: c1.id,
          nodeId: 'n1',
          expectedMoves: const [],
        );
        final d2 = RepertoireDecision.create(
          studyId: s1.id,
          chapterId: c2.id,
          nodeId: 'n2',
          expectedMoves: const [],
        );
        final d3 = RepertoireDecision.create(
          studyId: s2.id,
          chapterId: c3.id,
          nodeId: 'n3',
          expectedMoves: const [],
        );
        await repo.saveDecisions([d1, d2, d3]);

        final c1Decisions = await repo.getDecisionsByChapters([c1.id]);
        expect(c1Decisions.map((d) => d.id).toSet(), {d1.id});

        final c1c3Decisions = await repo.getDecisionsByChapters([c1.id, c3.id]);
        expect(c1c3Decisions.map((d) => d.id).toSet(), {d1.id, d3.id});
      } finally {
        await db.close();
      }
    });

    test(
      'saveAnswerBatch atomically commits knowledge states, legacy mirrors, and events',
      () async {
        final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
        try {
          final batch = db.batch();
          createSrsTables(batch);
          await batch.commit();

          final repo = SqliteStudyRepository(db);
          final now = DateTime.utc(2026, 9, 20, 10, 0);

          final study = Study.create(title: 'Batch Test Study');
          final chapter = Chapter.create(studyId: study.id, title: 'Chapter 1', sourceOrder: 0);
          final dec1 = RepertoireDecision(
            id: 'dec-batch-1',
            studyId: study.id,
            chapterId: chapter.id,
            nodeId: 'node-1',
            expectedMoves: [const RepertoireMove(from: 'e2', to: 'e4')],
            canonicalStateId: 'canon-1',
          );

          await repo.saveStudy(study);
          await repo.saveChapter(chapter);
          await repo.saveDecision(dec1);

          final kState = PositionKnowledgeState(
            canonicalId: 'canon-1',
            firstReviewedAt: now,
            lastReviewedAt: now,
            nextDueAt: now.add(const Duration(days: 1)),
            repetitionCount: 1,
            lapseCount: 0,
            stability: 86400000.0,
            difficulty: 5.0,
          );

          final event = ReviewEvent(
            decisionId: 'canon-1',
            when: now,
            result: ReviewResult.correct,
            oldState: const ReviewState(decisionId: 'canon-1'),
            newState: const ReviewState(decisionId: 'canon-1', repetitionCount: 1),
          );

          await repo.saveAnswerBatch(knowledgeStates: [kState], event: event);

          final fetchedK = await repo.getPositionKnowledgeState('canon-1');
          expect(fetchedK, isNotNull);
          expect(fetchedK!.repetitionCount, 1);
          expect(fetchedK.difficulty, 5.0);

          // Verify mirror in legacy srs_review_state
          final fetchedLegacy = await repo.getReviewState('dec-batch-1');
          expect(fetchedLegacy, isNotNull);
          expect(fetchedLegacy!.repetitionCount, 1);

          final events = await repo.getReviewEvents('canon-1');
          expect(events.length, 1);
          expect(events.first.result, ReviewResult.correct);
        } finally {
          await db.close();
        }
      },
    );

    test(
      'deleteStudy chunks large decision sets (>400) without hitting parameter limits',
      () async {
        final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
        try {
          final batch = db.batch();
          createSrsTables(batch);
          await batch.commit();

          final repo = SqliteStudyRepository(db);
          final study = Study.create(title: 'Large Study');
          final chapter = Chapter.create(studyId: study.id, title: 'Chapter 1', sourceOrder: 0);
          await repo.saveStudy(study);
          await repo.saveChapter(chapter);

          // Insert 450 decisions (exceeds single 400 chunk)
          final decisions = List.generate(
            450,
            (i) => RepertoireDecision(
              id: 'dec-$i',
              studyId: study.id,
              chapterId: chapter.id,
              nodeId: 'node-$i',
              expectedMoves: [const RepertoireMove(from: 'e2', to: 'e4')],
              canonicalStateId: 'canon-$i',
            ),
          );
          await repo.saveDecisions(decisions);

          // Delete study should chunk delete operations smoothly
          await repo.deleteStudy(study.id);

          final remainingDecisions = await repo.getDecisionsByStudy(study.id);
          expect(remainingDecisions, isEmpty);

          final remainingStudy = await repo.getStudy(study.id);
          expect(remainingStudy, isNull);
        } finally {
          await db.close();
        }
      },
    );

    test(
      'ReviewState roundtrips custom difficulty through saveReviewState and getReviewState',
      () async {
        final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
        try {
          final batch = db.batch();
          createSrsTables(batch);
          await batch.commit();

          final repo = SqliteStudyRepository(db);
          const state = ReviewState(
            decisionId: 'dec-diff-test',
            repetitionCount: 3,
            stability: 42.0,
            difficulty: 7.25,
          );

          await repo.saveReviewState(state);
          final loaded = await repo.getReviewState('dec-diff-test');
          expect(loaded, isNotNull);
          expect(loaded!.difficulty, equals(7.25));
          expect(loaded.stability, equals(42.0));
        } finally {
          await db.close();
        }
      },
    );

    test(
      'saveAnswerBatch commits with PRAGMA foreign_keys = ON without constraint errors',
      () async {
        final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
        try {
          await db.execute('PRAGMA foreign_keys = ON;');
          final batch = db.batch();
          createSrsTables(batch);
          await batch.commit();

          final repo = SqliteStudyRepository(db);
          final now = DateTime.utc(2026, 9, 23, 12, 0);

          final study = Study.create(title: 'FK Safety Study');
          final chapter = Chapter.create(studyId: study.id, title: 'Chapter 1', sourceOrder: 0);
          final decision = RepertoireDecision(
            id: 'dec-fk-1',
            studyId: study.id,
            chapterId: chapter.id,
            nodeId: 'node-fk-1',
            expectedMoves: [const RepertoireMove(from: 'e2', to: 'e4')],
            canonicalStateId: 'canonical-key-fk-1',
          );

          await repo.saveStudy(study);
          await repo.saveChapter(chapter);
          await repo.saveDecision(decision);

          final kState = PositionKnowledgeState(
            canonicalId: 'canonical-key-fk-1',
            firstReviewedAt: now,
            lastReviewedAt: now,
            nextDueAt: now.add(const Duration(days: 1)),
            repetitionCount: 1,
            lapseCount: 0,
            stability: 86400000.0,
            difficulty: 6.8,
          );

          final event = ReviewEvent(
            decisionId: 'canonical-key-fk-1',
            when: now,
            result: ReviewResult.correct,
            oldState: const ReviewState(decisionId: 'canonical-key-fk-1'),
            newState: const ReviewState(
              decisionId: 'canonical-key-fk-1',
              repetitionCount: 1,
              difficulty: 6.8,
            ),
          );

          // Should commit cleanly under active foreign keys
          await repo.saveAnswerBatch(knowledgeStates: [kState], event: event);

          final loadedKState = await repo.getPositionKnowledgeState('canonical-key-fk-1');
          expect(loadedKState, isNotNull);
          expect(loadedKState!.difficulty, equals(6.8));
        } finally {
          await db.close();
        }
      },
    );

    test('reviewStateToJson and reviewStateFromJson preserve difficulty', () {
      const state = ReviewState(
        decisionId: 'test-canon-json',
        repetitionCount: 4,
        lapseCount: 1,
        stability: 12345.0,
        difficulty: 8.75,
      );
      final json = reviewStateToJson(state);
      expect(json['difficulty'], equals(8.75));

      final restored = reviewStateFromJson(json);
      expect(restored.difficulty, equals(8.75));
      expect(restored.stability, equals(12345.0));
      expect(restored.repetitionCount, equals(4));
      expect(restored.lapseCount, equals(1));
    });

    test('database migration v12 to v13 adds difficulty column to srs_review_state', () async {
      // Create database at version 12 without difficulty column in srs_review_state
      final v12Db = await databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 12,
          onCreate: (db, version) async {
            final batch = db.batch();
            createSrsTables(batch);
            await batch.commit();
            await db.execute('ALTER TABLE $kTableSrsReviewState DROP COLUMN difficulty');
          },
        ),
      );

      // Verify difficulty column is absent
      var tableInfo = await v12Db.rawQuery('PRAGMA table_info($kTableSrsReviewState)');
      var hasDifficulty = tableInfo.any((col) => col['name'] == 'difficulty');
      expect(hasDifficulty, isFalse);
      await v12Db.close();

      // Open through openAppDatabase which upgrades to v13
      final upgradedDb = await openAppDatabase(databaseFactoryFfi, dbPath);
      tableInfo = await upgradedDb.rawQuery('PRAGMA table_info($kTableSrsReviewState)');
      hasDifficulty = tableInfo.any((col) => col['name'] == 'difficulty');
      expect(hasDifficulty, isTrue);

      final repo = SqliteStudyRepository(upgradedDb);
      await repo.saveReviewState(
        const ReviewState(
          decisionId: 'migrated-dec-1',
          repetitionCount: 2,
          stability: 50.0,
          difficulty: 7.2,
        ),
      );
      final states = await repo.getReviewStatesByIds(['migrated-dec-1']);
      expect(states.first.difficulty, equals(7.2));

      await upgradedDb.close();
    });

    test('database migration v13 to v14 rekeys and backfills canonical review state', () async {
      // A database written before the canonical key change: decisions carry old-format
      // canonicalStateId values, and all of the history is in the legacy table only.
      final v13Db = await databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 13,
          onCreate: (db, version) async {
            final batch = db.batch();
            createSrsTables(batch);
            await batch.commit();

            const fenKey = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -';
            await db.insert(kTableSrsStudy, {
              'id': 'st-1',
              'title': 'Old',
              'createdAt': '2026-01-01T00:00:00.000Z',
              'updatedAt': '2026-01-01T00:00:00.000Z',
              'isActive': 1,
            });
            await db.insert(kTableSrsChapter, {
              'id': 'ch-1',
              'studyId': 'st-1',
              'sourceOrder': 0,
              'startingFen': fenKey,
              'createdAt': '2026-01-01T00:00:00.000Z',
              'treeJson': jsonEncode(
                repertoireNodeToJson(
                  const RepertoireNode(id: 'node-1', fen: fenKey, fenKey: fenKey),
                ),
              ),
            });

            // One decision offering two moves, so the old key (first child only) and the new
            // key (the complete answer set) genuinely differ.
            const oldCanonical = '1111111111111111111111111111111111111111';
            await db.insert(kTableSrsDecision, {
              'id': 'occ-1',
              'studyId': 'st-1',
              'chapterId': 'ch-1',
              'nodeId': 'node-1',
              'expectedMoves': encodeExpectedMoves([
                const RepertoireMove(from: 'e2', to: 'e4', san: 'e4'),
                const RepertoireMove(from: 'd2', to: 'd4', san: 'd4'),
              ]),
              'canonicalStateId': oldCanonical,
            });

            // The history exists only in the legacy table, keyed by the occurrence.
            await db.insert(kTableSrsReviewState, {
              'decisionId': 'occ-1',
              'firstReviewedAt': '2026-01-02T00:00:00.000Z',
              'lastReviewedAt': '2026-01-20T00:00:00.000Z',
              'nextDueAt': '2026-02-20T00:00:00.000Z',
              'repetitionCount': 8,
              'lapseCount': 1,
              'stability': 42.5,
              'difficulty': 6.0,
            });
          },
        ),
      );
      await v13Db.close();

      // Opening through the real entry point has to run the upgrade.
      final upgraded = await openAppDatabase(databaseFactoryFfi, dbPath);
      try {
        final decisions = await upgraded.query(kTableSrsDecision);
        final newCanonical = decisions.single['canonicalStateId']! as String;
        expect(
          newCanonical,
          isNot('1111111111111111111111111111111111111111'),
          reason: 'the old first-child key should have been rewritten',
        );
        expect(
          newCanonical,
          canonicalKeyForPosition('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -', [
            'e2e4',
            'd2d4',
          ], repertoireSide: Side.white),
        );

        // And the legacy history followed the key across, rather than being stranded.
        final carried = await upgraded.query(kTablePositionKnowledgeState);
        expect(carried, hasLength(1));
        expect(carried.single['canonicalId'], newCanonical);
        expect(carried.single['repetitionCount'], 8);
        expect(carried.single['stability'], 42.5);

        // The legacy row is keyed by the occurrence and is left exactly where it was, so nothing
        // was lost on the way across.
        final legacy = await upgraded.query(
          kTableSrsReviewState,
          where: 'decisionId = ?',
          whereArgs: ['occ-1'],
        );
        expect(legacy, hasLength(1));
        expect(legacy.single['repetitionCount'], 8);
      } finally {
        await upgraded.close();
      }
    });

    test(
      'unlockDecisions, getUnlockedDecisionIds, and lockDecisions manage unlocked lines',
      () async {
        final db = await openAppDatabase(databaseFactoryFfi, dbPath);
        final repo = SqliteStudyRepository(db);

        try {
          final now = DateTime.utc(2026, 10, 15, 12, 0, 0);
          final study = Study(
            id: 'study-dyn',
            title: 'Dynamic Test',
            createdAt: now,
            updatedAt: now,
          );
          final chapter = Chapter(id: 'ch-dyn', studyId: study.id, sourceOrder: 0);
          const dec1 = RepertoireDecision(
            id: 'dec-dyn-1',
            studyId: 'study-dyn',
            chapterId: 'ch-dyn',
            nodeId: 'n1',
            expectedMoves: [],
          );
          const dec2 = RepertoireDecision(
            id: 'dec-dyn-2',
            studyId: 'study-dyn',
            chapterId: 'ch-dyn',
            nodeId: 'n2',
            expectedMoves: [],
          );

          await repo.saveStudy(study);
          await repo.saveChapter(chapter);
          await repo.saveDecision(dec1);
          await repo.saveDecision(dec2);

          expect(await repo.getUnlockedDecisionIds(), isEmpty);

          await repo.unlockDecisions(['dec-dyn-1']);
          expect(await repo.getUnlockedDecisionIds(), equals({'dec-dyn-1'}));
          expect(await repo.getUnlockedDecisionIds(studyId: 'study-dyn'), equals({'dec-dyn-1'}));

          await repo.lockDecisions(['dec-dyn-1']);
          expect(await repo.getUnlockedDecisionIds(), isEmpty);
        } finally {
          await db.close();
        }
      },
    );

    test('an unknown hash does not claim the first unhashed study during backfill', () async {
      // SPEC INV-003. The backfill walks unhashed rows and may only claim a
      // match when the computed hash equals the queried one; claiming the
      // first unhashed row unconditionally would hand an import the wrong
      // study.
      final db = await openAppDatabase(databaseFactoryFfi, dbPath);
      final repo = SqliteStudyRepository(db);

      try {
        final result = importPgn(
          '[Orientation "white"]\n\n1. e4 *',
          studyTitle: 'Book',
          repertoireSide: Side.white,
        );
        expect(result.errors, isEmpty);
        await repo.saveStudy(result.study);
        for (final chapter in result.chapters) {
          await repo.saveChapter(chapter);
        }
        // Pretend the study was stored before the pgnHash column existed.
        await db.update(kTableSrsStudy, {'pgnHash': null});

        expect(await repo.getStudyByPgnHash('sha256-not-a-study-hash'), isNull);
      } finally {
        await db.close();
      }
    });

    test('the backfill side filter rejects an unhashed study of the other side', () async {
      // SPEC INV-003. The batching test checks the side filter only after the
      // white call has already backfilled every hash, so the unhashed branch
      // that decides the match was never exercised.
      final db = await openAppDatabase(databaseFactoryFfi, dbPath);
      final repo = SqliteStudyRepository(db);

      try {
        final result = importPgn(
          '[Orientation "white"]\n\n1. e4 *',
          studyTitle: 'Book',
          repertoireSide: Side.white,
        );
        expect(result.errors, isEmpty);
        await repo.saveStudy(result.study);
        for (final chapter in result.chapters) {
          await repo.saveChapter(chapter);
        }
        final targetHash = computeRepertoireTreeHash(result.chapters);
        // Pretend the study was stored before the pgnHash column existed.
        await db.update(kTableSrsStudy, {'pgnHash': null});

        expect(await repo.getStudyByPgnHash(targetHash, forSide: Side.black), isNull);
        // The same hash with the matching side still finds it.
        expect(
          (await repo.getStudyByPgnHash(targetHash, forSide: Side.white))?.id,
          result.study.id,
        );
      } finally {
        await db.close();
      }
    });

    test('a linked remote study round-trips through getStudyByRemoteId', () async {
      // No SPEC invariant covers remote-link metadata; this pins the read path
      // review_controller's linked-study update depends on.
      final db = await openAppDatabase(databaseFactoryFfi, dbPath);
      final repo = SqliteStudyRepository(db);

      try {
        const study = Study(id: 's_remote', title: 'Linked Study');
        await repo.saveStudy(study);
        final linkedAt = DateTime.utc(2026, 1, 2, 3, 4, 5);
        await repo.updateStudyRemoteRef(
          studyId: 's_remote',
          remoteStudyId: 'lich-abc',
          remoteUpdatedAt: linkedAt,
        );

        final found = await repo.getStudyByRemoteId('lich-abc');
        expect(found, isNotNull);
        expect(found!.study.id, 's_remote');
        expect(found.study.title, 'Linked Study');
        expect(found.remoteUpdatedAt, linkedAt);
        expect(await repo.getStudyByRemoteId('lich-missing'), isNull);
      } finally {
        await db.close();
      }
    });

    test('a side-filtered chapter batch beyond 50 ids applies the side filter', () async {
      // SPEC INV-051. The >50-id path reads chapters with a bare side filter
      // and matches study ids in memory; the side arguments must still be
      // passed through, or the query binds a placeholder to nothing.
      final db = await openAppDatabase(databaseFactoryFfi, dbPath);
      final repo = SqliteStudyRepository(db);

      try {
        final whiteImport = importPgn(
          '[Orientation "white"]\n\n1. e4 *',
          studyTitle: 'White book',
          repertoireSide: Side.white,
        );
        final blackImport = importPgn(
          '[Orientation "black"]\n\n1. d4 d5 *',
          studyTitle: 'Black book',
          repertoireSide: Side.black,
        );
        for (final result in [whiteImport, blackImport]) {
          expect(result.errors, isEmpty);
          await repo.saveStudy(result.study);
          for (final chapter in result.chapters) {
            await repo.saveChapter(chapter);
          }
        }
        final studyIds = [
          whiteImport.study.id,
          blackImport.study.id,
          for (var i = 0; i < 49; i++) 'missing-study-$i',
        ];

        final blackChapters = await repo.getChaptersByStudyIds(studyIds, side: Side.black);
        expect(blackChapters.map((c) => c.studyId).toSet(), {blackImport.study.id});

        final whiteChapters = await repo.getChaptersByStudyIds(studyIds, side: Side.white);
        expect(whiteChapters.map((c) => c.studyId).toSet(), {whiteImport.study.id});
      } finally {
        await db.close();
      }
    });

    test('getReviewState follows the canonical redirect of a legacy decision', () async {
      // SPEC INV-016. A decision whose review progress only exists under its
      // canonical state id must resolve to that state; the direct row is
      // absent here because the knowledge state predates the decision (so the
      // per-occurrence mirror never wrote one for this decision id).
      final db = await openAppDatabase(databaseFactoryFfi, dbPath);
      final repo = SqliteStudyRepository(db);

      try {
        const study = Study(id: 's_legacy', title: 'Legacy Study');
        await repo.saveStudy(study);
        final ch = Chapter.create(studyId: 's_legacy', sourceOrder: 0);
        await repo.saveChapter(ch);

        final now = DateTime.utc(2026, 9, 18, 12);
        await repo.savePositionKnowledgeState(
          PositionKnowledgeState(
            canonicalId: 'canon_legacy_1',
            firstReviewedAt: now,
            lastReviewedAt: now,
            nextDueAt: now.add(const Duration(days: 3)),
            repetitionCount: 4,
            lapseCount: 1,
            stability: 259200000.0,
            difficulty: 4.8,
            latencyEmaMs: 1420.5,
            latencySampleCount: 5,
            lastExposedAt: now.subtract(const Duration(hours: 5)),
          ),
        );
        await repo.saveDecision(
          RepertoireDecision(
            id: 'dec_legacy_1',
            studyId: 's_legacy',
            chapterId: ch.id,
            nodeId: 'n1',
            expectedMoves: const [RepertoireMove(from: 'e2', to: 'e4', san: 'e4')],
            canonicalStateId: 'canon_legacy_1',
          ),
        );

        final loaded = await repo.getReviewState('dec_legacy_1');
        expect(loaded, isNotNull);
        expect(loaded!.decisionId, 'dec_legacy_1');
        expect(loaded.repetitionCount, 4);
        expect(loaded.nextDueAt, now.add(const Duration(days: 3)));
      } finally {
        await db.close();
      }
    });

    test('getReviewEvents widens a legacy decision to its canonical event history', () async {
      // SPEC INV-016. Events keyed by the canonical id belong to this
      // decision's history; reading only the decision key would lose them.
      final db = await openAppDatabase(databaseFactoryFfi, dbPath);
      final repo = SqliteStudyRepository(db);

      try {
        const study = Study(id: 's_legacy_events', title: 'Legacy Events');
        await repo.saveStudy(study);
        final ch = Chapter.create(studyId: 's_legacy_events', sourceOrder: 0);
        await repo.saveChapter(ch);
        await repo.saveDecision(
          RepertoireDecision(
            id: 'dec_legacy_2',
            studyId: 's_legacy_events',
            chapterId: ch.id,
            nodeId: 'n1',
            expectedMoves: const [RepertoireMove(from: 'e2', to: 'e4', san: 'e4')],
            canonicalStateId: 'canon_legacy_2',
          ),
        );

        final reviewedAt = DateTime.utc(2026, 9, 18, 13);
        await repo.saveReviewEvent(
          ReviewEvent(
            decisionId: 'canon_legacy_2',
            when: reviewedAt,
            result: ReviewResult.correct,
            oldState: const ReviewState(decisionId: 'canon_legacy_2'),
            newState: const ReviewState(decisionId: 'canon_legacy_2', repetitionCount: 1),
          ),
        );

        final events = await repo.getReviewEvents('dec_legacy_2');
        expect(events, hasLength(1));
        expect(events.single.decisionId, 'canon_legacy_2');
        expect(events.single.when, reviewedAt);
      } finally {
        await db.close();
      }
    });

    test('review-state reads at exactly the 400-id chunk boundary return the matches', () async {
      // SPEC INV-051. The chunk loop must stop at the boundary: an inclusive
      // loop condition issues a second query with an empty IN () list, which
      // SQLite rejects.
      final db = await openAppDatabase(databaseFactoryFfi, dbPath);
      final repo = SqliteStudyRepository(db);

      try {
        await repo.saveReviewStates([
          const ReviewState(decisionId: 'dec_boundary', repetitionCount: 3),
        ]);
        final ids = ['dec_boundary', for (var i = 0; i < 399; i++) 'missing-review-$i'];

        final loaded = await repo.getReviewStatesByIds(ids);
        expect(loaded, hasLength(1));
        expect(loaded.single.decisionId, 'dec_boundary');
        expect(loaded.single.repetitionCount, 3);
      } finally {
        await db.close();
      }
    });

    test('chapter and canonical-state reads at the 400-id boundary return the matches', () async {
      // SPEC INV-051. Same boundary for getDecisionsByChapters and
      // getKnowledgeStatesByCanonicalIds, which run their own 400-item loops.
      final db = await openAppDatabase(databaseFactoryFfi, dbPath);
      final repo = SqliteStudyRepository(db);

      try {
        const study = Study(id: 's_boundary_read', title: 'Boundary Reads');
        await repo.saveStudy(study);
        final ch = Chapter.create(studyId: 's_boundary_read', sourceOrder: 0);
        await repo.saveChapter(ch);
        await repo.saveDecision(
          RepertoireDecision(
            id: 'dec_boundary_read',
            studyId: 's_boundary_read',
            chapterId: ch.id,
            nodeId: 'n1',
            expectedMoves: const [RepertoireMove(from: 'e2', to: 'e4', san: 'e4')],
            canonicalStateId: 'canon_boundary_read',
          ),
        );

        final chapterIds = [ch.id, for (var i = 0; i < 399; i++) 'missing-chapter-$i'];
        final decisions = await repo.getDecisionsByChapters(chapterIds);
        expect(decisions.map((d) => d.id), contains('dec_boundary_read'));

        final now = DateTime.utc(2026, 9, 18, 12);
        await repo.savePositionKnowledgeState(
          PositionKnowledgeState(
            canonicalId: 'canon_boundary',
            firstReviewedAt: now,
            lastReviewedAt: now,
            nextDueAt: now.add(const Duration(days: 3)),
            repetitionCount: 4,
            lapseCount: 1,
            stability: 259200000.0,
            difficulty: 4.8,
            latencyEmaMs: 1420.5,
            latencySampleCount: 5,
            lastExposedAt: now.subtract(const Duration(hours: 5)),
          ),
        );
        final canonicalIds = [
          'canon_boundary',
          for (var i = 0; i < 399; i++) 'missing-canonical-$i',
        ];
        final states = await repo.getKnowledgeStatesByCanonicalIds(canonicalIds);
        expect(states.map((s) => s.canonicalId), contains('canon_boundary'));
      } finally {
        await db.close();
      }
    });

    test('deleteStudy with exactly 400 decisions completes and removes them', () async {
      // SPEC INV-051. A study whose decision count is an exact multiple of the
      // 400-item chunk must not trip the chunk loop's boundary in either the
      // per-decision cleanup or the canonical-state cleanup.
      final db = await openAppDatabase(databaseFactoryFfi, dbPath);
      final repo = SqliteStudyRepository(db);

      try {
        const study = Study(id: 's_bulk_delete', title: 'Bulk Delete');
        await repo.saveStudy(study);
        final ch = Chapter.create(studyId: 's_bulk_delete', sourceOrder: 0);
        await repo.saveChapter(ch);
        await repo.saveDecisions([
          for (var i = 0; i < 400; i++)
            RepertoireDecision(
              id: 'dec_bulk_$i',
              studyId: 's_bulk_delete',
              chapterId: ch.id,
              nodeId: 'n$i',
              expectedMoves: const [RepertoireMove(from: 'e2', to: 'e4', san: 'e4')],
              canonicalStateId: 'canon_bulk_$i',
            ),
        ]);
        expect((await repo.getDecisionsByChapters([ch.id])).length, 400);

        await repo.deleteStudy('s_bulk_delete');

        expect(await repo.getStudy('s_bulk_delete'), isNull);
        expect(await repo.getDecisionsByChapters([ch.id]), isEmpty);
      } finally {
        await db.close();
      }
    });

    test('lockDecisions with exactly 400 ids completes and removes the rows', () async {
      // SPEC INV-051. The delete loop's boundary: 400 ids must lock in one
      // chunk instead of issuing an empty second delete.
      final db = await openAppDatabase(databaseFactoryFfi, dbPath);
      final repo = SqliteStudyRepository(db);

      try {
        const study = Study(id: 's_bulk_lock', title: 'Bulk Lock');
        await repo.saveStudy(study);
        final ch = Chapter.create(studyId: 's_bulk_lock', sourceOrder: 0);
        await repo.saveChapter(ch);
        await repo.saveDecisions([
          for (var i = 0; i < 2; i++)
            RepertoireDecision(
              id: 'dec_lock_$i',
              studyId: 's_bulk_lock',
              chapterId: ch.id,
              nodeId: 'n$i',
              expectedMoves: const [RepertoireMove(from: 'e2', to: 'e4', san: 'e4')],
              canonicalStateId: 'canon_lock_$i',
            ),
        ]);
        await repo.unlockDecisions(['dec_lock_0', 'dec_lock_1']);
        expect(await repo.getUnlockedDecisionIds(), hasLength(2));

        final ids = ['dec_lock_0', 'dec_lock_1', for (var i = 0; i < 398; i++) 'missing-lock-$i'];
        await repo.lockDecisions(ids);

        expect(await repo.getUnlockedDecisionIds(), isEmpty);
      } finally {
        await db.close();
      }
    });
  });
}
