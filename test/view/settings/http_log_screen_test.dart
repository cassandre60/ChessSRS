// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/model/log/http_log_storage.dart';
import 'package:chess_srs/src/view/settings/http_log_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../binding.dart';
import '../../test_provider_scope.dart';

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
    final now = DateTime.now();

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
}
