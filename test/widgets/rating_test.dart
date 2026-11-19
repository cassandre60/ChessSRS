import 'package:chess_srs/src/widgets/rating.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RatingWidget', () {
    testWidgets('displays floored rating without provisional marker', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: RatingWidget(rating: 1542.9, deviation: 50),
        ),
      );

      expect(find.text('1542'), findsOneWidget);
      expect(find.textContaining('?'), findsNothing);
    });

    testWidgets('shows provisional marker when provisional is true', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: RatingWidget(rating: 1500, deviation: 50, provisional: true),
        ),
      );

      expect(find.text('1500?'), findsOneWidget);
    });

    testWidgets('shows provisional marker when deviation exceeds threshold', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: RatingWidget(rating: 1500, deviation: 111),
        ),
      );

      expect(find.text('1500?'), findsOneWidget);
    });

    testWidgets('does not show marker at threshold deviation without provisional flag', (
      tester,
    ) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: RatingWidget(rating: 1500, deviation: 110),
        ),
      );

      expect(find.text('1500'), findsOneWidget);
      expect(find.textContaining('?'), findsNothing);
    });

    testWidgets('applies provided text style', (tester) async {
      const style = TextStyle(fontSize: 20, fontWeight: FontWeight.bold);
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: RatingWidget(rating: 1500, deviation: 50, style: style),
        ),
      );

      final text = tester.widget<Text>(find.byType(Text));
      expect(text.style, style);
    });
  });
}
