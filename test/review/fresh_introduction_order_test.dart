// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/review/fresh_introduction_order.dart';
import 'package:flutter_test/flutter_test.dart';

RepertoireDecision _decision({
  required String id,
  required String studyId,
  required String chapterId,
  String nodeId = 'node',
  String? canonicalStateId,
}) {
  return RepertoireDecision(
    id: id,
    studyId: studyId,
    chapterId: chapterId,
    nodeId: nodeId,
    expectedMoves: const [RepertoireMove(from: 'e2', to: 'e4', san: 'e4')],
    canonicalStateId: canonicalStateId,
  );
}

ReviewState _learned(String decisionId) {
  final now = DateTime.utc(2026, 11, 4, 12);
  return ReviewState(
    decisionId: decisionId,
    firstReviewedAt: now,
    nextDueAt: now.add(const Duration(days: 1)),
    repetitionCount: 1,
  );
}

void main() {
  group('spreadFreshIntroductions', () {
    test('returns the same list when there are two or fewer items', () {
      final one = [_decision(id: 'd1', studyId: 's1', chapterId: 'c1')];
      final two = [
        _decision(id: 'd1', studyId: 's1', chapterId: 'c1'),
        _decision(id: 'd2', studyId: 's2', chapterId: 'c2'),
      ];

      expect(
        identical(
          spreadFreshIntroductions(
            one,
            presentedByStudy: const {},
            presentedByChapter: const {},
          ),
          one,
        ),
        isTrue,
      );
      expect(
        identical(
          spreadFreshIntroductions(
            two,
            presentedByStudy: const {},
            presentedByChapter: const {},
          ),
          two,
        ),
        isTrue,
      );
    });

    test('interleaves studies least-presented first and round-robins', () {
      final a1 = _decision(id: 'a1', studyId: 'a', chapterId: 'a1c');
      final a2 = _decision(id: 'a2', studyId: 'a', chapterId: 'a1c');
      final b1 = _decision(id: 'b1', studyId: 'b', chapterId: 'b1c');
      final b2 = _decision(id: 'b2', studyId: 'b', chapterId: 'b1c');
      final c1 = _decision(id: 'c1', studyId: 'c', chapterId: 'c1c');

      final result = spreadFreshIntroductions(
        [a1, a2, b1, b2, c1],
        presentedByStudy: const {'a': 3, 'b': 1},
        presentedByChapter: const {},
      );

      expect(
        result.map((d) => d.id).toList(),
        ['c1', 'b1', 'a1', 'b2', 'a2'],
        reason: 'never-presented study c comes first, then least-presented b, then a; round-robin',
      );
    });

    test('keeps study tie order stable by first appearance', () {
      final a1 = _decision(id: 'a1', studyId: 'a', chapterId: 'a1c');
      final b1 = _decision(id: 'b1', studyId: 'b', chapterId: 'b1c');
      final c1 = _decision(id: 'c1', studyId: 'c', chapterId: 'c1c');

      final result = spreadFreshIntroductions(
        [b1, a1, c1],
        presentedByStudy: const {},
        presentedByChapter: const {},
      );

      expect(result.map((d) => d.id).toList(), ['b1', 'a1', 'c1']);
    });

    test('single study interleaves its chapters least-presented first', () {
      final c1a = _decision(id: 'c1a', studyId: 's', chapterId: 'c1');
      final c1b = _decision(id: 'c1b', studyId: 's', chapterId: 'c1');
      final c2a = _decision(id: 'c2a', studyId: 's', chapterId: 'c2');
      final c3a = _decision(id: 'c3a', studyId: 's', chapterId: 'c3');

      final result = spreadFreshIntroductions(
        [c1a, c1b, c2a, c3a],
        presentedByStudy: const {},
        presentedByChapter: const {'c1': 5, 'c2': 0, 'c3': 1},
      );

      expect(
        result.map((d) => d.id).toList(),
        ['c2a', 'c3a', 'c1a', 'c1b'],
        reason: 'chapters ordered by presented count then round-robined, preserving chapter order',
      );
    });

    test('interleaves chapters within each study stream', () {
      final a1 = _decision(id: 'a1', studyId: 'a', chapterId: 'a-c1');
      final a2 = _decision(id: 'a2', studyId: 'a', chapterId: 'a-c2');
      final b1 = _decision(id: 'b1', studyId: 'b', chapterId: 'b-c1');
      final b2 = _decision(id: 'b2', studyId: 'b', chapterId: 'b-c2');

      final result = spreadFreshIntroductions(
        [a1, a2, b1, b2],
        presentedByStudy: const {},
        presentedByChapter: const {},
      );

      expect(result.map((d) => d.studyId).toSet(), {'a', 'b'});
      expect(result, hasLength(4));
      // First round should take first item from each study stream (stable ties).
      expect(result[0].studyId, 'a');
      expect(result[1].studyId, 'b');
    });
  });

  group('freshIntroductionOrderFor', () {
    test('counts only decisions that have been reviewed in either id form', () {
      final reviewedById = _decision(id: 'd1', studyId: 's1', chapterId: 'c1');
      final reviewedByCanonical = _decision(
        id: 'd2',
        studyId: 's1',
        chapterId: 'c1',
        canonicalStateId: 'canon-2',
      );
      final freshA = _decision(id: 'd3', studyId: 's1', chapterId: 'c1');
      final freshB = _decision(id: 'd4', studyId: 's2', chapterId: 'c2');
      final freshC = _decision(id: 'd5', studyId: 's3', chapterId: 'c3');
      final unseen = _decision(id: 'd6', studyId: 's4', chapterId: 'c4');

      final order = freshIntroductionOrderFor(
        decisions: [
          reviewedById,
          reviewedByCanonical,
          freshA,
          freshB,
          freshC,
          unseen,
        ],
        reviewStates: {'d1': _learned('d1'), 'canon-2': _learned('canon-2')},
      );

      final result = order([freshA, freshB, freshC]);

      expect(
        result.map((d) => d.id).toList(),
        ['d4', 'd5', 'd3'],
        reason: 'study s1 has 2 presented decisions so it is deprioritized behind never-presented s2/s3',
      );
    });
  });
}
