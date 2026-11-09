// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC coverage: INV-068.

// Dynamic mode with nothing unlocked cannot introduce a single new position;
// the banner is the only place that says so. Tested on its own because the
// full review screen needs a live session and database to reach this branch.

import 'package:chess_srs/src/view/review/review_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('the freeze banner names the cause and offers turn-off', (tester) async {
    var turnOffRequests = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 640,
              child: DynamicFreezeBanner(onTurnOff: () => turnOffRequests++),
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('no lines are unlocked'), findsOneWidget);
    expect(find.textContaining('only positions you have already learned'), findsOneWidget);
    expect(find.text('Turn off'), findsOneWidget);

    await tester.tap(find.text('Turn off'));
    expect(turnOffRequests, 1, reason: 'the banner must offer the one-tap escape it promises');
  });
}
