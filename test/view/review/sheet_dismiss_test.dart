// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/view/review/library_sheet.dart';
import 'package:chess_srs/src/view/review/repertoire_import_dialog.dart';
import 'package:chess_srs/src/view/review/review_scope_drawer.dart';
import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../binding.dart';
import '../../test_provider_scope.dart';

void main() {
  setUpAll(() {
    TestLichessBinding.ensureInitialized();
  });

  testWidgets('tapping outside ReviewScopeDrawer dismisses it', (tester) async {
    final app = await makeTestProviderScopeApp(
      tester,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => ReviewScopeDrawer.show(context, Side.white),
              child: const Text('Open Scope'),
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(app);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open Scope'));
    await tester.pumpAndSettle();

    expect(find.byType(ReviewScopeDrawer), findsOneWidget);

    // Tap at top right outside the bottom sheet/drawer
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(find.byType(ReviewScopeDrawer), findsNothing);
  });

  testWidgets('tapping outside SrsLibrarySheet dismisses it', (tester) async {
    final app = await makeTestProviderScopeApp(
      tester,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => SrsLibrarySheet.show(context),
              child: const Text('Open Library'),
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(app);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open Library'));
    await tester.pumpAndSettle();

    expect(find.byType(SrsLibrarySheet), findsOneWidget);

    // Tap at top left outside the sheet
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(find.byType(SrsLibrarySheet), findsNothing);
  });

  testWidgets('tapping outside RepertoireImportDialog dismisses it', (tester) async {
    final app = await makeTestProviderScopeApp(
      tester,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => RepertoireImportDialog.show(context),
              child: const Text('Open Import'),
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(app);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open Import'));
    await tester.pumpAndSettle();

    expect(find.byType(RepertoireImportDialog), findsOneWidget);

    // Tap at top left outside the sheet
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(find.byType(RepertoireImportDialog), findsNothing);
  });
}
