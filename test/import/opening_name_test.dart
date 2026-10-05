// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC coverage: INV-067.

import 'package:chess_srs/src/import/opening_name.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('opening name predicates', () {
    test('a title that merely mentions an opening is not a family (INV-067)', () {
      expect(isLikelyOpeningFamily('White vs French'), isFalse);
      expect(mentionsOpeningButIsNotFamily('White vs French'), isTrue);
      expect(mentionsOpeningButIsNotFamily('My French Repertoire'), isTrue);
    });

    test('a real family is kept, including one the ECO table produces', () {
      for (final name in const [
        'French Defense',
        'Sicilian Defense',
        'Caro-Kann Defense',
        "Queen's Gambit",
        'Petrov Defense',
      ]) {
        expect(isLikelyOpeningFamily(name), isTrue, reason: name);
        expect(mentionsOpeningButIsNotFamily(name), isFalse, reason: name);
      }
    });

    test('every family the ECO fallback can produce is one the repair keeps', () {
      for (final code in const [
        'B20',
        'B12',
        'B05',
        'C00',
        'C30',
        'C60',
        'D10',
        'D30',
        'D80',
        'E40',
        'E60',
        'E00',
        'A20',
        'A40',
        'A80',
      ]) {
        final family = ecoToOpeningFamily(code);
        expect(family, isNotNull, reason: code);
        expect(mentionsOpeningButIsNotFamily(family!), isFalse, reason: '$code → $family');
      }
    });

    test('an unrecognised name is left alone rather than erased', () {
      expect(mentionsOpeningButIsNotFamily('QGD Exchange Variation'), isFalse);
      expect(mentionsOpeningButIsNotFamily('My Repertoire'), isFalse);
    });
  });
}
