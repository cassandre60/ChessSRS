// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC coverage: INV-068.

import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/review/fresh_introduction_order.dart';
import 'package:flutter_test/flutter_test.dart';

RepertoireDecision _dec({
  required String id,
  required String studyId,
  required String chapterId,
  String? canonicalStateId,
}) {
  return RepertoireDecision(
    id: id,
    studyId: studyId,
    chapterId: chapterId,
    nodeId: 'node-$id',
    expectedMoves: const [RepertoireMove(from: 'e2', to: 'e4', san: 'e4')],
    canonicalStateId: canonicalStateId ?? id,
    fenKey: 'fen-$id',
  );
}

void main() {
  group('spreadFreshIntroductions & freshIntroductionOrderFor (INV-068)', () {
    test('returns empty and <=2 lists unchanged', () {
      // SPEC INV-068. Short inputs need no spreading.
      expect(
        spreadFreshIntroductions(
          const [],
          presentedByStudy: const {},
          presentedByChapter: const {},
        ),
        isEmpty,
      );

      final single = [_dec(id: 'd1', studyId: 's1', chapterId: 'c1')];
      expect(
        spreadFreshIntroductions(single, presentedByStudy: const {}, presentedByChapter: const {}),
        equals(single),
      );

      final pair = [
        _dec(id: 'd1', studyId: 's1', chapterId: 'c1'),
        _dec(id: 'd2', studyId: 's2', chapterId: 'c2'),
      ];
      expect(
        spreadFreshIntroductions(pair, presentedByStudy: const {}, presentedByChapter: const {}),
        equals(pair),
      );
    });

    test('interleaves chapters inside a single study, least-presented chapter first', () {
      // SPEC INV-068. Within one study, least-presented chapters contribute first
      // and round-robin one item per round while preserving within-chapter order.
      final c1a = _dec(id: 'c1-a', studyId: 's1', chapterId: 'c1');
      final c1b = _dec(id: 'c1-b', studyId: 's1', chapterId: 'c1');
      final c2a = _dec(id: 'c2-a', studyId: 's1', chapterId: 'c2');
      final c2b = _dec(id: 'c2-b', studyId: 's1', chapterId: 'c2');

      // c1 has 5 presented items, c2 has 1 -> c2 goes first in each round
      final ordered = spreadFreshIntroductions(
        [c1a, c1b, c2a, c2b],
        presentedByStudy: const {'s1': 6},
        presentedByChapter: const {'c1': 5, 'c2': 1},
      );

      expect(ordered.map((d) => d.id).toList(), ['c2-a', 'c1-a', 'c2-b', 'c1-b']);
    });

    test('interleaves multiple studies and their chapters least-presented first', () {
      // SPEC INV-068. Across multiple studies, the study with fewer presented positions
      // leads each round, and ties preserve input order deterministically.
      final s1c1 = _dec(id: 's1-c1-1', studyId: 's1', chapterId: 's1c1');
      final s1c2 = _dec(id: 's1-c2-1', studyId: 's1', chapterId: 's1c2');
      final s2c1 = _dec(id: 's2-c1-1', studyId: 's2', chapterId: 's2c1');
      final s2c2 = _dec(id: 's2-c2-1', studyId: 's2', chapterId: 's2c2');

      // s1 has 10 presented, s2 has 0 -> s2 leads round 1 and round 2
      final ordered = spreadFreshIntroductions(
        [s1c1, s1c2, s2c1, s2c2],
        presentedByStudy: const {'s1': 10, 's2': 0},
        presentedByChapter: const {'s1c1': 8, 's1c2': 2, 's2c1': 0, 's2c2': 0},
      );

      // Inside s2: s2c1 and s2c2 tie at 0 -> input order [s2-c1-1, s2-c2-1]
      // Inside s1: s1c2 (2) < s1c1 (8) -> [s1-c2-1, s1-c1-1]
      // Interleaving s2 then s1: [s2-c1-1, s1-c2-1, s2-c2-1, s1-c1-1]
      expect(ordered.map((d) => d.id).toList(), ['s2-c1-1', 's1-c2-1', 's2-c2-1', 's1-c1-1']);
    });

    test(
      'freshIntroductionOrderFor tallies presented states by canonicalId or id and enforces caps',
      () {
        // SPEC INV-068. freshIntroductionOrderFor derives presented counts from reviewStates
        // and integrates with ReviewSession's remainingNewQuota (0, exact, and exceeding cap).
        final s1Shown = _dec(
          id: 's1-shown',
          studyId: 's1',
          chapterId: 'c1',
          canonicalStateId: 'k-shown',
        );
        final s1Fresh1 = _dec(id: 's1-f1', studyId: 's1', chapterId: 'c1');
        final s1Fresh2 = _dec(id: 's1-f2', studyId: 's1', chapterId: 'c1');
        final s2Fresh1 = _dec(id: 's2-f1', studyId: 's2', chapterId: 'c2');
        final s2Fresh2 = _dec(id: 's2-f2', studyId: 's2', chapterId: 'c2');

        final now = DateTime.utc(2026, 6, 15, 12);
        final states = <String, ReviewState>{
          'k-shown': ReviewState(
            decisionId: 'k-shown',
            firstReviewedAt: now.subtract(const Duration(days: 3)),
            lastReviewedAt: now.subtract(const Duration(days: 1)),
            nextDueAt: now.add(const Duration(days: 5)),
            repetitionCount: 2,
            stability: 432000000.0,
          ),
        };

        final allDecisions = [s1Shown, s1Fresh1, s1Fresh2, s2Fresh1, s2Fresh2];
        final policy = freshIntroductionOrderFor(decisions: allDecisions, reviewStates: states);

        final freshOnly = [s1Fresh1, s1Fresh2, s2Fresh1, s2Fresh2];
        final spread = policy(freshOnly);
        // s2 has 0 presented, s1 has 1 presented ('k-shown') -> s2 leads each round
        expect(spread.map((d) => d.id).toList(), ['s2-f1', 's1-f1', 's2-f2', 's1-f2']);

        const study1 = Study(id: 's1', title: 'S1');
        const study2 = Study(id: 's2', title: 'S2');
        final root = RepertoireNode.root(
          fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
          fenKey: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -',
        );
        final ch1 = Chapter(id: 'c1', studyId: 's1', title: 'C1', sourceOrder: 0, root: root);
        final ch2 = Chapter(id: 'c2', studyId: 's2', title: 'C2', sourceOrder: 0, root: root);

        // 0 cap: no fresh positions admitted
        final zeroSession = ReviewSession(
          studies: const [study1, study2],
          chapters: [ch1, ch2],
          decisions: allDecisions,
          reviewStates: states,
          clock: FixedClock(now),
          remainingNewQuota: 0,
          freshIntroductionOrder: policy,
        );
        expect(zeroSession.initialQueueCount, 0);
        expect(zeroSession.scopeFreshCount, 4);

        // Exact cap of 2: admits 1 from s2 and 1 from s1
        final cappedSession = ReviewSession(
          studies: const [study1, study2],
          chapters: [ch1, ch2],
          decisions: allDecisions,
          reviewStates: states,
          clock: FixedClock(now),
          remainingNewQuota: 2,
          freshIntroductionOrder: policy,
        );
        expect(cappedSession.initialQueueCount, 2);

        // Cap exceeding fresh count (10 > 4): admits all 4
        final uncappedSession = ReviewSession(
          studies: const [study1, study2],
          chapters: [ch1, ch2],
          decisions: allDecisions,
          reviewStates: states,
          clock: FixedClock(now),
          remainingNewQuota: 10,
          freshIntroductionOrder: policy,
        );
        expect(uncappedSession.initialQueueCount, 4);
      },
    );
  });
}
