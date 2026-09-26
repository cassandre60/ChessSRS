// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// Headless screenshot capture for design review.
//
// AGENTS.md requires screenshot evidence for visual work, at phone, tablet and desktop
// widths, in light and dark. Doing that by hand needs exclusive use of a desktop session,
// which is not always available — and a capture nobody takes is a capture nobody checks.
// This renders the real screens through the real provider scope and writes PNGs.
//
// It is a review tool, not a gate. Pixel comparison across machines and font stacks is too
// brittle to assert on, so nothing here compares anything: it writes files and passes. That
// is also why it is opt-in — `flutter test` in CI should not scribble into the tree.
//
//   SRS_CAPTURE_SCREENSHOTS=1 fvm flutter test test/view/screenshot_capture_test.dart
//   SRS_CAPTURE_DIR=/tmp/shots SRS_CAPTURE_SCREENSHOTS=1 fvm flutter test ...
//
// Brightness is pinned twice on purpose: the harness pins SrsTheme, and the preference
// pins themeMode to an explicit value. Left on `system`, the app resolves against
// MediaQuery.platformBrightness, which a widget test cannot reliably push through
// MaterialApp's MediaQuery — and a file named "dark" that quietly rendered light would be
// worse than no capture at all.

import 'dart:convert';
import 'dart:io';

import 'package:chess_srs/src/domain/clock.dart';
import 'package:chess_srs/src/import/pgn_importer.dart';
import 'package:chess_srs/src/model/analysis/analysis_controller.dart';
import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chess_srs/src/model/common/id.dart';
import 'package:chess_srs/src/model/settings/general_preferences.dart';
import 'package:chess_srs/src/model/settings/preferences_storage.dart';
import 'package:chess_srs/src/model/study/study_preferences.dart';
import 'package:chess_srs/src/persistence/persistence.dart';
import 'package:chess_srs/src/review/review_controller.dart';
import 'package:chess_srs/src/review/review_service.dart';
import 'package:chess_srs/src/view/analysis/analysis_screen.dart';
import 'package:chess_srs/src/view/review/review_screen.dart';
import 'package:chess_srs/src/view/settings/srs_settings_screen.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override, ProviderOrFamily;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show Scaffold;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../binding.dart';
import '../test_provider_scope.dart';

/// Set to anything truthy to run. Skipped otherwise, so CI leaves the tree alone.
final bool _enabled = switch (Platform.environment['SRS_CAPTURE_SCREENSHOTS']) {
  '1' || 'true' || 'yes' => true,
  _ => false,
};

// The golden comparator owns the output path now (see `capture`), so there is no output
// directory constant here to redirect.

/// Widths to capture. Phone and desktop are the demo's own frame sizes widened to a
/// realistic aspect; the tablet width is the portrait iPad logical size, which is the
/// awkward middle this layout has to survive.
const List<(String, Size)> _surfaces = [
  ('phone', Size(390, 844)),
  ('tablet', Size(834, 1112)),
  ('desktop', Size(1440, 900)),
];

final GlobalKey _captureKey = GlobalKey();

/// A position with a line already played, so Analysis opens on a tree rather than a void.
const _analysisOptions = AnalysisOptions.pgn(
  id: StringId('capture'),
  orientation: Side.white,
  pgn: '1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 *',
  isComputerAnalysisAllowed: false,
  variant: Variant.standard,
);

