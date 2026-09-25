import 'package:chess_srs/src/design/design.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'srs_test_app.dart';

void main() {
  group('SrsDisclosure', () {
    srsPhoneTestWidgets('starts collapsed, hiding its contents from sight and semantics', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpSrs(
        tester,
        const SrsDisclosure(title: 'Advanced', child: Text('Scheduling algorithm')),
      );

      expect(find.text('Scheduling algorithm'), findsNothing);
      expect(find.bySemanticsLabel('Scheduling algorithm'), findsNothing);
      handle.dispose();
    });

    srsPhoneTestWidgets('reveals its contents on tap', (tester) async {
      await pumpSrs(
        tester,
        const SrsDisclosure(title: 'Advanced', child: Text('Scheduling algorithm')),
      );

      await tester.tap(find.text('Advanced'));
      await tester.pumpAndSettle();

      expect(find.text('Scheduling algorithm'), findsOneWidget);
    });

    srsPhoneTestWidgets('collapses again on a second tap', (tester) async {
      await pumpSrs(
        tester,
        const SrsDisclosure(title: 'Advanced', child: Text('Scheduling algorithm')),
      );

      await tester.tap(find.text('Advanced'));
      await tester.pumpAndSettle();
      expect(find.text('Scheduling algorithm'), findsOneWidget);

      await tester.tap(find.text('Advanced'));
      await tester.pumpAndSettle();
      expect(find.text('Scheduling algorithm'), findsNothing);
    });

    srsPhoneTestWidgets('can start expanded', (tester) async {
      await pumpSrs(
        tester,
        const SrsDisclosure(
          title: 'Advanced',
          initiallyExpanded: true,
          child: Text('Scheduling algorithm'),
        ),
      );

      expect(find.text('Scheduling algorithm'), findsOneWidget);
    });

    srsPhoneTestWidgets('exposes its open state to semantics', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpSrs(
        tester,
        const SrsDisclosure(title: 'Advanced', child: Text('Scheduling algorithm')),
      );

      // Assert the toggled state, not the label: the contents sit beside the header, so
      // the node Flutter hands back is the merged one and carries both labels. That merge
      // is Flutter's business; the contract the disclosure owns is "is it open".
      expect(
        tester.getSemantics(find.byType(SrsPressable)),
        isSemantics(isButton: true, hasToggledState: true, isToggled: false),
      );

      await tester.tap(find.text('Advanced'));
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(find.byType(SrsPressable)),
        isSemantics(isButton: true, hasToggledState: true, isToggled: true),
      );
      handle.dispose();
    });

    srsPhoneTestWidgets('header clears the 44px touch target', (tester) async {
      await pumpSrs(
        tester,
        const SrsDisclosure(title: 'Advanced', child: Text('Scheduling algorithm')),
      );

      expect(tester.getSize(find.byType(SrsPressable)).height, greaterThanOrEqualTo(44));
    });

    srsPhoneTestWidgets('keeps its contents in the tree so control state survives', (tester) async {
      // Offstage, not rebuilt: a switch or a text field inside must not lose what the
      // user typed every time the section is collapsed.
      await pumpSrs(
        tester,
        const SrsDisclosure(title: 'Advanced', initiallyExpanded: true, child: _Counter()),
      );

      await tester.tap(find.byType(_Counter));
      await tester.pumpAndSettle();
      expect(find.text('1'), findsOneWidget);

      await tester.tap(find.text('Advanced'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Advanced'));
      await tester.pumpAndSettle();

      expect(find.text('1'), findsOneWidget);
    });
  });
}

/// A control with state, to prove the disclosure does not rebuild its contents.
class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int _count = 0;

  @override
  Widget build(BuildContext context) =>
      GestureDetector(onTap: () => setState(() => _count++), child: Text('$_count'));
}
