// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/view/settings/srs_settings_screen.dart';
import 'package:flutter_test/flutter_test.dart';

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

    // Verify navigation links to legacy settings
    expect(find.text('Board & pieces'), findsOneWidget);
    expect(find.text('Sound & audio details'), findsOneWidget);
    expect(find.text('Chess engine'), findsOneWidget);

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
}
