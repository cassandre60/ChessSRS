// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/model/log/app_log_storage.dart';
import 'package:chess_srs/src/model/settings/log_preferences.dart';
import 'package:chess_srs/src/view/settings/app_log_settings_screen.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:material_ui/material_ui.dart';

import '../../binding.dart';
import '../../test_provider_scope.dart';

/// A fixed stamp for the fixtures. The log query filters on id, level and text, never on the
/// time, so the wall clock has no place in these entries.
final _now = DateTime.utc(2026, 1, 1);

AppLogEntry _entry({
  required String message,
  String loggerName = 'StudyRepository',
  Level level = Level.INFO,
  String? error,
  String? stackTrace,
}) => AppLogEntry(
  logTime: _now,
  loggerName: loggerName,
  levelValue: level.value,
  levelName: level.name,
  message: message,
  error: error,
  stackTrace: stackTrace,
);

/// Pumps the app-log screen and hands back the scope's [WidgetRef], so a test can reach the
/// log storage the screen itself reads from.
Future<WidgetRef> pumpAppLogScreen(
  WidgetTester tester, {
  LogCategory initialCategory = LogCategory.all,
}) async {
  late WidgetRef capturedRef;
  final app = await makeTestProviderScopeApp(
    tester,
    home: Consumer(
      builder: (context, ref, _) {
        capturedRef = ref;
        return AppLogSettingsScreen(initialCategory: initialCategory);
      },
    ),
  );

  await tester.pumpWidget(app);
  await tester.pumpAndSettle();

  return capturedRef;
}

/// Stores [entries] in the log table and reloads the screen so that they are on it.
Future<void> showLogs(WidgetTester tester, WidgetRef ref, List<AppLogEntry> entries) async {
  final storage = await ref.read(appLogStorageProvider.future);
  // The default level is WARNING and the fixtures are INFO, so the level has to come down
  // first. The screen reloads on the level change, which is why the empty state is still
  // the one on screen when the entries are stored.
  await ref.read(logPreferencesProvider.notifier).setLogLevel(Level.ALL);
  await tester.pumpAndSettle();

  for (final entry in entries) {
    await storage.save(entry);
  }

  await tester.tap(find.text('Refresh'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
}

/// Records every text the app writes to the clipboard.
List<String> captureClipboard() {
  final copied = <String>[];
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (methodCall) async {
    if (methodCall.method == 'Clipboard.setData') {
      final arguments = methodCall.arguments as Map<Object?, Object?>;
      copied.add(arguments['text']! as String);
    }
    return null;
  });
  addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));
  return copied;
}

