// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC coverage: INV-065.
import 'dart:math';

import 'package:chess_srs/src/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

/// Review-time transposition support (P-TRANSPOSE): a legal move that matches
/// no expected continuation here is still accepted when the position it
/// reaches exists in the active scope's repertoire tree.
///
/// Chapter A drills 2.Nf3; chapter B reaches the same positions one move
/// order later (2.Bc4 first). Playing 2.Bc4 at A's prompt is book — just book
/// from the other line.
void main() {
  group('ReviewSession transpositions', () {
    late FixedClock clock;
    late DateTime baseTime;

    setUp(() {
      baseTime = DateTime.utc(2026, 10, 3, 10, 0, 0);
      clock = FixedClock(baseTime);
    });

    // A: start -> e4 -> e5 (prompt, expects Nf3). B: start -> e4 -> e5 ->
    // Bc4 -> Nf6 (prompt, expects d4) -> d4. Playing Bc4 at A's prompt
    // reaches B's Bc4 position exactly.
    (Study, Chapter, Chapter, List<RepertoireDecision>) buildTransposedRepertoire() {
      const startFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
      const startKey = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -';
      const afterE4Fen = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1';
      const afterE4Key = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq -';
      const afterE5Fen = 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2';
      const afterE5Key = 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq -';
      const afterBc4Fen = 'rnbqkbnr/pppp1ppp/8/4p3/2B1P3/8/PPPP1PPP/RNBQK1NR b KQkq - 1 2';
      const afterBc4Key = 'rnbqkbnr/pppp1ppp/8/4p3/2B1P3/8/PPPP1PPP/RNBQK1NR b KQkq -';
      const afterNf6Fen = 'rnbqkb1r/pppp1ppp/5n2/4p3/2B1P3/8/PPPP1PPP/RNBQK1NR w KQkq - 2 3';
      const afterNf6Key = 'rnbqkb1r/pppp1ppp/5n2/4p3/2B1P3/8/PPPP1PPP/RNBQK1NR w KQkq -';
      const afterD4Fen = 'rnbqkb1r/pppp1ppp/5n2/4p3/2BPP3/8/PPP2PPP/RNBQK1NR b KQkq - 0 3';
      const afterD4Key = 'rnbqkb1r/pppp1ppp/5n2/4p3/2BPP3/8/PPP2PPP/RNBQK1NR b KQkq -';

      final study = Study(
        id: 'study-transpose',
        title: 'Transpositions',
        createdAt: baseTime,
        updatedAt: baseTime,
      );

      final chapterA = Chapter(
        id: 'chapter-a',
        studyId: 'study-transpose',
        sourceOrder: 0,
        title: 'Nf3 line',
        createdAt: baseTime,
        startingFen: startFen,
        root: const RepertoireNode(
          id: 'node-a-root',
          fen: startFen,
          fenKey: startKey,
          children: [
            RepertoireNode(
              id: 'node-a-e4',
              fen: afterE4Fen,
              fenKey: afterE4Key,
              incomingMove: RepertoireMove(from: 'e2', to: 'e4', san: 'e4'),
              children: [
                RepertoireNode(
                  id: 'node-a-e5',
                  fen: afterE5Fen,
                  fenKey: afterE5Key,
                  incomingMove: RepertoireMove(from: 'e7', to: 'e5', san: 'e5'),
                ),
              ],
            ),
          ],
        ),
      );

      final chapterB = Chapter(
        id: 'chapter-b',
        studyId: 'study-transpose',
        sourceOrder: 1,
        title: 'Bc4 line',
        createdAt: baseTime,
        startingFen: startFen,
        root: const RepertoireNode(
          id: 'node-b-root',
          fen: startFen,
          fenKey: startKey,
          children: [
            RepertoireNode(
              id: 'node-b-e4',
              fen: afterE4Fen,
              fenKey: afterE4Key,
              incomingMove: RepertoireMove(from: 'e2', to: 'e4', san: 'e4'),
              children: [
                RepertoireNode(
                  id: 'node-b-e5',
                  fen: afterE5Fen,
                  fenKey: afterE5Key,
                  incomingMove: RepertoireMove(from: 'e7', to: 'e5', san: 'e5'),
                  children: [
                    RepertoireNode(
                      id: 'node-b-bc4',
                      fen: afterBc4Fen,
                      fenKey: afterBc4Key,
                      incomingMove: RepertoireMove(from: 'f1', to: 'c4', san: 'Bc4'),
                      children: [
                        RepertoireNode(
                          id: 'node-b-nf6',
                          fen: afterNf6Fen,
                          fenKey: afterNf6Key,
                          incomingMove: RepertoireMove(from: 'g8', to: 'f6', san: 'Nf6'),
                          children: [
                            RepertoireNode(
                              id: 'node-b-d4',
                              fen: afterD4Fen,
                              fenKey: afterD4Key,
                              incomingMove: RepertoireMove(from: 'd2', to: 'd4', san: 'd4'),
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
        ),
      );

      const decisions = [
        RepertoireDecision(
          id: 'dec-a-root',
          studyId: 'study-transpose',
          chapterId: 'chapter-a',
          nodeId: 'node-a-root',
          expectedMoves: [RepertoireMove(from: 'e2', to: 'e4', san: 'e4')],
        ),
        RepertoireDecision(
          id: 'dec-a-2',
          studyId: 'study-transpose',
          chapterId: 'chapter-a',
          nodeId: 'node-a-e5',
          expectedMoves: [RepertoireMove(from: 'g1', to: 'f3', san: 'Nf3')],
        ),
        RepertoireDecision(
          id: 'dec-b-3',
          studyId: 'study-transpose',
          chapterId: 'chapter-b',
          nodeId: 'node-b-nf6',
          expectedMoves: [RepertoireMove(from: 'd2', to: 'd4', san: 'd4')],
        ),
      ];

      return (study, chapterA, chapterB, decisions);
    }

    ReviewSession startSession(
      Study study,
      Chapter chapterA,
      Chapter chapterB,
      List<RepertoireDecision> decisions, {
      ReviewScope scope = const ReviewScope.all(),
      bool transposeAccept = true,
    }) {
      final engine = ReviewEngine(clock: clock);
      return engine.createSession(
        studies: [study],
        chapters: [chapterA, chapterB],
        decisions: decisions,
        reviewStates: const {},
        scope: scope,
        transposeAccept: transposeAccept,
        random: Random(0),
      );
    }

    test('accepts a transposed repertoire move and continues from that line', () {
      final (study, chapterA, chapterB, decisions) = buildTransposedRepertoire();
      final session = startSession(study, chapterA, chapterB, decisions);

      expect(session.currentPrompt?.nodeId, 'node-a-root');
      final first = session.submitMove(from: 'e2', to: 'e4');
      expect(first.isCorrect, isTrue);
      expect(session.currentPrompt?.nodeId, 'node-a-e5');

      // 2.Bc4 is not expected here (Nf3 is), but it is book in chapter B.
      final result = session.submitMove(from: 'f1', to: 'c4');

      expect(result.isCorrect, isTrue);
      expect(result.movePlayed.san, 'Bc4');
      expect(result.event?.result, ReviewResult.correct);
      // The drilled decision is graded; review continues from the
      // transposed line: opponent auto-replies Nf6, next prompt is B's d4.
      expect(session.reviewStates['dec-a-2']?.repetitionCount, 1);
      expect(result.nextPrompt?.nodeId, 'node-b-nf6');
      expect(result.nextPrompt?.chapterId, 'chapter-b');
    });

    test('a transposition outside the scope stays incorrect', () {
      final (study, chapterA, chapterB, decisions) = buildTransposedRepertoire();
      final session = startSession(
        study,
        chapterA,
        chapterB,
        decisions,
        scope: const ReviewScope.chapter(studyId: 'study-transpose', chapterId: 'chapter-a'),
      );

      session.submitMove(from: 'e2', to: 'e4');
      expect(session.currentPrompt?.nodeId, 'node-a-e5');

      // Bc4 reaches chapter B, which is out of scope: still a lapse.
      final result = session.submitMove(from: 'f1', to: 'c4');

      expect(result.isCorrect, isFalse);
      expect(result.event?.result, ReviewResult.incorrect);
      expect(session.currentPrompt?.nodeId, 'node-a-e5');
    });

    test('with acceptance off, a transposed move stays incorrect', () {
      final (study, chapterA, chapterB, decisions) = buildTransposedRepertoire();
      final session = startSession(study, chapterA, chapterB, decisions, transposeAccept: false);

      session.submitMove(from: 'e2', to: 'e4');
      expect(session.currentPrompt?.nodeId, 'node-a-e5');

      // Bc4 is book in chapter B, but the switch is off: still a lapse.
      final result = session.submitMove(from: 'f1', to: 'c4');

      expect(result.isCorrect, isFalse);
      expect(result.event?.result, ReviewResult.incorrect);
      expect(session.currentPrompt?.nodeId, 'node-a-e5');
    });

    test('retrying with a transposed move advances without grading', () {
      final (study, chapterA, chapterB, decisions) = buildTransposedRepertoire();
      final session = startSession(study, chapterA, chapterB, decisions);

      session.submitMove(from: 'e2', to: 'e4');
      final lapse = session.submitMove(from: 'd2', to: 'd4');
      expect(lapse.isCorrect, isFalse);

      final retry = session.retryMove(from: 'f1', to: 'c4');

      expect(retry.isCorrect, isTrue);
      expect(retry.event, isNull);
      expect(retry.nextPrompt?.nodeId, 'node-b-nf6');
    });
  });
}
