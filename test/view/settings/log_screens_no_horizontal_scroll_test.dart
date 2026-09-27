// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/view/settings/app_log_settings_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../binding.dart';
import '../../test_provider_scope.dart';

/// The design forbids horizontal scrolling: nothing in the app may require a sideways swipe to
/// reach a control. The app log screen's category filter was a horizontal `ListView` of
/// `ChoiceChip`, so everything past the fourth category was only reachable by dragging
/// sideways. It is a `Wrap` of `SrsPillButton`s now, and this is the guard.
void main() {
  setUpAll(TestLichessBinding.ensureInitialized);

  testWidgets('the app log category filter fits the width instead of scrolling sideways', (
    tester,
  ) async {
    await tester.pumpWidget(
      await makeTestProviderScopeApp(
        tester,
        home: const AppLogSettingsScreen(),
        surfaceSize: const Size(390, 844),
      ),
    );
    await tester.pumpAndSettle();

    // Every category is laid out as its own control, one per category.
    final chips = find.byType(SrsPillButton);
    expect(chips, findsNWidgets(LogCategory.values.length + 1)); // + the log level

    // And every one of them is inside a phone's width.
    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    for (final element in chips.evaluate()) {
      final origin = (element.renderObject! as RenderBox).localToGlobal(Offset.zero);
      expect(
        origin.dx,
        inInclusiveRange(0, width),
        reason:
            'a filter control at x=${origin.dx} sits outside a ${width}px screen, so '
            'reaching it needs a sideways swipe',
      );
    }

    // No scrollable in the tree runs on the horizontal axis.
    for (final element in find.byType(Scrollable).evaluate()) {
      expect(
        (element.widget as Scrollable).axisDirection,
        anyOf(isNot(AxisDirection.right), isNot(AxisDirection.left)),
        reason: 'a horizontal scrollable was reintroduced',
      );
    }
  });
}
