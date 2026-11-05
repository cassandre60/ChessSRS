// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC coverage: INV-050, INV-065.

import 'package:chess_srs/src/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

/// INV-050: a wrong move must not decode every chapter tree to find a
/// transposition. With the flat FEN→node index, only the chapter holding the
/// target is decoded; without it, the old fallback decodes them all.
void main() {
  const startFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
  const startKey = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -';
  const afterE4Fen = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1';
  const afterE4Key = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq -';

  Map<String, List<NodePosition>> indexOf(List<Chapter> chapters) {
    final index = <String, List<NodePosition>>{};
    for (final chapter in chapters) {
      final root = chapter.root;
      if (root == null) continue;
      var rank = 0;
      void walk(RepertoireNode node) {
        index
            .putIfAbsent(node.fenKey, () => <NodePosition>[])
            .add((chapterId: chapter.id, nodeId: node.id, nodeRank: rank++));
        for (final child in node.children) {
          walk(child);
        }
      }

      walk(root);
    }
    return index;
  }

  late List<Chapter> chapters;
  late RepertoireDecision decision;
  late Map<String, ReviewState> states;

  setUp(() {
    const study = Study(id: 's', title: 'S');
    chapters = [
      for (var i = 0; i < 12; i++)
        if (i == 0)
          Chapter(
            id: 'ch-0',
            studyId: study.id,
            sourceOrder: 0,
            startingFen: startFen,
            root: const RepertoireNode(id: 'p0', fen: startFen, fenKey: startKey),
          )
        else if (i == 5)
          // The transposition target: the position after 1.e4.
          Chapter(
            id: 'ch-5',
            studyId: study.id,
            sourceOrder: 5,
            startingFen: afterE4Fen,
            root: const RepertoireNode(id: 't0', fen: afterE4Fen, fenKey: afterE4Key),
          )
        else
          Chapter(
            id: 'ch-$i',
            studyId: study.id,
            sourceOrder: i,
            startingFen: startFen,
            root: RepertoireNode(id: 'r$i', fen: startFen, fenKey: startKey),
          ),
    ];
    // The prompt expects 1.d4; playing 1.e4 is wrong here but transposes into
    // chapter 5.
    decision = RepertoireDecision.create(
      studyId: 's',
      chapterId: 'ch-0',
      nodeId: 'p0',
      fenKey: startKey,
      expectedMoves: const [RepertoireMove(from: 'd2', to: 'd4', san: 'd4')],
    );
    final now = DateTime.utc(2026, 11, 5, 12);
    states = {
      decision.canonicalId: ReviewState(
        decisionId: decision.canonicalId,
        firstReviewedAt: now.subtract(const Duration(days: 1)),
        nextDueAt: now.subtract(const Duration(days: 1)),
        repetitionCount: 1,
      ),
    };
  });

  ReviewSession build({Map<String, List<NodePosition>>? nodeIndex}) {
    return ReviewEngine(clock: FixedClock(DateTime.utc(2026, 11, 5, 12))).createSession(
      studies: const [Study(id: 's', title: 'S')],
      chapters: chapters,
      decisions: [decision],
      reviewStates: states,
      nodeIndex: nodeIndex ?? const {},
    );
  }

  test('a transposed wrong move decodes only the target chapter', () {
    final session = build(nodeIndex: indexOf(chapters));
    expect(session.currentPrompt?.decision.id, decision.id);
    final before = session.decodedChapterCount;

    final result = session.submitMove(from: 'e2', to: 'e4');

    expect(result.isCorrect, isTrue, reason: 'the 1.e4 position exists in chapter 5');
    expect(
      session.decodedChapterCount,
      lessThanOrEqualTo(before + 1),
      reason: 'only the chapter holding the target should be decoded, not all twelve',
    );
  });

  test('without the flat index the fallback still finds it, decoding every chapter', () {
    final session = build();
    session.submitMove(from: 'e2', to: 'e4');
    expect(
      session.decodedChapterCount,
      chapters.length,
      reason: 'the legacy path decodes the whole library, which is what INV-050 removes',
    );
  });
}
