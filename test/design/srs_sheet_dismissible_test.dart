// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/view/review/library_sheet.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../binding.dart';
import '../test_provider_scope.dart';

/// Sheets must follow the finger on swipe-down, not vanish in one frame.
///
/// Owner report 2026-09-29: swiping a hanging menu down did nothing until
/// release, then it disappeared instantly. The custom dialog sheets
/// (Library, scope, study actions, import) share [SrsSheetDismissible] for
/// finger tracking; these pin the mechanism and one sheet's wiring.
void main() {
  setUpAll(TestLichessBinding.ensureInitialized);

  Future<void> openSheet(WidgetTester tester) async {
    await tester.pumpWidget(
      await makeTestProviderScopeApp(
        tester,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SrsSheetDismissible(child: Text('sheet')),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('sheet'), findsOneWidget);
  }

  testWidgets('a downward fling tracks and dismisses the sheet', (tester) async {
    await openSheet(tester);

    await tester.fling(find.text('sheet'), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();

    expect(find.text('sheet'), findsNothing);
  });

  testWidgets('a short drag snaps back instead of dismissing', (tester) async {
    await openSheet(tester);

    await tester.drag(find.text('sheet'), const Offset(0, 30));
    await tester.pumpAndSettle();

    expect(find.text('sheet'), findsOneWidget);
  });

  testWidgets('the sheet follows the finger mid-drag', (tester) async {
    // The actual complaint: the old handler did nothing until release, then
    // the sheet vanished in one frame. Mid-drag, the sheet must already have
    // moved with the finger.
    await openSheet(tester);

    final rest = tester.getCenter(find.text('sheet')).dy;
    final gesture = await tester.startGesture(tester.getCenter(find.text('sheet')));
    await gesture.moveBy(const Offset(0, 100));
    await tester.pump();

    expect(tester.getCenter(find.text('sheet')).dy, greaterThan(rest + 50));

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('the Library sheet swipes down gracefully', (tester) async {
    await tester.pumpWidget(
      await makeTestProviderScopeApp(
        tester,
        home: Builder(
          builder: (context) =>
              TextButton(onPressed: () => SrsLibrarySheet.show(context), child: const Text('open')),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(SrsLibrarySheet), findsOneWidget);

    await tester.fling(find.text('Analysis'), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();

    expect(find.byType(SrsLibrarySheet), findsNothing);
  });
}
