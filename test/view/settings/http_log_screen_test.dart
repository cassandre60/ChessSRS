// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/model/log/http_log_paginator.dart';
import 'package:chess_srs/src/model/log/http_log_storage.dart';
import 'package:chess_srs/src/view/settings/http_log_screen.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../binding.dart';
import '../../test_helpers.dart' show kTestSurfaceSize;
import '../../test_provider_scope.dart';

/// A fixed local stamp, so the time of day in a formatted date does not depend
/// on the machine's timezone.
final _at = DateTime(2026, 1, 1, 13, 45, 30);

/// One stored log row.
HttpLogEntry _entry({
  required String id,
  required String url,
  String method = 'GET',
  DateTime? at,
  int? code,
  Duration? took,
  String? error,
}) {
  final stamp = at ?? _at;
  return HttpLogEntry(
    httpLogId: id,
    requestMethod: method,
    requestUrl: Uri.parse(url),
    requestDateTime: stamp,
    responseCode: code,
    responseDateTime: took == null ? null : stamp.add(took),
    errorMessage: error,
  );
}

/// Builds the screen and hands back the [WidgetRef] the test can seed the log
/// storage through, the way the app itself writes the rows.
Future<WidgetRef> _pumpScreen(WidgetTester tester, {Size? surfaceSize}) async {
  late WidgetRef capturedRef;
  final app = await makeTestProviderScopeApp(
    tester,
    home: Consumer(
      builder: (context, ref, _) {
        capturedRef = ref;
        return const HttpLogScreen();
      },
    ),
    surfaceSize: surfaceSize ?? kTestSurfaceSize,
  );

  await tester.pumpWidget(app);
  await tester.pumpAndSettle();

  return capturedRef;
}