/// The design's own typefaces, loaded so the captures show real typography.
///
/// `flutter test` ships no fonts, so every glyph falls back to a filled box. That is fine
/// for a layout assertion and useless for a design review: you cannot judge a type scale,
/// a line height, a truncation, or whether an icon is the right icon. These are the
/// families the app declares in pubspec, registered under the same names its styles use.
Future<void> _loadDesignFonts() async {
  // The icon faces matter as much as the text ones: without them every glyph in the
  // analysis bottom bar and the engine panel renders as a filled box, which is precisely
  // the kind of thing a capture is supposed to be checking.
  for (final (family, path) in const [
    ('InstrumentSans', 'assets/fonts/InstrumentSans[wdth,wght].ttf'),
    ('Newsreader', 'assets/fonts/Newsreader[opsz,wght].ttf'),
    ('LichessIcons', 'assets/fonts/LichessIcons.ttf'),
    ('SocialIcons', 'assets/fonts/SocialIcons.ttf'),
    ('ChessFont', 'assets/fonts/ChessSansPiratf.ttf'),
    ('LichessPuzzleIcons', 'assets/fonts/PuzzleIcons.ttf'),
  ]) {
    final loader = FontLoader(family)..addFont(rootBundle.load(path));
    await loader.load();
  }
}

