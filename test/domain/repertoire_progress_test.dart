// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RepertoireProgress', () {
    test('computes correct fractions and percentages', () {
      const p1 = RepertoireProgress(totalDecisions: 10, learnedDecisions: 7, dueDecisions: 3);

      expect(p1.totalDecisions, 10);
      expect(p1.learnedDecisions, 7);
      expect(p1.dueDecisions, 3);
      expect(p1.unlearnedDecisions, 3);
      expect(p1.progressFraction, 0.7);
      expect(p1.progressPercentage, 70);
    });

    test('handles zero decisions safely without division by zero', () {
      const pZero = RepertoireProgress.zero;

      expect(pZero.totalDecisions, 0);
      expect(pZero.learnedDecisions, 0);
      expect(pZero.dueDecisions, 0);
      expect(pZero.unlearnedDecisions, 0);
      expect(pZero.progressFraction, 0.0);
      expect(pZero.progressPercentage, 0);
    });

    test('operator + aggregates multiple progress records', () {
      const ch1 = RepertoireProgress(totalDecisions: 8, learnedDecisions: 4, dueDecisions: 2);
      const ch2 = RepertoireProgress(totalDecisions: 12, learnedDecisions: 6, dueDecisions: 3);

      final combined = ch1 + ch2;
      expect(combined.totalDecisions, 20);
      expect(combined.learnedDecisions, 10);
      expect(combined.dueDecisions, 5);
      expect(combined.progressPercentage, 50);
    });

    test('equality and hashCode', () {
      const a = RepertoireProgress(totalDecisions: 5, learnedDecisions: 2, dueDecisions: 1);
      const b = RepertoireProgress(totalDecisions: 5, learnedDecisions: 2, dueDecisions: 1);
      const c = RepertoireProgress(totalDecisions: 5, learnedDecisions: 3, dueDecisions: 1);

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('operator + aggregates freshDecisions and re-derives scheduledDecisions', () {
      const ch1 = RepertoireProgress(
        totalDecisions: 8,
        learnedDecisions: 4,
        dueDecisions: 2,
        freshDecisions: 2,
      );
      const ch2 = RepertoireProgress(
        totalDecisions: 12,
        learnedDecisions: 6,
        dueDecisions: 3,
        freshDecisions: 3,
      );

      final combined = ch1 + ch2;
      expect(combined.totalDecisions, 20);
      expect(combined.learnedDecisions, 10);
      expect(combined.dueDecisions, 5);
      expect(combined.freshDecisions, 5);
      expect(combined.scheduledDecisions, 10);
      expect(combined.progressPercentage, 50);
    });

    test('INV-068: fresh, due, and scheduled partition total decisions', () {
      // SPEC INV-068: The three states — fresh, due, scheduled — are disjoint and
      // partition each scope's positions: fresh + due + scheduled == total.
      const p = RepertoireProgress(
        totalDecisions: 20,
        learnedDecisions: 12,
        dueDecisions: 5,
        freshDecisions: 3,
      );

      expect(p.freshDecisions, 3);
      expect(p.dueDecisions, 5);
      expect(p.scheduledDecisions, 12);
      expect(p.unlearnedDecisions, 8);
      expect(p.freshDecisions + p.dueDecisions + p.scheduledDecisions, p.totalDecisions);
    });

    test('INV-068: scheduledDecisions clamps to zero when fresh and due exceed total', () {
      // Defensive clamp ensures scheduledDecisions never goes negative under inconsistent data.
      const pOver = RepertoireProgress(
        totalDecisions: 10,
        learnedDecisions: 0,
        dueDecisions: 8,
        freshDecisions: 5,
      );

      expect(pOver.scheduledDecisions, 0);
    });

    test('progressFraction clamps cleanly between 0.0 and 1.0', () {
      const pExcess = RepertoireProgress(totalDecisions: 10, learnedDecisions: 15, dueDecisions: 0);
      expect(pExcess.progressFraction, 1.0);
      expect(pExcess.progressPercentage, 100);
    });

    test('equality and hashCode verify each field with runtime-constructed operands', () {
      // SPEC INV-068: equality must verify each partition field independently
      // without short-circuiting via const object canonicalisation (identical).
      final base = RepertoireProgress(
        totalDecisions: int.parse('10'),
        learnedDecisions: int.parse('6'),
        dueDecisions: int.parse('2'),
        freshDecisions: int.parse('1'),
      );
      final same = RepertoireProgress(
        totalDecisions: int.parse('10'),
        learnedDecisions: int.parse('6'),
        dueDecisions: int.parse('2'),
        freshDecisions: int.parse('1'),
      );

      expect(identical(base, same), isFalse);
      expect(base, equals(same));
      expect(base.hashCode, equals(same.hashCode));

      final diffTotal = RepertoireProgress(
        totalDecisions: int.parse('11'),
        learnedDecisions: int.parse('6'),
        dueDecisions: int.parse('2'),
        freshDecisions: int.parse('1'),
      );
      final diffLearned = RepertoireProgress(
        totalDecisions: int.parse('10'),
        learnedDecisions: int.parse('5'),
        dueDecisions: int.parse('2'),
        freshDecisions: int.parse('1'),
      );
      final diffDue = RepertoireProgress(
        totalDecisions: int.parse('10'),
        learnedDecisions: int.parse('6'),
        dueDecisions: int.parse('3'),
        freshDecisions: int.parse('1'),
      );
      final diffFresh = RepertoireProgress(
        totalDecisions: int.parse('10'),
        learnedDecisions: int.parse('6'),
        dueDecisions: int.parse('2'),
        freshDecisions: int.parse('2'),
      );

      expect(base, isNot(equals(diffTotal)));
      expect(base, isNot(equals(diffLearned)));
      expect(base, isNot(equals(diffDue)));
      expect(base, isNot(equals(diffFresh)));
      expect(base, isNot(equals(Object())));
    });
  });
}