/// Stores [entries] and reloads the list the screen shows.
Future<void> _saveLogs(WidgetTester tester, WidgetRef ref, List<HttpLogEntry> entries) async {
  final storage = await ref.read(httpLogStorageProvider.future);
  for (final entry in entries) {
    await storage.save(entry);
  }

  await tester.tap(find.text('Tap to refresh'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
}

/// Captures what the screen puts on the clipboard.
List<String> _captureClipboard() {
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

/// Opens the details dialog of the row whose endpoint is [endpoint] and reads
/// what the dialog says about the request.
///
/// The status is the only text the dialog paints at 16pt and the method badge
/// the only one at 13pt, which is how the two are told apart without naming
/// the status the screen is supposed to show.
Future<({String status, Color? statusColour, Color? badgeColour, Color? badgeBackground})>
_openDetails(WidgetTester tester, String endpoint) async {
  await tester.tap(find.text(endpoint));
  await tester.pumpAndSettle();

  final dialog = find.byType(SrsDialog);
  final statusFinder = find.descendant(
    of: dialog,
    matching: find.byWidgetPredicate((widget) => widget is Text && widget.style?.fontSize == 16),
  );
  final badgeFinder = find.descendant(
    of: dialog,
    matching: find.byWidgetPredicate((widget) => widget is Text && widget.style?.fontSize == 13),
  );
  final status = tester.widget<Text>(statusFinder);
  final badge = tester.widget<Text>(badgeFinder);
  // The badge sits in the box that carries its fill.
  final badgeBox = tester.widget<Container>(
    find.ancestor(of: badgeFinder, matching: find.byType(Container)).first,
  );

  final result = (
    status: status.data ?? '',
    statusColour: status.style?.color,
    badgeColour: badge.style?.color,
    badgeBackground: (badgeBox.decoration! as BoxDecoration).color,
  );

  await tester.tap(find.text('Close'));
  await tester.pumpAndSettle();

  return result;
}

void main() {
  setUpAll(() {
    TestLichessBinding.ensureInitialized();
  });

  setUp(() async {
    await TestLichessBinding.instance.sharedPreferences.clear();
  });

  testWidgets('HttpLogScreen renders empty state when no logs exist', (tester) async {
    final app = await makeTestProviderScopeApp(tester, home: const HttpLogScreen());

    await tester.pumpWidget(app);
    await tester.pumpAndSettle();

    expect(find.text('HTTP logs'), findsOneWidget);
    expect(find.text('No logs to show'), findsOneWidget);
    expect(find.text('Tap to refresh'), findsOneWidget);
  });

  testWidgets('HttpLogScreen renders entries and opens details dialog on tap', (tester) async {
    late WidgetRef capturedRef;
    final app = await makeTestProviderScopeApp(
      tester,
      home: Consumer(
        builder: (context, ref, _) {
          capturedRef = ref;
          return const HttpLogScreen();
        },
      ),
    );

    await tester.pumpWidget(app);
    await tester.pumpAndSettle();

    final storage = await capturedRef.read(httpLogStorageProvider.future);
    // A fixed stamp: the log query filters on id and text, never on the time, so the wall
    // clock has no place in this fixture.
    final now = DateTime.utc(2026, 1, 1);

    await storage.save(
      HttpLogEntry(
        httpLogId: 'test-1',
        requestMethod: 'GET',
        requestUrl: Uri.parse('https://lichess.org/api/study/test1234.pgn'),
        requestDateTime: now,
        responseCode: 200,
        responseDateTime: now.add(const Duration(milliseconds: 145)),
      ),
    );

    await storage.save(
      HttpLogEntry(
        httpLogId: 'test-2',
        requestMethod: 'POST',
        requestUrl: Uri.parse('https://lichess.org/api/study/error999.pgn'),
        requestDateTime: now,
        responseCode: 404,
        responseDateTime: now.add(const Duration(milliseconds: 320)),
        errorMessage: 'Study not found on Lichess',
      ),
    );

    // Pull to refresh or invalidate paginator to load saved logs
    await tester.tap(find.text('Tap to refresh'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    // Verify method badges and endpoints
    expect(find.text('GET'), findsOneWidget);
    expect(find.text('POST'), findsOneWidget);
    expect(find.text('200'), findsOneWidget);
    expect(find.text('404'), findsOneWidget);
    expect(find.text('/api/study/test1234.pgn'), findsOneWidget);
    expect(find.text('/api/study/error999.pgn'), findsOneWidget);
    expect(find.text('Study not found on Lichess'), findsOneWidget);

    // Tap the failed entry to inspect details modal
    await tester.tap(find.text('/api/study/error999.pgn'));
    await tester.pumpAndSettle();

    // Verify detail dialog is presented
    expect(find.text('Request URL'), findsOneWidget);
    expect(find.text('https://lichess.org/api/study/error999.pgn'), findsOneWidget);
    expect(find.text('Error Details'), findsOneWidget);
    expect(find.text('Copy URL'), findsOneWidget);
    expect(find.text('Copy all'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);

    // Close the dialog
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(find.text('Request URL'), findsNothing);

    // Search filtering
    await tester.enterText(find.byType(TextField), 'error999');
    await tester.pumpAndSettle();

    expect(find.text('/api/study/error999.pgn'), findsOneWidget);
    expect(find.text('/api/study/test1234.pgn'), findsNothing);

    // Clear search
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.text('/api/study/test1234.pgn'), findsOneWidget);

    // Export button is visible when logs exist
    expect(find.byIcon(Icons.share), findsOneWidget);

    // Delete all logs
    await tester.tap(find.byIcon(Icons.delete_sweep));
    await tester.pumpAndSettle();

    // Confirm deletion
    expect(find.text('Delete all logs'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.text('No logs to show'), findsOneWidget);
  });

  testWidgets('shows the whole URL of a request to a host that is not Lichess', (tester) async {
    final ref = await _pumpScreen(tester);

    await _saveLogs(tester, ref, [
      _entry(id: 'foreign', url: 'https://example.com/api/study/abc1234.pgn'),
    ]);

    expect(find.text('https://example.com/api/study/abc1234.pgn'), findsOneWidget);
  });

  // SPEC INV-006. The redaction itself is proven where the row is written
  // (test/network/http_redaction_test.dart); what this pins is the screen's
  // half of it: the row it shows is the stored, redacted URL, with the
  // placeholder and the diagnostic parameters still readable, so the log can
  // be told apart without the secret coming back.
  testWidgets(
    'shows the path and the query of a Lichess request, with the redacted parameters in place',
    (tester) async {
      final ref = await _pumpScreen(tester);

      await _saveLogs(tester, ref, [
        _entry(
          id: 'redacted',
          url: 'https://lichess.org/auth/mobile-code/email?email=***&username=***',
        ),
      ]);

      final endpoint = tester.widget<Text>(find.textContaining('/auth/mobile-code/email')).data!;

      // The redacted parameters are still there, so the request is identifiable.
      expect(endpoint, contains('email=***'));
      expect(endpoint, contains('username=***'));
      // The host is dropped for a first-party request, the secret never appears.
      expect(endpoint, isNot(contains('lichess.org')));
    },
  );

  testWidgets('copies the whole URL, not the shortened endpoint, when a row is long-pressed', (
    tester,
  ) async {
    final copied = _captureClipboard();
    final ref = await _pumpScreen(tester);

    await _saveLogs(tester, ref, [
      _entry(id: 'copy', url: 'https://lichess.org/api/study/abc1234.pgn'),
    ]);

    await tester.longPress(find.text('/api/study/abc1234.pgn'));
    await tester.pumpAndSettle();

    expect(copied, contains('https://lichess.org/api/study/abc1234.pgn'));
  });

  testWidgets('copies the whole URL and the whole entry from the details dialog', (tester) async {
    final copied = _captureClipboard();
    final ref = await _pumpScreen(tester);

    await _saveLogs(tester, ref, [
      _entry(
        id: 'copy',
        url: 'https://lichess.org/api/study/abc1234.pgn',
        code: 200,
        took: const Duration(milliseconds: 145),
      ),
    ]);

    await tester.tap(find.text('/api/study/abc1234.pgn'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy URL'));
    await tester.pumpAndSettle();

    expect(copied, contains('https://lichess.org/api/study/abc1234.pgn'));

    await tester.tap(find.text('/api/study/abc1234.pgn'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy all'));
    await tester.pumpAndSettle();

    expect(copied.last, contains('https://lichess.org/api/study/abc1234.pgn'));
    expect(copied.last, contains('Status: 200'));
  });

  testWidgets('exports every entry with its status, its duration and its error', (tester) async {
    final copied = _captureClipboard();
    final ref = await _pumpScreen(tester);

    await _saveLogs(tester, ref, [
      _entry(
        id: 'ok',
        url: 'https://lichess.org/api/study/ok.pgn',
        code: 200,
        took: const Duration(milliseconds: 145),
      ),
      _entry(
        id: 'failed',
        url: 'https://lichess.org/api/study/failed.pgn',
        code: 404,
        took: const Duration(milliseconds: 320),
        error: 'Study not found on Lichess',
      ),
      _entry(id: 'pending', url: 'https://lichess.org/api/study/pending.pgn'),
    ]);

    await tester.tap(find.byIcon(Icons.share));
    await tester.pumpAndSettle();

    final exported = copied.single;

    expect(exported, contains('Status: 200'));
    expect(exported, contains('Duration: 145ms'));
    expect(exported, contains('Status: 404'));
    expect(exported, contains('Error: Study not found on Lichess'));
    expect(exported, contains('Status: No response'));
    expect(exported, contains('13:45:30'));
    // The entries are separated, so one request does not run into the next.
    expect(exported, contains('---'));
  });

  testWidgets(
    'shows a duration of exactly one second in seconds and a shorter one in milliseconds',
    (tester) async {
      final ref = await _pumpScreen(tester);

      await _saveLogs(tester, ref, [
        _entry(
          id: 'one-second',
          url: 'https://lichess.org/api/study/second.pgn',
          code: 200,
          took: const Duration(seconds: 1),
        ),
        _entry(
          id: 'sub-second',
          url: 'https://lichess.org/api/study/sub.pgn',
          code: 200,
          took: const Duration(milliseconds: 999),
        ),
      ]);

      expect(find.text('1.0s'), findsOneWidget);
      expect(find.text('999ms'), findsOneWidget);
      expect(find.text('1000ms'), findsNothing);
    },
  );

  testWidgets('marks a failed request as an error and an ordinary one as ordinary', (tester) async {
    final ref = await _pumpScreen(tester);

    await _saveLogs(tester, ref, [
      _entry(
        id: 'ok',
        url: 'https://lichess.org/api/study/ok.pgn',
        code: 200,
        took: const Duration(milliseconds: 145),
      ),
      _entry(
        id: 'bad-request',
        url: 'https://lichess.org/api/study/bad-request.pgn',
        code: 400,
        took: const Duration(milliseconds: 100),
      ),
      _entry(
        id: 'pending-error',
        url: 'https://lichess.org/api/study/pending-error.pgn',
        error: 'Connection timed out',
      ),
      _entry(id: 'pending-ok', url: 'https://lichess.org/api/study/pending-ok.pgn'),
    ]);

    // Only the rows without a response carry an icon; a row that has one shows
    // its status code instead.
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.byIcon(Icons.pending_outlined), findsOneWidget);

    // The error colour is the one the error icon is painted in, so the
    // assertion does not have to name a colour.
    final severe = tester.widget<Icon>(find.byIcon(Icons.error_outline)).color;
    final failedColour = tester.widget<Text>(find.text('/api/study/bad-request.pgn')).style?.color;
    final okColour = tester.widget<Text>(find.text('/api/study/ok.pgn')).style?.color;

    expect(failedColour, severe);
    expect(okColour, isNot(severe));
  });

  testWidgets('the details dialog shows the request status and marks a failure in red', (
    tester,
  ) async {
    final ref = await _pumpScreen(tester);

    await _saveLogs(tester, ref, [
      _entry(
        id: 'ok',
        url: 'https://lichess.org/api/study/ok.pgn',
        code: 200,
        took: const Duration(milliseconds: 145),
      ),
      _entry(
        id: 'failed',
        url: 'https://lichess.org/api/study/failed.pgn',
        code: 404,
        took: const Duration(milliseconds: 320),
        error: 'Study not found on Lichess',
      ),
      _entry(
        id: 'bad-request',
        url: 'https://lichess.org/api/study/bad-request.pgn',
        code: 400,
        took: const Duration(milliseconds: 100),
      ),
      _entry(
        id: 'failed-code',
        url: 'https://lichess.org/api/study/failed-code.pgn',
        code: 0,
        error: 'Connection reset by peer',
      ),
      _entry(id: 'pending', url: 'https://lichess.org/api/study/pending.pgn'),
    ]);

    final ok = await _openDetails(tester, '/api/study/ok.pgn');
    expect(ok.status, '200');
    expect(ok.statusColour, isNull);
    expect(ok.badgeColour!.g, greaterThan(ok.badgeColour!.r));
    expect(ok.badgeBackground!.g, greaterThan(ok.badgeBackground!.r));

    final failed = await _openDetails(tester, '/api/study/failed.pgn');
    expect(failed.status, '404');
    expect(failed.statusColour!.r, greaterThan(failed.statusColour!.g));
    expect(failed.badgeColour!.r, greaterThan(failed.badgeColour!.g));
    expect(failed.badgeBackground!.r, greaterThan(failed.badgeBackground!.g));

    // A 4xx is a failure on its own, without an error message beside it.
    final badRequest = await _openDetails(tester, '/api/study/bad-request.pgn');
    expect(badRequest.status, '400');
    expect(badRequest.statusColour!.r, greaterThan(badRequest.statusColour!.g));

    // A request that never got a status code is reported as failed, not as 0.
    final failedCode = await _openDetails(tester, '/api/study/failed-code.pgn');
    expect(failedCode.status, 'Failed');

    final pending = await _openDetails(tester, '/api/study/pending.pgn');
    expect(pending.status, 'Pending');
  });

  testWidgets(
    'renders a response that carries no timestamp, and opens its details without a duration',
    (tester) async {
      final ref = await _pumpScreen(tester);

      await _saveLogs(tester, ref, [
        _entry(id: 'no-stamp', url: 'https://lichess.org/api/study/no-stamp.pgn', code: 200),
      ]);

      expect(find.text('200'), findsOneWidget);
      expect(find.text('/api/study/no-stamp.pgn'), findsOneWidget);

      await tester.tap(find.text('/api/study/no-stamp.pgn'));
      await tester.pumpAndSettle();

      expect(find.text('Request URL'), findsOneWidget);
      expect(find.text('Duration: '), findsNothing);
    },
  );

  testWidgets('loads the next page when the list is scrolled to within 300px of its end', (
    tester,
  ) async {
    // A shorter surface, so the 300px threshold sits inside the list.
    final ref = await _pumpScreen(tester, surfaceSize: const Size(390, 500));

    final storage = await ref.read(httpLogStorageProvider.future);
    for (var i = 0; i < 25; i++) {
      await storage.save(
        _entry(
          id: 'entry-$i',
          url: 'https://lichess.org/api/study/entry-$i.pgn',
          code: 200,
          took: const Duration(milliseconds: 100),
        ),
      );
    }

    await tester.tap(find.text('Tap to refresh'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(ref.read(httpLogPaginatorProvider(null)).value?.logs.length, 20);

    final position = tester
        .state<ScrollableState>(
          find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)),
        )
        .position;
    // The threshold is 300px above the end, so the list has to be long enough
    // for the threshold to sit inside it.
    expect(position.maxScrollExtent, greaterThan(300));

    position.jumpTo(position.maxScrollExtent - 300);
    await tester.pumpAndSettle();

    expect(ref.read(httpLogPaginatorProvider(null)).value?.logs.length, 25);
  });

  testWidgets('shows the time of the request in the row', (tester) async {
    final ref = await _pumpScreen(tester);

    await _saveLogs(tester, ref, [
      _entry(
        id: 'timed',
        url: 'https://lichess.org/api/study/timed.pgn',
        code: 200,
        took: const Duration(milliseconds: 145),
      ),
    ]);

    expect(find.textContaining('13:45:30'), findsOneWidget);
  });
}
