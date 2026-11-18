import 'package:chess_srs/src/styles/lichess_icons.dart';
import 'package:chess_srs/src/widgets/progression_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildWidget(int progress) {
    return MaterialApp(home: Scaffold(body: ProgressionWidget(progress)));
  }

  Icon progressionIcon(WidgetTester tester) {
    return tester.widget<Icon>(
      find.descendant(of: find.byType(ProgressionWidget), matching: find.byType(Icon)),
    );
  }

  group('ProgressionWidget', () {
    testWidgets('renders a plain zero with no arrow', (tester) async {
      await tester.pumpWidget(buildWidget(0));

      expect(find.text('0'), findsOneWidget);
      expect(
        find.descendant(of: find.byType(ProgressionWidget), matching: find.byType(Icon)),
        findsNothing,
      );
    });

    testWidgets('renders an up arrow and the positive value', (tester) async {
      await tester.pumpWidget(buildWidget(5));

      expect(progressionIcon(tester).icon, LichessIcons.arrow_full_upperright);
      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('renders a down arrow and the absolute value when negative', (tester) async {
      await tester.pumpWidget(buildWidget(-3));

      expect(progressionIcon(tester).icon, LichessIcons.arrow_full_lowerright);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('-3'), findsNothing);
    });
  });
}
