// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/design/design.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../binding.dart';

/// Covers the three primitives the log screens needed, none of which existed before: a
/// head action, a search field, and a selected pill.
/// A `MaterialApp` is required, not optional: `SrsSearchField` builds a `TextField`, and a
/// `TextField` asserts on a Material ancestor. `SrsTheme` wraps it because the primitives read
/// `context.srs`.
Widget _wrap(Widget child, {double width = 390, double height = 844}) {
  return MaterialApp(
    // The Scaffold is inside `home` on purpose: a `TextField` asserts on a Material ancestor
    // within the closest LookupBoundary, and the Navigator is one.
    home: Scaffold(
      body: SrsTheme(
        colors: SrsColors.light(SrsAccent.ultramarine),
        child: MediaQuery(
          data: MediaQueryData(size: Size(width, height)),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Align(alignment: Alignment.topLeft, child: child),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(TestLichessBinding.ensureInitialized);

  group('SrsIconButton', () {
    testWidgets('meets the 44px touch target and announces itself', (tester) async {
      await tester.pumpWidget(
        _wrap(SrsIconButton(icon: Icons.share, tooltip: 'Export logs', onPressed: () {})),
      );

      final size = tester.getSize(find.byType(SrsIconButton));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));

      // A bare icon button has nothing but the tooltip to announce, so the tooltip is the
      // accessibility name and must be the one SrsPressable is given.
      final pressable = tester.widget<SrsPressable>(find.byType(SrsPressable).first);
      expect(pressable.semanticLabel, 'Export logs');
    });

    testWidgets('fires onPressed and goes inert when disabled', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _wrap(SrsIconButton(icon: Icons.close, tooltip: 'Clear', onPressed: () => taps++)),
      );
      await tester.tap(find.byType(SrsIconButton));
      expect(taps, 1);

      await tester.pumpWidget(
        _wrap(const SrsIconButton(icon: Icons.close, tooltip: 'Clear', onPressed: null)),
      );
      await tester.tap(find.byType(SrsIconButton));
      expect(taps, 1, reason: 'a disabled button must not fire');
    });
  });

  group('SrsSearchField', () {
    testWidgets('reports typing and clearing', (tester) async {
      final typed = <String>[];
      var cleared = 0;
      final controller = TextEditingController();

      await tester.pumpWidget(
        _wrap(
          SrsSearchField(controller: controller, onChanged: typed.add, onClear: () => cleared++),
        ),
      );

      await tester.enterText(find.byType(EditableText), '18ms');
      expect(typed, ['18ms']);

      await tester.tap(find.bySemanticsLabel('Clear search'));
      expect(cleared, 1);

      // The spec gives the field a hairline and nothing else, so the Material theme's fill
      // must not also be there.
      final decoration = tester
          .widget<TextField>(
            find
                .descendant(of: find.byType(SrsSearchField), matching: find.byType(TextField))
                .first,
          )
          .decoration!;
      expect(decoration.filled, isFalse);
      expect(decoration.border, InputBorder.none);
    });
  });

  group('SrsPillButton', () {
    testWidgets('marks the selected pill as toggled', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SrsPillButton(label: 'All', onPressed: null, selected: true),
              SrsPillButton(label: 'Review', onPressed: null),
            ],
          ),
        ),
      );

      // A screen reader has to be able to tell the two pills apart, which it only can if the
      // selected one is announced as pressed.
      final toggled = tester
          .widgetList<SrsPressable>(find.byType(SrsPressable))
          .map((p) => p.semanticsToggled)
          .toList();
      expect(toggled, [true, false]);
    });

    testWidgets('an unselected pill is outlined so the set reads as a group', (tester) async {
      await tester.pumpWidget(_wrap(const SrsPillButton(label: 'All', onPressed: null)));

      final box = tester.widget<Container>(
        find.descendant(of: find.byType(SrsPillButton), matching: find.byType(Container)).first,
      );
      final decoration = box.decoration! as BoxDecoration;
      expect(decoration.border, isNotNull);
    });
  });

  group('SrsSettingsRow', () {
    testWidgets('a leading widget sits left of the label', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SrsSettingsRow(
            label: 'GET /api/account',
            leading: SizedBox(width: 44, child: Text('200')),
          ),
        ),
      );

      final lead = tester.getRect(find.text('200'));
      final label = tester.getRect(find.text('GET /api/account'));
      expect(lead.right, lessThanOrEqualTo(label.left));
    });
  });
}
