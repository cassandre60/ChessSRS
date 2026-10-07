// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC coverage: INV-030.

import 'dart:io';

import 'package:chess_srs/src/db/database.dart';
import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/import/pgn_importer.dart';
import 'package:chess_srs/src/persistence/persistence.dart';
import 'package:chess_srs/src/review/review_controller.dart';
import 'package:chess_srs/src/review/review_service.dart';
import 'package:chess_srs/src/view/review/review_scope_drawer.dart';
import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderContainer, ProviderScope;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../binding.dart';
import '../../test_helpers.dart';
import '../../test_provider_scope.dart';

/// Owner request 2026-10-06: one drawer per repertoire colour rather than one
/// drawer holding both.
///
/// The property that matters is independence: what is reachable from the White
/// drawer must not change when the Black library changes, and vice versa. Every
/// assertion below is about that, because a shared list is the failure mode
/// that looks correct in a screenshot with one study per colour and is wrong the
/// moment the user has an uneven library — which is the ordinary state, since
/// "I imported everything as White" is how most libraries start.
void main() {
  setUpAll(() {
    TestLichessBinding.ensureInitialized();
    sqfliteFfiInit();
  });

  late Directory tempDir;
  late Database db;
  late SqliteStudyRepository repo;
  late FixedClock clock;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('chess_srs_split_drawers_');
    db = await openAppDatabase(databaseFactoryFfi, p.join(tempDir.path, 'drawers.db'));
    repo = SqliteStudyRepository(db);
    clock = FixedClock(DateTime.utc(2026, 10, 6, 12));

    // One study and one opening per colour. The opening headers are what put a
    // hub in the drawer, so a colour with only a study would not exercise the
    // Openings group.
    await repo.saveImportResult(
      importPgn(
        '[Event "Sicilian Defence"]\n1. e4 c5 *',
        studyTitle: 'White book',
        repertoireSide: Side.white,
      ),
    );
    await repo.saveImportResult(
      importPgn(
        '[Event "French Defence"]\n1. e4 e6 *',
        studyTitle: 'Black book',
        repertoireSide: Side.black,
      ),
    );
  });

  tearDown(() async {
    await db.close();
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<ProviderContainer> pumpDrawer(WidgetTester tester, Side side) async {
    final app = await makeTestProviderScopeApp(
      tester,
      surfaceSize: const Size(1400, 900),
      home: ReviewScopeDrawer(side: side),
      overrides: {
        srsStudyRepositoryProvider: srsStudyRepositoryProvider.overrideWith((ref) => repo),
        clockProvider: clockProvider.overrideWithValue(clock),
        reviewServiceProvider: reviewServiceProvider.overrideWith(
          (ref) => ReviewService(repository: repo, clock: clock),
        ),
      },
    );
    await tester.pumpWidget(app);
    // Not pumpAndSettle: the drawer's search field autofocuses on a wide layout
    // and its cursor blinks forever, so settling never completes.
    await pumpAsync(tester);
    // Captured before any tap: the drawer pops itself on selection, so its
    // element is gone by the time the resulting scope is read.
    return ProviderScope.containerOf(tester.element(find.byType(ReviewScopeDrawer)));
  }

  Finder inDrawer(Finder matching) =>
      find.descendant(of: find.byType(ReviewScopeDrawer), matching: matching);

  testWidgets('the White drawer lists only White material', (tester) async {
    await pumpDrawer(tester, Side.white);

    expect(inDrawer(find.text('White book')), findsOneWidget);
    expect(inDrawer(find.text('Sicilian Defence')), findsOneWidget);
    expect(
      inDrawer(find.text('Black book')),
      findsNothing,
      reason: 'a Black study in the White drawer is the independence bug this file is for',
    );
    expect(inDrawer(find.text('French Defence')), findsNothing);
  });

  testWidgets('the Black drawer lists only Black material', (tester) async {
    await pumpDrawer(tester, Side.black);

    expect(inDrawer(find.text('Black book')), findsOneWidget);
    expect(inDrawer(find.text('French Defence')), findsOneWidget);
    expect(inDrawer(find.text('White book')), findsNothing);
    expect(inDrawer(find.text('Sicilian Defence')), findsNothing);
  });

  testWidgets('neither drawer spells out the colour or offers an everywhere row', (tester) async {
    for (final side in [Side.white, Side.black]) {
      await pumpDrawer(tester, side);

      expect(inDrawer(find.text('All studies')), findsNothing);
      expect(inDrawer(find.text('Repertoires')), findsNothing);
      expect(inDrawer(find.textContaining('White repertoire')), findsNothing);
      expect(inDrawer(find.textContaining('Black repertoire')), findsNothing);
    }
  });

  testWidgets('tapping a row scopes to it and carries the drawer’s colour', (tester) async {
    final container = await pumpDrawer(tester, Side.black);

    await tester.tap(inDrawer(find.text('Black book')));
    await pumpAsync(tester);

    final state = await tester.runAsync(() async => container.read(reviewControllerProvider).value);
    expect(state?.scope.studyId, isNotNull);
    expect(
      state?.activeSide,
      Side.black,
      reason: 'the active colour must follow the study, so the top bar square matches',
    );
  });

  testWidgets('an opening row carries the colour too', (tester) async {
    final container = await pumpDrawer(tester, Side.white);

    await tester.tap(inDrawer(find.text('Sicilian Defence')));
    await pumpAsync(tester);

    final state = await tester.runAsync(() async => container.read(reviewControllerProvider).value);
    expect(state?.scope.openingFamily, 'Sicilian Defence');
    expect(state?.activeSide, Side.white);
  });

  testWidgets('an empty colour lists nothing rather than the other side’s work', (tester) async {
    final blackBook = await tester.runAsync(() async {
      final all = await repo.getAllStudies();
      return all.where((s) => s.title == 'Black book').first;
    });
    await tester.runAsync(() async {
      await repo.deleteStudy(blackBook!.id);
    });

    await pumpDrawer(tester, Side.black);

    expect(inDrawer(find.text('Black book')), findsNothing);
    expect(
      inDrawer(find.text('White book')),
      findsNothing,
      reason: 'the White study must not stand in for the Black drawer having nothing',
    );
    expect(inDrawer(find.text('Openings')), findsNothing);
    expect(inDrawer(find.text('Studies')), findsNothing);
  });

  testWidgets('searching only matches within the drawer’s own colour', (tester) async {
    await pumpDrawer(tester, Side.white);

    await tester.enterText(find.byType(EditableText).first, 'French');
    await pumpAsync(tester);

    expect(inDrawer(find.text('Black book')), findsNothing);
    expect(inDrawer(find.text('Sicilian Defence')), findsNothing);
    expect(find.text('Nothing matches “French”.'), findsOneWidget);
  });
}