/// Whether the category pill carrying [label] is the selected one.
bool pillSelected(WidgetTester tester, String label) =>
    tester.widget<SrsPillButton>(find.widgetWithText(SrsPillButton, label)).selected;

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
      // A fixed stamp: the log query filters on id, level and text, never on the time, so
      // the wall clock has no place in this fixture.
      final now = DateTime.utc(2026, 1, 1);

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

  // No invariant in SPEC.md names the app-log settings screen, so none of the tests below
  // cites one: each pins the screen's own contract — what it offers, what it filters on,
  // what it copies, and what it prunes. The behaviour each one names is spelled out in the
  // test's own comment.

  testWidgets('AppLogSettingsScreen offers the export action only when there are logs', (
    tester,
  ) async {
    // The contract: the header offers "Export logs" once there is something to export, and
    // offers nothing at all when the log is empty. An export of nothing is a dead control.
    final ref = await pumpAppLogScreen(tester);

    expect(find.byIcon(Icons.share), findsNothing);

    await showLogs(tester, ref, [_entry(message: 'exportable entry')]);

    expect(find.byIcon(Icons.share), findsOneWidget);
  });

  testWidgets('AppLogSettingsScreen exports the entries with their error and stack trace', (
    tester,
  ) async {
    // The contract: the exported text is the whole entry — time, subsystem, level, message,
    // error and stack trace — so that a log file pasted somewhere else still carries the
    // failure that caused it. A half-exported entry is the defect this pins.
    final copied = captureClipboard();
    final ref = await pumpAppLogScreen(tester);
    await showLogs(tester, ref, [
      _entry(
        message: 'Malformed PGN header in chapter 2',
        loggerName: 'StudyImporter',
        level: Level.WARNING,
        error: 'FormatException: Missing right bracket',
        stackTrace: '#0 pgn_parser.dart:45',
      ),
      _entry(message: 'Saved import result in 18ms'),
    ]);

    await tester.tap(find.byIcon(Icons.share));
    await tester.pumpAndSettle();

    expect(copied, hasLength(1));
    final exported = copied.single;
    expect(exported, contains('[StudyImporter] [WARNING] Malformed PGN header in chapter 2'));
    expect(exported, contains('Error: FormatException: Missing right bracket'));
    expect(exported, contains('Stack trace:\n#0 pgn_parser.dart:45'));
    expect(exported, contains('Saved import result in 18ms'));
    // Entries are separated by a rule, so one file is not one long line.
    expect(exported, contains('\n\n---\n\n'));
  });

  testWidgets('AppLogSettingsScreen offers the copy-error action only when there is one', (
    tester,
  ) async {
    // The contract: "Copy error" copies the error and the stack trace, so it is offered only
    // when the entry carries at least one of them. An entry with neither has nothing to copy.
    final ref = await pumpAppLogScreen(tester);
    await showLogs(tester, ref, [
      _entry(message: 'plain entry'),
      _entry(message: 'entry with error', error: 'Boom'),
    ]);

    await tester.tap(find.text('plain entry'));
    await tester.pumpAndSettle();

    expect(find.text('Copy message'), findsOneWidget);
    expect(find.text('Copy error'), findsNothing);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    // An error without a stack trace is still an error to copy.
    await tester.tap(find.text('entry with error'));
    await tester.pumpAndSettle();

    expect(find.text('Copy error'), findsOneWidget);
  });

  testWidgets(
    'AppLogSettingsScreen tells a severe entry apart from a warning and an ordinary one',
    (tester) async {
      // The contract: severity is readable at a glance — the icon on the row says severe,
      // warning or ordinary, and the three are never confused with one another.
      final ref = await pumpAppLogScreen(tester);
      await showLogs(tester, ref, [
        _entry(message: 'severe entry', level: Level.SEVERE),
        _entry(message: 'warning entry', level: Level.WARNING),
        _entry(message: 'ordinary entry'),
      ]);

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_outlined), findsOneWidget);
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
    },
  );

  testWidgets('AppLogSettingsScreen colours the severity badge in the details dialog', (
    tester,
  ) async {
    // The contract: the dialog's badge keeps the severity colours of the row, so a severe
    // entry is red in both places and a warning is orange in both. The palette has no
    // warning or error hue of its own, so this badge is the screen's only red.
    final ref = await pumpAppLogScreen(tester);
    await showLogs(tester, ref, [
      _entry(message: 'severe entry', level: Level.SEVERE),
      _entry(message: 'warning entry', level: Level.WARNING),
    ]);

    await tester.tap(find.text('severe entry'));
    await tester.pumpAndSettle();

    expect(tester.widget<Text>(find.text('SEVERE')).style?.color, Colors.red);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('warning entry'));
    await tester.pumpAndSettle();

    expect(tester.widget<Text>(find.text('WARNING')).style?.color, Colors.orange);
  });

  testWidgets('AppLogSettingsScreen colours the subsystem badge per logger family', (tester) async {
    // The contract: the badge says which subsystem logged the entry, and each family keeps
    // its own colour. A badge that paints every family the same colour says nothing.
    final ref = await pumpAppLogScreen(tester);
    await showLogs(tester, ref, [
      _entry(message: 'review entry', loggerName: 'ReviewEngine'),
      _entry(message: 'repository entry', loggerName: 'StudyRepository'),
      _entry(message: 'import entry', loggerName: 'StudyImporter'),
      _entry(message: 'network entry', loggerName: 'HttpClient'),
    ]);

    Color badgeOf(String loggerName) => tester.widget<Text>(find.text(loggerName)).style!.color!;

    expect(badgeOf('ReviewEngine'), Colors.blue);
    expect(badgeOf('StudyRepository'), Colors.purple);
    expect(badgeOf('StudyImporter'), Colors.teal);
    expect(badgeOf('HttpClient'), Colors.orange);
  });

  testWidgets('AppLogSettingsScreen colours the engine and unknown subsystem badges', (
    tester,
  ) async {
    // The contract, continued for the families the first badge test has no room for: the
    // engine family keeps its own colour, and a subsystem the screen knows nothing about
    // falls back to the neutral one rather than borrowing another family's.
    final ref = await pumpAppLogScreen(tester);
    await showLogs(tester, ref, [
      _entry(message: 'engine entry', loggerName: 'EngineOpponent'),
      _entry(message: 'stockfish entry', loggerName: 'StockfishTransport'),
      _entry(message: 'other entry', loggerName: 'SomethingElse'),
    ]);

    Color badgeOf(String loggerName) => tester.widget<Text>(find.text(loggerName)).style!.color!;

    expect(badgeOf('EngineOpponent'), Colors.indigo);
    expect(badgeOf('StockfishTransport'), Colors.indigo);
    expect(badgeOf('SomethingElse'), Colors.blueGrey);
  });

  testWidgets('AppLogSettingsScreen marks the chosen category as the selected one', (tester) async {
    // The contract: exactly one category is selected, and it is the one the user chose.
    // The screen opens on "All", and tapping a chip moves the selection to it.
    await pumpAppLogScreen(tester);

    expect(pillSelected(tester, 'All'), isTrue);
    expect(pillSelected(tester, 'Review'), isFalse);

    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();

    expect(pillSelected(tester, 'Review'), isTrue);
    expect(pillSelected(tester, 'All'), isFalse);
  });

  testWidgets(
    'AppLogSettingsScreen filters a category by the subsystem that logged, not by its label',
    (tester) async {
      // The contract: a category filters on the name of the logger it stands for, not on the
      // words on the chip. "Repo / DB" stands for the StudyRepository logger, so the chip's
      // own wording must never become the filter.
      final ref = await pumpAppLogScreen(tester);
      await showLogs(tester, ref, [
        _entry(message: 'repository entry', loggerName: 'StudyRepository'),
        _entry(message: 'import entry', loggerName: 'StudyImporter'),
      ]);

      await tester.tap(find.text('Repo / DB'));
      await tester.pumpAndSettle();

      expect(find.text('repository entry'), findsOneWidget);
      expect(find.text('import entry'), findsNothing);
    },
  );

  testWidgets('AppLogSettingsScreen keeps the engine own logs under the Engine category', (
    tester,
  ) async {
    // The contract: the "Engine" chip selects the engine's own loggers, so the entries they
    // logged stay on the list when the chip is tapped. A category that hides the subsystem it
    // names is the defect this pins: the chip used to filter on "fish", which matches the
    // stockfish transport and none of the engine's own loggers.
    final ref = await pumpAppLogScreen(tester);
    await showLogs(tester, ref, [
      _entry(message: 'engine own log line', loggerName: 'EngineOpponent'),
      _entry(message: 'engine evaluator log line', loggerName: 'PositionEvaluator'),
      _entry(message: 'network log line', loggerName: 'HttpClient'),
      _entry(message: 'review log line', loggerName: 'ReviewEngine'),
    ]);

    await tester.tap(find.text('Engine'));
    await tester.pumpAndSettle();

    expect(find.text('engine own log line'), findsOneWidget);
    expect(find.text('engine evaluator log line'), findsOneWidget);
    // The network loggers have a chip of their own, and the review session's logger is the
    // review's: neither of them is the engine's, so neither belongs under "Engine".
    expect(find.text('network log line'), findsNothing);
    expect(find.text('review log line'), findsNothing);
  });

  testWidgets('AppLogSettingsScreen says so when a search matched nothing', (tester) async {
    // The contract: "no logs" and "no logs match this" are different sentences, and the
    // search is named in the second one so the reader knows what was looked for.
    final ref = await pumpAppLogScreen(tester);
    await showLogs(tester, ref, [_entry(message: 'some entry')]);

    await tester.enterText(find.byType(TextField), 'zzz-no-such-log');
    await tester.pumpAndSettle();

    expect(find.text('Nothing matches \u201czzz-no-such-log\u201d.'), findsOneWidget);
    expect(find.text('No logs to show'), findsNothing);
  });

  testWidgets('AppLogSettingsScreen loads the next page when the list is scrolled to the end', (
    tester,
  ) async {
    // The contract: the log is longer than one page, and scrolling to the end asks for the
    // next one instead of leaving the reader at a wall of the same twenty entries.
    final ref = await pumpAppLogScreen(tester);
    await showLogs(tester, ref, [for (var i = 0; i < 25; i++) _entry(message: 'entry $i')]);

    // The first page holds twenty entries, newest first; the five older ones are not on the
    // list yet.
    expect(find.text('entry 24'), findsOneWidget);
    expect(find.text('entry 0'), findsNothing);

    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await tester.pumpAndSettle();

    // The first drag reaches the end of the first page, which is where the next page is
    // asked for; the list is longer afterwards, so it takes a second drag to reach the end
    // of the second one.
    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await tester.pumpAndSettle();

    expect(find.text('entry 0'), findsOneWidget);
  });

  testWidgets('AppLogSettingsScreen changes the log level from the level pill', (tester) async {
    // The contract: the pill carries the level in force, choosing another one applies it,
    // and the list then holds only the entries at or above that level.
    final ref = await pumpAppLogScreen(tester);
    await showLogs(tester, ref, [
      _entry(message: 'ordinary entry'),
      _entry(message: 'severe entry', level: Level.SEVERE),
    ]);

    expect(find.text('ALL'), findsOneWidget);

    await tester.tap(find.text('ALL'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('SEVERE'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SEVERE'));
    await tester.pumpAndSettle();

    expect(find.text('SEVERE'), findsOneWidget);
    expect(find.text('severe entry'), findsOneWidget);
    expect(find.text('ordinary entry'), findsNothing);
  });

  testWidgets('AppLogSettingsScreen opens on the category it was given', (tester) async {
    // The contract: the screen opens on the category it was handed, not always on "All".
    await pumpAppLogScreen(tester, initialCategory: LogCategory.network);

    expect(pillSelected(tester, 'Network'), isTrue);
    expect(pillSelected(tester, 'All'), isFalse);
  });
}
