// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC coverage: INV-030.

import 'dart:io';

import 'package:chess_srs/src/db/database.dart';
import 'package:chess_srs/src/design/design.dart' show SrsPressable;
import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/import/pgn_importer.dart';
import 'package:chess_srs/src/persistence/persistence.dart';
import 'package:chess_srs/src/review/review_controller.dart';
import 'package:chess_srs/src/review/review_service.dart';
import 'package:chess_srs/src/view/review/review_scope_drawer.dart';
import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderScope;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show TextField;
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../binding.dart';
import '../../test_helpers.dart';
import '../../test_provider_scope.dart';

/// Owner request 2026-10-05: the drawer's single `All studies` row becomes two
/// side-by-side buttons, `White repertoire` and `Black repertoire`.
///
/// The assertion is deliberately on the rendered drawer rather than on
/// `ReviewScope` alone: a scope that exists but is never offered is not a
/// feature, and `All studies` surviving as a third row would give the user a
/// third way to review the same pool.
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
    tempDir = Directory.systemTemp.createTempSync('chess_srs_scope_buttons_');
    db = await openAppDatabase(databaseFactoryFfi, p.join(tempDir.path, 'buttons.db'));
    repo = SqliteStudyRepository(db);
    clock = FixedClock(DateTime.utc(2026, 10, 5, 12));

    // One study per side, so both buttons have material to show.
    await repo.saveImportResult(
      importPgn('[Orientation "white"]\n1. e4 e5 *', studyTitle: 'White book'),
    );
    await repo.saveImportResult(
      importPgn('[Orientation "black"]\n1. d4 d5 *', studyTitle: 'Black book'),
    );
  });

  tearDown(() async {
    await db.close();
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> pumpDrawer(WidgetTester tester, {Size size = const Size(1400, 900)}) async {
    await tester.pumpWidget(
      await makeTestProviderScopeApp(
        tester,
        surfaceSize: size,
        home: const ReviewScopeDrawer(),
        overrides: {
          srsStudyRepositoryProvider: srsStudyRepositoryProvider.overrideWith((ref) => repo),
          clockProvider: clockProvider.overrideWithValue(clock),
          reviewServiceProvider: reviewServiceProvider.overrideWith(
            (ref) => ReviewService(repository: repo, clock: clock),
          ),
        },
      ),
    );
    // Not pumpAndSettle: the drawer's search field autofocuses on a wide layout
    // and its cursor blinks forever, so settling never completes. This is the
    // same reason the review tests use pumpAsync.
    await pumpAsync(tester);
  }

  Finder inDrawer(Finder matching) =>
      find.descendant(of: find.byType(ReviewScopeDrawer), matching: matching);

  testWidgets('both repertoire buttons are offered', (tester) async {
    await pumpDrawer(tester);

    expect(inDrawer(find.text('White repertoire')), findsOneWidget);
    expect(inDrawer(find.text('Black repertoire')), findsOneWidget);
  });

  testWidgets('the single All studies row is gone', (tester) async {
    await pumpDrawer(tester);

    expect(
      inDrawer(find.text('All studies')),
      findsNothing,
      reason: 'the two side buttons replace it; keeping it would be a third path to the same pool',
    );
  });

  testWidgets('the two buttons sit side by side, not stacked', (tester) async {
    await pumpDrawer(tester);

    final white = tester.getRect(inDrawer(find.text('White repertoire')));
    final black = tester.getRect(inDrawer(find.text('Black repertoire')));

    // Side by side means the same vertical band and no horizontal overlap: a
    // stacked pair shares x and differs in y, which is the layout this replaced.
    expect(white.center.dy, closeTo(black.center.dy, 12.0));
    expect(white.right, lessThanOrEqualTo(black.left));
  });

  testWidgets('each button shows only its own side’s due count', (tester) async {
    await pumpDrawer(tester);

    // Expected counts come from the repository, not from the widget, so a button
    // that showed the total instead of its own half fails here. Read inside
    // runAsync: these are real SQLite futures, and a testWidgets body runs in a
    // fake-async zone where awaiting one never completes.
    final expected = <String, int>{};
    await tester.runAsync(() async {
      var whiteDue = 0;
      var blackDue = 0;
      for (final study in await repo.getAllStudies()) {
        for (final chapter in await repo.getChaptersByStudy(study.id)) {
          final count = (await repo.getDecisionsByChapter(chapter.id)).length;
          if (chapter.orientation == Side.white) {
            whiteDue += count;
          } else {
            blackDue += count;
          }
        }
      }
      expected['White repertoire'] = whiteDue;
      expected['Black repertoire'] = blackDue;
    });
    expect(expected['White repertoire'], greaterThan(0));
    expect(expected['Black repertoire'], greaterThan(0));

    String countUnder(String label) {
      final card = find.ancestor(
        of: inDrawer(find.text(label)),
        matching: find.byType(SrsPressable),
      );
      final numerals = tester
          .widgetList<Text>(find.descendant(of: card.first, matching: find.byType(Text)))
          .map((t) => t.data)
          .whereType<String>()
          .where((s) => int.tryParse(s) != null);
      expect(numerals, isNotEmpty, reason: '$label must show a due count');
      return numerals.first;
    }

    for (final entry in expected.entries) {
      expect(countUnder(entry.key), '${entry.value}', reason: '${entry.key} due count');
    }
  });

  testWidgets('tapping a button selects that side’s scope', (tester) async {
    await pumpDrawer(tester);

    // Captured before the tap: the drawer pops itself on selection, so its element
    // is gone by the time the resulting scope is read.
    final container = ProviderScope.containerOf(tester.element(find.byType(ReviewScopeDrawer)));

    await tester.tap(inDrawer(find.text('Black repertoire')));
    await pumpAsync(tester);

    // Read through the container rather than the fill colour: any highlight at all
    // would satisfy a colour assertion, but only the scope proves the button did
    // its job.
    final scope = await tester.runAsync(
      () async => container.read(reviewControllerProvider).value?.scope,
    );
    expect(scope?.side, Side.black);
  });

  testWidgets('both buttons stay reachable on a narrow phone', (tester) async {
    await pumpDrawer(tester, size: const Size(360, 640));

    expect(inDrawer(find.text('White repertoire')), findsOneWidget);
    expect(inDrawer(find.text('Black repertoire')), findsOneWidget);

    // Neither card may be pushed off the side of a phone-sized window.
    for (final label in ['White repertoire', 'Black repertoire']) {
      final box = tester.getRect(inDrawer(find.text(label)));
      expect(box.left, greaterThanOrEqualTo(0), reason: label);
      expect(box.right, lessThanOrEqualTo(360), reason: label);
    }
  });

  testWidgets('searching for one side keeps only its button', (tester) async {
    await pumpDrawer(tester);

    await tester.enterText(find.byType(TextField).first, 'black');
    await pumpAsync(tester);

    expect(inDrawer(find.text('Black repertoire')), findsOneWidget);
    expect(inDrawer(find.text('White repertoire')), findsNothing);
  });
}
