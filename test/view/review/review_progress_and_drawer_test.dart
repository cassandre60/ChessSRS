// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC coverage: INV-068 (fresh/due/retained vocabulary), INV-030 (colour scopes).

import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/import/pgn_importer.dart';
import 'package:chess_srs/src/persistence/persistence.dart';
import 'package:chess_srs/src/review/review_service.dart';
import 'package:chess_srs/src/view/review/review_screen.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../binding.dart';
import '../../test_helpers.dart';
import '../../test_provider_scope.dart';

/// The two owner-reported fixes on the review screen:
///
/// * the drawer used to open with no title, so a sheet covering the top bar
///   left nothing on screen saying which repertoire it listed;
/// * the screen showed no progress at all, so a productive session and a stuck
///   one looked identical.
void main() {
  setUpAll(() {
    TestLichessBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late SqliteStudyRepository repo;
  late FixedClock clock;

  setUp(() async {
    await TestLichessBinding.instance.sharedPreferences.clear();
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    final batch = db.batch();
    createSrsTables(batch);
    await batch.commit();
    repo = SqliteStudyRepository(db);
    clock = FixedClock(DateTime.utc(2026, 11, 4, 10));
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pumpReview(WidgetTester tester) async {
    final importResult = importPgn(
      '1. e4 e5 2. Nf3 *',
      studyTitle: 'King Pawn Repertoire',
      repertoireSide: Side.white,
    );
    await tester.runAsync(() async {
      await repo.saveImportResult(importResult);
    });

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
    await pumpUntilFound(tester, find.byType(ReviewScreen));
  }

  testWidgets('active review shows session progress and retention, not just a due count', (
    tester,
  ) async {
    await pumpReview(tester);
    await pumpUntilFound(tester, find.textContaining('done ·'));

    // The line reports both halves the owner asked for: how far through today's
    // queue the session is, and how much of the repertoire is retained.
    expect(find.textContaining('of'), findsWidgets);
    expect(find.textContaining('retained'), findsOneWidget);
    expect(
      find.textContaining('done ·'),
      findsOneWidget,
      reason: 'the session progress line must be on screen during review, not only when idle',
    );
  });

  testWidgets('the colour drawer names its repertoire before listing anything', (tester) async {
    await pumpReview(tester);
    await pumpUntilFound(tester, find.byTooltip('White repertoire'));

    await tester.tap(find.byTooltip('White repertoire'));
    await tester.pumpAndSettle();

    // The title is the only visible text carrying the colour's name (the
    // top-bar tooltip is not a Text unless it is being shown).
    expect(find.text('White repertoire'), findsOneWidget);
    expect(
      find.textContaining('study'),
      findsOneWidget,
      reason: 'the drawer summary says what the colour holds, so an empty drawer is not a mystery',
    );
  });
}
