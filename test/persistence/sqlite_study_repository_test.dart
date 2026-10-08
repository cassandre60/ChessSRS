// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC coverage: INV-001, INV-002, INV-004, INV-005, INV-031, INV-051.

import 'dart:convert';
import 'dart:io';

import 'package:chess_srs/src/db/database.dart';
import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/persistence/persistence.dart';
import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

    test(
      'incremental persistence: review answer touches only review_state and review_event',
      () async {
        final db = await openAppDatabase(databaseFactoryFfi, dbPath);
        final repo = SqliteStudyRepository(db);

        try {
          final now = DateTime.utc(2026, 9, 16, 12, 0, 0);
          final study = Study(id: 'study-1', title: 'Test Study', createdAt: now, updatedAt: now);
          final chapter = Chapter(
            id: 'ch-1',
            studyId: study.id,
            sourceOrder: 0,
            title: 'Ch 1',
            root: const RepertoireNode(id: 'r', fen: 'startfen', fenKey: 'startkey'),
          );
          const decision = RepertoireDecision(
            id: 'dec-1',
            studyId: 'study-1',
            chapterId: 'ch-1',
            nodeId: 'r',
            expectedMoves: [RepertoireMove(from: 'e2', to: 'e4')],
          );

          await repo.saveStudy(study);
          await repo.saveChapter(chapter);
          await repo.saveDecision(decision);

          // Fetch initial chapter and study row state
          final chapterBefore = await db.query(
            kTableSrsChapter,
            where: 'id = ?',
            whereArgs: ['ch-1'],
          );
          final studyBefore = await db.query(
            kTableSrsStudy,
            where: 'id = ?',
            whereArgs: ['study-1'],
          );

          // Incremental review update
          final nextState = ReviewState(
            decisionId: decision.id,
            firstReviewedAt: now,
            lastReviewedAt: now,
            nextDueAt: now.add(const Duration(days: 1)),
            repetitionCount: 1,
            stability: 1.0,
          );
          final event = ReviewEvent(
            decisionId: decision.id,
            when: now,
            result: ReviewResult.correct,
            oldState: ReviewState.initial(decisionId: decision.id),
            newState: nextState,
          );

          await repo.saveReviewState(nextState);
          await repo.saveReviewEvent(event);

          // Verify that srs_chapter and srs_study rows were NOT touched
          final chapterAfter = await db.query(
            kTableSrsChapter,
            where: 'id = ?',
            whereArgs: ['ch-1'],
          );
          final studyAfter = await db.query(
            kTableSrsStudy,
            where: 'id = ?',
            whereArgs: ['study-1'],
          );

          expect(chapterAfter, equals(chapterBefore));
          expect(studyAfter, equals(studyBefore));

          // Verify that srs_review_state and srs_review_event have the new data
          final stateRows = await db.query(kTableSrsReviewState);
          expect(stateRows.length, 1);
          expect(stateRows.first['decisionId'], 'dec-1');

          final eventRows = await db.query(kTableSrsReviewEvent);
          expect(eventRows.length, 1);
          expect(eventRows.first['decisionId'], 'dec-1');
        } finally {
          await db.close();
        }
      },
    );

    test('getDueReviewStates retrieves past and unreviewed items ordered by due date', () async {
      final db = await openAppDatabase(databaseFactoryFfi, dbPath);
      final repo = SqliteStudyRepository(db);

      try {
        final now = DateTime.utc(2026, 9, 16, 12, 0, 0);

        const unreviewed = ReviewState(decisionId: 'unreviewed');
        final overdue = ReviewState(
          decisionId: 'overdue',
          nextDueAt: now.subtract(const Duration(hours: 2)),
          repetitionCount: 2,
        );
        final dueNow = ReviewState(decisionId: 'dueNow', nextDueAt: now, repetitionCount: 1);
        final future = ReviewState(
          decisionId: 'future',
          nextDueAt: now.add(const Duration(days: 3)),
          repetitionCount: 3,
        );

        await repo.saveReviewStates([future, overdue, unreviewed, dueNow]);

        final dueItems = await repo.getDueReviewStates(now);
        final dueIds = dueItems.map((s) => s.decisionId).toList();

        // Should include unreviewed, overdue, and dueNow, but NOT future
        expect(dueIds, containsAll(['unreviewed', 'overdue', 'dueNow']));
        expect(dueIds, isNot(contains('future')));

        // Null nextDueAt comes first in SQLite ASC order
        expect(dueItems.first.decisionId, 'unreviewed');
        expect(dueItems[1].decisionId, 'overdue');
        expect(dueItems[2].decisionId, 'dueNow');
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

    test('getReviewStatesByDecisions retrieves only review states for specified IDs', () async {
      final db = await openAppDatabase(databaseFactoryFfi, dbPath);
      final repo = SqliteStudyRepository(db);

      try {
        const s1 = ReviewState(decisionId: 'dec-1', repetitionCount: 1);
        const s2 = ReviewState(decisionId: 'dec-2', repetitionCount: 2);
        const s3 = ReviewState(decisionId: 'dec-3', repetitionCount: 3);
        await repo.saveReviewStates([s1, s2, s3]);

        final queried = await repo.getReviewStatesByDecisions(['dec-1', 'dec-3']);
        expect(queried.length, 2);
        expect(queried.map((s) => s.decisionId).toSet(), equals({'dec-1', 'dec-3'}));

        final emptyQuery = await repo.getReviewStatesByDecisions([]);
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

        const dec = RepertoireDecision(
          id: 'dec_canon_1',
          studyId: 's_canon',
          chapterId: 'ch_canon_1',
          nodeId: 'n1',
          expectedMoves: [RepertoireMove(from: 'e2', to: 'e4', san: 'e4')],
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
      final states = await repo.getReviewStatesByDecisions(['migrated-dec-1']);
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
          ]),
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
  });
}
