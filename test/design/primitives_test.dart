import 'package:chess_srs/src/design/design.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'srs_test_app.dart';

void main() {
  group('SrsPillButton', () {
    srsPhoneTestWidgets('is 46 tall, ink filled, ground label', (tester) async {
      await pumpSrs(
        tester,
        Center(
          child: SrsPillButton(label: 'Continue', onPressed: () {}),
        ),
      );

      final c = srsTestColors();
      expect(tester.getSize(find.byType(SrsPillButton)).height, 46.0);

      final label = tester.widget<Text>(find.text('Continue'));
      expect(label.style?.color, c.ground);
      expect(label.style?.fontSize, 15.0);
      expect(label.style?.fontWeight, FontWeight.w600);
    });

    srsPhoneTestWidgets('reports itself as a button to semantics', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpSrs(tester, SrsPillButton(label: 'Continue', onPressed: () {}));

      expect(
        tester.getSemantics(find.byType(SrsPillButton)),
        isSemantics(
          label: 'Continue',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });

    srsPhoneTestWidgets('announces its label exactly once', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpSrs(tester, SrsPillButton(label: 'Continue', onPressed: () {}));

      expect(tester.getSemantics(find.byType(SrsPillButton)).label, 'Continue');
      handle.dispose();
    });

    srsPhoneTestWidgets('is inert when onPressed is null', (tester) async {
      await pumpSrs(tester, const SrsPillButton(label: 'Continue', onPressed: null));

      final handle = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.byType(SrsPillButton)),
        isSemantics(label: 'Continue', isButton: true, hasEnabledState: true, isEnabled: false),
      );
      handle.dispose();
    });
  });

  group('SrsTextButton', () {
    srsPhoneTestWidgets('clears the 44px minimum touch target', (tester) async {
      await pumpSrs(
        tester,
        Center(
          child: SrsTextButton(label: 'Skip', onPressed: () {}),
        ),
      );

      expect(tester.getSize(find.byType(SrsTextButton)).height, greaterThanOrEqualTo(44));
    });
  });

  group('keyboard hints', () {
    srsPhoneTestWidgets('are hidden on touch platforms', (tester) async {
      await pumpSrs(tester, SrsPillButton(label: 'Skip', shortcut: 'S', onPressed: () {}));
      expect(find.byType(SrsKbd), findsNothing);
    });

    srsDesktopTestWidgets('are shown on desktop platforms', (tester) async {
      await pumpSrs(tester, SrsPillButton(label: 'Skip', shortcut: 'S', onPressed: () {}));
      expect(find.byType(SrsKbd), findsOneWidget);
      expect(find.text('S'), findsOneWidget);
    });
  });

  group('SrsSegmented', () {
    srsPhoneTestWidgets('paints the selected option as an ink pill on ground text', (tester) async {
      await pumpSrs(
        tester,
        Center(
          child: SrsSegmented<String>(
            options: const {'a': 'Light', 'b': 'Dark'},
            value: 'a',
            onChanged: (_) {},
          ),
        ),
      );

      final c = srsTestColors();
      expect(tester.widget<Text>(find.text('Light')).style?.color, c.ground);
      expect(tester.widget<Text>(find.text('Dark')).style?.color, c.ink2);
    });

    srsPhoneTestWidgets('exposes the selected option as toggled', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpSrs(
        tester,
        Center(
          child: SrsSegmented<String>(
            options: const {'a': 'Light', 'b': 'Dark'},
            value: 'b',
            onChanged: (_) {},
          ),
        ),
      );

      expect(
        tester.getSemantics(find.text('Light')),
        isSemantics(isButton: true, hasToggledState: true, isToggled: false),
      );
      expect(
        tester.getSemantics(find.text('Dark')),
        isSemantics(isButton: true, hasToggledState: true, isToggled: true),
      );
      handle.dispose();
    });

    srsPhoneTestWidgets('announces each option exactly once', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpSrs(
        tester,
        Center(
          child: SrsSegmented<String>(
            options: const {'a': 'Light', 'b': 'Dark'},
            value: 'a',
            onChanged: (_) {},
          ),
        ),
      );

      expect(tester.getSemantics(find.text('Light')).label, 'Light');
      expect(tester.getSemantics(find.text('Dark')).label, 'Dark');
      handle.dispose();
    });

    srsPhoneTestWidgets('reports the tapped option', (tester) async {
      String? picked;
      await pumpSrs(
        tester,
        Center(
          child: SrsSegmented<String>(
            options: const {'a': 'Light', 'b': 'Dark'},
            value: 'a',
            onChanged: (v) => picked = v,
          ),
        ),
      );

      await tester.tap(find.text('Dark'));
      expect(picked, 'b');
    });
  });

  group('SrsSwitch', () {
    srsPhoneTestWidgets('is a 44x26 toggle reporting its state', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpSrs(
        tester,
        Center(
          child: SrsSwitch(value: true, semanticLabel: 'Sound', onChanged: (_) {}),
        ),
      );

      final box = tester.getSize(find.byType(AnimatedContainer));
      expect(box.width, 44.0);
      expect(box.height, 26.0);
      expect(
        tester.getSemantics(find.byType(SrsSwitch)),
        isSemantics(
          label: 'Sound',
          isButton: true,
          hasToggledState: true,
          isToggled: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });

    srsPhoneTestWidgets('reports the inverted state when tapped', (tester) async {
      bool? next;
      await pumpSrs(
        tester,
        Center(
          child: SrsSwitch(value: true, semanticLabel: 'Sound', onChanged: (v) => next = v),
        ),
      );

      await tester.tap(find.byType(SrsSwitch));
      expect(next, isFalse);
    });
  });

  group('SrsAccentDots', () {
    srsPhoneTestWidgets('offers the four shipped accents and marks the active one', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpSrs(
        tester,
        Center(
          child: SrsAccentDots(value: SrsAccent.violet, onChanged: (_) {}),
        ),
      );

      for (final accent in SrsAccent.values) {
        expect(
          tester.getSemantics(find.bySemanticsLabel(accent.name)),
          isSemantics(isToggled: accent == SrsAccent.violet, hasToggledState: true),
          reason: 'accent ${accent.name}',
        );
      }
      handle.dispose();
    });

    srsPhoneTestWidgets('reports the tapped accent', (tester) async {
      SrsAccent? picked;
      await pumpSrs(
        tester,
        Center(
          child: SrsAccentDots(value: SrsAccent.ultramarine, onChanged: (a) => picked = a),
        ),
      );

      await tester.tap(find.bySemanticsLabel('ochre'));
      expect(picked, SrsAccent.ochre);
    });
  });

  group('SrsLogoMark', () {
    srsPhoneTestWidgets('draws the 22px geometric mark', (tester) async {
      await pumpSrs(tester, const Center(child: SrsLogoMark()));

      expect(tester.getSize(find.byType(SrsLogoMark)), const Size(22, 22));
    });
  });
}
