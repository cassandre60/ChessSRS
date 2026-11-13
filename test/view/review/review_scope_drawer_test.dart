import 'dart:ui';

import 'package:chess_srs/l10n/l10n.dart';
import 'package:chess_srs/src/view/review/review_scope_drawer.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReviewScopeDrawer.sideLabel', () {
    late AppLocalizations strings;

    setUpAll(() async {
      strings = await AppLocalizations.delegate.load(const Locale('en'));
    });

    test('returns white repertoire label for white side', () {
      expect(ReviewScopeDrawer.sideLabel(Side.white, strings), strings.mobileReviewWhiteRepertoire);
    });

    test('returns black repertoire label for black side', () {
      expect(ReviewScopeDrawer.sideLabel(Side.black, strings), strings.mobileReviewBlackRepertoire);
    });

    test('returns distinct labels for white and black', () {
      expect(
        ReviewScopeDrawer.sideLabel(Side.white, strings),
        isNot(equals(ReviewScopeDrawer.sideLabel(Side.black, strings))),
      );
    });
  });
}
