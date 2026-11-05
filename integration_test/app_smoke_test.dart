// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// Runtime smoke: drives the real review screen on a real engine (Linux desktop,
// under Xvfb) with a real SQLite database. It imports a PGN and answers the
// first prompt, then asserts the answer reached the database.
//
// This is not a per-PR gate and not a substitute for the human device pass
// (TEST_STRATEGY §4). It proves the core loop runs off the test binding — real
// rendering, real board taps, real persistence — which widget tests cannot.
//
//   xvfb-run -a flutter test integration_test/app_smoke_test.dart -d linux

import 'dart:io';

import 'package:chess_srs/l10n/l10n.dart';
import 'package:chess_srs/src/binding.dart';
import 'package:chess_srs/src/db/database.dart';
import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/persistence/persistence.dart';
import 'package:chess_srs/src/review/review_controller.dart';
import 'package:chess_srs/src/review/review_service.dart';
import 'package:chess_srs/src/view/review/review_screen.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:l10n_esperanto/l10n_esperanto.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // The real app binding, because settings providers read SharedPreferences.
  // In the app this happens in `main()`; here nothing else would do it.
  final lichessBinding = AppLichessBinding.ensureInitialized();
  setUpAll(() => lichessBinding.preloadSharedPreferences());

  testWidgets('a user imports a PGN and answers the first review prompt', (tester) async {
    // The desktop database path the app itself uses (sqflite ffi), on a temp file.
    sqfliteFfiInit();
    final dir = Directory.systemTemp.createTempSync('chess_srs_smoke_');
    final db = await openAppDatabase(databaseFactoryFfi, '${dir.path}/smoke.db');
    final repo = SqliteStudyRepository(db);
    final clock = FixedClock(DateTime.utc(2026, 11, 5, 12));

    addTearDown(() async {
      await db.close();
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });

    final colors = SrsColors.forBrightness(Brightness.light, kSrsDefaultAccent);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          srsStudyRepositoryProvider.overrideWith((ref) => repo),
          clockProvider.overrideWithValue(clock),
          reviewServiceProvider.overrideWith(
            (ref) => ReviewService(repository: repo, clock: clock),
          ),
        ],
        child: SrsTheme(
          colors: colors,
          child: MaterialApp(
            // Mirror production: the review screen reads AppLocalizations.
            localizationsDelegates: const [
              AppLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
              MaterialLocalizationsEo.delegate,
              CupertinoLocalizationsEo.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            theme: srsThemeData(colors),
            home: const ReviewScreen(),
          ),
        ),
      ),
    );
    await _pumpUntil(tester, () => find.byType(ReviewScreen).evaluate().isNotEmpty);

    // Import a two-move repertoire through the real controller.
    final container = ProviderScope.containerOf(tester.element(find.byType(ReviewScreen)));
    await tester.runAsync(
      () => container
          .read(reviewControllerProvider.notifier)
          .importPgnText(pgnText: '1. e4 e5 2. Nf3 *', title: 'Smoke', repertoireSide: Side.white),
    );

    await _pumpUntil(tester, () => find.byType(Chessboard).evaluate().isNotEmpty);
    final prompt = container.read(reviewControllerProvider).requireValue.currentPrompt;
    expect(prompt, isNotNull, reason: 'the imported repertoire should offer a prompt');

    // Answer it on the board, like a user would.
    final move = prompt!.expectedMoves.first;
    await _playMove(tester, move.from, move.to);

    // The answer must reach the real database; the write is async, so poll.
    var reviewed = 0;
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (reviewed == 0 && DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 100));
      reviewed = (await tester.runAsync(() => repo.getTodayReviewedPositionsCount(clock.now())))!;
    }
    expect(
      reviewed,
      greaterThan(0),
      reason: 'the graded answer must be persisted in the real SQLite database',
    );
  });
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('runtime smoke: timed out waiting for a condition');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _playMove(WidgetTester tester, String from, String to) async {
  final rect = tester.getRect(find.byType(Chessboard));
  final squareSize = rect.width / 8;
  Offset squareCenter(String square) {
    final file = square.codeUnitAt(0) - 'a'.codeUnitAt(0);
    final rank = int.parse(square[1]) - 1;
    return Offset(rect.left + (file + 0.5) * squareSize, rect.top + (7 - rank + 0.5) * squareSize);
  }

  await tester.tapAt(squareCenter(from));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tapAt(squareCenter(to));
  await tester.pump(const Duration(milliseconds: 100));
}
