// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC coverage: INV-066.
import 'dart:math';

import 'package:chess_srs/src/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

/// Review queue order (P-ORDER, INV-066): the due *set* never depends on the
/// order — urgency filtering and the quota cut apply first. By-line order
/// presents the same cards walking study, then chapter, then tree order.
///
/// Chapter A drills 1.e4 e5 2.Nf3; chapter B drills 1.d4 d5 2.Nf3. B's cards
/// are deliberately more overdue, so due-date order serves B first.
void main() {
  group('ReviewSession queue order', () {
    late FixedClock clock;
    late DateTime baseTime;

    setUp(() {
      baseTime = DateTime.utc(2026, 10, 3, 12, 0, 0);
      clock = FixedClock(baseTime);
    });

    (Study, Chapter, Chapter, List<RepertoireDecision>) buildTwoLines() {
      const startFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
      const startKey = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -';

      final study = Study(
        id: 'study-lines',
        title: 'Lines',
        createdAt: baseTime,
        updatedAt: baseTime,
      );

      final chapterA = Chapter(
        id: 'chapter-a',
        studyId: 'study-lines',
        sourceOrder: 0,
        title: 'E4 line',
        startingFen: startFen,
        createdAt: baseTime,
        root: const RepertoireNode(
          id: 'node-a-root',
          fen: startFen,
          fenKey: startKey,
          children: [
            RepertoireNode(
              id: 'node-a-e4',
              fen: 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1',
              fenKey: 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq -',
              incomingMove: RepertoireMove(from: 'e2', to: 'e4', san: 'e4'),
              children: [
                RepertoireNode(
                  id: 'node-a-e5',
                  fen: 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2',
                  fenKey: 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq -',
                  incomingMove: RepertoireMove(from: 'e7', to: 'e5', san: 'e5'),
                  children: [
                    RepertoireNode(
                      id: 'node-a-nf3',
                      fen: 'rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2',
                      fenKey: 'rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq -',
                      incomingMove: RepertoireMove(from: 'g1', to: 'f3', san: 'Nf3'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      );

      final chapterB = Chapter(
        id: 'chapter-b',
        studyId: 'study-lines',
        sourceOrder: 1,
        title: 'D4 line',
        startingFen: startFen,
        createdAt: baseTime,
        root: const RepertoireNode(
          id: 'node-b-root',
          fen: startFen,
          fenKey: startKey,
          children: [
            RepertoireNode(
              id: 'node-b-d4',
              fen: 'rnbqkbnr/ppp1pppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq - 0 1',
              fenKey: 'rnbqkbnr/ppp1pppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq -',
              incomingMove: RepertoireMove(from: 'd2', to: 'd4', san: 'd4'),
              children: [
                RepertoireNode(
                  id: 'node-b-d5',
                  fen: 'rnbqkbnr/ppp1pppp/8/3p4/3P4/8/PPP1PPPP/RNBQKBNR w KQkq - 0 2',
                  fenKey: 'rnbqkbnr/ppp1pppp/8/3p4/3P4/8/PPP1PPPP/RNBQKBNR w KQkq -',
                  incomingMove: RepertoireMove(from: 'd7', to: 'd5', san: 'd5'),
                  children: [
                    RepertoireNode(
                      id: 'node-b-nf3',
                      fen: 'rnbqkbnr/ppp1pppp/8/3p4/3P4/5N2/PPP1PPPP/RNBQKB1R b KQkq - 1 2',
                      fenKey: 'rnbqkbnr/ppp1pppp/8/3p4/3P4/5N2/PPP1PPPP/RNBQKB1R b KQkq -',
                      incomingMove: RepertoireMove(from: 'g1', to: 'f3', san: 'Nf3'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      );

      const decisions = [
        RepertoireDecision(
          id: 'dec-a-root',
          studyId: 'study-lines',
          chapterId: 'chapter-a',
          nodeId: 'node-a-root',
          expectedMoves: [RepertoireMove(from: 'e2', to: 'e4', san: 'e4')],
        ),
        RepertoireDecision(
          id: 'dec-a-2',
          studyId: 'study-lines',
          chapterId: 'chapter-a',
          nodeId: 'node-a-e5',
          expectedMoves: [RepertoireMove(from: 'g1', to: 'f3', san: 'Nf3')],
        ),
        RepertoireDecision(
          id: 'dec-b-root',
          studyId: 'study-lines',
          chapterId: 'chapter-b',
          nodeId: 'node-b-root',
          expectedMoves: [RepertoireMove(from: 'd2', to: 'd4', san: 'd4')],
        ),
        RepertoireDecision(
          id: 'dec-b-2',
          studyId: 'study-lines',
          chapterId: 'chapter-b',
          nodeId: 'node-b-d5',
          expectedMoves: [RepertoireMove(from: 'g1', to: 'f3', san: 'Nf3')],
        ),
      ];

      return (study, chapterA, chapterB, decisions);
    }

    Map<String, ReviewState> scrambledStates(List<RepertoireDecision> decisions) {
      // B long overdue, A barely due: due-date order serves B first.
      return {
        for (final d in decisions)
          d.id: ReviewState(
            decisionId: d.id,
            nextDueAt: d.chapterId == 'chapter-b'
                ? baseTime.subtract(const Duration(days: 5))
                : baseTime.subtract(const Duration(hours: 1)),
          ),
      };
    }

    ReviewSession startSession(
      Study study,
      Chapter chapterA,
      Chapter chapterB,
      List<RepertoireDecision> decisions,
      Map<String, ReviewState> states, {
      ReviewOrder order = ReviewOrder.byLine,
      int? remainingDailyQuota,
    }) {
      final engine = ReviewEngine(clock: clock);
      return engine.createSession(
        studies: [study],
        chapters: [chapterA, chapterB],
        decisions: decisions,
        reviewStates: states,
        order: order,
        remainingDailyQuota: remainingDailyQuota,
        random: Random(0),
      );
    }

    List<String> walkSession(ReviewSession session, List<(String, String)> moves) {
      final seen = <String>[session.currentPrompt!.nodeId];
      for (final move in moves) {
        session.submitMove(from: move.$1, to: move.$2);
        final prompt = session.currentPrompt;
        if (prompt != null) seen.add(prompt.nodeId);
      }
      return seen;
    }

    test('by-line order walks each chapter in tree order despite due dates', () {
      final (study, chapterA, chapterB, decisions) = buildTwoLines();
      final session = startSession(
        study,
        chapterA,
        chapterB,
        decisions,
        scrambledStates(decisions),
      );

      final seen = walkSession(session, const [
        ('e2', 'e4'),
        ('g1', 'f3'),
        ('d2', 'd4'),
        ('g1', 'f3'),
      ]);

      expect(seen, ['node-a-root', 'node-a-e5', 'node-b-root', 'node-b-d5']);
      expect(session.isComplete, isTrue);
    });

    test('due-date order still serves the most overdue first', () {
      final (study, chapterA, chapterB, decisions) = buildTwoLines();
      final session = startSession(
        study,
        chapterA,
        chapterB,
        decisions,
        scrambledStates(decisions),
        order: ReviewOrder.dueDate,
      );

      expect(session.currentPrompt?.nodeId, 'node-b-root');
    });

    List<String> walkToEnd(ReviewSession session) {
      final seen = <String>[];
      for (var i = 0; i < 10 && session.currentPrompt != null; i++) {
        final prompt = session.currentPrompt!;
        seen.add(prompt.nodeId);
        final move = prompt.expectedMoves.first;
        session.submitMove(from: move.from, to: move.to, promotion: move.promotion);
      }
      return seen;
    }

    test('random order is deterministic per seed and covers the due set', () {
      final (study, chapterA, chapterB, decisions) = buildTwoLines();
      ReviewSession startSeeded() {
        final engine = ReviewEngine(clock: clock);
        return engine.createSession(
          studies: [study],
          chapters: [chapterA, chapterB],
          decisions: decisions,
          reviewStates: scrambledStates(decisions),
          order: ReviewOrder.random,
          random: Random(0),
        );
      }

      final first = startSeeded();
      final second = startSeeded();
      final seenFirst = walkToEnd(first);
      final seenSecond = walkToEnd(second);

      expect(seenFirst, seenSecond);
      expect(seenFirst.toSet(), {'node-a-root', 'node-a-e5', 'node-b-root', 'node-b-d5'});
      expect(first.isComplete, isTrue);
    });

    test('the daily quota still cuts the most overdue first under by-line order', () {
      final (study, chapterA, chapterB, decisions) = buildTwoLines();
      final session = startSession(
        study,
        chapterA,
        chapterB,
        decisions,
        scrambledStates(decisions),
        remainingDailyQuota: 1,
      );

      // Same due set rule as ever: quota keeps the single most urgent card.
      expect(session.currentPrompt?.nodeId, 'node-b-root');
      expect(session.remainingDueCount, 1);
    });
  });
}
