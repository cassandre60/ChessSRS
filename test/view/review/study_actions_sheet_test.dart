// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC coverage: INV-030.

import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/view/review/review_scope_drawer.dart';
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
    VoidCallback? onDismiss,
    VoidCallback? onTogglePause,
    VoidCallback? onAnalyze,
    VoidCallback? onPractice,
    VoidCallback? onExport,
    VoidCallback? onRename,
    VoidCallback? onDelete,
  }) {
    return StudyActionsSheet(
      study: study,
      anchor: anchor,
      onDismiss: onDismiss ?? () {},
      onTogglePause: onTogglePause ?? () {},
      onAnalyze: onAnalyze ?? () {},
      onPractice: onPractice ?? () {},
      onExport: onExport ?? () {},
      onRename: onRename ?? () {},
      onDelete: onDelete ?? () {},
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

    testWidgets('a row low in the list still shows Delete inside the window', (tester) async {
      const window = Size(1400, 700);
      await pumpAtRowPosition(tester, rowTop: 600, window: window);

      expect(find.text('Delete'), findsOneWidget);

      // The proof that matters: the row's box is on screen, not merely present in
      // the tree. A widget can be found and still be clipped away entirely.
      final deleteBox = tester.getRect(find.text('Delete'));
      expect(
        deleteBox.bottom,
        lessThanOrEqualTo(window.height),
        reason: 'Delete must not sit below the window',
      );
      expect(deleteBox.height, greaterThan(0));
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

      await tester.tap(find.text('Delete'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(deleted, isTrue, reason: 'the clipped row must be reachable, not just rendered');
    });

    testWidgets('a row high in the list is unaffected', (tester) async {
      await pumpAtRowPosition(tester, rowTop: 80, window: const Size(1400, 700));

      expect(find.text('Delete'), findsOneWidget);
      expect(tester.getRect(find.text('Delete')).bottom, lessThanOrEqualTo(700));
    });
  });
}
