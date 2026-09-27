// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/model/log/app_log_storage.dart';
import 'package:chess_srs/src/model/settings/log_preferences.dart';
import 'package:chess_srs/src/view/settings/app_log_settings_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
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

  testWidgets('AppLogSettingsScreen renders empty state when no logs exist', (tester) async {
    final app = await makeTestProviderScopeApp(tester, home: const AppLogSettingsScreen());

    await tester.pumpWidget(app);
    await tester.pumpAndSettle();

    expect(find.text('App Logs'), findsOneWidget);
    expect(find.text('No logs to show'), findsOneWidget);
    // "Refresh", not the old "Tap to refresh": the demo's voice is terse verbs, and every
    // other action in the reskin is one.
    expect(find.text('Refresh'), findsOneWidget);

    // Verify category chips are present
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);
    expect(find.text('Repo / DB'), findsOneWidget);
    expect(find.text('Import'), findsOneWidget);
  });

  testWidgets(
    'AppLogSettingsScreen renders entries, filters by category, and shows details dialog',
    (tester) async {
      late WidgetRef capturedRef;
      final app = await makeTestProviderScopeApp(
        tester,
        home: Consumer(
          builder: (context, ref, _) {
            capturedRef = ref;
            return const AppLogSettingsScreen();
          },
        ),
      );

      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      final storage = await capturedRef.read(appLogStorageProvider.future);
      await capturedRef.read(logPreferencesProvider.notifier).setLogLevel(Level.ALL);
      final now = DateTime.now();

      await storage.save(
        AppLogEntry(
          logTime: now,
          loggerName: 'ReviewEngine',
          levelValue: Level.INFO.value,
          levelName: Level.INFO.name,
          message: 'ReviewSession created with 12 due moves',
        ),
      );

      await storage.save(
        AppLogEntry(
          logTime: now.add(const Duration(seconds: 1)),
          loggerName: 'StudyImporter',
          levelValue: Level.WARNING.value,
          levelName: Level.WARNING.name,
          message: 'Malformed PGN header in chapter 2',
          error: 'FormatException: Missing right bracket',
          stackTrace: '#0 pgn_parser.dart:45',
        ),
      );

      await storage.save(
        AppLogEntry(
          logTime: now.add(const Duration(seconds: 2)),
          loggerName: 'StudyRepository',
          levelValue: Level.INFO.value,
          levelName: Level.INFO.name,
          message: 'Saved import result in 18ms',
        ),
      );

      // Refresh to load saved logs
      await tester.tap(find.text('Refresh'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      // Verify all 3 entries are rendered
      expect(find.text('ReviewEngine'), findsOneWidget);
      expect(find.text('StudyImporter'), findsOneWidget);
      expect(find.text('StudyRepository'), findsOneWidget);
      expect(find.text('ReviewSession created with 12 due moves'), findsOneWidget);
      expect(find.text('Malformed PGN header in chapter 2'), findsOneWidget);

      // Filter by Review category chip
      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();

      expect(find.text('ReviewSession created with 12 due moves'), findsOneWidget);
      expect(find.text('Malformed PGN header in chapter 2'), findsNothing);

      // Scroll horizontal chips to make Import visible
      await tester.drag(find.text('Review'), const Offset(-120, 0));
      await tester.pumpAndSettle();

      // Filter by Import category chip
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();

      expect(find.text('Malformed PGN header in chapter 2'), findsOneWidget);
      expect(find.text('ReviewSession created with 12 due moves'), findsNothing);

      // Tap on the Import entry to inspect the detail modal
      await tester.tap(find.text('Malformed PGN header in chapter 2'));
      await tester.pumpAndSettle();

      // Verify dialog content
      expect(find.text('Message'), findsOneWidget);
      expect(find.text('Malformed PGN header in chapter 2'), findsWidgets);
      expect(find.text('Error'), findsOneWidget);
      expect(find.text('FormatException: Missing right bracket'), findsWidgets);
      expect(find.text('Stack Trace'), findsOneWidget);
      expect(find.text('Copy message'), findsOneWidget);
      expect(find.text('Copy error'), findsOneWidget);
      expect(find.text('Copy all'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);

      // Close details dialog
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(find.text('Message'), findsNothing);

      // Scroll chips back to make All visible
      // Return to All
      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();

      expect(find.text('ReviewEngine'), findsOneWidget);
      expect(find.text('StudyImporter'), findsOneWidget);
      expect(find.text('StudyRepository'), findsOneWidget);

      // Search bar filter
      await tester.enterText(find.byType(TextField), '18ms');
      await tester.pumpAndSettle();

      expect(find.text('Saved import result in 18ms'), findsOneWidget);
      expect(find.text('ReviewSession created with 12 due moves'), findsNothing);

      // Clear search
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.text('ReviewSession created with 12 due moves'), findsOneWidget);

      // Delete all logs
      await tester.tap(find.byIcon(Icons.delete_sweep));
      await tester.pumpAndSettle();

      expect(find.text('Delete all logs'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.text('No logs to show'), findsOneWidget);
    },
  );
}
