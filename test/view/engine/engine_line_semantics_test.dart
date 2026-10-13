// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/model/account/account_preferences.dart';
import 'package:chess_srs/src/model/common/eval.dart';
import 'package:chess_srs/src/view/engine/engine_lines.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show Material;

import '../../test_provider_scope.dart';

// A11Y-FIX-30: an engine line is tappable chrome — without a role and a label a screen
// reader finds bare eval/PV text with no announcement of what it is.
void main() {
  Future<void> pumpLine(WidgetTester tester, PvData pv) async {
    final app = await makeTestProviderScopeApp(
      tester,
      home: Material(child: Engineline(null, Chess.initial, pv)),
      overrides: {
        pieceNotationProvider: pieceNotationProvider.overrideWith((ref) => PieceNotation.letter),
      },
    );
    await tester.pumpWidget(app);
    await tester.pump();
  }

  testWidgets('engine line announces as a button with eval and PV', (tester) async {
    final handle = tester.ensureSemantics();

    await pumpLine(tester, PvData(moves: ['e2e4', 'e7e5'].lock, cp: 120));

    const label = 'Engine line, evaluation +1.2: 1. e4 e5 ';
    expect(find.bySemanticsLabel(label), findsOneWidget);

    final node = tester.getSemantics(find.bySemanticsLabel(label));
    expect(node.flagsCollection.isButton, isTrue);

    handle.dispose();
  });

  testWidgets('empty engine line renders nothing to announce', (tester) async {
    final handle = tester.ensureSemantics();

    await pumpLine(tester, PvData(moves: const <String>[].lock));

    expect(find.byType(Engineline), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Engine line')), findsNothing);

    handle.dispose();
  });
}
