// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/view/settings/srs_settings_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../binding.dart';
import '../../test_provider_scope.dart';

void main() {
  setUpAll(() {
    TestLichessBinding.ensureInitialized();
  });

  setUp(() async {
    await TestLichessBinding.instance.sharedPreferences.clear();
  });

  testWidgets('SrsSettingsScreen renders Diagram layout and updates preferences', (tester) async {
    final app = await makeTestProviderScopeApp(tester, home: const SrsSettingsScreen());

    await tester.pumpWidget(app);
    await tester.pumpAndSettle();

    // Verify title and back button
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);

    // Verify main rows exist
    expect(find.text('Daily limit'), findsOneWidget);
    expect(find.text('Target retention'), findsOneWidget);
    expect(find.text('Show notes after a move'), findsOneWidget);
    // The design's words (01-identity.md:89); the row gates studyPrefs.showAnnotations.
    expect(find.text('Show arrows and circles'), findsOneWidget);
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('Accent'), findsOneWidget);
    expect(find.text('Sound'), findsOneWidget);
    expect(find.text('Scheduling algorithm'), findsOneWidget);

    // Segmented daily limits
    expect(find.text('25'), findsOneWidget);
    expect(find.text('50'), findsOneWidget);
    expect(find.text('100'), findsOneWidget);
    expect(find.text('None'), findsOneWidget);

    // Tap 50 daily limit
    await tester.tap(find.text('50'));
    await tester.pumpAndSettle();

    // Tap 95% retention
    expect(find.text('95%'), findsOneWidget);
    await tester.tap(find.text('95%'));
    await tester.pumpAndSettle();

    // Toggle notes. Scrolled to rather than assumed present: the settings list is long and
    // which rows a ListView has built depends on the height of the rows above them, so
    // `ensureVisible` on a not-yet-built row throws instead of scrolling to it.
    await tester.scrollUntilVisible(find.text('Show notes after a move'), 200);
    await tester.tap(find.text('Show notes after a move'));
    await tester.pumpAndSettle();

    // Collapsible list groups: same row-tap pattern, gates the drawer collapse switch.
    await tester.scrollUntilVisible(find.text('Collapsible list groups'), 200);
    await tester.tap(find.text('Collapsible list groups'));
    await tester.pumpAndSettle();

    // Transposed moves: the P-TRANSPOSE three-way scope (default In scope).
    await tester.scrollUntilVisible(find.text('Transposed moves'), 200);
    expect(find.text('Transposed moves'), findsOneWidget);
    await tester.tap(find.text('Within study'));
    await tester.pumpAndSettle();

    // Toggle arrows -- the design's label for the row that gates showAnnotations.
    await tester.scrollUntilVisible(find.text('Show arrows and circles'), 200);
    await tester.tap(find.text('Show arrows and circles'));
    await tester.pumpAndSettle();

    // Toggle theme to Dark
    await tester.ensureVisible(find.text('Dark'));
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    // Select violet accent dot
    await tester.ensureVisible(find.bySemanticsLabel('violet'));
    await tester.tap(find.bySemanticsLabel('violet'));
    await tester.pumpAndSettle();

    // Verify navigation links to legacy settings — Board & pieces and Sound sub-screens
    // are now inlined; only Chess engine remains a nav row.
    expect(find.text('Chess engine'), findsOneWidget);

    // Board/appearance settings are now inline
    expect(find.text('Board theme'), findsOneWidget);
    expect(find.text('Piece set'), findsOneWidget);
    expect(find.text('Board coordinates'), findsOneWidget);
    expect(find.text('Piece animation'), findsOneWidget);

    // Sound is now inline with a volume slider
    expect(find.text('Volume'), findsOneWidget);

    // Verify algorithm controls are visible
    expect(find.text('Scheduling algorithm'), findsOneWidget);
    expect(find.text('FSRS'), findsOneWidget);
    expect(find.text('Simple'), findsOneWidget);
    expect(find.text('Ease'), findsOneWidget);
    expect(find.text('Review Diagnostics HUD'), findsOneWidget);
    expect(find.text('Local database size'), findsOneWidget);
    expect(find.text('HTTP network logs'), findsOneWidget);
    expect(find.text('App diagnostics logs'), findsOneWidget);

    // Switch algorithm to Simple
    await tester.ensureVisible(find.text('Simple'));
    await tester.tap(find.text('Simple'));
    await tester.pumpAndSettle();

    // Toggle diagnostics
    await tester.ensureVisible(find.text('Review Diagnostics HUD'));
    await tester.tap(find.text('Review Diagnostics HUD'));
    await tester.pumpAndSettle();
  });

  testWidgets('phone settings keep small controls inline and disclose help on demand', (
    tester,
  ) async {
    const width = 320.0;
    final app = await makeTestProviderScopeApp(
      tester,
      home: const SrsSettingsScreen(),
      surfaceSize: const Size(width, 800),
    );
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();

    // Account navigation remains tappable; its explanation is opt-in on phones.
    const accountHelp = 'Sign in to import private and unlisted studies.';
    expect(find.text(accountHelp), findsNothing);
    await tester.tap(find.byTooltip('About Lichess account'));
    await tester.pumpAndSettle();
    expect(find.text(accountHelp), findsOneWidget);
    expect(find.byType(SrsSettingsScreen), findsOneWidget);
    await tester.tap(find.byTooltip('Hide details for Lichess account'));
    await tester.pumpAndSettle();
    expect(find.text(accountHelp), findsNothing);

    // The six-way control wraps inside a narrow viewport rather than overflowing.
    await tester.ensureVisible(find.text('Daily limit'));
    expect(tester.getRect(find.text('None')).right, lessThanOrEqualTo(width));
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(find.text('Show move notation'), 200);
    final switchFinder = find.byWidgetPredicate(
      (widget) => widget is SrsSwitch && widget.semanticLabel == 'Show move notation',
    );
    expect(
      (tester.getCenter(find.text('Show move notation')).dy - tester.getCenter(switchFinder).dy)
          .abs(),
      lessThan(20),
    );
    const moveHelp = 'Display preceding moves (e.g. 1. e4 e5) in the review screen.';
    expect(find.text(moveHelp), findsNothing);
    await tester.tap(find.byTooltip('About Show move notation'));
    await tester.pumpAndSettle();
    expect(find.text(moveHelp), findsOneWidget);
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide settings retain visible descriptions', (tester) async {
    final app = await makeTestProviderScopeApp(
      tester,
      home: const SrsSettingsScreen(),
      surfaceSize: const Size(900, 800),
    );
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
    expect(find.text('Sign in to import private and unlisted studies.'), findsOneWidget);
    expect(find.byTooltip('About Lichess account'), findsNothing);
  });
}
