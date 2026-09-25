// Pins the review screen's user-visible copy to the demo
// (ChessSRS_ new visual identityV2.html, `idle`, `correction` and `error` scenes).
//
// Copy drift is invisible in screenshots and survives `./verify`, so every string the
// design fixes lives in lib/src/view/review/review_copy.dart and is asserted here against
// what the demo actually says. The review_screen_test cases that touch these strings are
// not the only guard; this file states the contract directly.
import 'package:chess_srs/src/view/review/review_copy.dart';
import 'package:chess_srs/src/view/review/review_states.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('idle copy', () {
    test('the daily-limit title is the demo wording, not a gamified one', () {
      // Demo setIdleCopy(true): 'Daily limit reached.'
      expect(kSrsDailyLimitReachedTitle, 'Daily limit reached.');
      // The previous copy was 'Daily Goal Reached!', which is exactly the celebration
      // tone the visual identity removes (demo: "No icon, no confetti"; 01-identity).
      expect(kSrsDailyLimitReachedTitle, isNot(contains('Goal')));
      expect(kSrsDailyLimitReachedTitle, isNot(contains('!')));
    });

    test('the nothing-due title is the demo wording', () {
      expect(kSrsNothingDueTitle, 'Nothing due.');
    });

    test('the adjust link is the demo wording', () {
      expect(kSrsAdjustLimitLabel, 'Adjust limit');
    });

    test('the practice footnote is the demo wording', () {
      expect(kSrsPracticeFootnote, 'Practice never changes your schedule.');
    });
  });

  group('next review sentence', () {
    test('the prefix stays bare because the duration carries its own "in"', () {
      // review_controller's timeUntilNextReview returns 'in 1 day', 'in 3 hours', …
      // so the screen composes kSrsNextReviewPrefix + duration + '.'. If the prefix
      // ever gains its own "in", the screen reads "Next review in in 1 day." — which
      // is exactly the bug the existing 'Next review in 1 day' assertion caught.
      expect(kSrsNextReviewPrefix, 'Next review ');
      expect('$kSrsNextReviewPrefix${'in 1 day'}.', 'Next review in 1 day.');
      expect('$kSrsNextReviewPrefix${'in 1 day'}.', isNot(contains('in in')));
    });
  });

  group('correction copy', () {
    test('the answer help is the demo sentence, with no inline move name', () {
      expect(kSrsAnswerHelpText, 'Play this move to continue. The position will come back soon.');
      // The correct move is already rendered large above this line (design/docs/03 §4),
      // so the previous "(Repertoire was $san)." parenthetical was redundant noise.
      expect(kSrsAnswerHelpText, isNot(contains('Repertoire was')));
    });

    test('the note attribution is the demo wording', () {
      expect(kSrsNoteAttribution, 'From your study');
    });
  });

  group('error copy', () {
    test('the title is the demo wording', () {
      expect(kSrsErrorTitle, 'Something went wrong.');
    });

    test('the sentence does not promise the demo promises for a save failure', () {
      // The demo's error scene covers a failed *save* ("Your place is kept; nothing was
      // lost."). This build has no save-failure state, so it must not borrow that
      // reassurance, which would be an unverifiable claim.
      expect(kSrsReviewLoadFailedDetail, isNot(contains('nothing was lost')));
      expect(kSrsReviewLoadFailedDetail, isNot(contains('Your place is kept')));
    });

    test('the actions are the demo labels', () {
      expect(kSrsRetryLabel, 'Try again');
      expect(kSrsCopyDetailsLabel, 'Copy details');
    });
  });

  group('first-launch copy', () {
    test('matches the demo word for word', () {
      expect(kSrsBringYourRepertoire, 'Bring your repertoire.');
      expect(
        kSrsFirstLaunchLede,
        'Import a PGN or a Lichess study. Everything stays on this device, and reviews work offline.',
      );
      expect(kSrsDropPgnHere, 'Drop a PGN file here');
    });
  });

  group('loading copy', () {
    test('is a quiet label, not a message with a progress value', () {
      expect(kSrsLoadingLabel, 'Loading…');
      expect(kSrsLoadingLabel, isNot(contains('%')));
    });

    test('waits before it appears', () {
      expect(kSrsLoadingLabelDelay, greaterThan(Duration.zero));
    });
  });
}