void main() {
  setUpAll(() async {
    TestLichessBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await _loadDesignFonts();
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
    clock = FixedClock(DateTime.utc(2026, 9, 16, 10, 0));
  });

  tearDown(() async {
    await db.close();
  });

  Map<ProviderOrFamily, Override> repoOverrides() => {
    srsStudyRepositoryProvider: srsStudyRepositoryProvider.overrideWith((ref) => repo),
    clockProvider: clockProvider.overrideWithValue(clock),
    reviewServiceProvider: reviewServiceProvider.overrideWith(
      (ref) => ReviewService(repository: repo, clock: clock),
    ),
  };

  /// Pumps [home] at [surface] in [brightness] and writes `<screen>-<width>-<theme>.png`.
  ///
  /// [seed] runs before the first pump, for screens that need data the pump cannot create.
  /// A due position has to be written straight to the repository: importing it through the
  /// live controller deadlocks, because that controller's database futures never complete
  /// outside `runAsync` and the widget is mid-pump. This is the order
  /// review_screen_test.dart uses.
  /// Settles the real async work a screen kicks off.
  ///
  /// The review controller reads the database through futures that never complete under the
  /// fake-async test zone, so pumping alone leaves every screen frozen on its loading state
  /// — which is a deliberately empty ground, and captured as a blank white PNG. This is the
  /// same shape as the pumpAsync helper in review_screen_test.dart.
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> capture(
    WidgetTester tester, {
    required String screen,
    required Widget home,
    required Size surface,
    required Brightness brightness,
    Map<ProviderOrFamily, Override> overrides = const {},
    Future<void> Function(WidgetTester tester)? seed,
    Future<void> Function(WidgetTester tester)? afterSettle,
    bool showMoveHistory = false,
  }) async {
    final theme = brightness == Brightness.dark ? 'dark' : 'light';

    final app = await makeTestProviderScopeApp(
      tester,
      // The RepaintBoundary is the capture surface: everything within the surface size.
      home: RepaintBoundary(key: _captureKey, child: home),
      surfaceSize: surface,
      brightness: brightness,
      overrides: overrides,
      defaultPreferences: {
        if (showMoveHistory)
          PrefCategory.study.storageKey: jsonEncode(
            StudyPrefs.defaults.copyWith(showMoveHistory: true).toJson(),
          ),
        PrefCategory.general.storageKey: jsonEncode(
          GeneralPrefs.defaults
              .copyWith(
                themeMode: brightness == Brightness.dark
                    ? BackgroundThemeMode.dark
                    : BackgroundThemeMode.light,
              )
              .toJson(),
        ),
      },
    );

    if (seed != null) await seed(tester);

    await tester.pumpWidget(app);
    await settle(tester);

    if (afterSettle != null) {
      await afterSettle(tester);
      await settle(tester);
    }

    // A capture that silently produced an empty frame would be worse than no capture: a
    // white PNG sitting in a directory of design evidence reads as "checked, fine". So the
    // screen has to actually be there before anything is written.
    expect(
      find.byKey(_captureKey),
      findsOneWidget,
      reason: 'the capture boundary is gone, so the file would be blank',
    );
    expect(
      find.byType(Scaffold),
      findsWidgets,
      reason: 'nothing rendered, so the file would be blank',
    );

    // Written through the golden-file comparator rather than RenderRepaintBoundary.toImage:
    // the test binding does not composite a layer tree on demand, so toImage hands back an
    // empty frame — a white PNG, which is exactly what it did. This is the path Flutter
    // supports. Golden paths are relative to this file, so the pair of `..` lands the
    // evidence in docs/ rather than in test/.
    await expectLater(
      find.byKey(_captureKey),
      matchesGoldenFile('../../docs/screenshots/$screen-${surface.width.round()}-$theme.png'),
    );

    // ignore: avoid_print
    print('captured $screen ${surface.width.round()} $theme');
  }

  for (final (label, surface) in _surfaces) {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      testWidgets('capture: review empty state, $label, ${brightness.name}', (tester) async {
        await capture(
          tester,
          screen: 'review-empty',
          home: const ReviewScreen(),
          surface: surface,
          brightness: brightness,
          overrides: repoOverrides(),
        );
      }, skip: !_enabled);

      testWidgets('capture: review with a due position, $label, ${brightness.name}', (
        tester,
      ) async {
        await capture(
          tester,
          screen: 'review-prompt',
          home: const ReviewScreen(),
          surface: surface,
          brightness: brightness,
          overrides: repoOverrides(),
          seed: (t) async {
            final result = importPgn(
              '1. d4 d5 2. c4 e6 3. Nc3 Nf6 *',
              studyTitle: 'Queen Pawn',
              repertoireSide: Side.white,
            );
            await t.runAsync(() => repo.saveImportResult(result));
          },
        );
      }, skip: !_enabled);

      // The state the design spends most of its detail on: the answer, the note, the
      // Continue affordance and its keyboard hint. It has never been seen, because
      // reaching it means playing a move.
      testWidgets('capture: review after a correct move, $label, ${brightness.name}', (
        tester,
      ) async {
        await capture(
          tester,
          screen: 'review-answered',
          // The notation line is off by default in the build, so without this the capture
          // would not show the thing design/docs/03-components.md §111 calls "the headline".
          // It is captured here rather than turned on in the app: study_preferences.dart is
          // another agent's file and the default is a product decision, not a capture's.
          showMoveHistory: true,
          home: const ReviewScreen(),
          surface: surface,
          brightness: brightness,
          overrides: repoOverrides(),
          seed: (t) async {
            final result = importPgn(
              // A comment, so the note block the design specifies is actually populated.
              '1. d4 {The Queen Pawn Game} d5 2. c4 e6 3. Nc3 Nf6 *',
              studyTitle: 'Queen Pawn',
              repertoireSide: Side.white,
            );
            await t.runAsync(() => repo.saveImportResult(result));
          },
          afterSettle: (t) async {
            // Inside runAsync: the controller's futures need real async to complete, and
            // calling it straight from the fake-async zone deadlocks the test.
            await t.runAsync(() async {
              final container = ProviderScope.containerOf(
                t.element(find.byType(ReviewScreen)),
                listen: false,
              );
              await container
                  .read(reviewControllerProvider.notifier)
                  .onUserMove(const NormalMove(from: Square.d2, to: Square.d4));
            });
          },
        );
      }, skip: !_enabled);

      testWidgets('capture: settings, $label, ${brightness.name}', (tester) async {
        await capture(
          tester,
          screen: 'settings',
          home: const SrsSettingsScreen(),
          surface: surface,
          brightness: brightness,
        );
      }, skip: !_enabled);

      testWidgets('capture: analysis, $label, ${brightness.name}', (tester) async {
        await capture(
          tester,
          screen: 'analysis',
          home: const AnalysisScreen(options: _analysisOptions),
          surface: surface,
          brightness: brightness,
          overrides: repoOverrides(),
        );
      }, skip: !_enabled);
    }
  }
}
