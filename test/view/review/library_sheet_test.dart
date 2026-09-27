// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/db/database.dart';
import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/import/pgn_importer.dart';
import 'package:chess_srs/src/persistence/persistence.dart';
import 'package:chess_srs/src/review/review_controller.dart';
import 'package:chess_srs/src/view/explorer/opening_explorer_screen.dart';
import 'package:chess_srs/src/view/review/about_page.dart';
import 'package:chess_srs/src/view/review/library_sheet.dart';
import 'package:chess_srs/src/view/review/repertoire_import_dialog.dart';
import 'package:chess_srs/src/view/review/review_screen.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  Future<void> openLibrarySheet(WidgetTester tester) async {
    final app = await makeTestProviderScopeApp(tester, home: const ReviewScreen());
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Library and settings'));
    await tester.pumpAndSettle();
    expect(find.byType(SrsLibrarySheet), findsOneWidget);
  }

  group('SrsLibrarySheet (Diagram #sheetLib)', () {
    testWidgets('renders demo rows with Explore header and no Preferences header', (tester) async {
      await openLibrarySheet(tester);

      expect(find.text('Import PGN'), findsOneWidget);
      expect(find.text('From a file, pasted text or a Lichess study'), findsOneWidget);
      expect(find.text('Studies & Repertoires'), findsOneWidget);
      expect(find.text('Choose active study or opening hub'), findsOneWidget);
      expect(find.text('Explore'), findsOneWidget);
      expect(find.text('Analysis board'), findsOneWidget);
      expect(find.text('Opening explorer'), findsOneWidget);
      expect(find.text('Board editor'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('About and licences'), findsOneWidget);
      expect(find.text('Preferences'), findsNothing);
    });

    testWidgets('tapping Opening explorer pushes OpeningExplorerScreen', (tester) async {
      await openLibrarySheet(tester);

      await tester.tap(find.text('Opening explorer'));
      await tester.pumpAndSettle();

      expect(find.byType(OpeningExplorerScreen), findsOneWidget);
      expect(find.byType(SrsLibrarySheet), findsNothing);
    });

    testWidgets('tapping Import PGN opens RepertoireImportDialog', (tester) async {
      await openLibrarySheet(tester);

      await tester.tap(find.text('Import PGN'));
      await tester.pumpAndSettle();

      expect(find.byType(RepertoireImportDialog), findsOneWidget);
      expect(find.byType(SrsLibrarySheet), findsNothing);
    });

    testWidgets('tapping About and licences pushes AboutPage', (tester) async {
      await openLibrarySheet(tester);

      await tester.tap(find.text('About and licences'));
      await tester.pumpAndSettle();

      expect(find.byType(AboutPage), findsOneWidget);
      expect(find.byType(SrsLibrarySheet), findsNothing);
    });

    testWidgets('Chapters row only appears for a study scope', (tester) async {
      final db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      final batch = db.batch();
      createSrsTables(batch);
      await batch.commit();
      final repo = SqliteStudyRepository(db);
      final importResult = importPgn(
        '1. e4 e5 *',
        studyTitle: 'King Pawn',
        repertoireSide: Side.white,
      );
      await tester.runAsync(() => repo.saveImportResult(importResult));

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

      // All-studies scope: no Chapters row (no study selected).
      await tester.tap(find.byTooltip('Library and settings'));
      await tester.pumpAndSettle();
      expect(find.byType(SrsLibrarySheet), findsOneWidget);
      expect(find.text('Chapters'), findsNothing);

      // Switching to the study scope reveals its Chapters row.
      final container = ProviderScope.containerOf(tester.element(find.byType(SrsLibrarySheet)));
      await tester.runAsync(
        () => container
            .read(reviewControllerProvider.notifier)
            .changeScope(ReviewScope.study(importResult.study.id)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Chapters'), findsOneWidget);
    });
  });

  group('AboutPage (Diagram about scene)', () {
    testWidgets('renders wordmark, version, links, and licence rows', (tester) async {
      final app = await makeTestProviderScopeApp(tester, home: const AboutPage());
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      expect(find.text('ChessSRS'), findsOneWidget);
      expect(find.text('About'), findsOneWidget);
      expect(find.text('Version 0.0.0. Based on Lichess Mobile (GPL-3.0).'), findsOneWidget);
      expect(find.text('Lichess Mobile source'), findsOneWidget);
      expect(find.text('ChessSRS source'), findsOneWidget);
      for (final name in [
        'Lichess Mobile',
        'chessground',
        'dartchess',
        'Instrument Sans',
        'Newsreader',
      ]) {
        expect(find.text(name), findsWidgets);
      }
      expect(find.text('GPL-3.0', findRichText: true), findsWidgets);
    });
  });
}
