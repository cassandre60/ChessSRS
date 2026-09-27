// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/db/database.dart';
import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/domain/clock.dart';
import 'package:chess_srs/src/persistence/persistence.dart';
import 'package:chess_srs/src/review/review_service.dart';
import 'package:chess_srs/src/view/review/import_pages.dart';
import 'package:chess_srs/src/view/review/review_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show TextField;
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

  group('Import pages (Diagram .pg)', () {
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

    testWidgets('PastePgnPage renders Diagram copy and validates empty input', (tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: const PastePgnPage(),
        overrides: {
          srsStudyRepositoryProvider: srsStudyRepositoryProvider.overrideWith((ref) => repo),
          databaseProvider: databaseProvider.overrideWith((ref) => db),
        },
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      expect(find.text('Paste PGN text'), findsOneWidget);
      expect(
        find.text('Paste one game or a whole study in PGN format.'),
        findsOneWidget,
      );
      expect(find.text('Train as'), findsOneWidget);
      expect(find.text('Import'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();
      expect(find.text('Paste a PGN first.'), findsOneWidget);
    });

    testWidgets('PastePgnPage imports valid PGN and pops', (tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: const PastePgnPage(),
        overrides: {
          srsStudyRepositoryProvider: srsStudyRepositoryProvider.overrideWith((ref) => repo),
          databaseProvider: databaseProvider.overrideWith((ref) => db),
        },
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '1. e4 e5 2. Nf3 *');
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();

      // Page pops back after successful import and the study is persisted.
      expect(find.byType(PastePgnPage), findsNothing);
      final studies = await repo.getAllStudies();
      expect(studies, isNotEmpty);
    });

    testWidgets('PastePgnPage with non-PGN text opens ImportErrorPage', (tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: const PastePgnPage(),
        overrides: {
          srsStudyRepositoryProvider: srsStudyRepositoryProvider.overrideWith((ref) => repo),
          databaseProvider: databaseProvider.overrideWith((ref) => db),
        },
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'hello world, not chess');
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();

      expect(find.byType(ImportErrorPage), findsOneWidget);
      expect(find.text('Something went wrong.'), findsOneWidget);
      expect(find.textContaining('No moves were found'), findsOneWidget);
    });

    testWidgets('LichessImportPage renders and validates bad link', (tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: const LichessImportPage(),
        overrides: {
          srsStudyRepositoryProvider: srsStudyRepositoryProvider.overrideWith((ref) => repo),
          databaseProvider: databaseProvider.overrideWith((ref) => db),
        },
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      expect(find.text('Import a Lichess study'), findsOneWidget);
      expect(
        find.text('Paste the link to the study. Its chapters are imported as one repertoire.'),
        findsOneWidget,
      );
      expect(find.text('Import study'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'not a link');
      await tester.tap(find.text('Import study'));
      await tester.pumpAndSettle();
      expect(find.text('That link is not a Lichess study.'), findsOneWidget);
    });

    testWidgets('ImportErrorPage renders actions and Try again pops', (tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: const PastePgnPage(),
        overrides: {
          srsStudyRepositoryProvider: srsStudyRepositoryProvider.overrideWith((ref) => repo),
          databaseProvider: databaseProvider.overrideWith((ref) => db),
        },
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'garbage without moves');
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();
      expect(find.byType(ImportErrorPage), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Copy details'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.byType(ImportErrorPage), findsNothing);
      expect(find.byType(PastePgnPage), findsOneWidget);
    });

    testWidgets('SrsDialog-backed pages use Diagram tokens (ink3 lede)', (tester) async {
      // Smoke: pages build without overflow and expose Train-as segmented options.
      final app = await makeTestProviderScopeApp(
        tester,
        home: const LichessImportPage(),
        overrides: {
          srsStudyRepositoryProvider: srsStudyRepositoryProvider.overrideWith((ref) => repo),
          databaseProvider: databaseProvider.overrideWith((ref) => db),
        },
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();
      expect(find.text('Auto'), findsOneWidget);
      expect(find.text('White'), findsOneWidget);
      expect(find.text('Black'), findsOneWidget);
      expect(find.byType(SrsPillButton), findsOneWidget);
      expect(find.byType(SrsTextButton), findsOneWidget);
    });

    testWidgets('PastePgnPage honors initialText and suggestedTitle', (tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: const PastePgnPage(
          initialText: '1. e4 e5 *',
          suggestedTitle: 'File Pick Title',
        ),
        overrides: {
          srsStudyRepositoryProvider: srsStudyRepositoryProvider.overrideWith((ref) => repo),
          databaseProvider: databaseProvider.overrideWith((ref) => db),
        },
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      // Prefilled field keeps the provided text.
      expect(find.textContaining('1. e4 e5'), findsOneWidget);

      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();

      expect(find.byType(PastePgnPage), findsNothing);
      final studies = await repo.getAllStudies();
      expect(studies.map((s) => s.title), contains('File Pick Title'));
    });

    testWidgets('Lichess link pasted in PGN field routes to LichessImportPage', (tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: const PastePgnPage(),
        overrides: {
          srsStudyRepositoryProvider: srsStudyRepositoryProvider.overrideWith((ref) => repo),
          databaseProvider: databaseProvider.overrideWith((ref) => db),
        },
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'https://lichess.org/study/m1AbCd2E');
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();

      expect(find.byType(LichessImportPage), findsOneWidget);
      expect(find.textContaining('lichess.org/study/m1AbCd2E'), findsOneWidget);
    });

    testWidgets('empty-state Paste PGN text opens PastePgnPage', (tester) async {
      final clock = FixedClock(DateTime.utc(2026, 9, 16, 10, 0));
      final app = await makeTestProviderScopeApp(
        tester,
        home: const ReviewScreen(),
        overrides: {
          srsStudyRepositoryProvider: srsStudyRepositoryProvider.overrideWith((ref) => repo),
          clockProvider: clockProvider.overrideWithValue(clock),
          reviewServiceProvider: reviewServiceProvider.overrideWith(
            (ref) => ReviewService(repository: repo, clock: clock),
          ),
        },
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      expect(find.text('Bring your repertoire.'), findsOneWidget);
      await tester.tap(find.text('Paste PGN text'));
      await tester.pumpAndSettle();

      expect(find.byType(PastePgnPage), findsOneWidget);
      expect(find.text('Paste one game or a whole study in PGN format.'), findsOneWidget);
    });

    testWidgets('empty-state Import a Lichess study opens LichessImportPage', (tester) async {
      final clock = FixedClock(DateTime.utc(2026, 9, 16, 10, 0));
      final app = await makeTestProviderScopeApp(
        tester,
        home: const ReviewScreen(),
        overrides: {
          srsStudyRepositoryProvider: srsStudyRepositoryProvider.overrideWith((ref) => repo),
          clockProvider: clockProvider.overrideWithValue(clock),
          reviewServiceProvider: reviewServiceProvider.overrideWith(
            (ref) => ReviewService(repository: repo, clock: clock),
          ),
        },
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      expect(find.text('Bring your repertoire.'), findsOneWidget);
      await tester.tap(find.text('Import a Lichess study'));
      await tester.pumpAndSettle();

      expect(find.byType(LichessImportPage), findsOneWidget);
      expect(
        find.text('Paste the link to the study. Its chapters are imported as one repertoire.'),
        findsOneWidget,
      );
    });
  });
}
