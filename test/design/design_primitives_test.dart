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

    testWidgets('the label never takes the background colour', (tester) async {
      // The pill is the one filled button in the system, so its background is `ink` (or `accent`)
      // in every state. A label that matched the background would render as an empty black pill:
      // this shipped that way and no assertion noticed, because the label was still in the tree.
      for (final selected in [false, true]) {
        await tester.pumpWidget(
          _wrap(SrsPillButton(label: 'Practice', onPressed: () {}, selected: selected)),
        );

        final label = tester.widget<Text>(find.text('Practice'));
        final surface = tester.widget<Container>(
          find.descendant(of: find.byType(SrsPillButton), matching: find.byType(Container)).first,
        );
        final background = (surface.decoration! as BoxDecoration).color!;

        expect(label.style?.color, isNot(background), reason: 'selected: $selected');
      }
    });

    testWidgets('expands to the width it is given when asked', (tester) async {
      // A pill among others should shrink-wrap, so a set of them sits together. The one pill that
      // is the only action on a sheet has to fill the sheet instead, and asking for that with a
      // surrounding SizedBox does not work: the pressable's Stack passes loose constraints down,
      // so the pill shrink-wraps to its label however wide its parent is. Measure the painted
      // surface, not the widget, which comes out full width either way.
      Finder paintedPill() =>
          find.descendant(of: find.byType(SrsPillButton), matching: find.byType(Container)).first;

      await tester.pumpWidget(
        _wrap(const SizedBox(width: 300, child: SrsPillButton(label: 'Practice', onPressed: null))),
      );
      expect(tester.getSize(paintedPill()).width, lessThan(300));

      await tester.pumpWidget(
        _wrap(
          const SizedBox(
            width: 300,
            child: SrsPillButton(label: 'Practice', onPressed: null, expand: true),
          ),
        ),
      );
      expect(tester.getSize(paintedPill()).width, 300);
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
