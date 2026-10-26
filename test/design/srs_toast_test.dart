// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/widgets/feedback.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../binding.dart';
import '../test_provider_scope.dart';

/// `design/docs/03-components.md` §12 fixes the toast's numbers: "ink pill (`ink` bg, `ground`
/// text 14/500), bottom 24, centered, padding 11/18, fades in 160 ms (translate 10px), visible
/// 2.4 s. One line, no actions." The demo's `.toast` rule adds radius 999 and
/// `max-width: calc(100% - 32px)`.
///
/// Those are the assertions, because "a toast appeared" is the one thing this widget could do
/// while being wrong: a Material `SnackBar` also appears, and it appeared here first.
/// Builds the overlay entry, then runs its 160 ms entry animation to completion.
Future<void> settleToast(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  setUpAll(TestLichessBinding.ensureInitialized);

  Future<void> open(WidgetTester tester, {SnackBarType type = SnackBarType.info}) async {
    await tester.pumpWidget(
      await makeTestProviderScopeApp(
        tester,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: SrsTextButton(
                label: 'Act',
                onPressed: () => showSnackBar(context, 'Saved', type: type),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('is the ink pill the spec describes, not a Material SnackBar', (tester) async {
    await open(tester);
    final c = SrsColors.light(SrsAccent.ultramarine);

    await tester.tap(find.text('Act'));
    await settleToast(tester);

    expect(find.byType(SnackBar), findsNothing);

    final pill = find.byType(Container).evaluate().map((e) => e).toList();
    expect(pill, isNotEmpty);

    // The pill's own decoration, taken from the toast rather than any ancestor.
    final box = tester
        .widgetList<Container>(find.byType(Container))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .firstWhere((d) => d.color == c.ink);
    expect(box.borderRadius, BorderRadius.circular(999));

    final text = tester.widget<Text>(find.text('Saved'));
    expect(text.style?.fontSize, 14);
    expect(text.style?.fontWeight, FontWeight.w500);
    expect(text.style?.color, c.ground);
    // "One line" is in the spec, so a long message truncates rather than wrapping.
    expect(text.maxLines, 1);
  });

  testWidgets('sits 24px from the bottom, centred, and no wider than the screen less 32', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('Act'));
    await settleToast(tester);

    final size = tester.view.physicalSize / tester.view.devicePixelRatio;

    final text = tester.getRect(find.text('Saved'));
    final centre = text.center.dx;
    expect(centre, closeTo(size.width / 2, 1), reason: 'the toast is centred');

    final pill = tester.getRect(
      find.ancestor(of: find.text('Saved'), matching: find.byType(Container)).first,
    );
    // The toast adds the bottom safe area, which is right on a device with a home indicator
    // and is what the design's "bottom 24" is measured from. Read the same inset the toast
    // read, so the assertion is on the spec's number and not on the harness's padding.
    final inset = MediaQuery.paddingOf(tester.element(find.byType(SlideTransition).first)).bottom;
    expect(pill.bottom, closeTo(size.height - 24 - inset, 1), reason: 'bottom 24');
    expect(pill.width, lessThanOrEqualTo(size.width - 32));
  });

  testWidgets('fades in over 160ms rather than appearing instantly', (tester) async {
    await open(tester);

    // Scoped to the toast: the app's own route transitions are FadeTransitions too.
    final fade = find.ancestor(of: find.text('Saved'), matching: find.byType(FadeTransition));

    await tester.tap(find.text('Act'));
    await tester.pump();

    // At the very start of the transition the text is laid out but not yet opaque.
    final opacity = tester.widget<FadeTransition>(fade).opacity.value;
    await tester.pump(const Duration(milliseconds: 80));
    final midway = tester.widget<FadeTransition>(fade).opacity.value;
    await tester.pump(const Duration(milliseconds: 120));

    expect(opacity, lessThan(midway), reason: 'it ramps rather than snapping');
    expect(midway, lessThan(1.0));
    expect(tester.widget<FadeTransition>(fade).opacity.value, 1.0);
  });

  testWidgets('is gone after 2.4s, and a second toast replaces the first', (tester) async {
    await open(tester);

    await tester.tap(find.text('Act'));
    await settleToast(tester);
    expect(find.text('Saved'), findsOneWidget);

    // Still up just before the dwell expires.
    await tester.pump(const Duration(milliseconds: 2000));
    expect(find.text('Saved'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Saved'), findsNothing);

    // Two in a row must not stack: the design describes one.
    await tester.tap(find.text('Act'));
    await settleToast(tester);
    await tester.tap(find.text('Act'));
    await settleToast(tester);
    expect(find.text('Saved'), findsOneWidget);
  });

  testWidgets('renders every tone identically, because the design has one toast', (tester) async {
    // The 53 call sites pass error/success/info and the design specifies no difference, so
    // this is deliberate rather than an oversight. If a tone ever gains a look, this is the
    // test that should be changed with it.
    final c = SrsColors.light(SrsAccent.ultramarine);
    for (final type in SnackBarType.values) {
      await open(tester, type: type);
      await tester.tap(find.text('Act'));
      await settleToast(tester);
      expect(find.text('Saved'), findsOneWidget, reason: '$type must still show');

      final box = tester
          .widgetList<Container>(find.byType(Container))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .firstWhere((d) => d.color == c.ink);
      expect(box.borderRadius, BorderRadius.circular(999), reason: '$type must render ink pill');

      final text = tester.widget<Text>(find.text('Saved'));
      expect(text.style?.color, c.ground, reason: '$type text color must be ground');

      await tester.pump(const Duration(milliseconds: 2400));
    }
  });

  testWidgets('shows from a Navigator context, where the Overlay is below not above', (
    tester,
  ) async {
    // The deep-link service takes its context from a GlobalKey<NavigatorState> so it can
    // navigate before the first frame. That context sits *above* the Navigator's own Overlay,
    // so the usual walk-up finds nothing and the toast was silently never inserted -- which
    // `ScaffoldMessenger` had hidden, because MaterialApp installs one above the Navigator.
    // A deep link to a bad FEN reported nothing at all.
    final navigatorKey = GlobalKey<NavigatorState>();

    // Shaped as app.dart has it: SrsTheme outside MaterialApp.
    await tester.pumpWidget(
      SrsTheme(
        colors: SrsColors.light(SrsAccent.ultramarine),
        child: MaterialApp(
          navigatorKey: navigatorKey,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: SrsTextButton(
                  label: 'Act',
                  onPressed: () =>
                      showSrsToast(navigatorKey.currentContext!, 'From a navigator context'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(navigatorKey.currentContext, isNotNull);
    // The premise: that context is not under the Overlay.
    expect(find.byType(Overlay), findsOneWidget);

    await tester.tap(find.text('Act'));
    await settleToast(tester);

    expect(find.text('From a navigator context'), findsOneWidget);
  });

  testWidgets('renders in the root overlay even from inside a nested navigator', (tester) async {
    // The toast is app chrome: §12 puts it at z-index 40, above the scrim (10) and the
    // sheet (20), neither of which lives inside a nested subtree. A host app may embed its
    // own Navigator (a tab shell does), so the lookup must ask for the rootmost overlay --
    // settling for the nearest one would file the toast inside that subtree, under the
    // shell's own chrome, and two shells could each keep a "single" toast.
    const shellMarker = ValueKey('shell-subtree');

    await tester.pumpWidget(
      SrsTheme(
        colors: SrsColors.light(SrsAccent.ultramarine),
        child: MaterialApp(
          home: KeyedSubtree(
            key: shellMarker,
            child: Navigator(
              onGenerateRoute: (settings) => PageRouteBuilder<void>(
                pageBuilder: (_, _, _) => Builder(
                  builder: (context) => Scaffold(
                    body: Center(
                      child: SrsTextButton(
                        label: 'Act',
                        onPressed: () => showSrsToast(context, 'Above the shell'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The premise: the button's context is under the nested navigator's own overlay, so a
    // nearest-overlay lookup would succeed locally.
    final overlays = tester.widgetList<Overlay>(find.byType(Overlay)).toList();
    expect(overlays.length, 2, reason: 'the shell embeds its own navigator');
    expect(find.ancestor(of: find.text('Act'), matching: find.byKey(shellMarker)), findsOneWidget);

    await tester.tap(find.text('Act'));
    await settleToast(tester);

    expect(find.text('Above the shell'), findsOneWidget);
    // Not a descendant of the shell subtree: the root overlay hosts it, above the shell.
    expect(
      find.ancestor(of: find.text('Above the shell'), matching: find.byKey(shellMarker)),
      findsNothing,
      reason: 'the toast must render in the root overlay, not the nearest one',
    );
  });

  testWidgets('a navigator-key context past a LookupBoundary still resolves to the root', (
    tester,
  ) async {
    // The second lookup exists for contexts that cannot see any overlay. One way that
    // happens without a missing ancestor: the framework clips inherited lookups at a
    // LookupBoundary, so a nested navigator's own key context below one finds no overlay at
    // all even though overlays sit above it. The fallback must then climb to the rootmost
    // navigator -- taking the nearest one would file the toast inside the clipped subtree.
    final nestedKey = GlobalKey<NavigatorState>();
    const shellMarker = ValueKey('shell-subtree');

    await tester.pumpWidget(
      SrsTheme(
        colors: SrsColors.light(SrsAccent.ultramarine),
        child: MaterialApp(
          home: KeyedSubtree(
            key: shellMarker,
            child: LookupBoundary(
              child: Navigator(
                key: nestedKey,
                onGenerateRoute: (settings) => PageRouteBuilder<void>(
                  pageBuilder: (_, _, _) => Scaffold(
                    body: Center(
                      child: SrsTextButton(
                        label: 'Act',
                        onPressed: () =>
                            showSrsToast(nestedKey.currentContext!, 'Past the boundary'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The premise: the key context cannot see an overlay (the boundary clips the walk), yet
    // overlays exist above it.
    expect(nestedKey.currentContext, isNotNull);
    expect(find.ancestor(of: find.text('Act'), matching: find.byKey(shellMarker)), findsOneWidget);

    await tester.tap(find.text('Act'));
    await settleToast(tester);

    expect(find.text('Past the boundary'), findsOneWidget);
    expect(
      find.ancestor(of: find.text('Past the boundary'), matching: find.byKey(shellMarker)),
      findsNothing,
      reason: 'the fallback must climb to the rootmost navigator, not the context-owned one',
    );
  });
}
