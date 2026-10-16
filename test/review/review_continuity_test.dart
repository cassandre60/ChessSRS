// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC coverage: INV-022, INV-066.
import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/model/study/study_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

/// Line continuity (owner-reported A → C skips over an unasked B, plus
/// position-to-position jumps at branches).
///
/// `dueOnly` keeps the SRS-efficient behavior: only due positions are
/// quizzed, known moves auto-play, and the opponent steers toward due
/// material (INV-022). `fullLine` quizzes every step of the walked line in
/// tree order — even when not yet due — and picks branches deterministically
/// (mainline first), so a line never jumps over its middle.
void main() {
  group('ReviewContinuity', () {
    late FixedClock clock;
    late DateTime baseTime;

    setUp(() {
      baseTime = DateTime.utc(2026, 10, 16, 12, 0, 0);
      clock = FixedClock(baseTime);
    });

    // Root -> 1. e4 (dec-1) -> 1... e5 -> 2. Nf3 (dec-2) -> 2... Nc6 -> 3. Bc4 (dec-3)
    (Study, Chapter, List<RepertoireDecision>) buildLine() {
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

      final study = Study(
        id: 'study-line',
        title: 'Line',
        createdAt: baseTime,
        updatedAt: baseTime,
      );
      final chapter = Chapter(
        id: 'chapter-line',
        studyId: study.id,
        sourceOrder: 0,
        title: 'Line',
        startingFen: rootNode.fen,
        root: rootNode,
        createdAt: baseTime,
      );
      const decisions = [
        RepertoireDecision(
          id: 'dec-1',
          studyId: 'study-line',
          chapterId: 'chapter-line',
          nodeId: 'node-root',
          expectedMoves: [RepertoireMove(from: 'e2', to: 'e4', san: 'e4')],
        ),
        RepertoireDecision(
          id: 'dec-2',
          studyId: 'study-line',
          chapterId: 'chapter-line',
          nodeId: 'node-e5',
          expectedMoves: [RepertoireMove(from: 'g1', to: 'f3', san: 'Nf3')],
        ),
        RepertoireDecision(
          id: 'dec-3',
          studyId: 'study-line',
          chapterId: 'chapter-line',
          nodeId: 'node-nc6',
          expectedMoves: [RepertoireMove(from: 'f1', to: 'c4', san: 'Bc4')],
        ),
      ];
      return (study, chapter, decisions);
    }

    // SPEC INV-022. Due-only keeps the efficient behavior: the learned middle
    // step auto-plays and review jumps from A to C.
    test('dueOnly skips the learned middle step (efficient, current behavior)', () {
      final (study, chapter, decisions) = buildLine();
      final reviewStates = {
        'dec-2': ReviewState(
          decisionId: 'dec-2',
          nextDueAt: baseTime.add(const Duration(days: 5)),
          repetitionCount: 2,
        ),
      };
      final session = ReviewEngine(clock: clock).createSession(
        studies: [study],
        chapters: [chapter],
        decisions: decisions,
        reviewStates: reviewStates,
        continuity: ReviewContinuity.dueOnly,
      );

      expect(session.currentPrompt?.decision.id, 'dec-1');
      final result = session.submitMove(from: 'e2', to: 'e4');
      expect(result.isCorrect, isTrue);
      expect(result.nextPrompt?.decision.id, 'dec-3');
      expect(
        result.autoPlayedMoves.where((m) => m.isUserMove).map((m) => m.move.san),
        contains('Nf3'),
      );
    });

    // SPEC INV-022, INV-066. Full line never jumps over an unasked middle
    // step: A is followed by B, then C, in tree order.
    test('fullLine quizzes every step of the line in order, even when not due', () {
      final (study, chapter, decisions) = buildLine();
      final reviewStates = {
        'dec-2': ReviewState(
          decisionId: 'dec-2',
          nextDueAt: baseTime.add(const Duration(days: 5)),
          repetitionCount: 2,
        ),
      };
      final session = ReviewEngine(clock: clock).createSession(
        studies: [study],
        chapters: [chapter],
        decisions: decisions,
        reviewStates: reviewStates,
        continuity: ReviewContinuity.fullLine,
      );

      expect(session.currentPrompt?.decision.id, 'dec-1');
      final afterA = session.submitMove(from: 'e2', to: 'e4');
      expect(afterA.isCorrect, isTrue);
      // B is asked, not auto-played: only the opponent reply precedes it.
      expect(afterA.nextPrompt?.decision.id, 'dec-2');
      expect(afterA.autoPlayedMoves.length, 1);
      expect(afterA.autoPlayedMoves.single.move.san, 'e5');

      final afterB = session.submitMove(from: 'g1', to: 'f3');
      expect(afterB.isCorrect, isTrue);
      expect(afterB.nextPrompt?.decision.id, 'dec-3');
    });

    // SPEC INV-022. Full line picks branches deterministically (mainline
    // first) instead of steering toward whichever branch holds due material.
    test('fullLine follows tree order at branches, not due density', () {
      const root = RepertoireNode(
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
      final study = Study(
        id: 'study-branches',
        title: 'Branches',
        createdAt: baseTime,
        updatedAt: baseTime,
      );
      final chapter = Chapter(
        id: 'ch-1',
        studyId: study.id,
        sourceOrder: 0,
        title: 'Main',
        startingFen: root.fen,
        root: root,
      );
      const dec1 = RepertoireDecision(
        id: 'dec-1',
        studyId: 'study-branches',
        chapterId: 'ch-1',
        nodeId: 'root',
        expectedMoves: [RepertoireMove(from: 'e2', to: 'e4', san: 'e4')],
      );
      const decE5 = RepertoireDecision(
        id: 'dec-e5',
        studyId: 'study-branches',
        chapterId: 'ch-1',
        nodeId: 'node-e5',
        expectedMoves: [RepertoireMove(from: 'g1', to: 'f3', san: 'Nf3')],
      );
      const decC5 = RepertoireDecision(
        id: 'dec-c5',
        studyId: 'study-branches',
        chapterId: 'ch-1',
        nodeId: 'node-c5',
        expectedMoves: [RepertoireMove(from: 'g1', to: 'f3', san: 'Nf3')],
      );

      // Due density favors c5, but tree order leads with e5.
      final states = {
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
      final session = ReviewEngine(clock: clock).createSession(
        studies: [study],
        chapters: [chapter],
        decisions: const [dec1, decE5, decC5],
        reviewStates: states,
        continuity: ReviewContinuity.fullLine,
      );

      final result = session.submitMove(from: 'e2', to: 'e4');
      expect(result.isCorrect, isTrue);
      expect(result.autoPlayedMoves.single.move.san, 'e5');
      expect(result.nextPrompt?.decision.id, 'dec-e5');
    });

    test('line continuity defaults to due-only and round-trips', () {
      expect(StudyPrefs.defaults.reviewContinuity, ReviewContinuity.dueOnly);
      const prefs = StudyPrefs.defaults;
      expect(StudyPrefs.fromJson(prefs.toJson()), prefs);
    });

    // SPEC INV-021, INV-022. Acknowledging a lapse mid-line does not
    // abandon the line: review continues with the next decision down the
    // same line while the failed card waits for its re-test. Due-only pops
    // the next queue card here, which is a different line.
    test('fullLine continueAfterIncorrect stays in the same line', () {
      final (study, chapter, decisions) = buildLine();
      const zRoot = RepertoireNode(
        id: 'node-z-root',
        fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
        fenKey: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -',
        children: [
          RepertoireNode(
            id: 'node-z-d4',
            fen: 'rnbqkbnr/ppp1pppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq - 0 1',
            fenKey: 'rnbqkbnr/ppp1pppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq -',
            incomingMove: RepertoireMove(from: 'd2', to: 'd4', san: 'd4'),
          ),
        ],
      );
      final chapterZ = Chapter(
        id: 'chapter-z',
        studyId: study.id,
        sourceOrder: 1,
        title: 'Other line',
        startingFen: zRoot.fen,
        root: zRoot,
        createdAt: baseTime,
      );
      const decZ = RepertoireDecision(
        id: 'dec-z',
        studyId: 'study-line',
        chapterId: 'chapter-z',
        nodeId: 'node-z-root',
        expectedMoves: [RepertoireMove(from: 'd2', to: 'd4', san: 'd4')],
      );
      final allDecisions = [...decisions, decZ];
      final reviewStates = {
        'dec-1': ReviewState(
          decisionId: 'dec-1',
          nextDueAt: baseTime.subtract(const Duration(days: 5)),
          repetitionCount: 1,
        ),
        'dec-z': ReviewState(
          decisionId: 'dec-z',
          nextDueAt: baseTime.subtract(const Duration(days: 1)),
          repetitionCount: 1,
        ),
        'dec-2': ReviewState(
          decisionId: 'dec-2',
          nextDueAt: baseTime.subtract(const Duration(hours: 2)),
          repetitionCount: 1,
        ),
        'dec-3': ReviewState(
          decisionId: 'dec-3',
          nextDueAt: baseTime.subtract(const Duration(hours: 1)),
          repetitionCount: 1,
        ),
      };
      final session = ReviewEngine(clock: clock).createSession(
        studies: [study],
        chapters: [chapter, chapterZ],
        decisions: allDecisions,
        reviewStates: reviewStates,
        order: ReviewOrder.dueDate,
        continuity: ReviewContinuity.fullLine,
      );

      expect(session.currentPrompt?.decision.id, 'dec-1');
      final lapse = session.submitMove(from: 'd2', to: 'd4');
      expect(lapse.isCorrect, isFalse);

      session.continueAfterIncorrect();
      // Next decision down the same line — not dec-z from the other chapter.
      expect(session.currentPrompt?.decision.id, 'dec-2');
      // Nothing dropped: the failed card waits for its re-test.
      expect(session.remainingDueCount, 4);
    });
    // SPEC INV-022, INV-066. A queued mid-line card opens at its line's
    // first unanswered move: with only C due, review starts at A and walks
    // A → B → C instead of jumping straight to C.
    test('fullLine opens a queued mid-line card at its line start', () {
      final (study, chapter, decisions) = buildLine();
      final future = baseTime.add(const Duration(days: 5));
      final reviewStates = {
        'dec-1': ReviewState(decisionId: 'dec-1', nextDueAt: future, repetitionCount: 2),
        'dec-2': ReviewState(decisionId: 'dec-2', nextDueAt: future, repetitionCount: 2),
      };
      final session = ReviewEngine(clock: clock).createSession(
        studies: [study],
        chapters: [chapter],
        decisions: decisions,
        reviewStates: reviewStates,
        continuity: ReviewContinuity.fullLine,
      );

      // Only C was queued, but the session opens at the line start.
      expect(session.currentPrompt?.decision.id, 'dec-1');

      final seen = <String>[session.currentPrompt!.nodeId];
      for (var i = 0; i < 4 && session.currentPrompt != null; i++) {
        final prompt = session.currentPrompt!;
        final move = prompt.expectedMoves.first;
        session.submitMove(from: move.from, to: move.to, promotion: move.promotion);
        if (session.currentPrompt != null) seen.add(session.currentPrompt!.nodeId);
      }
      expect(seen, ['node-root', 'node-e5', 'node-nc6']);
      expect(session.isComplete, isTrue);
    });

    // SPEC INV-022. Branches are never steered: the walk follows PGN tree
    // order (mainline first) even when the queued card lives down the
    // sideline. The bypassed sideline is not lost: its walk missed, so the
    // next pop prompts it directly instead of walking the line again.
    test('fullLine walks the mainline first, then prompts the bypassed sideline', () {
      const root = RepertoireNode(
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
      final study = Study(
        id: 'study-branches',
        title: 'Branches',
        createdAt: baseTime,
        updatedAt: baseTime,
      );
      final chapter = Chapter(
        id: 'ch-1',
        studyId: study.id,
        sourceOrder: 0,
        title: 'Main',
        startingFen: root.fen,
        root: root,
      );
      const dec1 = RepertoireDecision(
        id: 'dec-1',
        studyId: 'study-branches',
        chapterId: 'ch-1',
        nodeId: 'root',
        expectedMoves: [RepertoireMove(from: 'e2', to: 'e4', san: 'e4')],
      );
      const decE5 = RepertoireDecision(
        id: 'dec-e5',
        studyId: 'study-branches',
        chapterId: 'ch-1',
        nodeId: 'node-e5',
        expectedMoves: [RepertoireMove(from: 'g1', to: 'f3', san: 'Nf3')],
      );
      const decC5 = RepertoireDecision(
        id: 'dec-c5',
        studyId: 'study-branches',
        chapterId: 'ch-1',
        nodeId: 'node-c5',
        expectedMoves: [RepertoireMove(from: 'g1', to: 'f3', san: 'Nf3')],
      );

      // C (sideline) is most overdue, so due-date order pops it first even
      // though the line starts at dec-1.
      final states = {
        'dec-1': ReviewState(
          decisionId: 'dec-1',
          nextDueAt: baseTime.subtract(const Duration(hours: 1)),
          repetitionCount: 1,
        ),
        'dec-e5': ReviewState(
          decisionId: 'dec-e5',
          nextDueAt: baseTime.add(const Duration(days: 5)),
          repetitionCount: 2,
        ),
        'dec-c5': ReviewState(
          decisionId: 'dec-c5',
          nextDueAt: baseTime.subtract(const Duration(days: 5)),
          repetitionCount: 1,
        ),
      };
      final session = ReviewEngine(clock: clock).createSession(
        studies: [study],
        chapters: [chapter],
        decisions: const [dec1, decE5, decC5],
        reviewStates: states,
        order: ReviewOrder.dueDate,
        continuity: ReviewContinuity.fullLine,
      );

      // Opens at the line start, not at C.
      expect(session.currentPrompt?.decision.id, 'dec-1');
      final result = session.submitMove(from: 'e2', to: 'e4');
      expect(result.isCorrect, isTrue);
      // Mainline first: e5, even though C waits down the c5 sideline.
      expect(result.autoPlayedMoves.single.move.san, 'e5');
      expect(result.nextPrompt?.decision.id, 'dec-e5');

      // The mainline ends at the e5 leaf; the bypassed sideline C is
      // prompted directly rather than walked past again.
      final afterE5 = session.submitMove(from: 'g1', to: 'f3');
      expect(afterE5.isCorrect, isTrue);
      expect(session.currentPrompt?.decision.id, 'dec-c5');
      expect(session.submitMove(from: 'g1', to: 'f3').isCorrect, isTrue);
      expect(session.isComplete, isTrue);
    });

    // SPEC INV-022. A settings flip mid-review steers the very next
    // traversal: no rebuild, no lost progress, no stale behavior.
    test('assigning continuity steers the next traversal without a rebuild', () {
      final (study, chapter, decisions) = buildLine();
      final reviewStates = {
        'dec-2': ReviewState(
          decisionId: 'dec-2',
          nextDueAt: baseTime.add(const Duration(days: 5)),
          repetitionCount: 2,
        ),
      };
      final session = ReviewEngine(clock: clock).createSession(
        studies: [study],
        chapters: [chapter],
        decisions: decisions,
        reviewStates: reviewStates,
      );
      expect(session.continuity, ReviewContinuity.dueOnly);

      session.continuity = ReviewContinuity.fullLine;
      final afterA = session.submitMove(from: 'e2', to: 'e4');
      expect(afterA.isCorrect, isTrue);
      expect(afterA.nextPrompt?.decision.id, 'dec-2');
    });
  });
}
