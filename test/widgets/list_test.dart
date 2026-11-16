import 'package:chess_srs/src/widgets/list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ListSection', () {
    testWidgets('renders children in a card', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ListSection(
              children: [
                ListTile(title: Text('A')),
                ListTile(title: Text('B')),
              ],
            ),
          ),
        ),
      );

      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
    });

    testWidgets('renders header when provided', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ListSection(
              header: Text('Header'),
              children: [ListTile(title: Text('Row'))],
            ),
          ),
        ),
      );

      expect(find.text('Header'), findsOneWidget);
      expect(find.text('Row'), findsOneWidget);
    });

    testWidgets('loading constructor shows placeholders', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListSection.loading(itemsNumber: 2, header: true),
          ),
        ),
      );

      expect(find.byType(ListSection), findsOneWidget);
    });
  });
}
