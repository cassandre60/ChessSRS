// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/view/settings/settings_screen.dart';
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

  testWidgets(
    'SettingsScreen displays Spaced repetition (SRS) and navigates to SrsSettingsScreen',
    (tester) async {
      final app = await makeTestProviderScopeApp(tester, home: const SettingsScreen());

      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      // Verify Spaced repetition (SRS) entry tile exists alongside other main settings
      expect(find.text('Spaced repetition (SRS)'), findsOneWidget);
      expect(find.text('Simple Doubling (2x)'), findsOneWidget);

      // Tap Spaced repetition (SRS) to navigate to the unified SrsSettingsScreen
      await tester.tap(find.text('Spaced repetition (SRS)'));
      await tester.pumpAndSettle();

      // We are now on SrsSettingsScreen (Diagram design layout)
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Daily limit'), findsOneWidget);
      expect(find.text('Target retention'), findsOneWidget);

      // The algorithm controls live behind the Advanced disclosure.
      expect(find.text('Scheduling algorithm'), findsNothing);
      await tester.ensureVisible(find.text('Advanced'));
      await tester.tap(find.text('Advanced'));
      await tester.pumpAndSettle();

      expect(find.text('Scheduling algorithm'), findsOneWidget);
      expect(find.text('FSRS'), findsOneWidget);
      expect(find.text('Simple'), findsOneWidget);
      expect(find.text('Ease'), findsOneWidget);

      // Switch to FSRS algorithm
      await tester.ensureVisible(find.text('FSRS'));
      await tester.tap(find.text('FSRS'));
      await tester.pumpAndSettle();

      // Navigate back to SettingsScreen
      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();

      // Verify SettingsScreen updated scheduler label
      expect(find.text('Spaced repetition (SRS)'), findsOneWidget);
      expect(find.text('ChessFSRS (DSR Power-Law)'), findsOneWidget);
    },
  );
}
