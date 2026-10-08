// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC coverage: INV-062.

import 'package:chess_srs/src/design/design.dart';
import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_provider_scope.dart';

/// Leaving Practice mode, per design/docs/00-agent-brief.md open decision 3 (resolved 2026-09-28):
/// a tappable `Practice` label with semantics `Exit practice` and a 44dp target.
///
/// The first version of this was a 12px `Exit Practice` text button beside an inert `Practice`
/// label — a 168x16px tap target for the *only* way out of a mode the user opted into, against the
/// 44x44 minimum in design/docs/03-components.md §6. It was invisible to every other assertion
/// here, because nothing asked how big the target was.
void main() {
  Future<void> showPracticeTopBar(WidgetTester tester, {VoidCallback? onExitPractice}) async {
    await tester.pumpWidget(
      await makeTestProviderScopeApp(
        tester,
        home: Center(
          child: SrsTopBar(
            activeSide: Side.white,
            isPracticeMode: true,
            onExitPractice: onExitPractice ?? () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('Practice mode exit', () {
    testWidgets('the Practice label is the tap target and meets 44px', (tester) async {
      await showPracticeTopBar(tester);

      final label = find.text('Practice');
      expect(label, findsOneWidget);

      // The pressable that wraps the label, not the label's own text box: the 44px is the
      // *target*, and a 12px `Text` is not what the finger aims at.
      final target = find.ancestor(of: label, matching: find.byType(SrsPressable));
      expect(target, findsOneWidget, reason: 'the Practice label itself must be tappable');

      final size = tester.getSize(target);
      expect(
        size.height,
        greaterThanOrEqualTo(SrsLayout.minTouchTarget),
        reason:
            'got a ${size.height}px tall target; the design minimum is '
            '${SrsLayout.minTouchTarget}px and this is the only way out of Practice mode',
      );
      expect(size.width, greaterThanOrEqualTo(SrsLayout.minTouchTarget));
    });

    testWidgets('tapping the Practice label exits, and the due count returns', (tester) async {
      var exits = 0;
      await showPracticeTopBar(tester, onExitPractice: () => exits++);

      await tester.tap(find.text('Practice'));
      await tester.pumpAndSettle();

      expect(exits, 1, reason: 'the label must actually leave Practice mode');
    });

    testWidgets('the due count is hidden while practising', (tester) async {
      await showPracticeTopBar(tester);

      // `Practice` occupies the due count's slot, per the prototype. Both showing at once would
      // put a mode badge and a count where one number belongs.
      expect(find.textContaining('due'), findsNothing);
    });

    testWidgets('the target is announced as "Exit practice"', (tester) async {
      await showPracticeTopBar(tester);

      // A screen reader hears the semantics label, not the visible text, and a label of just
      // "Practice" announces a state rather than an action.
      expect(find.bySemanticsLabel('Exit practice'), findsOneWidget);
    });

    // The target went from a 12px text button to a 44px one -- 32px more top bar, on a screen whose
    // vertical budget the board competes for. Nothing else asserted the bar's height, so this is
    // the assertion that the fix did not cost board space.
    testWidgets('the taller target does not overflow the top bar row', (tester) async {
      await tester.pumpWidget(
        await makeTestProviderScopeApp(
          tester,
          surfaceSize: const Size(390, 844),
          home: Center(
            child: SrsTopBar(
              activeSide: Side.white,
              isPracticeMode: true,
              onExitPractice: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // `SrsTopBar` is a `Row`; a child taller than the row is the overflow this could cause.
      expect(tester.takeException(), isNull);
    });
  });
}
