// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC coverage: INV-065.
import 'dart:math';

import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/import/pgn_importer.dart';
import 'package:dartchess/dartchess.dart' show Side;
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

    // Same shared position as above, but the Bc4 line lives in a second
    // study with no decisions of its own.
    (Study, Chapter, Study, Chapter, List<RepertoireDecision>) buildCrossStudyRepertoire() {
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

      final study1 = Study(
        id: 'study-one',
        title: 'Study One',
        createdAt: baseTime,
        updatedAt: baseTime,
      );
      final study2 = Study(
        id: 'study-two',
        title: 'Study Two',
        createdAt: baseTime,
        updatedAt: baseTime,
      );

      final chapterA = Chapter(
        id: 'chapter-a',
        studyId: 'study-one',
        sourceOrder: 0,
        title: 'Nf3 line',
        startingFen: startFen,
        createdAt: baseTime,
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

      final chapterC = Chapter(
        id: 'chapter-c',
        studyId: 'study-two',
        sourceOrder: 0,
        title: 'Bc4 line',
        startingFen: startFen,
        createdAt: baseTime,
        root: const RepertoireNode(
          id: 'node-c-root',
          fen: startFen,
          fenKey: startKey,
          children: [
            RepertoireNode(
              id: 'node-c-e4',
              fen: afterE4Fen,
              fenKey: afterE4Key,
              incomingMove: RepertoireMove(from: 'e2', to: 'e4', san: 'e4'),
              children: [
                RepertoireNode(
                  id: 'node-c-e5',
                  fen: afterE5Fen,
                  fenKey: afterE5Key,
                  incomingMove: RepertoireMove(from: 'e7', to: 'e5', san: 'e5'),
                  children: [
                    RepertoireNode(
                      id: 'node-c-bc4',
                      fen: afterBc4Fen,
                      fenKey: afterBc4Key,
                      incomingMove: RepertoireMove(from: 'f1', to: 'c4', san: 'Bc4'),
                      children: [
                        RepertoireNode(
                          id: 'node-c-nf6',
                          fen: afterNf6Fen,
                          fenKey: afterNf6Key,
                          incomingMove: RepertoireMove(from: 'g8', to: 'f6', san: 'Nf6'),
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
          studyId: 'study-one',
          chapterId: 'chapter-a',
          nodeId: 'node-a-root',
          expectedMoves: [RepertoireMove(from: 'e2', to: 'e4', san: 'e4')],
        ),
        RepertoireDecision(
          id: 'dec-a-2',
          studyId: 'study-one',
          chapterId: 'chapter-a',
          nodeId: 'node-a-e5',
          expectedMoves: [RepertoireMove(from: 'g1', to: 'f3', san: 'Nf3')],
        ),
        RepertoireDecision(
          id: 'dec-c-3',
          studyId: 'study-two',
          chapterId: 'chapter-c',
          nodeId: 'node-c-nf6',
          expectedMoves: [RepertoireMove(from: 'd2', to: 'd4', san: 'd4')],
        ),
      ];

      return (study1, chapterA, study2, chapterC, decisions);
    }

    ReviewSession startSession(
      Study study,
      Chapter chapterA,
      Chapter chapterB,
      List<RepertoireDecision> decisions, {
      ReviewScope scope = const ReviewScope.all(),
      TransposeScope transposeScope = TransposeScope.inScope,
      List<Study>? allStudies,
      List<Chapter>? allChapters,
    }) {
      final engine = ReviewEngine(clock: clock);
      return engine.createSession(
        studies: allStudies ?? [study],
        chapters: allChapters ?? [chapterA, chapterB],
        decisions: decisions,
        reviewStates: const {},
        scope: scope,
        transposeScope: transposeScope,
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

    // A position reached by a different move than the repertoire used to get
    // there. Chapter A drills 1.Nc3 Nf6 2.e4; chapter B holds the Nimzo-ish
    // 1.Nf3 Nf6 2.Nc3. After 1.Nc3 Nf6 the two lines sit on *different*
    // positions (the knight is on c3 in one and f3 in the other), but the
    // position after 1.Nc3 Nf6 2.Nf3 is the same as the one after
    // 1.Nf3 Nf6 2.Nc3: the knights are interchangeable.
    //
    // So at chapter A's second White move, playing 2.Nf3 reaches chapter B's
    // position - reached there by 2.Nc3. The position is in scope, so SPEC
    // INV-065 says the move is graded correct and review continues from that
    // line. The arrival move differs, which is the whole point of the case.
    //
    // The fixture is imported rather than hand-written, so the positions are
    // the ones the app really stores.
    ImportResult buildDifferentArrivalRepertoire() {
      const pgn = '''
[Event "Nc3 line"]

1. Nc3 Nf6 2. e4 *

[Event "Nf3 line"]

1. Nf3 Nf6 2. Nc3 Nc6 3. g3 *
''';
      final imported = importPgn(pgn, studyTitle: 'Different arrival', repertoireSide: Side.white);
      expect(imported.errors, isEmpty);
      expect(imported.chapters, hasLength(2));
      return imported;
    }

    test('a position reached by a different arrival move is still accepted (INV-065)', () {
      // SPEC INV-065: a legal move that matches no expected continuation is
      // graded correct when the position it reaches exists in the active
      // scope's repertoire tree. The position here is in scope, and the move
      // that reached it in the repertoire (Nc3) is not the move the user
      // played (Nf3). The position is what the rule is about.
      final imported = buildDifferentArrivalRepertoire();
      final engine = ReviewEngine(clock: clock);
      final session = engine.createSession(
        studies: [imported.study],
        chapters: imported.chapters,
        decisions: imported.decisions,
        reviewStates: const {},
        scope: const ReviewScope.all(),
        transposeScope: TransposeScope.inScope,
        random: Random(0),
      );

      // The first question is chapter A's 1.Nc3.
      expect(session.currentPrompt?.expectedMoves.first.san, 'Nc3');
      final first = session.submitMove(from: 'b1', to: 'c3');
      expect(first.isCorrect, isTrue);
      // The opponent replies 1...Nf6 and the drill asks for 2.e4.
      expect(session.currentPrompt?.expectedMoves.first.san, 'e4');

      // The user plays 2.Nf3, which reaches chapter B's position after 2.Nc3.
      final result = session.submitMove(from: 'g1', to: 'f3');

      expect(
        result.isCorrect,
        isTrue,
        reason: 'the position the move reaches is in scope, so the move is graded correct',
      );
      // Review continues from the transposed line: the opponent's Nc6 reply,
      // then chapter B's own question (2...Nc6 asks for 3.g3).
      expect(result.autoPlayedMoves.map((m) => m.move.san), ['Nc6']);
      expect(result.nextPrompt?.expectedMoves.first.san, 'g3');
      expect(result.nextPrompt?.chapterId, imported.chapters[1].id);
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
      final session = startSession(
        study,
        chapterA,
        chapterB,
        decisions,
        transposeScope: TransposeScope.off,
      );

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

    test('within-study scope accepts same-study transpositions', () {
      final (study, chapterA, chapterB, decisions) = buildTransposedRepertoire();
      final session = startSession(
        study,
        chapterA,
        chapterB,
        decisions,
        transposeScope: TransposeScope.withinStudy,
      );

      session.submitMove(from: 'e2', to: 'e4');
      final result = session.submitMove(from: 'f1', to: 'c4');

      expect(result.isCorrect, isTrue);
      expect(result.nextPrompt?.chapterId, 'chapter-b');
    });

    test('within-study scope rejects cross-study transpositions', () {
      final (study1, chapterA, study2, chapterC, decisions) = buildCrossStudyRepertoire();
      final session = startSession(
        study1,
        chapterA,
        chapterC,
        decisions,
        transposeScope: TransposeScope.withinStudy,
        allStudies: [study1, study2],
        allChapters: [chapterA, chapterC],
      );

      session.submitMove(from: 'e2', to: 'e4');
      expect(session.currentPrompt?.nodeId, 'node-a-e5');

      // Bc4 exists only in study 2: out of the within-study scope.
      final result = session.submitMove(from: 'f1', to: 'c4');

      expect(result.isCorrect, isFalse);
      expect(session.currentPrompt?.nodeId, 'node-a-e5');
    });

    test('in-scope transpositions jump across studies', () {
      final (study1, chapterA, study2, chapterC, decisions) = buildCrossStudyRepertoire();
      final session = startSession(
        study1,
        chapterA,
        chapterC,
        decisions,
        allStudies: [study1, study2],
        allChapters: [chapterA, chapterC],
      );

      session.submitMove(from: 'e2', to: 'e4');
      final result = session.submitMove(from: 'f1', to: 'c4');

      expect(result.isCorrect, isTrue);
      expect(result.nextPrompt?.nodeId, 'node-c-nf6');
      expect(result.nextPrompt?.chapterId, 'chapter-c');
    });

    test('grades the transposition identically when the rows carry their fen key', () {
      // The v21 decision row carries its node's fen key so the session can
      // build its transposition index without decoding trees. Fill every
      // decision the way the importer and the v21 backfill leave it — the
      // keys read straight off the trees, the truth the column copies — and
      // require the same acceptance and continuation the fallback path
      // (unfilled rows) gives above. INV-065 must not care which way the
      // identity arrived.
      final (study, chapterA, chapterB, decisions) = buildTransposedRepertoire();
      String? fenKeyOf(String nodeId) {
        String? walk(RepertoireNode node) {
          if (node.id == nodeId) return node.fenKey;
          for (final child in node.children) {
            final hit = walk(child);
            if (hit != null) return hit;
          }
          return null;
        }

        return walk(chapterA.root!) ?? walk(chapterB.root!);
      }

      final filled = [
        for (final d in decisions)
          RepertoireDecision(
            id: d.id,
            studyId: d.studyId,
            chapterId: d.chapterId,
            nodeId: d.nodeId,
            expectedMoves: d.expectedMoves,
            canonicalStateId: d.canonicalStateId,
            fenKey: fenKeyOf(d.nodeId),
          ),
      ];
      expect(
        filled.every((d) => d.fenKey != null),
        isTrue,
        reason: 'the fixture must actually exercise the row-keyed path',
      );

      final session = startSession(study, chapterA, chapterB, filled);

      expect(session.currentPrompt?.nodeId, 'node-a-root');
      session.submitMove(from: 'e2', to: 'e4');
      final result = session.submitMove(from: 'f1', to: 'c4');

      expect(result.isCorrect, isTrue);
      expect(result.movePlayed.san, 'Bc4');
      expect(result.event?.result, ReviewResult.correct);
      expect(result.nextPrompt?.nodeId, 'node-b-nf6');
    });
  });
}
