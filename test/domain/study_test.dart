// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Study', () {
    test('create defaults isActive to true and pgnHash to null', () {
      final now = DateTime(2026, 11, 13, 12);
      final study = Study.create(title: 'Najdorf', createdAt: now);

      expect(study.id, isNotEmpty);
      expect(study.title, 'Najdorf');
      expect(study.createdAt, now);
      expect(study.updatedAt, now);
      expect(study.isActive, isTrue);
      expect(study.pgnHash, isNull);
    });

    test('create preserves explicit isActive and pgnHash', () {
      final now = DateTime(2026, 11, 13, 12);
      final study = Study.create(
        title: 'French',
        createdAt: now,
        isActive: false,
        pgnHash: 'abc123',
      );

      expect(study.isActive, isFalse);
      expect(study.pgnHash, 'abc123');
      expect(study.createdAt, now);
      expect(study.updatedAt, now);
    });

    test('create without createdAt sets non-null timestamps', () {
      final before = DateTime.now();
      final study = Study.create(title: 'Caro-Kann');
      final after = DateTime.now();

      expect(study.createdAt, isNotNull);
      expect(study.updatedAt, isNotNull);
      expect(study.createdAt, equals(study.updatedAt));
      expect(
        study.createdAt!.isAfter(before.subtract(const Duration(seconds: 1))) &&
            study.createdAt!.isBefore(after.add(const Duration(seconds: 1))),
        isTrue,
      );
    });

    test('copyWith updates title, updatedAt, isActive, and pgnHash', () {
      final created = DateTime(2026, 1, 1);
      final updated = DateTime(2026, 2, 1);
      final study = Study(
        id: 'study-1',
        title: 'Original',
        createdAt: created,
        updatedAt: created,
        isActive: true,
        pgnHash: 'old',
      );

      final copy = study.copyWith(
        title: 'Renamed',
        updatedAt: updated,
        isActive: false,
        pgnHash: 'new',
      );

      expect(copy.id, 'study-1');
      expect(copy.title, 'Renamed');
      expect(copy.createdAt, created);
      expect(copy.updatedAt, updated);
      expect(copy.isActive, isFalse);
      expect(copy.pgnHash, 'new');
    });

    test('copyWith keeps existing values when arguments are omitted', () {
      final created = DateTime(2026, 1, 1);
      final study = Study(
        id: 'study-1',
        title: 'Original',
        createdAt: created,
        updatedAt: created,
        isActive: false,
        pgnHash: 'hash',
      );

      final copy = study.copyWith();

      expect(copy, equals(study));
      expect(identical(copy, study), isFalse);
    });

    test('equality and hashCode differ when mutable metadata differs', () {
      final created = DateTime(2026, 1, 1);
      final a = Study(id: 's', title: 'T', createdAt: created, updatedAt: created);
      final b = a.copyWith(isActive: false);
      final c = a.copyWith(pgnHash: 'h');
      final d = a.copyWith(updatedAt: created.add(const Duration(days: 1)));

      expect(a == b, isFalse);
      expect(a == c, isFalse);
      expect(a == d, isFalse);
      expect(a.hashCode == b.hashCode, isFalse);
      expect(a.hashCode == c.hashCode, isFalse);
      expect(a.hashCode == d.hashCode, isFalse);
    });

    test('toString includes id, title, active state, and hash', () {
      const study = Study(id: 'study-1', title: 'Sicilian', isActive: false, pgnHash: 'deadbeef');

      expect(
        study.toString(),
        'Study(id: study-1, title: Sicilian, active: false, hash: deadbeef)',
      );
    });
  });
}
