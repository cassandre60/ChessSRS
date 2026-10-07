// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC coverage: INV-030.

import 'package:chess_srs/src/domain/review/review_scope.dart';
import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReviewScope side scopes', () {
    test('a side scope matches only its side', () {
      const scope = ReviewScope.white();
      expect(scope.matches(studyId: 's', chapterId: 'c', side: Side.white), isTrue);
      expect(scope.matches(studyId: 's', chapterId: 'c', side: Side.black), isFalse);
    });

    test('a chapter of unknown side is excluded, not admitted', () {
      // Null here means the chapter could not be resolved. Counting it as a match
      // would let unresolvable positions back into a queue the user narrowed by
      // colour, which is the opposite of what tapping the button asked for.
      const scope = ReviewScope.black();
      expect(scope.matches(studyId: 's', chapterId: 'c'), isFalse);
    });

    test('all() and the study/chapter/opening scopes do not filter by side', () {
      // Each scope is given the arguments that satisfy its *own* restriction, so
      // the only thing under test is whether the side argument changes anything.
      for (final scope in const [
        ReviewScope.all(),
        ReviewScope.study('s'),
        ReviewScope.chapter(studyId: 's', chapterId: 'c'),
        ReviewScope.opening('Sicilian Defense'),
      ]) {
        expect(scope.side, isNull, reason: '$scope');
        expect(
          scope.matches(
            studyId: 's',
            chapterId: 'c',
            openingFamily: 'Sicilian Defense',
            side: Side.black,
          ),
          isTrue,
          reason: '$scope must not filter by side',
        );
        expect(
          scope.matches(studyId: 's', chapterId: 'c', openingFamily: 'Sicilian Defense'),
          isTrue,
          reason: '$scope',
        );
      }
    });

    test('the two side scopes are distinct values', () {
      // Distinctness is what makes one card read as selected and the other not;
      // were these equal the drawer's two buttons would be indistinguishable.
      expect(const ReviewScope.white(), isNot(const ReviewScope.black()));
      expect(const ReviewScope.white(), isNot(const ReviewScope.all()));
      expect(const ReviewScope.white(), const ReviewScope.white());
      expect(const ReviewScope.white().hashCode, const ReviewScope.white().hashCode);
    });

    test('a side scope is aggregate, so transpositions are deduplicated', () {
      expect(const ReviewScope.white().isAggregate, isTrue);
      expect(const ReviewScope.black().isAggregate, isTrue);
      expect(const ReviewScope.study('s').isAggregate, isFalse);
    });
  });

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
