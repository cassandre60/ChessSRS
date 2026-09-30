// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/domain/review/review_scope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReviewScope.matches opening normalization', () {
    test('trailing whitespace does not exclude an opening', () {
      const scope = ReviewScope.opening('Sicilian Defense');
      expect(
        scope.matches(studyId: 's', chapterId: 'c', openingFamily: 'Sicilian Defense '),
        isTrue,
      );
      expect(
        scope.matches(studyId: 's', chapterId: 'c', openingFamily: ' Sicilian Defense'),
        isTrue,
      );
    });

    test('different openings still do not match', () {
      const scope = ReviewScope.opening('Sicilian Defense');
      expect(scope.matches(studyId: 's', chapterId: 'c', openingFamily: 'French Defense'), isFalse);
      expect(scope.matches(studyId: 's', chapterId: 'c'), isFalse);
    });
  });
}
