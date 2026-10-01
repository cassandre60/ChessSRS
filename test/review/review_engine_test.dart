// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC coverage: INV-012, INV-015, INV-016, INV-017, INV-020, INV-021, INV-022, INV-023, INV-027,
//   INV-028, INV-029, INV-031, INV-033, INV-041.

import 'dart:math';

import 'package:chess_srs/src/domain/domain.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

class _FixedRandom implements Random {
  _FixedRandom(this._value);
  final int _value;
  @override
  int nextInt(int max) => _value % max;
  @override
  bool nextBool() => true;
  @override
  double nextDouble() => 0.0;
}

void main() {
  group('ReviewSession Engine', () {
    late FixedClock clock;
    late DateTime baseTime;

    setUp(() {
      baseTime = DateTime.utc(2026, 9, 16, 10, 0, 0);
      clock = FixedClock(baseTime);
    });

    // Helper to build a basic study and chapter
    (Study, Chapter, List<RepertoireDecision>) buildTestRepertoire() {
      final study = Study(
        id: 'study-openings',
        title: 'Openings',
        createdAt: baseTime,
        updatedAt: baseTime,
      );

      // Root -> 1. e4 (dec-1) -> 1... e5 -> 2. Nf3 (dec-2) -> 2... Nc6 -> 3. Bc4 (dec-3)
      const rootNode = RepertoireNode(
        id: 'node-root',
        fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
        fenKey: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -',
        children: [
          RepertoireNode(
            id: 'node-e4',
            fen: 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1',
            fenKey: 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq -',
            incomingMove: RepertoireMove(from: 'e2', to: 'e4', san: 'e4'),
            children: [
              RepertoireNode(
                id: 'node-e5',
                fen: 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2',
                fenKey: 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq -',
                incomingMove: RepertoireMove(from: 'e7', to: 'e5', san: 'e5'),
                children: [
                  RepertoireNode(
                    id: 'node-nf3',
                    fen: 'rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2',
                    fenKey: 'rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq -',
                    incomingMove: RepertoireMove(from: 'g1', to: 'f3', san: 'Nf3'),
                    children: [
                      RepertoireNode(
                        id: 'node-nc6',
                        fen: 'r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3',
                        fenKey: 'r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq -',
                        incomingMove: RepertoireMove(from: 'b8', to: 'c6', san: 'Nc6'),
                        children: [
                          RepertoireNode(
                            id: 'node-bc4',
                            fen:
                                'r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 3 3',
                            fenKey: 'r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R b KQkq -',
                            incomingMove: RepertoireMove(from: 'f1', to: 'c4', san: 'Bc4'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      );

      final chapter = Chapter(
        id: 'chapter-italian',
        studyId: study.id,
        sourceOrder: 0,
        title: 'Italian Game',
        startingFen: rootNode.fen,
        root: rootNode,
        createdAt: baseTime,
      );

      final decisions = [
        const RepertoireDecision(
          id: 'dec-1',
          studyId: 'study-openings',
          chapterId: 'chapter-italian',
          nodeId: 'node-root',
          expectedMoves: [RepertoireMove(from: 'e2', to: 'e4', san: 'e4')],
        ),
        const RepertoireDecision(
          id: 'dec-2',
          studyId: 'study-openings',
          chapterId: 'chapter-italian',
          nodeId: 'node-e5',
          expectedMoves: [RepertoireMove(from: 'g1', to: 'f3', san: 'Nf3')],
        ),
        const RepertoireDecision(
          id: 'dec-3',
          studyId: 'study-openings',
          chapterId: 'chapter-italian',
          nodeId: 'node-nc6',
          expectedMoves: [RepertoireMove(from: 'f1', to: 'c4', san: 'Bc4')],
        ),
      ];

      return (study, chapter, decisions);
    }

    test('initializes empty session when no decisions are due', () {
      final (study, chapter, decisions) = buildTestRepertoire();
      // Schedule all decisions in the future
      final futureStates = {
        for (final d in decisions)
          d.id: ReviewState(decisionId: d.id, nextDueAt: baseTime.add(const Duration(days: 2))),
      };

      final engine = ReviewEngine(clock: clock);
      final session = engine.createSession(
        studies: [study],
        chapters: [chapter],
        decisions: decisions,
        reviewStates: futureStates,
      );

      expect(session.isComplete, isTrue);
      expect(session.currentPrompt, isNull);
      expect(session.remainingDueCount, 0);
    });

    test('validates correct move and performs auto-traversal through opponent reply', () {
      final (study, chapter, decisions) = buildTestRepertoire();
      // All decisions are due (unreviewed)
      final engine = ReviewEngine(clock: clock);
      final session = engine.createSession(
        studies: [study],
        chapters: [chapter],
        decisions: decisions,
        reviewStates: const {},
      );

      expect(session.isComplete, isFalse);
      expect(session.remainingDueCount, 3);
      expect(session.currentPrompt?.nodeId, 'node-root');
      expect(session.currentPrompt?.sideToMove, Side.white);

      // User plays correct move 1. e4
      final result = session.submitMove(from: 'e2', to: 'e4');

      expect(result.isCorrect, isTrue);
      expect(result.updatedState.repetitionCount, 1);
      expect(result.updatedState.nextDueAt, baseTime.add(const Duration(days: 1)));

      // Auto-played moves should include opponent reply: 1... e5
      expect(result.autoPlayedMoves.length, 1);
      final opponentMove = result.autoPlayedMoves.first;
      expect(opponentMove.isUserMove, isFalse);
      expect(opponentMove.move.san, 'e5');

      // Next prompt should be stopped at node-e5 (dec-2: 2. Nf3)
      expect(result.nextPrompt, isNotNull);
      expect(result.nextPrompt?.nodeId, 'node-e5');
      expect(result.nextPrompt?.decision.id, 'dec-2');
      expect(session.remainingDueCount, 2);
      expect(session.completedCount, 1);
    });

    test('auto-traversal skips already-learned (non-due) user moves (Invariant §2.4)', () {
      final (study, chapter, decisions) = buildTestRepertoire();
      // dec-1 is DUE
      // dec-2 (Nf3) is LEARNED and NOT due (due in 5 days)
      // dec-3 (Bc4) is DUE
      final reviewStates = {
        'dec-2': ReviewState(
          decisionId: 'dec-2',
          nextDueAt: baseTime.add(const Duration(days: 5)),
          repetitionCount: 2,
        ),
      };

      final engine = ReviewEngine(clock: clock);
      final session = engine.createSession(
        studies: [study],
        chapters: [chapter],
        decisions: decisions,
        reviewStates: reviewStates,
      );

      expect(session.remainingDueCount, 2); // dec-1 and dec-3
      expect(session.currentPrompt?.decision.id, 'dec-1');

      // User plays 1. e4
      final result = session.submitMove(from: 'e2', to: 'e4');

      expect(result.isCorrect, isTrue);

      // Auto-played should contain:
      // 1. Opponent 1... e5 (isUserMove: false)
      // 2. Learned user move 2. Nf3 (isUserMove: true)
      // 3. Opponent reply 2... Nc6 (isUserMove: false)
      expect(result.autoPlayedMoves.length, 3);
      expect(result.autoPlayedMoves[0].move.san, 'e5');
      expect(result.autoPlayedMoves[0].isUserMove, isFalse);
      expect(result.autoPlayedMoves[1].move.san, 'Nf3');
      expect(result.autoPlayedMoves[1].isUserMove, isTrue);
      expect(result.autoPlayedMoves[2].move.san, 'Nc6');
      expect(result.autoPlayedMoves[2].isUserMove, isFalse);

      // Next prompt should stop at dec-3 (3. Bc4), which is due!
      expect(result.nextPrompt?.decision.id, 'dec-3');
      expect(session.remainingDueCount, 1);
    });

    test('validates incorrect move against repertoire and re-queues failed decision', () {
      final (study, chapter, decisions) = buildTestRepertoire();
      final engine = ReviewEngine(clock: clock);
      final session = engine.createSession(
        studies: [study],
        chapters: [chapter],
        decisions: decisions,
        reviewStates: const {},
      );

      // User plays 1. d4 instead of prepared 1. e4
      final result = session.submitMove(from: 'd2', to: 'd4');

      expect(result.isCorrect, isFalse);
      expect(result.movePlayed.from, 'd2');
      expect(result.movePlayed.to, 'd4');
      expect(result.expectedMoves.first.san, 'e4');
      expect(result.updatedState.lapseCount, 1);
      expect(result.updatedState.repetitionCount, 0);
      expect(result.updatedState.nextDueAt, baseTime.add(const Duration(days: 1)));

      // Current prompt remains for user feedback
      expect(session.currentPrompt?.decision.id, 'dec-1');

      // User acknowledges feedback and continues
      session.continueAfterIncorrect();

      // Next prompt advances to the next due item in queue (dec-2)
      expect(session.currentPrompt?.decision.id, 'dec-2');

      // dec-1 is still in the queue at the end
      expect(session.remainingDueCount, 3);
    });

    test('filtering by ReviewScope.study confines review to matching study', () {
      final (studyA, chapterA, decisionsA) = buildTestRepertoire();

      const studyB = Study(id: 'study-b', title: 'Study B');
      final chapterB = Chapter(id: 'ch-b', studyId: studyB.id, sourceOrder: 0);
      const decB = RepertoireDecision(
        id: 'dec-b1',
        studyId: 'study-b',
        chapterId: 'ch-b',
        nodeId: 'node-b1',
        expectedMoves: [RepertoireMove(from: 'c2', to: 'c4')],
      );

      final engine = ReviewEngine(clock: clock);

      // Scope to study-openings only
      final session = engine.createSession(
        studies: [studyA, studyB],
        chapters: [chapterA, chapterB],
        decisions: [...decisionsA, decB],
        reviewStates: const {},
        scope: const ReviewScope.study('study-openings'),
      );

      expect(session.remainingDueCount, 3);
      expect(session.currentPrompt?.studyId, 'study-openings');
    });

    test('deterministic clock advancement surfaces due items over time (Invariant §3.2)', () {
      final (study, chapter, decisions) = buildTestRepertoire();
      final engine = ReviewEngine(clock: clock);

      // All decisions scheduled for tomorrow (baseTime + 24 hours)
      final tomorrow = baseTime.add(const Duration(days: 1));
      final futureStates = {
        for (final d in decisions) d.id: ReviewState(decisionId: d.id, nextDueAt: tomorrow),
      };

      // Initially at baseTime: nothing is due
      var session = engine.createSession(
        studies: [study],
        chapters: [chapter],
        decisions: decisions,
        reviewStates: futureStates,
      );
      expect(session.isComplete, isTrue);

      // Advance clock by 25 hours: all decisions become due!
      clock.advance(const Duration(hours: 25));

      session = engine.createSession(
        studies: [study],
        chapters: [chapter],
        decisions: decisions,
        reviewStates: futureStates,
      );
      expect(session.isComplete, isFalse);
      expect(session.remainingDueCount, 3);
    });

    test('skip moves current prompt to the back of queue', () {
      final (study, chapter, decisions) = buildTestRepertoire();
      final engine = ReviewEngine(clock: clock);
      final session = engine.createSession(
        studies: [study],
        chapters: [chapter],
        decisions: decisions,
        reviewStates: const {},
      );

      expect(session.currentPrompt?.decision.id, 'dec-1');

      final nextPrompt = session.skip();
      expect(nextPrompt?.decision.id, 'dec-2');

      // dec-1 is now at the end of the queue
      expect(session.remainingDueCount, 3);
    });

    test(
      'ReviewMode.practice tests all decisions even when none are due, without modifying states',
      () {
        final (study, chapter, decisions) = buildTestRepertoire();
        final engine = ReviewEngine(clock: clock);

        // All decisions scheduled for next month (not due)
        final future = baseTime.add(const Duration(days: 30));
        final futureStates = {
          for (final d in decisions)
            d.id: ReviewState(
              decisionId: d.id,
              nextDueAt: future,
              repetitionCount: 5,
              stability: 30.0,
            ),
        };

        // In standard SRS mode: session is empty (isComplete == true)
        final srsSession = engine.createSession(
          studies: [study],
          chapters: [chapter],
          decisions: decisions,
          reviewStates: futureStates,
          mode: ReviewMode.srs,
        );
        expect(srsSession.isComplete, isTrue);

        // In practice mode: all 3 decisions are queued for training!
        final practiceSession = engine.createSession(
          studies: [study],
          chapters: [chapter],
          decisions: decisions,
          reviewStates: futureStates,
          mode: ReviewMode.practice,
        );
        expect(practiceSession.isComplete, isFalse);
        expect(practiceSession.remainingDueCount, 3);
        expect(practiceSession.currentPrompt?.decision.id, 'dec-1');

        // Submit correct move in practice mode
        final result1 = practiceSession.submitMove(from: 'e2', to: 'e4');
        expect(result1.isCorrect, isTrue);
        // Invariant: Practice mode produces NO ReviewEvent and preserves previous ReviewState
        expect(result1.event, isNull);
        expect(result1.updatedState.repetitionCount, 5); // Unchanged!
        expect(result1.updatedState.stability, 30.0); // Unchanged!

        // Submit incorrect move in practice mode
        final result2 = practiceSession.submitMove(from: 'd2', to: 'd4');
        expect(result2.isCorrect, isFalse);
        expect(result2.event, isNull);
        expect(result2.updatedState.lapseCount, 0); // No lapse recorded!
        expect(result2.updatedState.repetitionCount, 5); // Repetitions not reset!
      },
    );

    test(
      'due-aware opponent selection: plays branch with due moves over branch with no due moves',
      () {
        final study = Study(
          id: 'study-branches',
          title: 'Openings',
          createdAt: baseTime,
          updatedAt: baseTime,
        );

        // Root -> 1. e4 (dec-1) -> has 2 Black branches:
        // Branch A: 1... e5 -> 2. Nf3 (dec-e5, NOT due)
        // Branch B: 1... c5 -> 2. Nf3 (dec-c5, DUE)
        const nodeRoot = RepertoireNode(
          id: 'root',
          fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
          fenKey: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -',
          children: [
            RepertoireNode(
              id: 'node-e4',
              fen: 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1',
              fenKey: 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq -',
              incomingMove: RepertoireMove(from: 'e2', to: 'e4', san: 'e4'),
              children: [
                RepertoireNode(
                  id: 'node-e5',
                  fen: 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2',
                  fenKey: 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq -',
                  incomingMove: RepertoireMove(from: 'e7', to: 'e5', san: 'e5'),
                  children: [
                    RepertoireNode(
                      id: 'node-nf3-e5',
                      fen: 'rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2',
                      fenKey: 'rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq -',
                      incomingMove: RepertoireMove(from: 'g1', to: 'f3', san: 'Nf3'),
                    ),
                  ],
                ),
                RepertoireNode(
                  id: 'node-c5',
                  fen: 'rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w KQkq c6 0 2',
                  fenKey: 'rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w KQkq -',
                  incomingMove: RepertoireMove(from: 'c7', to: 'c5', san: 'c5'),
                  children: [
                    RepertoireNode(
                      id: 'node-nf3-c5',
                      fen: 'rnbqkbnr/pp1ppppp/8/2p5/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2',
                      fenKey: 'rnbqkbnr/pp1ppppp/8/2p5/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq -',
                      incomingMove: RepertoireMove(from: 'g1', to: 'f3', san: 'Nf3'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        );

        final chapter = Chapter(
          id: 'ch-1',
          studyId: study.id,
          sourceOrder: 0,
          title: 'Main',
          startingFen: nodeRoot.fen,
          root: nodeRoot,
        );

        final dec1 = RepertoireDecision(
          id: 'dec-1',
          studyId: study.id,
          chapterId: chapter.id,
          nodeId: 'root',
          expectedMoves: const [RepertoireMove(from: 'e2', to: 'e4', san: 'e4')],
        );
        final decE5 = RepertoireDecision(
          id: 'dec-e5',
          studyId: study.id,
          chapterId: chapter.id,
          nodeId: 'node-e5',
          expectedMoves: const [RepertoireMove(from: 'g1', to: 'f3', san: 'Nf3')],
        );
        final decC5 = RepertoireDecision(
          id: 'dec-c5',
          studyId: study.id,
          chapterId: chapter.id,
          nodeId: 'node-c5',
          expectedMoves: const [RepertoireMove(from: 'g1', to: 'f3', san: 'Nf3')],
        );

        final engine = ReviewEngine(clock: clock);

        final statesWithDec1Due = {
          'dec-1': ReviewState.initial(decisionId: 'dec-1'),
          'dec-e5': ReviewState(
            decisionId: 'dec-e5',
            nextDueAt: baseTime.add(const Duration(days: 5)),
            repetitionCount: 2,
          ),
          'dec-c5': ReviewState(
            decisionId: 'dec-c5',
            nextDueAt: baseTime.subtract(const Duration(hours: 1)),
            repetitionCount: 1,
          ),
        };

        final session = engine.createSession(
          studies: [study],
          chapters: [chapter],
          decisions: [dec1, decE5, decC5],
          reviewStates: statesWithDec1Due,
        );

        expect(session.currentPrompt?.decision.id, 'dec-1');

        // User plays 1. e4: Opponent must pick between 1... e5 and 1... c5.
        // Branch A (1... e5) has NO due cards (scheduled in 5 days).
        // Branch B (1... c5) HAS due cards (dec-c5 is due).
        // Due-aware opponent selection plays 1... c5!
        final stepResult = session.submitMove(from: 'e2', to: 'e4');
        expect(stepResult.isCorrect, isTrue);
        expect(stepResult.autoPlayedMoves.length, 1);
        expect(stepResult.autoPlayedMoves.first.move.san, 'c5');
        expect(stepResult.nextPrompt?.decision.id, 'dec-c5');
      },
    );

    test(
      'due-aware opponent selection: weights selection between multiple branches with due moves',
      () {
        final study = Study(
          id: 'study-branches-2',
          title: 'Openings',
          createdAt: baseTime,
          updatedAt: baseTime,
        );

        const nodeRoot = RepertoireNode(
          id: 'root',
          fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
          fenKey: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -',
          children: [
            RepertoireNode(
              id: 'node-e4',
              fen: 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1',
              fenKey: 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq -',
              incomingMove: RepertoireMove(from: 'e2', to: 'e4', san: 'e4'),
              children: [
                RepertoireNode(
                  id: 'node-e5',
                  fen: 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2',
                  fenKey: 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq -',
                  incomingMove: RepertoireMove(from: 'e7', to: 'e5', san: 'e5'),
                  children: [
                    RepertoireNode(
                      id: 'node-nf3-e5',
                      fen: 'rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2',
                      fenKey: 'rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq -',
                      incomingMove: RepertoireMove(from: 'g1', to: 'f3', san: 'Nf3'),
                    ),
                  ],
                ),
                RepertoireNode(
                  id: 'node-c5',
                  fen: 'rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w KQkq c6 0 2',
                  fenKey: 'rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w KQkq -',
                  incomingMove: RepertoireMove(from: 'c7', to: 'c5', san: 'c5'),
                  children: [
                    RepertoireNode(
                      id: 'node-nf3-c5',
                      fen: 'rnbqkbnr/pp1ppppp/8/2p5/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2',
                      fenKey: 'rnbqkbnr/pp1ppppp/8/2p5/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq -',
                      incomingMove: RepertoireMove(from: 'g1', to: 'f3', san: 'Nf3'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        );

        final chapter = Chapter(
          id: 'ch-1',
          studyId: study.id,
          sourceOrder: 0,
          title: 'Main',
          startingFen: nodeRoot.fen,
          root: nodeRoot,
        );

        final dec1 = RepertoireDecision(
          id: 'dec-1',
          studyId: study.id,
          chapterId: chapter.id,
          nodeId: 'root',
          expectedMoves: const [RepertoireMove(from: 'e2', to: 'e4', san: 'e4')],
        );
        final decE5 = RepertoireDecision(
          id: 'dec-e5',
          studyId: study.id,
          chapterId: chapter.id,
          nodeId: 'node-e5',
          expectedMoves: const [RepertoireMove(from: 'g1', to: 'f3', san: 'Nf3')],
        );
        final decC5 = RepertoireDecision(
          id: 'dec-c5',
          studyId: study.id,
          chapterId: chapter.id,
          nodeId: 'node-c5',
          expectedMoves: const [RepertoireMove(from: 'g1', to: 'f3', san: 'Nf3')],
        );

        // Both dec-e5 and dec-c5 are due!
        final states = {
          'dec-1': ReviewState.initial(decisionId: 'dec-1'),
          'dec-e5': ReviewState.initial(decisionId: 'dec-e5'),
          'dec-c5': ReviewState.initial(decisionId: 'dec-c5'),
        };

        // FakeRandom(0): roll = 0, weight of e5 is 1, so 0 < 1 -> selects e5
        final engineA = ReviewEngine(clock: clock, random: _FixedRandom(0));
        final sessionA = engineA.createSession(
          studies: [study],
          chapters: [chapter],
          decisions: [dec1, decE5, decC5],
          reviewStates: states,
        );
        final resultA = sessionA.submitMove(from: 'e2', to: 'e4');
        expect(resultA.isCorrect, isTrue);
        expect(resultA.autoPlayedMoves.first.move.san, 'e5');

        // FakeRandom(1): roll = 1, weight of e5 is 1 (1 not < 1), remaining roll = 0 < 1 -> selects c5
        final engineB = ReviewEngine(clock: clock, random: _FixedRandom(1));
        final sessionB = engineB.createSession(
          studies: [study],
          chapters: [chapter],
          decisions: [dec1, decE5, decC5],
          reviewStates: states,
        );
        final resultB = sessionB.submitMove(from: 'e2', to: 'e4');
        expect(resultB.isCorrect, isTrue);
        expect(resultB.autoPlayedMoves.first.move.san, 'c5');
      },
    );

    test(
      'queue prefetching buffers decisions and refills when threshold is reached (chessrs semantics)',
      () {
        const study = Study(id: 's_prefetch', title: 'Prefetch Study');
        final chapter = Chapter.create(studyId: 's_prefetch', sourceOrder: 0);

        // Create 10 decisions
        final decisions = List.generate(10, (i) {
          return RepertoireDecision(
            id: 'dec-$i',
            studyId: study.id,
            chapterId: chapter.id,
            nodeId: 'node-$i',
            expectedMoves: const [RepertoireMove(from: 'e2', to: 'e4')],
          );
        });

        final engine = ReviewEngine(clock: clock);

        // Session configured with prefetchBatchSize: 3 and prefetchRefillThreshold: 1
        final session = engine.createSession(
          studies: [study],
          chapters: [chapter],
          decisions: decisions,
          reviewStates: const {},
          prefetchBatchSize: 3,
          prefetchRefillThreshold: 1,
        );

        // Total remaining due count accurately accounts for all 10 items (1 current prompt + 9 queued)
        expect(session.initialDueCount, 10);
        expect(session.remainingDueCount, 10);
        expect(session.currentPrompt?.decision.id, 'dec-0');

        // Skip advances to dec-1, queue count should still be 10 (skipped item placed at back)
        session.skip();
        expect(session.currentPrompt?.decision.id, 'dec-1');
        expect(session.remainingDueCount, 10);

        // All 10 decisions are surfaced through the prefetch buffer
        final promptIds = <String>{};
        for (var i = 0; i < 15; i++) {
          if (session.currentPrompt != null) {
            promptIds.add(session.currentPrompt!.decision.id);
            session.skip();
          }
        }

        for (var i = 0; i < 10; i++) {
          expect(promptIds.contains('dec-$i'), isTrue);
        }
      },
    );

    test(
      'lapse on prompt propagates lapse contagion to learned descendant decisions in the repertoire line',
      () {
        final (study, chapter, decisions) = buildTestRepertoire();
        final dec1 = decisions[0]; // 1. e4
        final dec2 = decisions[1]; // 2. Nf3 (descendant at depth 1)
        final dec3 = decisions[2]; // 3. Bc4 (descendant at depth 2)

        final initialDec2Due = baseTime.add(const Duration(days: 10));
        final initialDec3Due = baseTime.add(const Duration(days: 20));

        final reviewStates = {
          dec1.id: ReviewState.initial(decisionId: dec1.id),
          dec2.id: ReviewState(
            decisionId: dec2.id,
            stability: 10.0 * 86400000,
            difficulty: 4.0,
            repetitionCount: 3,
            lastReviewedAt: baseTime.subtract(const Duration(days: 5)),
            nextDueAt: initialDec2Due,
          ),
          dec3.id: ReviewState(
            decisionId: dec3.id,
            stability: 20.0 * 86400000,
            difficulty: 4.0,
            repetitionCount: 4,
            lastReviewedAt: baseTime.subtract(const Duration(days: 5)),
            nextDueAt: initialDec3Due,
          ),
        };

        final engine = ReviewEngine(clock: clock);
        final session = engine.createSession(
          studies: [study],
          chapters: [chapter],
          decisions: decisions,
          reviewStates: reviewStates,
        );

        expect(session.currentPrompt?.decision.id, dec1.id);

        // Submit incorrect move (lapse) on dec-1
        final stepResult = session.submitMove(from: 'd2', to: 'd4');
        expect(stepResult.isCorrect, isFalse);
        expect(stepResult.updatedState.lapseCount, 1);

        // Lapse contagion should have updated dec-2 and dec-3
        expect(stepResult.sideEffectStates.length, 2);

        final updatedDec2 = session.reviewStates[dec2.id]!;
        final updatedDec3 = session.reviewStates[dec3.id]!;

        expect(updatedDec2.stability, lessThan(10.0 * 86400000));
        expect(updatedDec2.difficulty, greaterThan(4.0));
        expect(updatedDec2.nextDueAt!.isBefore(initialDec2Due), isTrue);

        expect(updatedDec3.stability, lessThan(20.0 * 86400000));
        expect(updatedDec3.difficulty, greaterThan(4.0));
        expect(updatedDec3.nextDueAt!.isBefore(initialDec3Due), isTrue);
      },
    );

    test(
      'auto-traversal through non-due decisions grants auto-traversal credit and includes updated states in sideEffectStates',
      () {
        final (study, chapter, decisions) = buildTestRepertoire();
        final dec1 = decisions[0]; // 1. e4 (due)
        final dec2 = decisions[1]; // 2. Nf3 (learned, NOT due)
        final dec3 = decisions[2]; // 3. Bc4 (due)

        final initialDec2Due = baseTime.add(const Duration(days: 5));
        const initialDec2Stability = 5.0 * 86400000;
        final initialDec2LastReviewed = baseTime.subtract(const Duration(days: 2));

        final reviewStates = {
          dec1.id: ReviewState.initial(decisionId: dec1.id),
          dec2.id: ReviewState(
            decisionId: dec2.id,
            stability: initialDec2Stability,
            difficulty: 4.5,
            repetitionCount: 2,
            lastReviewedAt: initialDec2LastReviewed,
            nextDueAt: initialDec2Due,
          ),
          dec3.id: ReviewState.initial(decisionId: dec3.id),
        };

        final engine = ReviewEngine(clock: clock);
        final session = engine.createSession(
          studies: [study],
          chapters: [chapter],
          decisions: decisions,
          reviewStates: reviewStates,
        );

        expect(session.currentPrompt?.decision.id, dec1.id);

        // Submit correct move 1. e4
        final stepResult = session.submitMove(from: 'e2', to: 'e4');
        expect(stepResult.isCorrect, isTrue);

        // Engine auto-played 1... e5, bypassed non-due dec-2 (auto-played 2. Nf3),
        // engine auto-played 2... Nc6, and arrived at dec-3
        expect(stepResult.nextPrompt?.decision.id, dec3.id);

        // Exposure credit granted to dec-2 and reported in sideEffectStates
        expect(stepResult.sideEffectStates, isNotEmpty);
        final exposedDec2 = stepResult.sideEffectStates.firstWhere((s) => s.decisionId == dec2.id);
        expect(exposedDec2.stability, closeTo(initialDec2Stability * 1.08, 100));
        expect(exposedDec2.nextDueAt!.isAfter(initialDec2Due), isTrue);
        expect(exposedDec2.lastReviewedAt, equals(initialDec2LastReviewed));
      },
    );

    test('playing a confusable sibling move couples difficulty of the sibling decision', () {
      const study1 = Study(id: 's1', title: 'Study 1');
      const study2 = Study(id: 's2', title: 'Study 2');

      const rootFenKey = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -';
      const root1 = RepertoireNode(
        id: 'n1',
        fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
        fenKey: rootFenKey,
      );
      const root2 = RepertoireNode(
        id: 'n2',
        fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
        fenKey: rootFenKey,
      );

      final dec1 = RepertoireDecision(
        id: 'd1',
        studyId: study1.id,
        chapterId: 'c1',
        nodeId: root1.id,
        expectedMoves: const [RepertoireMove(from: 'e2', to: 'e4')],
      );
      final dec2 = RepertoireDecision(
        id: 'd2',
        studyId: study2.id,
        chapterId: 'c2',
        nodeId: root2.id,
        expectedMoves: const [RepertoireMove(from: 'd2', to: 'd4')],
      );

      final chapter1 = Chapter(
        id: 'c1',
        studyId: study1.id,
        title: 'C1',
        sourceOrder: 0,
        root: root1,
      );
      final chapter2 = Chapter(
        id: 'c2',
        studyId: study2.id,
        title: 'C2',
        sourceOrder: 0,
        root: root2,
      );

      final reviewStates = {
        dec1.id: ReviewState(decisionId: dec1.id, stability: 1000, difficulty: 5.0),
        dec2.id: ReviewState(decisionId: dec2.id, stability: 1000, difficulty: 4.0),
      };

      final engine = ReviewEngine(clock: clock);
      final session = engine.createSession(
        studies: [study1, study2],
        chapters: [chapter1, chapter2],
        decisions: [dec1, dec2],
        reviewStates: reviewStates,
        scope: const ReviewScope.study('s1'),
      );

      expect(session.currentPrompt?.decision.id, dec1.id);

      // User plays d2d4 (the move from dec2) while prompted for dec1
      final stepResult = session.submitMove(from: 'd2', to: 'd4');
      expect(stepResult.isCorrect, isFalse);

      final updatedDec2 = session.reviewStates[dec2.id]!;
      // Difficulty coupled (+0.35)
      expect(updatedDec2.difficulty, closeTo(4.35, 0.001));
      expect(stepResult.sideEffectStates, contains(updatedDec2));
    });

    test('remainingDailyQuota caps the number of due decisions queued in SRS session', () {
      final (study, chapter, decisions) = buildTestRepertoire();
      final engine = ReviewEngine(clock: clock);

      // Total 3 decisions exist. Set quota to 1.
      final session = engine.createSession(
        studies: [study],
        chapters: [chapter],
        decisions: decisions,
        reviewStates: const {},
        remainingDailyQuota: 1,
      );

      // Only 1 decision is queued
      expect(session.remainingDueCount, 1);
      expect(session.isComplete, isFalse);

      // Play correct move: e2 -> e4
      final result = session.submitMove(from: 'e2', to: 'e4');
      expect(result.isCorrect, isTrue);

      // Session completes because quota of 1 position was reached!
      expect(session.isComplete, isTrue);
      expect(session.currentPrompt, isNull);
    });

    test('SRS review queue prioritizes overdue items by nextDueAt urgency', () {
      final (study, chapter, decisions) = buildTestRepertoire();
      final engine = ReviewEngine(clock: clock);
      // decisions: [dec-1 (1. e4), dec-2 (2. Nf3), dec-3 (3. Bc4)]
      // dec-3 is most overdue (due 5 days ago)
      // dec-1 is slightly overdue (due 1 hour ago)
      final states = {
        decisions[0].id: ReviewState(
          decisionId: decisions[0].id,
          nextDueAt: baseTime.subtract(const Duration(hours: 1)),
          repetitionCount: 1,
        ),
        decisions[1].id: ReviewState(
          decisionId: decisions[1].id,
          nextDueAt: baseTime.add(const Duration(days: 1)),
          repetitionCount: 1,
        ),
        decisions[2].id: ReviewState(
          decisionId: decisions[2].id,
          nextDueAt: baseTime.subtract(const Duration(days: 5)),
          repetitionCount: 1,
        ),
      };

      final session = engine.createSession(
        studies: [study],
        chapters: [chapter],
        decisions: decisions,
        reviewStates: states,
        mode: ReviewMode.srs,
      );

      // Most overdue (dec-3) should be served first!
      expect(session.currentPrompt?.decision.id, decisions[2].id);
    });

    test('retryMove preserves state keyed by canonicalId on correct retry after lapse', () {
      final (study, chapter, decisions) = buildTestRepertoire();
      final engine = ReviewEngine(clock: clock);

      const canonId = 'canonical-dec-1';
      final d0 = decisions[0];
      final dec1WithCanon = RepertoireDecision(
        id: d0.id,
        studyId: d0.studyId,
        chapterId: d0.chapterId,
        nodeId: d0.nodeId,
        expectedMoves: d0.expectedMoves,
        canonicalStateId: canonId,
      );
      final updatedDecisions = [dec1WithCanon, decisions[1], decisions[2]];

      final states = {
        canonId: ReviewState(
          decisionId: canonId,
          repetitionCount: 4,
          stability: 15.0 * 86400000,
          difficulty: 3.5,
          nextDueAt: baseTime.subtract(const Duration(hours: 2)),
        ),
        decisions[1].id: ReviewState(
          decisionId: decisions[1].id,
          nextDueAt: baseTime.add(const Duration(days: 1)),
        ),
        decisions[2].id: ReviewState(
          decisionId: decisions[2].id,
          nextDueAt: baseTime.add(const Duration(days: 2)),
        ),
      };

      final session = engine.createSession(
        studies: [study],
        chapters: [chapter],
        decisions: updatedDecisions,
        reviewStates: states,
        mode: ReviewMode.srs,
      );

      // Play incorrect move first
      final lapseResult = session.submitMove(from: 'd2', to: 'd4');
      expect(lapseResult.isCorrect, isFalse);

      // Now retry with correct move
      final retryResult = session.retryMove(from: 'e2', to: 'e4');
      expect(retryResult.isCorrect, isTrue);
      // State should not be a fresh initial state (lapseCount: 0)
      // but should preserve the updated state after the lapse (lapseCount: 1)
      final stateAfterRetry = session.reviewStates[canonId]!;
      expect(stateAfterRetry.lapseCount, 1);
    });

    test('a position answered correctly only on retry still counts toward the daily quota', () {
      final (study, chapter, decisions) = buildTestRepertoire();
      final engine = ReviewEngine(clock: clock);

      // A quota of one: the first completed position ends the session, and a retry counts as a
      // completed position like any other.
      final session = engine.createSession(
        studies: [study],
        chapters: [chapter],
        decisions: decisions,
        reviewStates: const {},
        mode: ReviewMode.srs,
        remainingDailyQuota: 1,
      );

      // Wrong first, then right: the position was reviewed, so it must be counted.
      expect(session.submitMove(from: 'd2', to: 'd4').isCorrect, isFalse);
      expect(session.retryMove(from: 'e2', to: 'e4').isCorrect, isTrue);

      expect(
        session.isComplete,
        isTrue,
        reason: 'the retried position consumed the one review the day allowed',
      );
    });

    test('a retried position is counted once, not once per attempt', () {
      final (study, chapter, decisions) = buildTestRepertoire();
      final engine = ReviewEngine(clock: clock);

      final session = engine.createSession(
        studies: [study],
        chapters: [chapter],
        decisions: decisions,
        reviewStates: const {},
        mode: ReviewMode.srs,
        remainingDailyQuota: 2,
      );

      // Wrong twice, then right: three attempts at one position.
      expect(session.submitMove(from: 'd2', to: 'd4').isCorrect, isFalse);
      expect(session.retryMove(from: 'a2', to: 'a3').isCorrect, isFalse);
      expect(session.retryMove(from: 'e2', to: 'e4').isCorrect, isTrue);

      // One position used of the two allowed, so review is still open.
      expect(
        session.isComplete,
        isFalse,
        reason: 'attempts are not positions; only the completed one counts',
      );
    });

    test('a review is scheduled against the question that was asked, not a different one '
        'sharing its FEN and first move', () {
      // Two chapters whose roots are the same position and which both accept e2e4, but which
      // offer different complete answer sets. canonicalKeyForPosition keys those apart on
      // purpose (position_knowledge_state.dart:22-38), so they are separate memory items — the
      // code calls such a pair "confusable siblings" and hunts for them on purpose
      // (review_session.dart:768-789).
      final study = Study(
        id: 'study-collision',
        title: 'Collision',
        createdAt: baseTime,
        updatedAt: baseTime,
      );
      const startKey = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -';

      // Shared first move e2e4, divergent second moves: two questions, one position.
      const rootA = RepertoireNode(
        id: 'nA-root',
        fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
        fenKey: startKey,
        children: [
          RepertoireNode(
            id: 'nA-e4',
            fen: 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1',
            fenKey: 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq -',
            incomingMove: RepertoireMove(from: 'e2', to: 'e4', san: 'e4'),
            children: [
              RepertoireNode(
                id: 'nA-e5',
                fen: 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2',
                fenKey: 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq -',
                incomingMove: RepertoireMove(from: 'e7', to: 'e5', san: 'e5'),
              ),
            ],
          ),
          RepertoireNode(
            id: 'nA-d4',
            fen: 'rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq d3 0 1',
            fenKey: 'rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq -',
            incomingMove: RepertoireMove(from: 'd2', to: 'd4', san: 'd4'),
            children: [
              RepertoireNode(
                id: 'nA-d5',
                fen: 'rnbqkbnr/ppp1pppp/8/3p4/3P4/8/PPP1PPPP/RNBQKBNR w KQkq d6 0 2',
                fenKey: 'rnbqkbnr/ppp1pppp/8/3p4/3P4/8/PPP1PPPP/RNBQKBNR w KQkq -',
                incomingMove: RepertoireMove(from: 'd7', to: 'd5', san: 'd5'),
              ),
            ],
          ),
        ],
      );
      const rootB = RepertoireNode(
        id: 'nB-root',
        fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
        fenKey: startKey,
        children: [
          RepertoireNode(
            id: 'nB-e4',
            fen: 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1',
            fenKey: 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq -',
            incomingMove: RepertoireMove(from: 'e2', to: 'e4', san: 'e4'),
            children: [
              RepertoireNode(
                id: 'nB-c5',
                fen: 'rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w KQkq c6 0 2',
                fenKey: 'rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w KQkq -',
                incomingMove: RepertoireMove(from: 'c7', to: 'c5', san: 'c5'),
              ),
            ],
          ),
          RepertoireNode(
            id: 'nB-c4',
            fen: 'rnbqkbnr/pppppppp/8/8/2P5/8/PP1PPPPP/RNBQKBNR b KQkq c3 0 1',
            fenKey: 'rnbqkbnr/pppppppp/8/8/2P5/8/PP1PPPPP/RNBQKBNR b KQkq -',
            incomingMove: RepertoireMove(from: 'c2', to: 'c4', san: 'c4'),
            children: [
              RepertoireNode(
                id: 'nB-e5',
                fen: 'rnbqkbnr/pppp1ppp/8/2p5/2P5/8/PP1PPPPP/RNBQKBNR w KQkq e6 0 2',
                fenKey: 'rnbqkbnr/pppp1ppp/8/2p5/2P5/8/PP1PPPPP/RNBQKBNR w KQkq -',
                incomingMove: RepertoireMove(from: 'e7', to: 'e5', san: 'e5'),
              ),
            ],
          ),
        ],
      );

      final chapterA = Chapter(
        id: 'chA',
        studyId: study.id,
        sourceOrder: 0,
        title: 'A',
        root: rootA,
        createdAt: baseTime,
      );
      final chapterB = Chapter(
        id: 'chB',
        studyId: study.id,
        sourceOrder: 1,
        title: 'B',
        root: rootB,
        createdAt: baseTime,
      );

      // Canonical ids computed the way the importer computes them, from the complete accepted
      // set — so they are genuinely different memory items.
      final canonA = canonicalKeyForPosition(startKey, ['e2e4', 'd2d4']);
      final canonB = canonicalKeyForPosition(startKey, ['e2e4', 'c2c4']);
      expect(
        canonA,
        isNot(canonB),
        reason: 'the two chapters must offer different answer sets for this to be a collision',
      );

      final decA = RepertoireDecision(
        id: 'decA',
        studyId: study.id,
        chapterId: chapterA.id,
        nodeId: rootA.id,
        expectedMoves: const [
          RepertoireMove(from: 'e2', to: 'e4', san: 'e4'),
          RepertoireMove(from: 'd2', to: 'd4', san: 'd4'),
        ],
        canonicalStateId: canonA,
      );
      final decB = RepertoireDecision(
        id: 'decB',
        studyId: study.id,
        chapterId: chapterB.id,
        nodeId: rootB.id,
        expectedMoves: const [
          RepertoireMove(from: 'e2', to: 'e4', san: 'e4'),
          RepertoireMove(from: 'c2', to: 'c4', san: 'c4'),
        ],
        canonicalStateId: canonB,
      );

      // decA is a mature memory item; decB has never been seen.
      final session = ReviewEngine(clock: clock).createSession(
        studies: [study],
        chapters: [chapterA, chapterB],
        decisions: [decA, decB],
        reviewStates: {
          canonA: ReviewState(
            decisionId: canonA,
            stability: 30.0 * 86400000,
            difficulty: 4.0,
            repetitionCount: 12,
            lastReviewedAt: baseTime.subtract(const Duration(days: 3)),
            nextDueAt: baseTime.subtract(const Duration(hours: 1)),
          ),
        },
        scope: const ReviewScope.study('study-collision'),
      );

      // Never-reviewed positions sort ahead of scheduled ones, so decB is asked first and decA
      // second. Both are answered, because the damage shows on the second: decA is the mature
      // memory item, and answering it must advance decA's own history.
      expect(session.currentPrompt?.decision.id, decB.id);
      expect(session.submitMove(from: 'e2', to: 'e4').isCorrect, isTrue);
      expect(session.currentPrompt?.decision.id, decA.id);

      expect(session.submitMove(from: 'e2', to: 'e4').isCorrect, isTrue);

      // decA's own 12 repetitions are the base for the answer that was asked of it.
      final afterA = session.reviewStates[canonA]!;
      expect(
        afterA.repetitionCount,
        13,
        reason: 'decA was the question asked; its own 12 repetitions must be the base',
      );
      expect(
        afterA.stability,
        greaterThan(30.0 * 86400000),
        reason: "decA's accumulated stability must carry forward",
      );
      // decB got its own single correct answer and no more.
      expect(
        session.reviewStates[canonB]!.repetitionCount,
        1,
        reason: 'a second question at the same position was advanced by this answer',
      );
    });

    test('due-aware opponent selection counts due decisions keyed by canonicalId in subtree', () {
      final study = Study(
        id: 'study-canon-test',
        title: 'Canon Test',
        createdAt: baseTime,
        updatedAt: baseTime,
      );

      const nodeRoot = RepertoireNode(
        id: 'root',
        fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
        fenKey: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -',
        children: [
          RepertoireNode(
            id: 'node-e4',
            fen: 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1',
            fenKey: 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq -',
            incomingMove: RepertoireMove(from: 'e2', to: 'e4', san: 'e4'),
            children: [
              RepertoireNode(
                id: 'node-e5',
                fen: 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2',
                fenKey: 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq -',
                incomingMove: RepertoireMove(from: 'e7', to: 'e5', san: 'e5'),
                children: [
                  RepertoireNode(
                    id: 'node-nf3-e5',
                    fen: 'rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2',
                    fenKey: 'rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq -',
                    incomingMove: RepertoireMove(from: 'g1', to: 'f3', san: 'Nf3'),
                  ),
                ],
              ),
              RepertoireNode(
                id: 'node-c5',
                fen: 'rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w KQkq c6 0 2',
                fenKey: 'rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w KQkq -',
                incomingMove: RepertoireMove(from: 'c7', to: 'c5', san: 'c5'),
                children: [
                  RepertoireNode(
                    id: 'node-nf3-c5',
                    fen: 'rnbqkbnr/pp1ppppp/8/2p5/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2',
                    fenKey: 'rnbqkbnr/pp1ppppp/8/2p5/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq -',
                    incomingMove: RepertoireMove(from: 'g1', to: 'f3', san: 'Nf3'),
                  ),
                ],
              ),
            ],
          ),
        ],
      );

      final chapter = Chapter(
        id: 'ch-canon',
        studyId: study.id,
        sourceOrder: 0,
        title: 'Main',
        startingFen: nodeRoot.fen,
        root: nodeRoot,
      );

      final dec1 = RepertoireDecision(
        id: 'dec-1',
        studyId: study.id,
        chapterId: chapter.id,
        nodeId: 'root',
        expectedMoves: const [RepertoireMove(from: 'e2', to: 'e4', san: 'e4')],
      );
      final decE5 = RepertoireDecision(
        id: 'dec-e5',
        studyId: study.id,
        chapterId: chapter.id,
        nodeId: 'node-e5',
        expectedMoves: const [RepertoireMove(from: 'g1', to: 'f3', san: 'Nf3')],
        canonicalStateId: 'canon-e5',
      );
      final decC5 = RepertoireDecision(
        id: 'dec-c5',
        studyId: study.id,
        chapterId: chapter.id,
        nodeId: 'node-c5',
        expectedMoves: const [RepertoireMove(from: 'g1', to: 'f3', san: 'Nf3')],
        canonicalStateId: 'canon-c5',
      );

      final engine = ReviewEngine(clock: clock);

      // States keyed ONLY by canonicalId:
      // dec-e5: NOT due (due in 5 days)
      // dec-c5: DUE (due 1 hour ago)
      final states = {
        'dec-1': ReviewState.initial(decisionId: 'dec-1'),
        'canon-e5': ReviewState(
          decisionId: 'canon-e5',
          nextDueAt: baseTime.add(const Duration(days: 5)),
          repetitionCount: 2,
        ),
        'canon-c5': ReviewState(
          decisionId: 'canon-c5',
          nextDueAt: baseTime.subtract(const Duration(hours: 1)),
          repetitionCount: 1,
        ),
      };

      final session = engine.createSession(
        studies: [study],
        chapters: [chapter],
        decisions: [dec1, decE5, decC5],
        reviewStates: states,
      );

      expect(session.currentPrompt?.decision.id, 'dec-1');

      // User plays 1. e4. Opponent must select 1... c5 because canon-c5 is due!
      final stepResult = session.submitMove(from: 'e2', to: 'e4');
      expect(stepResult.isCorrect, isTrue);
      expect(stepResult.autoPlayedMoves.first.move.san, 'c5');
    });

    test('same position with different accepted sets keeps separate SRS memory', () {
      // Two modern decisions ask different questions at the same position:
      // A accepts {e4, d4}, B accepts {e4, c4}. They share the (FEN, e4) pair,
      // so the single-move adjacency slot collides — reviewing A must still
      // update only A's complete-set state and leave B untouched.
      const startFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
      const startKey = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -';
      const study = Study(id: 'study-collision', title: 'Collision');
      const rootA = RepertoireNode(
        id: 'node-a',
        fen: startFen,
        fenKey: startKey,
        children: [
          RepertoireNode(
            id: 'node-a-e4',
            fen: startFen,
            fenKey: startKey,
            incomingMove: RepertoireMove(from: 'e2', to: 'e4', san: 'e4'),
          ),
          RepertoireNode(
            id: 'node-a-d4',
            fen: startFen,
            fenKey: startKey,
            incomingMove: RepertoireMove(from: 'd2', to: 'd4', san: 'd4'),
          ),
        ],
      );
      const rootB = RepertoireNode(
        id: 'node-b',
        fen: startFen,
        fenKey: startKey,
        children: [
          RepertoireNode(
            id: 'node-b-e4',
            fen: startFen,
            fenKey: startKey,
            incomingMove: RepertoireMove(from: 'e2', to: 'e4', san: 'e4'),
          ),
          RepertoireNode(
            id: 'node-b-c4',
            fen: startFen,
            fenKey: startKey,
            incomingMove: RepertoireMove(from: 'c2', to: 'c4', san: 'c4'),
          ),
        ],
      );
      const chapterA = Chapter(
        id: 'chapter-a',
        studyId: 'study-collision',
        sourceOrder: 0,
        title: 'A',
        startingFen: startFen,
        root: rootA,
      );
      const chapterB = Chapter(
        id: 'chapter-b',
        studyId: 'study-collision',
        sourceOrder: 1,
        title: 'B',
        startingFen: startFen,
        root: rootB,
      );
      const decA = RepertoireDecision(
        id: 'dec-a',
        studyId: 'study-collision',
        chapterId: 'chapter-a',
        nodeId: 'node-a',
        expectedMoves: [
          RepertoireMove(from: 'e2', to: 'e4', san: 'e4'),
          RepertoireMove(from: 'd2', to: 'd4', san: 'd4'),
        ],
        canonicalStateId: 'canon-a',
      );
      const decB = RepertoireDecision(
        id: 'dec-b',
        studyId: 'study-collision',
        chapterId: 'chapter-b',
        nodeId: 'node-b',
        expectedMoves: [
          RepertoireMove(from: 'e2', to: 'e4', san: 'e4'),
          RepertoireMove(from: 'c2', to: 'c4', san: 'c4'),
        ],
        canonicalStateId: 'canon-b',
      );

      final stateB = ReviewState(
        decisionId: 'canon-b',
        nextDueAt: baseTime.add(const Duration(days: 30)),
        repetitionCount: 5,
        stability: 777.0,
        difficulty: 4.0,
        firstReviewedAt: baseTime.subtract(const Duration(days: 40)),
        lastReviewedAt: baseTime.subtract(const Duration(days: 5)),
      );
      final reviewStates = {
        'canon-a': ReviewState(
          decisionId: 'canon-a',
          nextDueAt: baseTime.subtract(const Duration(hours: 1)),
          repetitionCount: 1,
        ),
        'canon-b': stateB,
      };

      final engine = ReviewEngine(clock: clock);
      final session = engine.createSession(
        studies: [study],
        chapters: [chapterA, chapterB],
        decisions: [decA, decB],
        reviewStates: reviewStates,
      );

      // Only A is due; B's learned state keeps it out of the queue.
      expect(session.remainingDueCount, 1);
      expect(session.currentPrompt?.decision.id, 'dec-a');

      final result = session.submitMove(from: 'e2', to: 'e4');
      expect(result.isCorrect, isTrue);
      expect(result.updatedState.decisionId, 'canon-a');
      expect(result.updatedState.repetitionCount, 2);

      // B's memory is untouched: no shared scheduling across questions.
      expect(session.reviewStates['canon-b'], equals(stateB));
    });

    // SPEC INV-015: side to move parsed robustly from FEN using dartchess Setup.
    group('ReviewSession.sideFromFen', () {
      test('identifies White to move from standard start FEN', () {
        expect(
          ReviewSession.sideFromFen('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'),
          Side.white,
        );
      });

      test('identifies Black to move from standard move-1 FEN', () {
        expect(
          ReviewSession.sideFromFen('rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1'),
          Side.black,
        );
      });

      test('handles whitespace padding and partial FENs', () {
        expect(
          ReviewSession.sideFromFen(
            '  rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1 \n',
          ),
          Side.black,
        );
        expect(ReviewSession.sideFromFen('8/8/8/8/8/8/8/8 w - - 0 1'), Side.white);
      });

      test('falls back gracefully to Side.white on malformed FEN', () {
        expect(ReviewSession.sideFromFen(''), Side.white);
        expect(ReviewSession.sideFromFen('not a valid fen'), Side.white);
        expect(ReviewSession.sideFromFen('8/8/8/8/8/8/8/8 x - - 0 1'), Side.white);
      });

      test('session prompt sideToMove reflects custom starting FEN with Black to move', () {
        const blackToMoveFen = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1';
        final study = Study(
          id: 's-black',
          title: 'Black Repertoire',
          createdAt: baseTime,
          updatedAt: baseTime,
        );
        const chapter = Chapter(
          id: 'ch-black',
          studyId: 's-black',
          sourceOrder: 0,
          title: 'French Defense',
          startingFen: blackToMoveFen,
          root: RepertoireNode(
            id: 'node-root-black',
            fen: blackToMoveFen,
            fenKey: 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq -',
          ),
        );
        final dec = RepertoireDecision(
          id: 'dec-black-1',
          studyId: study.id,
          chapterId: chapter.id,
          nodeId: 'node-root-black',
          expectedMoves: const [RepertoireMove(from: 'e7', to: 'e6', san: 'e6')],
        );

        final engine = ReviewEngine(clock: clock);
        final session = engine.createSession(
          studies: [study],
          chapters: [chapter],
          decisions: [dec],
          reviewStates: const {},
        );

        expect(session.currentPrompt?.sideToMove, Side.black);
      });
    });
  });
}
