import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chess_srs/src/model/common/node.dart';
import 'package:chess_srs/src/model/common/uci.dart';
import 'package:chess_srs/src/widgets/variations_bar.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ViewNode _nodeWithVariations({bool withAnnotations = false}) {
  final root = Root(position: Chess.initial);
  final e4 = Branch(
    sanMove: SanMove('e4', Move.parse('e2e4')!),
    position: Chess.initial.play(Move.parse('e2e4')!),
  );
  final d4 = Branch(
    sanMove: SanMove('d4', Move.parse('d2d4')!),
    position: Chess.initial.play(Move.parse('d2d4')!),
  );
  final c4 = Branch(
    sanMove: SanMove('c4', Move.parse('c2c4')!),
    position: Chess.initial.play(Move.parse('c2c4')!),
    nags: withAnnotations ? [1] : null,
  );
  root.addChild(e4);
  root.addChild(d4);
  root.addChild(c4);
  return root.view;
}

void main() {
  testWidgets('renders nothing when there is only one variation', (tester) async {
    final root = Root(position: Chess.initial);
    root.addChild(
      Branch(
        sanMove: SanMove('e4', Move.parse('e2e4')!),
        position: Chess.initial.play(Move.parse('e2e4')!),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VariationsBar(
            currentNode: root.view,
            currentPath: UciPath.empty,
            showAnnotations: false,
            onJump: (_) {},
          ),
        ),
      ),
    );

    expect(find.byType(VariationsBar), findsOneWidget);
    expect(find.text('e4'), findsNothing);
    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('renders variation moves and highlights the mainline', (tester) async {
    final node = _nodeWithVariations();
    final taps = <UciPath>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: VariationsBar(
              currentNode: node,
              currentPath: UciPath.empty,
              showAnnotations: false,
              onJump: taps.add,
            ),
          ),
        ),
      ),
    );

    expect(find.text('e4'), findsOneWidget);
    expect(find.text('d4'), findsOneWidget);
    expect(find.text('c4'), findsOneWidget);

    await tester.tap(find.text('d4'));
    await tester.pump();
    expect(taps, hasLength(1));
    expect(taps.single, UciPath.fromId(node.children[1].id));
  });

  testWidgets('shows move annotations when enabled', (tester) async {
    final node = _nodeWithVariations(withAnnotations: true);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: VariationsBar(
              currentNode: node,
              currentPath: UciPath.empty,
              showAnnotations: true,
              onJump: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('c4!'), findsOneWidget);
    expect(find.text('e4'), findsOneWidget);
  });

  testWidgets('hides annotations when disabled', (tester) async {
    final node = _nodeWithVariations(withAnnotations: true);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: VariationsBar(
              currentNode: node,
              currentPath: UciPath.empty,
              showAnnotations: false,
              onJump: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('c4!'), findsNothing);
    expect(find.text('c4'), findsOneWidget);
  });
}
