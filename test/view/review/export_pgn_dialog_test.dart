// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/db/database.dart';
import 'package:chess_srs/src/import/pgn_importer.dart';
import 'package:chess_srs/src/persistence/persistence.dart';
import 'package:chess_srs/src/view/review/export_pgn_dialog.dart';
import 'package:chess_srs/src/view/review/review_scope_drawer.dart';
import 'package:chess_srs/src/view/review/review_screen.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../binding.dart';
import '../../test_provider_scope.dart';

void main() {
  setUpAll(() {
    TestLichessBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await TestLichessBinding.instance.sharedPreferences.clear();
  });

  group('ExportPgnDialog', () {
    testWidgets('renders title, subtitle, and selectable PGN content', (tester) async {
      const samplePgn = '''
[Event "Sicilian Defense"]
[Site "ChessSRS"]

1. e4 c5 2. Nf3 d6 *
''';

      final app = await makeTestProviderScopeApp(
        tester,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => ExportPgnDialog.show(
                context,
                title: 'Sicilian Defense',
                pgnText: samplePgn,
                subtitle: '2 chapters',
              ),
              child: const Text('Open Export'),
            ),
          ),
        ),
      );

      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Export'));
      await tester.pumpAndSettle();

      expect(find.byType(ExportPgnDialog), findsOneWidget);
      expect(find.text('Export PGN'), findsOneWidget);
      expect(find.text('Sicilian Defense'), findsOneWidget);
      expect(find.text('2 chapters'), findsOneWidget);
      expect(find.textContaining('1. e4 c5 2. Nf3 d6 *'), findsOneWidget);

      // Verify buttons exist
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Save File'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);

      // Tap Copy button
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();

      // Dialog is dismissed
      expect(find.byType(ExportPgnDialog), findsNothing);
    });

    testWidgets('tapping Share triggers graceful share and dismisses dialog', (tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () =>
                  ExportPgnDialog.show(context, title: 'King Gambit', pgnText: '1. e4 e5 2. f4 *'),
              child: const Text('Open Export'),
            ),
          ),
        ),
      );

      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Export'));
      await tester.pumpAndSettle();

      expect(find.byType(ExportPgnDialog), findsOneWidget);

      await tester.tap(find.text('Share'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byType(ExportPgnDialog), findsNothing);
    });
  });

  group('Drawer and Chapters Screen PGN Export integration', () {
    late Database db;
    late SqliteStudyRepository repo;

    setUp(() async {
      db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
      final batch = db.batch();
      createSrsTables(batch);
      await batch.commit();
      repo = SqliteStudyRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    testWidgets('ReviewScopeDrawer study options sheet provides Export PGN option', (tester) async {
      const pgn = '''
[Event "French Defense: Winawer"]
[Site "ChessSRS"]

1. e4 e6 2. d4 d5 3. Nc3 Bb4 *
''';
      final importResult = importPgn(pgn, studyTitle: 'French Defense', repertoireSide: Side.black);
      await repo.saveImportResult(importResult);

      final app = await makeTestProviderScopeApp(
        tester,
        home: const ReviewScreen(),
        overrides: {
          srsStudyRepositoryProvider: srsStudyRepositoryProvider.overrideWith((ref) => repo),
          databaseProvider: databaseProvider.overrideWith((ref) => db),
        },
      );

      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      // Open drawer
      await tester.tap(find.byTooltip('Black repertoire'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: find.byType(ReviewScopeDrawer), matching: find.text('French Defense')),
        findsNWidgets(2),
      );

      // Two rows are called `French Defense` — the opening hub and the study. Only the study
      // carries actions, so its row is the one with a `…` on it. The scope rows' chevrons are
      // SrsIconButtons too now, so pick the button labelled for study options.
      final frenchRows = find.descendant(
        of: find.byType(ReviewScopeDrawer),
        matching: find.text('French Defense'),
      );
      expect(frenchRows, findsNWidgets(2));
      final studyRow = find.descendant(
        of: find.byType(ReviewScopeDrawer),
        matching: find.bySemanticsLabel('Study options'),
      );
      expect(studyRow, findsOneWidget);

      // design/docs/03-components.md §6.4 offers three routes to the actions sheet. This one is
      // the `…`; the long-press route is covered in review_screen_test.dart.
      await tester.tap(studyRow);
      await tester.pumpAndSettle();

      // Verify Export PGN option is present
      expect(find.text('Export PGN'), findsOneWidget);
      expect(find.text('Share or copy standard PGN notation'), findsOneWidget);

      // Tap Export PGN
      await tester.tap(find.text('Export PGN'));
      await tester.pumpAndSettle();

      // Verify ExportPgnDialog is shown with exported study PGN
      expect(find.byType(ExportPgnDialog), findsOneWidget);
      expect(find.textContaining('1. e4 e6 2. d4 d5 3. Nc3 Bb4 *'), findsOneWidget);

      // Close dialog
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(find.byType(ExportPgnDialog), findsNothing);
    });

    testWidgets('StudyChaptersScreen exports full study and individual chapter PGNs', (
      tester,
    ) async {
      const pgn = '''
[Event "Najdorf Variation"]
1. e4 c5 2. Nf3 d6 3. d4 cxd4 4. Nxd4 Nf6 5. Nc3 a6 *

[Event "Classical Variation"]
1. e4 c5 2. Nf3 d6 3. d4 cxd4 4. Nxd4 Nf6 5. Nc3 Nc6 *
''';
      final importResult = importPgn(
        pgn,
        studyTitle: 'Sicilian Repertoire',
        repertoireSide: Side.black,
      );
      await repo.saveImportResult(importResult);

      final app = await makeTestProviderScopeApp(
        tester,
        home: StudyChaptersScreen(study: importResult.study, chapters: importResult.chapters),
        overrides: {
          srsStudyRepositoryProvider: srsStudyRepositoryProvider.overrideWith((ref) => repo),
          databaseProvider: databaseProvider.overrideWith((ref) => db),
        },
      );

      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      expect(find.text('Sicilian Repertoire'), findsOneWidget);
      expect(find.text('2 chapters'), findsOneWidget);
      expect(find.text('Najdorf Variation'), findsOneWidget);
      expect(find.text('Classical Variation'), findsOneWidget);

      // 1. Export entire study via AppBar action
      expect(find.byTooltip('Export study PGN'), findsOneWidget);
      await tester.tap(find.byTooltip('Export study PGN'));
      await tester.pumpAndSettle();

      expect(find.byType(ExportPgnDialog), findsOneWidget);
      expect(find.text('2 chapters'), findsNWidgets(2));
      expect(
        find.descendant(
          of: find.byType(ExportPgnDialog),
          matching: find.textContaining('Najdorf Variation'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(ExportPgnDialog),
          matching: find.textContaining('Classical Variation'),
        ),
        findsOneWidget,
      );

      // Dismiss dialog
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // 2. Export individual chapter via list tile action
      final chapterExportButtons = find.byTooltip('Export chapter PGN');
      expect(chapterExportButtons, findsNWidgets(2));

      await tester.tap(chapterExportButtons.first);
      await tester.pumpAndSettle();

      expect(find.byType(ExportPgnDialog), findsOneWidget);
      expect(find.text('Najdorf Variation'), findsWidgets);
      expect(
        find.descendant(of: find.byType(ExportPgnDialog), matching: find.textContaining('a6 *')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(ExportPgnDialog),
          matching: find.textContaining('Classical Variation'),
        ),
        findsNothing,
      );

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    });
  });
}
