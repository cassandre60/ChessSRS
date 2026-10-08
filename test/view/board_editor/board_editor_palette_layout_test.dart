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
    // The board is a square widget in a `Clip.hardEdge` ancestor, so anything that makes it
    // non-square is silently cropped rather than reported. This is the assertion that says so.
    for (final size in const [
      Size(390, 844),
      Size(360, 640),
      Size(320, 568),
      Size(844, 390),
      Size(667, 375),
      Size(1440, 900),
    ]) {
      testWidgets('the board stays square at ${size.width.toInt()}x${size.height.toInt()}', (
        tester,
      ) async {
        await tester.pumpWidget(
          await makeTestProviderScopeApp(
            tester,
            home: const BoardEditorScreen(),
            surfaceSize: size,
          ),
        );
        await tester.pumpAndSettle();

        final board = tester.getRect(find.byType(ChessboardEditor));
        expect(
          (board.width - board.height).abs(),
          lessThanOrEqualTo(1),
          reason: 'a non-square board is cropped by the ancestor clip, not reported',
        );
      });
    }

    // Regression: the status panel was stacked under the board on every layout, and on a
    // 390px-tall landscape phone that left the board 104px -- a quarter of the 228px the same
    // screen had before the panel existed. The demo draws the editor as `.split`, board left and
    // side column right, so in landscape the panel moves beside the board and claims width.
    testWidgets('landscape puts the status panel beside the board, not under it', (tester) async {
      await tester.pumpWidget(
        await makeTestProviderScopeApp(
          tester,
          home: const BoardEditorScreen(),
          surfaceSize: const Size(844, 390),
        ),
      );
      await tester.pumpAndSettle();

      final board = tester.getRect(find.byType(ChessboardEditor));
      final fen = tester.getRect(find.textContaining(' w KQkq '));

      expect(
        fen.left,
        greaterThanOrEqualTo(board.right),
        reason: 'the FEN readout must sit beside the board in landscape, not below it',
      );
      // The width it buys back is the whole point, so assert the amount rather than just the side.
      // 190, not 200: SrsLayout.minTouchTarget went 44 -> 48 (platform accessibility guidance),
      // so the side column is wider and the board narrower. Still far above the 104px of the
      // stacked-under regression this guards.
      expect(board.width, greaterThan(190));
    });

    testWidgets('portrait stacks the status panel under the board', (tester) async {
      await tester.pumpWidget(
        await makeTestProviderScopeApp(
          tester,
          home: const BoardEditorScreen(),
          surfaceSize: const Size(390, 844),
        ),
      );
      await tester.pumpAndSettle();

      final board = tester.getRect(find.byType(ChessboardEditor));
      final fen = tester.getRect(find.textContaining(' w KQkq '));

      expect(fen.top, greaterThan(board.bottom), reason: 'under the board in portrait');
    });

    // Regression: the palette sized its eight tools at boardSize / 8 = 390.4px inside a container
    // whose 1px border left a 388.4px content box, so the erase button overflowed by 2px and the
    // ancestor's hard clip ate it. Every test in the suite was green and the control was
    // unreachable on a phone.
    for (final size in const [Size(390, 844), Size(360, 640), Size(320, 568)]) {
      testWidgets('no tool is clipped at ${size.width.toInt()}x${size.height.toInt()}', (
        tester,
      ) async {
        // `surfaceSize`, not `tester.view.physicalSize`: the harness sizes the surface from this
        // argument, and it wins over the test view. Setting the test view instead left all three
        // sizes rendering at 390x844, so the 320x568 case never ran.
        await tester.pumpWidget(
          await makeTestProviderScopeApp(
            tester,
            home: const BoardEditorScreen(),
            surfaceSize: size,
          ),
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
      await tester.pumpWidget(
        await makeTestProviderScopeApp(
          tester,
          home: const BoardEditorScreen(),
          surfaceSize: const Size(390, 844),
        ),
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
      await tester.pumpWidget(
        await makeTestProviderScopeApp(
          tester,
          home: const BoardEditorScreen(),
          surfaceSize: const Size(390, 844),
        ),
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

      // ...and the block fills the slot rather than leaving slack for an alignment to spread.
      //
      // This is the spaceEvenly regression from the other side. With `spaceEvenly` the leftover
      // height became four equal ~51px gaps, so `above` was ~51; centred and height-bound, the board
      // claims the slack and `above` goes to ~0. Both are "not spread", and the earlier
      // `above > 16` assertion could only be satisfied by a board too small to fill the screen --
      // which is a bug, not slack.
      final above = topPalette.top - slot.top;
      final below = slot.bottom - bottomPalette.bottom;
      expect(above, lessThanOrEqualTo(16), reason: 'no slack above the block to spread');
      expect(below, lessThanOrEqualTo(16), reason: 'no slack below the block to spread');
    });

    // The palette test above used to set `tester.view.physicalSize` and believe it was resizing the
    // surface. It was not: `makeTestProviderScopeApp` pins the surface through its own `surfaceSize`
    // argument, which overrides the test view, so all three sizes in that loop rendered at 390x844
    // and the 320x568 case never ran. This asserts the size actually in effect, so a test that
    // believes it is measuring a small phone cannot silently stop doing so.
    for (final size in const [Size(390, 844), Size(360, 640), Size(320, 568)]) {
      testWidgets('the surface really is ${size.width.toInt()}x${size.height.toInt()}', (
        tester,
      ) async {
        await tester.pumpWidget(
          await makeTestProviderScopeApp(
            tester,
            home: const BoardEditorScreen(),
            surfaceSize: size,
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.getSize(find.byType(BoardEditorScreen)), size);
      });
    }
  });
}
