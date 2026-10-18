// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:ui' show Tristate;

import 'package:chess_srs/src/design/design.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../binding.dart';
import '../test_provider_scope.dart';

void main() {
  setUpAll(TestLichessBinding.ensureInitialized);

  group('SrsPageHead (demo .set-head)', () {
    testWidgets('renders destination label, fires back, shows trailing', (tester) async {
      var backed = false;
      final app = await makeTestProviderScopeApp(
        tester,
        home: SrsPageHead(
          label: 'Review',
          onBack: () => backed = true,
          trailing: const Text('Trailing'),
        ),
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      expect(find.text('Review'), findsOneWidget);
      expect(find.text('Trailing'), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);

      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();
      expect(backed, isTrue);
    });

    testWidgets('hides trailing when absent and disables without onBack', (tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: const SrsPageHead(label: 'Library', onBack: null),
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      expect(find.text('Library'), findsOneWidget);
      expect(find.byType(SrsPageHead), findsOneWidget);

      // With no trailing widget the head's Row holds only the back control: no Spacer was added
      // to reserve the slot. A head that always laid out the trailing row would show up here.
      expect(
        find.descendant(of: find.byType(SrsPageHead), matching: find.byType(Spacer)),
        findsNothing,
      );

      // SPEC INV-062. The back control keeps its 44px-class touch target even when disabled.
      expect(
        tester.getSize(find.bySemanticsLabel('Back to Library')).height,
        greaterThanOrEqualTo(SrsLayout.minTouchTarget),
      );

      // A null onBack disables the control rather than leaving it silently tappable: the
      // pressable announces itself disabled and its GestureDetector is built without an onTap.
      final back = tester.getSemantics(find.bySemanticsLabel('Back to Library'));
      expect(back.flagsCollection.isButton, isTrue);
      expect(back.flagsCollection.isEnabled == Tristate.isFalse, isTrue);

      // Tapping the disabled control is inert: nothing fires and nothing throws.
      await tester.tap(find.bySemanticsLabel('Back to Library'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
