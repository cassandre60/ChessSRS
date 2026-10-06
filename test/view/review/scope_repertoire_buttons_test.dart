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

/// Owner request 2026-10-06: the two side-by-side repertoire buttons become
/// two menus, each heading the studies that train its side.
///
/// The assertion is deliberately on the rendered drawer rather than on
/// `ReviewScope` alone: a scope that exists but is never offered is not a
/// feature, and a study sitting outside its colour's menu is the layout this
/// replaces.
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
    tempDir = Directory.systemTemp.createTempSync('chess_srs_scope_menus_');
    db = await openAppDatabase(databaseFactoryFfi, p.join(tempDir.path, 'menus.db'));
    repo = SqliteStudyRepository(db);
    clock = FixedClock(DateTime.utc(2026, 10, 5, 12));

    // One study per side, plus one training both, so every menu has material
    // and the both-sides study exercises appearing under both menus.
    await repo.saveImportResult(
      importPgn('[Orientation "white"]\n1. e4 e5 *', studyTitle: 'White book'),
    );
    await repo.saveImportResult(
      importPgn('[Orientation "black"]\n1. d4 d5 *', studyTitle: 'Black book'),
    );
    await repo.saveImportResult(
      importPgn(
        '[Orientation "white"]\n1. c4 e5 *\n\n[Orientation "black"]\n1. e4 c5 *',
        studyTitle: 'Mixed lines',
      ),
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

  testWidgets('both repertoire menus are offered', (tester) async {
    await pumpDrawer(tester);

    expect(inDrawer(find.text('White repertoire')), findsOneWidget);
    expect(inDrawer(find.text('Black repertoire')), findsOneWidget);
  });

  testWidgets('the single All studies row is gone', (tester) async {
    await pumpDrawer(tester);

    expect(
      inDrawer(find.text('All studies')),
      findsNothing,
      reason: 'the two side menus replace it; keeping it would be a third path to the same pool',
    );
  });

  testWidgets('menus stack vertically with each study under its own menu', (tester) async {
    await pumpDrawer(tester);

    final whiteMenu = tester.getRect(inDrawer(find.text('White repertoire')));
    final whiteBook = tester.getRect(inDrawer(find.text('White book')));
    final blackMenu = tester.getRect(inDrawer(find.text('Black repertoire')));
    final blackBook = tester.getRect(inDrawer(find.text('Black book')));

    // The scope row heads its menu and the study sits inside it: the study's
    // row falls between its own menu's scope row and the other menu's.
    expect(whiteBook.top, greaterThan(whiteMenu.bottom));
    expect(whiteBook.bottom, lessThan(blackMenu.top));
    expect(blackBook.top, greaterThan(blackMenu.bottom));
    expect(whiteMenu.right, greaterThan(whiteMenu.left + 200));
  });

  testWidgets('each menu shows only its own side’s figures', (tester) async {
    await pumpDrawer(tester);

    // Expected counts come from the repository, not from the widget, so a menu
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
      final row = find.ancestor(
        of: inDrawer(find.text(label)),
        matching: find.byType(SrsPressable),
      );
      final numerals = tester
          .widgetList<Text>(find.descendant(of: row.first, matching: find.byType(Text)))
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

  testWidgets('a both-sides study appears under both menus', (tester) async {
    await pumpDrawer(tester);

    expect(
      inDrawer(find.text('Mixed lines')),
      findsNWidgets(2),
      reason: 'the study trains both sides, so it belongs to both menus',
    );

    final blackMenu = tester.getRect(inDrawer(find.text('Black repertoire')));
    final rows = inDrawer(find.text('Mixed lines')).evaluate().map((element) {
      final box = element.renderObject! as RenderBox;
      return box.localToGlobal(Offset.zero) & box.size;
    }).toList()..sort((Rect a, Rect b) => a.top.compareTo(b.top));
    expect(rows, hasLength(2));
    expect(rows[0].bottom, lessThan(blackMenu.top), reason: 'first copy sits in the White menu');
    expect(
      rows[1].top,
      greaterThan(blackMenu.bottom),
      reason: 'second copy sits in the Black menu',
    );
  });

  testWidgets('tapping a scope row selects that side’s scope', (tester) async {
    await pumpDrawer(tester);

    // Captured before the tap: the drawer pops itself on selection, so its element
    // is gone by the time the resulting scope is read.
    final container = ProviderScope.containerOf(tester.element(find.byType(ReviewScopeDrawer)));

    await tester.tap(inDrawer(find.text('Black repertoire')));
    await pumpAsync(tester);

    // Read through the container rather than the fill colour: any highlight at all
    // would satisfy a colour assertion, but only the scope proves the row did
    // its job.
    final scope = await tester.runAsync(
      () async => container.read(reviewControllerProvider).value?.scope,
    );
    expect(scope?.side, Side.black);
  });

  testWidgets('collapsing a menu hides its studies but keeps its scope row', (tester) async {
    await pumpDrawer(tester);

    expect(inDrawer(find.text('White book')), findsOneWidget);
    await tester.tap(inDrawer(find.bySemanticsLabel('Collapse White repertoire studies')));
    await pumpAsync(tester);

    expect(inDrawer(find.text('White repertoire')), findsOneWidget);
    expect(inDrawer(find.text('White book')), findsNothing);
    expect(inDrawer(find.text('Black book')), findsOneWidget);
  });

  testWidgets('both menus stay reachable on a narrow phone', (tester) async {
    await pumpDrawer(tester, size: const Size(360, 640));

    expect(inDrawer(find.text('White repertoire')), findsOneWidget);
    expect(inDrawer(find.text('Black repertoire')), findsOneWidget);

    // Neither menu may be pushed off the side of a phone-sized window.
    for (final label in ['White repertoire', 'Black repertoire']) {
      final box = tester.getRect(inDrawer(find.text(label)));
      expect(box.left, greaterThanOrEqualTo(0), reason: label);
      expect(box.right, lessThanOrEqualTo(360), reason: label);
    }
  });

  testWidgets('searching for one side keeps only its menu', (tester) async {
    await pumpDrawer(tester);

    await tester.enterText(find.byType(TextField).first, 'black');
    await pumpAsync(tester);

    expect(inDrawer(find.text('Black repertoire')), findsOneWidget);
    expect(inDrawer(find.text('White repertoire')), findsNothing);
    expect(inDrawer(find.text('Black book')), findsOneWidget);
    expect(inDrawer(find.text('White book')), findsNothing);
  });

  testWidgets('a White study offers only the Black version, which lands in the Black menu', (
    tester,
  ) async {
    await pumpDrawer(tester);

    // The `…` of the White book's own row, not another study's: the rows share
    // a tooltip, so pick the button riding next to this study's row.
    Future<void> openOptionsFor(String studyTitle) async {
      final row = tester.getRect(inDrawer(find.text(studyTitle)));
      final matches = inDrawer(find.bySemanticsLabel('Study options')).evaluate().where((element) {
        final box = element.renderObject! as RenderBox;
        final rect = box.localToGlobal(Offset.zero) & box.size;
        return (rect.center.dy - row.center.dy).abs() < 30;
      }).toList();
      expect(matches, hasLength(1), reason: 'one options button per study row');
      await tester.tap(find.byWidget(matches.first.widget));
      await pumpAsync(tester);
    }

    await openOptionsFor('White book');

    expect(find.text('Create Black version'), findsOneWidget);
    expect(find.text('Create White version'), findsNothing);

    await tester.tap(find.text('Create Black version'));
    await pumpAsync(tester);
    // The re-import hits real SQLite from the fake-async test zone, so give it
    // real time to land before asserting on the rebuilt list.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await pumpAsync(tester);

    expect(
      inDrawer(find.text('White book (Black)')),
      findsOneWidget,
      reason: 'the counterpart study is created',
    );
    final blackMenu = tester.getRect(inDrawer(find.text('Black repertoire')));
    final flipped = tester.getRect(inDrawer(find.text('White book (Black)')));
    expect(
      flipped.top,
      greaterThan(blackMenu.bottom),
      reason: 'the counterpart lands in the Black menu',
    );
  });
}
