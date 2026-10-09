// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC coverage: INV-062.

import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/design/top_bar.dart';
import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter/material.dart' show Tooltip;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_provider_scope.dart';

/// `SrsTopBar` inside the narrow bar padding, at the narrowest window the Linux runner
/// permits.
///
/// Literals rather than tokens, deliberately: this file has to compile against the code
/// under test so a regression here fails on an assertion instead of on a missing symbol.
/// `16` is `design/docs/03-components.md` §2 "Padding: narrow L16 R4", as applied by
/// `SrsReviewLayout`; `320` is the narrowest viewport the product supports, now also the
/// runner's minimum window width.
///
/// The bar's first item is the white colour square. Its hit target used to be nudged 10px
/// left of the bar's own padding by a `Transform.translate`, a leftover from the scope
/// button it replaced: that button carried a matching 10px horizontal inset, so the nudge
/// cancelled out. The squares carry no such inset, so the nudge only moved them out of the
/// padding box while layout kept reserving the full width — 10px of layout spent on nothing.
void main() {
  const narrowPadLeft = 16.0;
  const narrowPadRight = 4.0;
  const narrowestWindow = 320.0;

  Future<void> pumpNarrowBar(WidgetTester tester, {required int dueCount}) async {
    await tester.pumpWidget(
      await makeTestProviderScopeApp(
        tester,
        surfaceSize: const Size(narrowestWindow, 720),
        home: Padding(
          padding: const EdgeInsets.fromLTRB(narrowPadLeft, 0, narrowPadRight, 0),
          child: SrsTopBar(
            activeSide: Side.white,
            dueCount: dueCount,
            onSidePressed: (_) {},
            onOverflowPressed: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder square(Side side) {
    final label = side == Side.white ? 'White repertoire' : 'Black repertoire';
    return find.byWidgetPredicate((w) => w is Tooltip && w.message == label);
  }

  testWidgets('the first item starts at the bar padding, not before it', (tester) async {
    await pumpNarrowBar(tester, dueCount: 94);

    expect(
      tester.getRect(square(Side.white)).left,
      narrowPadLeft,
      reason:
          'the colour squares must sit inside the bar padding; a paint-time nudge puts them '
          'outside it while layout still reserves the width, so the bar needs 10px more window '
          'than it uses',
    );
  });

  testWidgets('the bar fits the narrowest permitted window without clipping', (tester) async {
    await pumpNarrowBar(tester, dueCount: 94);

    expect(tester.takeException(), isNull);
  });

  testWidgets('the bar still fits when the due count is widest', (tester) async {
    // A four-digit count is the widest the slot gets; at the window floor it is the case with
    // the least slack.
    await pumpNarrowBar(tester, dueCount: 9999);

    expect(tester.takeException(), isNull);
  });
}
