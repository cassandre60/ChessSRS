// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:chess_srs/src/db/database.dart';
import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/persistence/persistence.dart';
import 'package:chess_srs/src/review/review_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'gated_study_repository.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  group('ReviewService', () {
    late Directory tempDir;
    late String dbPath;
    late FixedClock clock;
    late DateTime now;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('chess_srs_review_service_test_');
      dbPath = p.join(tempDir.path, 'test_service.db');
      now = DateTime.utc(2026, 9, 16, 12, 0, 0);
      clock = FixedClock(now);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('incremental persistence: moves save state and event without rewriting trees', () async {
      final db = await openAppDatabase(databaseFactoryFfi, dbPath);
      final repo = SqliteStudyRepository(db);

      try {
        final study = Study(id: 's1', title: 'Service Study', createdAt: now, updatedAt: now);
        const root = RepertoireNode(
          id: 'n1',
          fen: 'startfen',
          fenKey: 'startkey',
          children: [
            RepertoireNode(
              id: 'n2',
              fen: 'after_e4',
              fenKey: 'after_e4_key',
              incomingMove: RepertoireMove(from: 'e2', to: 'e4', san: 'e4'),
            ),
          ],
        );
        final chapter = Chapter(
          id: 'c1',
          studyId: 's1',
          sourceOrder: 0,
          title: 'Chapter 1',
          root: root,
          createdAt: now,
        );
        const decision = RepertoireDecision(
          id: 'd1',
          studyId: 's1',
          chapterId: 'c1',
          nodeId: 'n1',
          expectedMoves: [RepertoireMove(from: 'e2', to: 'e4', san: 'e4')],
        );

        await repo.saveStudy(study);
        await repo.saveChapter(chapter);
        await repo.saveDecision(decision);

        final service = ReviewService(repository: repo, clock: clock);

        expect(await service.getDueCount(), 1);

        // Start session
        final session = await service.startSession();
        expect(session.currentPrompt?.decision.id, 'd1');

        // Submit correct move
        final result = await service.submitMove(from: 'e2', to: 'e4');
        expect(result.isCorrect, isTrue);

        // Verify that ReviewState is persisted in DB
        final persistedState = await repo.getReviewState('d1');
        expect(persistedState, isNotNull);
        expect(persistedState!.repetitionCount, 1);
        expect(persistedState.nextDueAt, now.add(const Duration(days: 1)));

        // Verify that ReviewEvent is appended in DB
        final events = await repo.getReviewEvents('d1');
        expect(events.length, 1);
        expect(events.first.result, ReviewResult.correct);
        expect(events.first.decisionId, 'd1');

        // Due count is now 0
        expect(await service.getDueCount(), 0);
      } finally {
        await db.close();
      }
    });

    test('rolls back in-memory session when answer persistence fails', () async {
      final db = await openAppDatabase(databaseFactoryFfi, dbPath);
      final repo = _ToggleFailureRepository(db);
      final service = ReviewService(repository: repo, clock: clock);

      try {
        final study = Study(id: 's1', title: 'Rollback Study', createdAt: now, updatedAt: now);
        const root = RepertoireNode(
          id: 'n1',
          fen: 'startfen',
          fenKey: 'startkey',
          children: [
            RepertoireNode(
              id: 'n2',
              fen: 'after_e4',
              fenKey: 'after_e4_key',
              incomingMove: RepertoireMove(from: 'e2', to: 'e4', san: 'e4'),
            ),
          ],
        );
        final chapter = Chapter(
          id: 'c1',
          studyId: 's1',
          sourceOrder: 0,
          title: 'Chapter 1',
          root: root,
          createdAt: now,
        );
        const decision = RepertoireDecision(
          id: 'd1',
          studyId: 's1',
          chapterId: 'c1',
          nodeId: 'n1',
          expectedMoves: [RepertoireMove(from: 'e2', to: 'e4', san: 'e4')],
        );

        await repo.saveStudy(study);
        await repo.saveChapter(chapter);
        await repo.saveDecision(decision);

        final session = await service.startSession();
        expect(session.currentPrompt?.decision.id, 'd1');

        final beforePrompt = session.currentPrompt;
        final beforeState = session.reviewStates['d1'];

        repo.failOnSaveAnswerBatch = true;
        await expectLater(service.submitMove(from: 'e2', to: 'e4'), throwsA(isA<Exception>()));
        repo.failOnSaveAnswerBatch = false;

        // In-memory session must be exactly as it was before the failed answer.
        expect(session.currentPrompt, same(beforePrompt));
        expect(session.completedCount, 0);
        expect(session.reviewStates['d1'], beforeState);
        expect(await repo.getReviewState('d1'), isNull);

        // A subsequent successful attempt persists normally.
        final result = await service.submitMove(from: 'e2', to: 'e4');
        expect(result.isCorrect, isTrue);
        final persisted = await repo.getReviewState('d1');
        expect(persisted, isNotNull);
        expect(persisted!.repetitionCount, 1);
      } finally {
        await db.close();
      }
    });

    test('ReviewScope.all excludes inactive studies from dueCount and session', () async {
      final db = await openAppDatabase(databaseFactoryFfi, dbPath);
      final repo = SqliteStudyRepository(db);
      final service = ReviewService(repository: repo, clock: clock);

      try {
        const activeStudy = Study(id: 'active_s', title: 'Active', isActive: true);
        const inactiveStudy = Study(id: 'inactive_s', title: 'Inactive', isActive: false);

        await repo.saveStudy(activeStudy);
        await repo.saveStudy(inactiveStudy);

        final d1 = RepertoireDecision.create(
          studyId: 'active_s',
          chapterId: 'c1',
          nodeId: 'n1',
          expectedMoves: const [RepertoireMove(from: 'e2', to: 'e4', san: 'e4')],
        );
        final d2 = RepertoireDecision.create(
          studyId: 'inactive_s',
          chapterId: 'c2',
          nodeId: 'n2',
          expectedMoves: const [RepertoireMove(from: 'd2', to: 'd4', san: 'd4')],
        );

        await repo.saveDecision(d1);
        await repo.saveDecision(d2);

        // Due count for all should only count the active study decision
        final allDueCount = await service.getDueCount(scope: const ReviewScope.all());
        expect(allDueCount, 1);

        // Explicit study scope still returns the inactive study due count
        final inactiveDueCount = await service.getDueCount(
          scope: const ReviewScope.study('inactive_s'),
        );
        expect(inactiveDueCount, 1);

        // Session for all should only load the active study decision
        final session = await service.startSession(scope: const ReviewScope.all());
        expect(session.remainingDueCount, 1);
        expect(session.currentPrompt?.studyId, 'active_s');
      } finally {
        await db.close();
      }
    });

    test(
      'ReviewScope.opening aggregates decisions across multiple studies with matching opening',
      () async {
        final db = await openAppDatabase(databaseFactoryFfi, dbPath);
        final repo = SqliteStudyRepository(db);
        final service = ReviewService(repository: repo, clock: clock);

        try {
          const study1 = Study(id: 's_sicilian_1', title: 'Najdorf');
          const study2 = Study(id: 's_sicilian_2', title: 'Dragon');
          const study3 = Study(id: 's_french', title: 'French');

          await repo.saveStudy(study1);
          await repo.saveStudy(study2);
          await repo.saveStudy(study3);

          final ch1 = Chapter.create(
            studyId: 's_sicilian_1',
            sourceOrder: 0,
            opening: 'Sicilian Defense',
          );
          final ch2 = Chapter.create(
            studyId: 's_sicilian_2',
            sourceOrder: 0,
            opening: 'Sicilian Defense',
          );
          final ch3 = Chapter.create(
            studyId: 's_french',
            sourceOrder: 0,
            opening: 'French Defense',
          );

          await repo.saveChapter(ch1);
          await repo.saveChapter(ch2);
          await repo.saveChapter(ch3);

          final d1 = RepertoireDecision.create(
            studyId: 's_sicilian_1',
            chapterId: ch1.id,
            nodeId: 'n1',
            expectedMoves: const [RepertoireMove(from: 'c7', to: 'c5', san: 'c5')],
          );
          final d2 = RepertoireDecision.create(
            studyId: 's_sicilian_2',
            chapterId: ch2.id,
            nodeId: 'n2',
            expectedMoves: const [RepertoireMove(from: 'd7', to: 'd6', san: 'd6')],
          );
          final d3 = RepertoireDecision.create(
            studyId: 's_french',
            chapterId: ch3.id,
            nodeId: 'n3',
            expectedMoves: const [RepertoireMove(from: 'e7', to: 'e6', san: 'e6')],
          );

          await repo.saveDecision(d1);
          await repo.saveDecision(d2);
          await repo.saveDecision(d3);

          // Scope by Sicilian Opening Hub: should pull d1 and d2 (2 decisions), excluding French (d3)
          final sicilianDue = await service.getDueCount(
            scope: const ReviewScope.opening('Sicilian Defense'),
          );
          expect(sicilianDue, 2);

          final frenchDue = await service.getDueCount(
            scope: const ReviewScope.opening('French Defense'),
          );
          expect(frenchDue, 1);

          final session = await service.startSession(
            scope: const ReviewScope.opening('Sicilian Defense'),
          );
          expect(session.remainingDueCount, 2);
        } finally {
          await db.close();
        }
      },
    );

    test(
      'ReviewScope.opening matches chapters despite surrounding whitespace in stored names',
      () async {
        final db = await openAppDatabase(databaseFactoryFfi, dbPath);
        final repo = SqliteStudyRepository(db);
        final service = ReviewService(repository: repo, clock: clock);

        try {
          const study = Study(id: 's_ws', title: 'Whitespace');
          await repo.saveStudy(study);

          final ch = Chapter.create(
            studyId: 's_ws',
            sourceOrder: 0,
            // Trailing space as stored by an older import/classifier.
            opening: 'Sicilian Defense ',
          );
          await repo.saveChapter(ch);

          final d = RepertoireDecision.create(
            studyId: 's_ws',
            chapterId: ch.id,
            nodeId: 'n1',
            expectedMoves: const [RepertoireMove(from: 'c7', to: 'c5', san: 'c5')],
          );
          await repo.saveDecision(d);

          // Due counting already trims; session loading must agree.
          final due = await service.getDueCount(
            scope: const ReviewScope.opening('Sicilian Defense'),
          );
          expect(due, 1);

          final session = await service.startSession(
            scope: const ReviewScope.opening('Sicilian Defense'),
          );
          expect(
            session.currentPrompt,
            isNotNull,
            reason: 'session loading must trim like due counting does',
          );
          expect(session.remainingDueCount, 1);
        } finally {
          await db.close();
        }
      },
    );

    test('getDueSummary computes accurate study and chapter progress metrics', () async {
      final db = await openAppDatabase(databaseFactoryFfi, dbPath);
      final repo = SqliteStudyRepository(db);
      final service = ReviewService(repository: repo, clock: clock);

      try {
        const study = Study(id: 's_prog', title: 'Progress Study');
        await repo.saveStudy(study);

        final ch1 = Chapter.create(studyId: 's_prog', sourceOrder: 0, title: 'Chapter 1');
        final ch2 = Chapter.create(studyId: 's_prog', sourceOrder: 1, title: 'Chapter 2');
        await repo.saveChapter(ch1);
        await repo.saveChapter(ch2);

        // 3 decisions in ch1, 2 decisions in ch2
        final d1 = RepertoireDecision.create(
          studyId: 's_prog',
          chapterId: ch1.id,
          nodeId: 'n1',
          expectedMoves: const [RepertoireMove(from: 'e2', to: 'e4', san: 'e4')],
        );
        final d2 = RepertoireDecision.create(
          studyId: 's_prog',
          chapterId: ch1.id,
          nodeId: 'n2',
          expectedMoves: const [RepertoireMove(from: 'g1', to: 'f3', san: 'Nf3')],
        );
        final d3 = RepertoireDecision.create(
          studyId: 's_prog',
          chapterId: ch1.id,
          nodeId: 'n3',
          expectedMoves: const [RepertoireMove(from: 'f1', to: 'c4', san: 'Bc4')],
        );
        final d4 = RepertoireDecision.create(
          studyId: 's_prog',
          chapterId: ch2.id,
          nodeId: 'n4',
          expectedMoves: const [RepertoireMove(from: 'd2', to: 'd4', san: 'd4')],
        );
        final d5 = RepertoireDecision.create(
          studyId: 's_prog',
          chapterId: ch2.id,
          nodeId: 'n5',
          expectedMoves: const [RepertoireMove(from: 'c2', to: 'c4', san: 'c4')],
        );

        await repo.saveDecisions([d1, d2, d3, d4, d5]);

        // d1 is learned and not due (due tomorrow)
        await repo.saveReviewState(
          ReviewState(
            decisionId: d1.id,
            repetitionCount: 2,
            nextDueAt: now.add(const Duration(days: 1)),
          ),
        );
        // d2 is learned but due now
        await repo.saveReviewState(
          ReviewState(
            decisionId: d2.id,
            repetitionCount: 1,
            nextDueAt: now.subtract(const Duration(hours: 1)),
          ),
        );
        // d3 is unlearned (repetitionCount 0) and due
        await repo.saveReviewState(
          ReviewState(decisionId: d3.id, repetitionCount: 0, nextDueAt: now),
        );
        // d4 is unlearned (no state record => due)
        // d5 is learned and not due
        await repo.saveReviewState(
          ReviewState(
            decisionId: d5.id,
            repetitionCount: 3,
            nextDueAt: now.add(const Duration(days: 5)),
          ),
        );

        final summary = await service.getDueSummary(studies: [study]);

        // Study progress: 5 total, 3 learned (d1, d2, d5), 3 due (d2, d3, d4)
        final studyProg = summary.studyProgress['s_prog'];
        expect(studyProg, isNotNull);
        expect(studyProg!.totalDecisions, 5);
        expect(studyProg.learnedDecisions, 3);
        expect(studyProg.dueDecisions, 3);
        expect(studyProg.progressPercentage, 60);

        // Chapter 1: 3 total, 2 learned (d1, d2), 2 due (d2, d3)
        final ch1Prog = summary.chapterProgress[ch1.id];
        expect(ch1Prog, isNotNull);
        expect(ch1Prog!.totalDecisions, 3);
        expect(ch1Prog.learnedDecisions, 2);
        expect(ch1Prog.dueDecisions, 2);
        expect(ch1Prog.progressPercentage, 67);

        // Chapter 2: 2 total, 1 learned (d5), 1 due (d4)
        final ch2Prog = summary.chapterProgress[ch2.id];
        expect(ch2Prog, isNotNull);
        expect(ch2Prog!.totalDecisions, 2);
        expect(ch2Prog.learnedDecisions, 1);
        expect(ch2Prog.dueDecisions, 1);
        expect(ch2Prog.progressPercentage, 50);
      } finally {
        await db.close();
      }
    });

    test(
      'ReviewService with EaseScalingScheduler schedules intervals via ease and scaling',
      () async {
        final db = await openAppDatabase(databaseFactoryFfi, dbPath);
        final repo = SqliteStudyRepository(db);
        const customScheduler = EaseScalingScheduler(
          firstInterval: Duration(days: 1),
          ease: 3.0,
          scaling: 1.8,
        );
        final service = ReviewService(repository: repo, scheduler: customScheduler, clock: clock);

        try {
          const study = Study(id: 's_ease', title: 'Ease Study');
          await repo.saveStudy(study);
          final ch = Chapter.create(studyId: 's_ease', sourceOrder: 0);
          await repo.saveChapter(ch);
          final d = RepertoireDecision.create(
            studyId: 's_ease',
            chapterId: ch.id,
            nodeId: 'n1',
            expectedMoves: const [RepertoireMove(from: 'e2', to: 'e4', san: 'e4')],
          );
          await repo.saveDecision(d);

          await service.startSession();
          final res1 = await service.submitMove(from: 'e2', to: 'e4');
          expect(res1.isCorrect, isTrue);

          // Rep 1: 1 day
          var state = await repo.getReviewState(d.id);
          expect(state?.repetitionCount, 1);
          expect(state?.nextDueAt, now.add(const Duration(days: 1)));

          // Advance clock by 1 day and submit again
          clock.advance(const Duration(days: 1));
          await service.startSession();
          final res2 = await service.submitMove(from: 'e2', to: 'e4');
          expect(res2.isCorrect, isTrue);

          // Rep 2: 1 day * 3.0 = 3 days
          state = await repo.getReviewState(d.id);
          expect(state?.repetitionCount, 2);
          expect(state?.nextDueAt, clock.now().add(const Duration(days: 3)));
        } finally {
          await db.close();
        }
      },
    );

    test(
      'startSession with ReviewScope.chapter loads only target chapter and its decisions',
      () async {
        final db = await openAppDatabase(databaseFactoryFfi, dbPath);
        final repo = SqliteStudyRepository(db);
        final service = ReviewService(repository: repo, clock: clock);

        try {
          const study = Study(id: 's_target', title: 'Target Study');
          await repo.saveStudy(study);

          final ch1 = Chapter.create(studyId: 's_target', sourceOrder: 0, title: 'Target Chapter');
          final ch2 = Chapter.create(studyId: 's_target', sourceOrder: 1, title: 'Other Chapter');
          await repo.saveChapter(ch1);
          await repo.saveChapter(ch2);

          final d1 = RepertoireDecision.create(
            studyId: 's_target',
            chapterId: ch1.id,
            nodeId: 'n1',
            expectedMoves: const [RepertoireMove(from: 'e2', to: 'e4', san: 'e4')],
          );
          final d2 = RepertoireDecision.create(
            studyId: 's_target',
            chapterId: ch2.id,
            nodeId: 'n2',
            expectedMoves: const [RepertoireMove(from: 'd2', to: 'd4', san: 'd4')],
          );
          await repo.saveDecisions([d1, d2]);

          final session = await service.startSession(
            scope: ReviewScope.chapter(studyId: 's_target', chapterId: ch1.id),
          );

          // Only ch1 decisions are loaded
          expect(session.remainingDueCount, 1);
          expect(session.currentPrompt?.chapterId, ch1.id);
          expect(session.getChapter(ch1.id), isNotNull);
          expect(session.getChapter(ch2.id), isNull);
        } finally {
          await db.close();
        }
      },
    );

    test(
      'transposition sharing: reviewing move in Study A updates shared canonical state in Study B',
      () async {
        final db = await openAppDatabase(databaseFactoryFfi, dbPath);
        final repo = SqliteStudyRepository(db);
        final service = ReviewService(repository: repo, clock: clock);

        try {
          const studyA = Study(id: 'study_a', title: 'Study A');
          const studyB = Study(id: 'study_b', title: 'Study B');
          await repo.saveStudy(studyA);
          await repo.saveStudy(studyB);

          final chA = Chapter.create(studyId: 'study_a', sourceOrder: 0);
          final chB = Chapter.create(studyId: 'study_b', sourceOrder: 0);
          await repo.saveChapter(chA);
          await repo.saveChapter(chB);

          // Same position (startpos), same move (1. e4)
          final cKey = canonicalKey('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -', 'e2e4');

          final decA = RepertoireDecision.create(
            studyId: 'study_a',
            chapterId: chA.id,
            nodeId: 'node_a_1',
            expectedMoves: const [RepertoireMove(from: 'e2', to: 'e4', san: 'e4')],
            canonicalStateId: cKey,
          );
          final decB = RepertoireDecision.create(
            studyId: 'study_b',
            chapterId: chB.id,
            nodeId: 'node_b_1',
            expectedMoves: const [RepertoireMove(from: 'e2', to: 'e4', san: 'e4')],
            canonicalStateId: cKey,
          );
          await repo.saveDecisions([decA, decB]);

          // In All Studies, the shared transposition is counted ONCE, not twice!
          final dueSummary = await service.getDueSummary(
            studies: [studyA, studyB],
            scope: const ReviewScope.all(),
          );
          expect(dueSummary.totalDueCount, 1);

          // Start session in Study A and answer the move correctly
          final session = await service.startSession(scope: const ReviewScope.study('study_a'));
          expect(session.remainingDueCount, 1);
          final stepResult = await service.submitMove(from: 'e2', to: 'e4');
          expect(stepResult.isCorrect, isTrue);

          // Canonical position knowledge state in DB is now learned and scheduled for tomorrow
          final kState = await repo.getPositionKnowledgeState(cKey);
          expect(kState, isNotNull);
          expect(kState!.repetitionCount, 1);
          expect(kState.nextDueAt, now.add(const Duration(days: 1)));

          // Study B's decision now also reflects that the shared position is learned!
          final dueSummaryAfter = await service.getDueSummary(
            studies: [studyA, studyB],
            scope: const ReviewScope.all(),
          );
          expect(dueSummaryAfter.totalDueCount, 0);

          // Session for Study B now has 0 due items
          final sessionB = await service.startSession(scope: const ReviewScope.study('study_b'));
          expect(sessionB.remainingDueCount, 0);
          expect(sessionB.isComplete, isTrue);
        } finally {
          await db.close();
        }
      },
    );

    test(
      'graph side effects: lapse on parent persists contagion updates to descendant canonical knowledge states in database',
      () async {
        final db = await openAppDatabase(databaseFactoryFfi, dbPath);
        final repo = SqliteStudyRepository(db);
        try {
          final service = ReviewService(repository: repo, clock: clock);

          final study = Study(id: 's_graph', title: 'Graph Study', createdAt: now, updatedAt: now);
          await repo.saveStudy(study);

          const rootNode = RepertoireNode(
            id: 'n_root',
            fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
            fenKey: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -',
            children: [
              RepertoireNode(
                id: 'n_e4',
                fen: 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1',
                fenKey: 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq -',
                incomingMove: RepertoireMove(from: 'e2', to: 'e4', san: 'e4'),
                children: [
                  RepertoireNode(
                    id: 'n_e5',
                    fen: 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2',
                    fenKey: 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq -',
                    incomingMove: RepertoireMove(from: 'e7', to: 'e5', san: 'e5'),
                    children: [
                      RepertoireNode(
                        id: 'n_nf3',
                        fen: 'rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2',
                        fenKey: 'rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq -',
                        incomingMove: RepertoireMove(from: 'g1', to: 'f3', san: 'Nf3'),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          );

          const chapter = Chapter(
            id: 'ch_g',
            studyId: 's_graph',
            title: 'Line',
            sourceOrder: 0,
            root: rootNode,
          );
          await repo.saveChapter(chapter);

          final dec1 = RepertoireDecision.create(
            studyId: 's_graph',
            chapterId: 'ch_g',
            nodeId: 'n_root',
            expectedMoves: const [RepertoireMove(from: 'e2', to: 'e4', san: 'e4')],
            canonicalStateId: 'canon_dec1',
          );
          final dec2 = RepertoireDecision.create(
            studyId: 's_graph',
            chapterId: 'ch_g',
            nodeId: 'n_e5',
            expectedMoves: const [RepertoireMove(from: 'g1', to: 'f3', san: 'Nf3')],
            canonicalStateId: 'canon_dec2',
          );
          await repo.saveDecisions([dec1, dec2]);

          // Set dec2 as learned with future due date
          final initialDue = now.add(const Duration(days: 10));
          const initialStability = 10.0 * 86400000;
          await repo.savePositionKnowledgeState(
            PositionKnowledgeState(
              canonicalId: 'canon_dec2',
              stability: initialStability,
              difficulty: 4.0,
              repetitionCount: 3,
              lastReviewedAt: now.subtract(const Duration(days: 2)),
              nextDueAt: initialDue,
            ),
          );

          final session = await service.startSession(scope: const ReviewScope.study('s_graph'));
          expect(session.currentPrompt?.decision.id, dec1.id);

          // Submit incorrect move (lapse) on dec1
          final stepResult = await service.submitMove(from: 'd2', to: 'd4');
          expect(stepResult.isCorrect, isFalse);
          expect(stepResult.sideEffectStates, isNotEmpty);

          // Verify dec2 canonical state was updated in database via contagion!
          final updatedChildKState = await repo.getPositionKnowledgeState('canon_dec2');
          expect(updatedChildKState, isNotNull);
          expect(updatedChildKState!.stability, lessThan(initialStability));
          expect(updatedChildKState.difficulty, greaterThan(4.0));
          expect(updatedChildKState.nextDueAt!.isBefore(initialDue), isTrue);
          // Invariant: repetition count and lapse count are NOT changed for descendant
          expect(updatedChildKState.repetitionCount, 3);
          expect(updatedChildKState.lapseCount, 0);
        } finally {
          await db.close();
        }
      },
    );

    group('session ownership', () {
      test(
        'a session that resolves after a newer one has been requested does not become active',
        () async {
          final db = await openAppDatabase(databaseFactoryFfi, dbPath);
          final repo = GatedStudyRepository(db);
          final service = ReviewService(repository: repo, clock: clock);

          try {
            for (final id in ['s_slow', 's_fast']) {
              await repo.saveStudy(Study(id: id, title: id, createdAt: now, updatedAt: now));
              final chapter = Chapter.create(studyId: id, sourceOrder: 0, title: 'Chapter');
              await repo.saveChapter(chapter);
              await repo.saveDecisions([
                RepertoireDecision.create(
                  studyId: id,
                  chapterId: chapter.id,
                  nodeId: 'n_$id',
                  expectedMoves: const [RepertoireMove(from: 'e2', to: 'e4', san: 'e4')],
                ),
              ]);
            }

            // Park the first session inside the repository so it is guaranteed to still be
            // loading when the second one starts — the ordering that loses the user their
            // review, arrived at by the database being slower the second time.
            repo.gatedStudyId = 's_slow';
            repo.gate = Completer<void>();
            repo.reachedGate = Completer<void>();

            final pendingSlow = service.startSession(
              scope: const ReviewScope.study('s_slow'),
              generation: 1,
            );
            await repo.reachedGate!.future;

            final fast = await service.startSession(
              scope: const ReviewScope.study('s_fast'),
              generation: 2,
            );
            expect(service.activeSession, same(fast));

            repo.gate!.complete();
            final slow = await pendingSlow;

            // The user asked for s_fast last, so s_fast is the session everything else must
            // agree on: the board shows it, and moves are graded against it. A session that
            // finishes loading late cannot be allowed to take that over.
            expect(slow.scope, const ReviewScope.study('s_slow'));
            expect(
              service.activeSession,
              same(fast),
              reason: 'the stale session took over the active slot on completion order alone',
            );
            expect(service.activeSession!.scope, const ReviewScope.study('s_fast'));
          } finally {
            await db.close();
          }
        },
      );

      test('a session started with a newer generation replaces the active one', () async {
        final db = await openAppDatabase(databaseFactoryFfi, dbPath);
        final repo = GatedStudyRepository(db);
        final service = ReviewService(repository: repo, clock: clock);

        try {
          for (final id in ['s_slow', 's_fast']) {
            await repo.saveStudy(Study(id: id, title: id, createdAt: now, updatedAt: now));
            final chapter = Chapter.create(studyId: id, sourceOrder: 0, title: 'Chapter');
            await repo.saveChapter(chapter);
            await repo.saveDecisions([
              RepertoireDecision.create(
                studyId: id,
                chapterId: chapter.id,
                nodeId: 'n_$id',
                expectedMoves: const [RepertoireMove(from: 'e2', to: 'e4', san: 'e4')],
              ),
            ]);
          }

          final slow = await service.startSession(
            scope: const ReviewScope.study('s_slow'),
            generation: 1,
          );
          expect(service.activeSession, same(slow));

          // In order this time: the newer request still wins, so ordering is not the thing
          // being relied on — the generation is.
          final fast = await service.startSession(
            scope: const ReviewScope.study('s_fast'),
            generation: 2,
          );
          expect(service.activeSession, same(fast));
        } finally {
          await db.close();
        }
      });
    });
  });
}

/// A [SqliteStudyRepository] whose [saveAnswerBatch] can be made to fail, to
/// exercise the session rollback path (QUALITY.md §2).
class _ToggleFailureRepository extends SqliteStudyRepository {
  _ToggleFailureRepository(super.db);

  bool failOnSaveAnswerBatch = false;

  @override
  Future<void> saveAnswerBatch({
    required List<PositionKnowledgeState> knowledgeStates,
    ReviewEvent? event,
  }) {
    if (failOnSaveAnswerBatch) {
      throw Exception('simulated persistence failure');
    }
    return super.saveAnswerBatch(knowledgeStates: knowledgeStates, event: event);
  }
}
