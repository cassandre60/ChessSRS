// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/domain/review_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReviewResult', () {
    test('contains the expected values in declaration order', () {
      expect(ReviewResult.values, const <ReviewResult>[
        ReviewResult.correct,
        ReviewResult.incorrect,
      ]);
    });

    test('has stable names', () {
      expect(ReviewResult.correct.name, 'correct');
      expect(ReviewResult.incorrect.name, 'incorrect');
    });
  });
}
