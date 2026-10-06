// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC coverage: INV-030.

import 'package:chess_srs/src/design/design.dart' show SrsSheetSurface;
import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/view/review/review_scope_drawer.dart';
import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../binding.dart';
import '../../test_provider_scope.dart';

/// Owner report 2026-09-29 Q8: on a small phone the study actions sheet
/// clipped its last rows — Delete was unreachable because the sheet's body
/// was a plain Column with no scroll. This pins Delete reachable by scroll
/// on a short viewport.
void main() {
  setUpAll(TestLichessBinding.ensureInitialized);

  const study = Study(id: 's1', title: 'My repertoire');

  Widget sheet({
    Rect? anchor,
    Side side = Side.white,
    VoidCallback? onDismiss,
    VoidCallback? onTogglePause,
    VoidCallback? onAnalyze,
    VoidCallback? onPractice,
    VoidCallback? onExport,
    VoidCallback? onRename,
    VoidCallback? onDelete,
    VoidCallback? onCreateOpposite,
  }) {
    return StudyActionsSheet(
      study: study,
      side: side,
      anchor: anchor,
      onDismiss: onDismiss ?? () {},
      onTogglePause: onTogglePause ?? () {},
      onAnalyze: onAnalyze ?? () {},
      onPractice: onPractice ?? () {},
      onExport: onExport ?? () {},
      onRename: onRename ?? () {},
      onDelete: onDelete ?? () {},
      onCreateOpposite: onCreateOpposite ?? () {},
    );
  }

  testWidgets('Delete stays reachable by scrolling on a small phone', (tester) async {
    var deleted = false;

    await tester.pumpWidget(
      await makeTestProviderScopeApp(
        tester,
        surfaceSize: const Size(360, 500),
        home: sheet(onDelete: () => deleted = true),
      ),
    );
    await tester.pumpAndSettle();

    // Without a scrollable body this throws UnableToFind / stays hidden.
    await tester.scrollUntilVisible(find.text('Delete'), 200);
    expect(find.text('Delete'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(deleted, isTrue, reason: 'Delete must be tappable, not clipped off-screen');
  });

  testWidgets('StudyActionsSheet displays Analyze and no longer displays Chapters', (tester) async {
    await tester.pumpWidget(await makeTestProviderScopeApp(tester, home: sheet()));
    await tester.pumpAndSettle();

    expect(find.text('Analyze'), findsOneWidget);
    expect(find.text('Chapters'), findsNothing);
  });

  group('the sheet carries no title of its own', () {
    // Owner report 2026-10-05: the sheet repeated the study name at the top even
    // though it is anchored to the row that already shows it, spending a line of
    // a short popover to repeat what is one row above.
    testWidgets('the study name appears once, in its rows', (tester) async {
      await tester.pumpWidget(await makeTestProviderScopeApp(tester, home: sheet()));
      await tester.pumpAndSettle();

      // The name is not rendered at all. Asserted on the rendered text rather than
      // on a text style: a heading is only one way to show a title, so the style
      // would pin the wrong thing.
      expect(find.text('My repertoire'), findsNothing);
    });

    testWidgets('no title is shown on a wide popover either', (tester) async {
      await tester.pumpWidget(
        await makeTestProviderScopeApp(
          tester,
          surfaceSize: const Size(1400, 900),
          home: sheet(anchor: const Rect.fromLTWH(200, 300, 400, 48)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('My repertoire'), findsNothing);
    });
  });

  group('wide popover fits its rows', () {
    // Owner report 2026-10-05: on a wide screen the popover was positioned by its
    // top edge but sized against the height of the whole window, so a row low in
    // the list pushed the bottom of the sheet — Delete — off the bottom of the
    // window, with no way to scroll to it because the inner scroll view was
    // already showing everything it had.
    ///
    // Two rows deep in the list is the case that used to clip: the sheet's own
    // height exceeds the space left below a row that low.
    Future<void> pumpAtRowPosition(
      WidgetTester tester, {
      required double rowTop,
      required Size window,
    }) async {
      await tester.pumpWidget(
        await makeTestProviderScopeApp(
          tester,
          surfaceSize: window,
          home: sheet(anchor: Rect.fromLTWH(200, rowTop, 400, 48)),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a row low in the list keeps the sheet inside the window', (tester) async {
      const window = Size(1400, 700);
      await pumpAtRowPosition(tester, rowTop: 600, window: window);

      expect(find.text('Delete'), findsOneWidget);

      // The invariant is that the sheet is bounded by the band, not that every
      // row happens to fit inside it. At 700px the sheet is taller than the
      // band, so Delete sits in the scroll: the assertion has to be about the
      // surface's extent, because a row can be found in the tree and still be
      // entirely below the window edge — which is the bug the band fixed.
      final surface = tester.getRect(find.byKey(SrsSheetSurface.surfaceKey));
      expect(
        surface.bottom,
        lessThanOrEqualTo(window.height),
        reason: 'the sheet must not extend past the window',
      );
      expect(surface.top, greaterThanOrEqualTo(0));

      // And it is scrollable rather than merely clipped: the row is reachable.
      await tester.scrollUntilVisible(find.text('Delete'), 120);
      expect(tester.getRect(find.text('Delete')).height, greaterThan(0));
    });

    testWidgets('Delete is tappable at that position', (tester) async {
      var deleted = false;
      const window = Size(1400, 700);
      await tester.pumpWidget(
        await makeTestProviderScopeApp(
          tester,
          surfaceSize: window,
          home: sheet(
            anchor: const Rect.fromLTWH(200, 600, 400, 48),
            onDelete: () => deleted = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Reachable, which is the invariant: at this height the sheet is taller
      // than the band and its last rows live in the scroll. A row that is only in
      // the tree but past the bottom edge is not reachable, which is what the
      // band exists to prevent.
      await tester.scrollUntilVisible(find.text('Delete'), 120);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(deleted, isTrue, reason: 'the clipped row must be reachable, not just rendered');
    });

    testWidgets('a row high in the list still fits without scrolling', (tester) async {
      await pumpAtRowPosition(tester, rowTop: 80, window: const Size(1400, 900));

      // A window with room for the sheet: the added row must not have made the
      // ordinary case a scrolling one. At 700px it is (see the tests above); at
      // 900px it should not be, or the extra row has quietly cost the desktop
      // popover its whole point.
      expect(find.text('Delete'), findsOneWidget);
      expect(tester.getRect(find.text('Delete')).bottom, lessThanOrEqualTo(900));
      expect(find.text('Create Black repertoire'), findsOneWidget);
    });
  });

  // Owner request 2026-10-06: the two drawers are independent, so a repertoire
  // imported into the wrong one has no counterpart until the user makes one.
  // "Everything got imported as White" is the ordinary way a Black library ends
  // up empty, and the fix is one tap.
  group('create in the other colour', () {
    testWidgets('a White study offers to create the Black one', (tester) async {
      await tester.pumpWidget(
        await makeTestProviderScopeApp(
          tester,
          surfaceSize: const Size(1400, 700),
          home: sheet(side: Side.white),
        ),
      );
      await tester.pumpAndSettle();

      // Names the colour it would land in, not the one it came from: "Create
      // White repertoire" on a White study would be a no-op dressed as an action.
      expect(find.text('Create Black repertoire'), findsOneWidget);
      expect(find.text('Create White repertoire'), findsNothing);
    });

    testWidgets('a Black study offers to create the White one', (tester) async {
      await tester.pumpWidget(
        await makeTestProviderScopeApp(
          tester,
          surfaceSize: const Size(1400, 700),
          home: sheet(side: Side.black),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Create White repertoire'), findsOneWidget);
      expect(find.text('Create Black repertoire'), findsNothing);
    });

    testWidgets('tapping it fires the action', (tester) async {
      var created = false;
      await tester.pumpWidget(
        await makeTestProviderScopeApp(
          tester,
          surfaceSize: const Size(1400, 700),
          home: sheet(side: Side.white, onCreateOpposite: () => created = true),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Create Black repertoire'));
      await tester.pumpAndSettle();
      expect(created, isTrue);
    });

    testWidgets('the row stays reachable on a short phone', (tester) async {
      // The sheet now has one row more than when the clipping bug was found, so
      // the bound that used to hold by a little has to be re-proved rather than
      // assumed: the first row is the one added, and it is the one furthest from
      // the scroll.
      await tester.pumpWidget(
        await makeTestProviderScopeApp(
          tester,
          surfaceSize: const Size(390, 500),
          home: sheet(side: Side.white),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Create Black repertoire'), findsOneWidget);
      expect(tester.getRect(find.text('Create Black repertoire')).height, greaterThan(0));
    });
  });
}
