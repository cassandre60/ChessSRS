// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RepertoireDecision', () {
    const moveE4 = RepertoireMove(from: 'e2', to: 'e4', san: 'e4');
    const moveD4 = RepertoireMove(from: 'd2', to: 'd4', san: 'd4');

    test('create assigns a fresh id and unmodifiable expected moves', () {
      final d = RepertoireDecision.create(
        studyId: 'study-1',
        chapterId: 'chapter-1',
        nodeId: 'node-1',
        expectedMoves: [moveE4],
        canonicalStateId: 'canon-1',
        fenKey: 'fen-key',
      );

      expect(d.id, isNotEmpty);
      expect(d.studyId, 'study-1');
      expect(d.chapterId, 'chapter-1');
      expect(d.nodeId, 'node-1');
      expect(d.expectedMoves, [moveE4]);
      expect(d.canonicalStateId, 'canon-1');
      expect(d.fenKey, 'fen-key');
      expect(d.canonicalId, 'canon-1');
      expect(() => d.expectedMoves.add(moveD4), throwsUnsupportedError);
    });

    test('canonicalId falls back to id when canonicalStateId is null', () {
      final d = RepertoireDecision.create(
        studyId: 's',
        chapterId: 'c',
        nodeId: 'n',
        expectedMoves: const [moveE4],
      );

      expect(d.canonicalStateId, isNull);
      expect(d.canonicalId, d.id);
    });

    test('accepts returns true for any accepted continuation', () {
      const d = RepertoireDecision(
        id: 'd1',
        studyId: 's',
        chapterId: 'c',
        nodeId: 'n',
        expectedMoves: [moveE4, moveD4],
      );

      expect(d.accepts(moveE4), isTrue);
      expect(d.accepts(moveD4), isTrue);
      expect(d.accepts(const RepertoireMove(from: 'c2', to: 'c4')), isFalse);
    });

    test('equality and hashCode compare identity fields only', () {
      const a = RepertoireDecision(
        id: 'same-id',
        studyId: 's',
        chapterId: 'c',
        nodeId: 'n',
        expectedMoves: [moveE4],
        canonicalStateId: 'canon',
        fenKey: 'fen-a',
      );
      const b = RepertoireDecision(
        id: 'same-id',
        studyId: 's',
        chapterId: 'c',
        nodeId: 'n',
        expectedMoves: [moveD4],
        canonicalStateId: 'canon',
        fenKey: 'fen-b',
      );
      const differentId = RepertoireDecision(
        id: 'other-id',
        studyId: 's',
        chapterId: 'c',
        nodeId: 'n',
        expectedMoves: [moveE4],
        canonicalStateId: 'canon',
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(differentId)));
    });

    test('toString includes id, nodeId, and effective canonical id', () {
      const d = RepertoireDecision(
        id: 'd1',
        studyId: 's',
        chapterId: 'c',
        nodeId: 'node-7',
        expectedMoves: [moveE4],
      );

      expect(d.toString(), 'RepertoireDecision(id: d1, nodeId: node-7, canonical: d1)');
    });
  });
}
