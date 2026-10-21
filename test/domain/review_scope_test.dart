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
      // SPEC INV-030: `white()`/`black()` aggregate across active studies, so
      // they are not aggregate-blocking; a scope naming a study or a chapter
      // is, while an opening family still aggregates.
      expect(const ReviewScope.white().isAggregate, isTrue);
      expect(const ReviewScope.black().isAggregate, isTrue);
      expect(const ReviewScope.study('s').isAggregate, isFalse);
      expect(const ReviewScope.chapter(studyId: 's', chapterId: 'c').isAggregate, isFalse);
      expect(const ReviewScope.opening('French Defense').isAggregate, isTrue);
    });

    test('INV-030: study and chapter scopes filter by their identifiers', () {
      // SPEC INV-030: `chapter()` isolates one chapter; a scope naming a study
      // must not admit another study's chapters.
      const study = ReviewScope.study('study-alpha');
      expect(study.matches(studyId: 'study-alpha', chapterId: 'ch-1'), isTrue);
      expect(study.matches(studyId: 'study-beta', chapterId: 'ch-1'), isFalse);

      const chapter = ReviewScope.chapter(studyId: 'study-alpha', chapterId: 'ch-1');
      expect(chapter.matches(studyId: 'study-alpha', chapterId: 'ch-1'), isTrue);
      expect(chapter.matches(studyId: 'study-beta', chapterId: 'ch-1'), isFalse);
      expect(chapter.matches(studyId: 'study-alpha', chapterId: 'ch-2'), isFalse);
    });

    test('INV-030: equality and hashCode verify each field with runtime-constructed operands', () {
      // SPEC INV-030: a scope identifies one filter exactly, so two scopes that
      // differ in any dimension are different filters. Must verify each
      // dimension without short-circuiting via const identical().
      final base = ReviewScope.chapter(
        studyId: 's'.trim(),
        chapterId: 'c'.trim(),
        side: Side.white,
      );
      final same = ReviewScope.chapter(
        studyId: 's'.trim(),
        chapterId: 'c'.trim(),
        side: Side.white,
      );
      expect(identical(base, same), isFalse);
      expect(base, equals(same));
      expect(base.hashCode, equals(same.hashCode));

      final diffStudy = ReviewScope.chapter(
        studyId: 's2'.trim(),
        chapterId: 'c'.trim(),
        side: Side.white,
      );
      final diffChapter = ReviewScope.chapter(
        studyId: 's'.trim(),
        chapterId: 'c2'.trim(),
        side: Side.white,
      );
      final diffSide = ReviewScope.chapter(
        studyId: 's'.trim(),
        chapterId: 'c'.trim(),
        side: Side.black,
      );
      final diffOpening = ReviewScope.opening('Sicilian Defense'.trim());
      final sameOpening = ReviewScope.opening('Sicilian Defense'.trim());

      expect(base, isNot(equals(diffStudy)));
      expect(base, isNot(equals(diffChapter)));
      expect(base, isNot(equals(diffSide)));
      expect(base, isNot(equals(diffOpening)));
      expect(base, isNot(equals(Object())));

      expect(identical(diffOpening, sameOpening), isFalse);
      expect(diffOpening, equals(sameOpening));
      expect(diffOpening.hashCode, equals(sameOpening.hashCode));
      expect(diffOpening, isNot(equals(ReviewScope.opening('French Defense'.trim()))));
    });

    test('study and opening scopes carry the drawer colour', () {
      // The scope doc requires every drawer-produced scope to name its side;
      // the constructors take it optionally so older callers keep meaning
      // "no restriction".
      const study = ReviewScope.study('s', side: Side.white);
      expect(study.side, Side.white);
      expect(study.matches(studyId: 's', chapterId: 'c', side: Side.white), isTrue);
      expect(study.matches(studyId: 's', chapterId: 'c', side: Side.black), isFalse);

      const opening = ReviewScope.opening('French Defense', side: Side.black);
      expect(opening.side, Side.black);
      expect(
        opening.matches(
          studyId: 's',
          chapterId: 'c',
          openingFamily: 'French Defense',
          side: Side.black,
        ),
        isTrue,
      );
      expect(
        opening.matches(
          studyId: 's',
          chapterId: 'c',
          openingFamily: 'French Defense',
          side: Side.white,
        ),
        isFalse,
      );

      const chapter = ReviewScope.chapter(studyId: 's', chapterId: 'c', side: Side.white);
      expect(chapter.side, Side.white);
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

    test('Defense and Defence spelling variants match each other', () {
      const scope = ReviewScope.opening('French Defense');
      expect(scope.matches(studyId: 's', chapterId: 'c', openingFamily: 'French Defence'), isTrue);
      const ukScope = ReviewScope.opening('French Defence');
      expect(
        ukScope.matches(studyId: 's', chapterId: 'c', openingFamily: 'French Defense'),
        isTrue,
      );
    });
  });
}
