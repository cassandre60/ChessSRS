import 'package:chess_srs/src/view/board_editor/board_editor_screen.dart';
import 'package:chessground/chessground.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_provider_scope.dart';

/// Lists every child of [parent] that paints outside the parent's own box.
///
/// A `Flex` with `MainAxisSize.min` inside a `clipBehavior: Clip.hardEdge` container drops
/// whatever does not fit, with no overflow error and no scroll: the control is simply gone.
/// `RenderFlex` exposes no public overflow or children accessor, so this walks the element tree.
List<String> clippedChildren(WidgetTester tester, Finder parent) {
  final dropped = <String>[];
  for (final element in parent.evaluate()) {
    final ro = element.renderObject;
    if (ro is! RenderBox || !ro.hasSize) continue;
    final box = ro.localToGlobal(Offset.zero) & ro.size;
    element.visitChildren((child) {
      final cro = child.renderObject;
      if (cro is RenderBox && cro.hasSize && cro.attached) {
        final cr = cro.localToGlobal(Offset.zero) & cro.size;
        if (cr.right > box.right + 0.5 ||
            cr.left < box.left - 0.5 ||
            cr.bottom > box.bottom + 0.5 ||
            cr.top < box.top - 0.5) {
          dropped.add('${child.widget.runtimeType} $cr outside $box');
        }
      }
    });
  }
  return dropped;
}

void main() {
  group('Board editor piece palette', () {
    // Regression: the palette sized its eight tools at boardSize / 8 = 390.4px inside a container
    // whose 1px border left a 388.4px content box, so the erase button overflowed by 2px and the
    // ancestor's hard clip ate it. Every test in the suite was green and the control was
    // unreachable on a phone.
    for (final size in const [Size(390, 844), Size(360, 640), Size(320, 568)]) {
      testWidgets('no tool is clipped at ${size.width.toInt()}x${size.height.toInt()}', (
        tester,
      ) async {
        tester.view.physicalSize = size * 3;
        tester.view.devicePixelRatio = 3.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          await makeTestProviderScopeApp(tester, home: const BoardEditorScreen()),
        );
        await tester.pumpAndSettle();

        // The erase button is the one that used to disappear, so assert on it directly...
        expect(
          find.byKey(const Key('delete-button-white')),
          findsOneWidget,
          reason: 'erase tool must exist in the tree',
        );

        // ...and on nothing being painted outside any palette box.
        expect(clippedChildren(tester, find.byType(Flex)), isEmpty);
      });
    }

    testWidgets('every tool is reachable, not merely present', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        await makeTestProviderScopeApp(tester, home: const BoardEditorScreen()),
      );
      await tester.pumpAndSettle();

      // A present-but-clipped widget still passes `findsOneWidget`, so hit-test it instead: the
      // erase tool has to actually receive a tap at its own centre.
      final erase = find.byKey(const Key('delete-button-white'));
      expect(tester.getCenter(erase).dx, lessThanOrEqualTo(390));

      expect(find.byType(ChessboardEditor), findsOneWidget);
      await tester.tap(erase);
      await tester.pumpAndSettle();
    });

    // Regression: the palette/board/palette column used `MainAxisAlignment.spaceEvenly`, which
    // spread the leftover height into four *equal* ~51px gaps on a 390x844 phone. The tool
    // palettes therefore floated as far from the board they act on as they did from the screen
    // edge. A square board is width-bound and cannot claim that height, so the block is centred
    // and the palette-to-board gap is kept tight instead of equal.
    testWidgets('palettes sit next to the board, not adrift in equal gaps', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        await makeTestProviderScopeApp(tester, home: const BoardEditorScreen()),
      );
      await tester.pumpAndSettle();

      // The three column children: palette, board, palette.
      final column = find.byType(Flex).first;
      final boxes = <Rect>[];
      tester.element(column).visitChildren((child) {
        final ro = child.renderObject;
        if (ro is RenderBox && ro.hasSize) {
          boxes.add(ro.localToGlobal(Offset.zero) & ro.size);
        }
      });
      expect(boxes.length, 3, reason: 'palette, board, palette');

      final topPalette = boxes[0];
      final board = boxes[1];
      final bottomPalette = boxes[2];
      final slot = tester.getRect(column);

      expect(
        board.top - topPalette.bottom,
        lessThanOrEqualTo(16),
        reason: 'top palette must hug the board',
      );
      expect(
        bottomPalette.top - board.bottom,
        lessThanOrEqualTo(16),
        reason: 'bottom palette must hug the board',
      );

      // ...while the block as a whole stays centred, so the slack becomes margin rather than a
      // gap between a control and the thing it controls.
      final above = topPalette.top - slot.top;
      final below = slot.bottom - bottomPalette.bottom;
      expect((above - below).abs(), lessThanOrEqualTo(1), reason: 'block must be centred');
      expect(above, greaterThan(16), reason: 'slack becomes margin, not a gap');
    });
  });
}
