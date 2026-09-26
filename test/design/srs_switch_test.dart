// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:ui' show Tristate;

import 'package:chess_srs/src/design/design.dart';
import 'package:flutter_test/flutter_test.dart';

import '../binding.dart';
import '../test_provider_scope.dart';

void main() {
  setUpAll(TestLichessBinding.ensureInitialized);

  group('SrsSwitch (demo .tog)', () {
    testWidgets('tapping toggles the value and semantics', (tester) async {
      var value = false;
      Future<void> pumpSwitch() async {
        final app = await makeTestProviderScopeApp(
          tester,
          home: SrsSwitch(value: value, semanticLabel: 'Engine', onChanged: (v) => value = v),
        );
        await tester.pumpWidget(app);
        await tester.pumpAndSettle();
      }

      await pumpSwitch();
      expect(find.bySemanticsLabel('Engine'), findsOneWidget);
      expect(
        tester.getSemantics(find.byType(SrsSwitch)).flagsCollection.isToggled == Tristate.isTrue,
        isFalse,
      );

      await tester.tap(find.byType(SrsSwitch));
      expect(value, isTrue);

      await pumpSwitch();
      expect(
        tester.getSemantics(find.byType(SrsSwitch)).flagsCollection.isToggled == Tristate.isTrue,
        isTrue,
      );
    });

    testWidgets('null onChanged disables the switch', (tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: const SrsSwitch(value: true, semanticLabel: 'Engine', onChanged: null),
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      final node = tester.getSemantics(find.byType(SrsSwitch));
      expect(node.flagsCollection.isEnabled == Tristate.isFalse, isTrue);
      expect(node.flagsCollection.isToggled == Tristate.isTrue, isTrue);
    });
  });
}
