// Board background: paper squares, ink-hatched dark squares, ink frame.
// Sits UNDER chessground (which must use transparent squares) inside a Stack.
// Adapted from design/flutter/board_background.dart.
import 'package:chess_srs/src/design/hatch.dart';
import 'package:chess_srs/src/design/tokens.dart';
import 'package:flutter/widgets.dart';

class SrsBoardBackgroundPainter extends CustomPainter {
  const SrsBoardBackgroundPainter({required this.colors, this.frame = true});
  final SrsColors colors;
  final bool frame;

  /// Which physical squares are dark, by file (0 = a) and row from the top.
  ///
  /// Chess fundamental, pinned in CI (`test/design/board_squares_test.dart`):
  /// h1 is light, a1 is dark. The rule is rotation-symmetric on an 8x8 board
  /// (`(7-f) + (7-r)` has the same parity as `f + r`), so it holds for both
  /// White and Black orientations with no orientation input: flipping the
  /// board moves h1 to the top-left, which is light either way.
  static bool isDarkSquare(int file, int rowFromTop) => (file + rowFromTop).isOdd;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final sq = s / 8;

    canvas.drawRect(Rect.fromLTWH(0, 0, s, s), Paint()..color = colors.squareLight);

    // Dark squares: (file + rowFromTop) is odd. a1 (file 0, row 7) is dark.
    final dark = Path();
    for (var f = 0; f < 8; f++) {
      for (var r = 0; r < 8; r++) {
        if (isDarkSquare(f, r)) dark.addRect(Rect.fromLTWH(f * sq, r * sq, sq, sq));
      }
    }
    canvas.drawPath(dark, Paint()..color = colors.squareDark);

    // Continuous hatch across the whole board, visible only on dark squares.
    canvas.save();
    canvas.clipPath(dark);
    final gap = (s / 100).clamp(4.6, 7.0);
    paintHatch(canvas, Size(s, s), color: colors.hatch, gap: gap, width: 1.1);
    canvas.restore();

    if (frame) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, s, s).inflate(0.75),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = colors.ink,
      );
    }
  }

  @override
  bool shouldRepaint(SrsBoardBackgroundPainter old) => old.colors != colors;
}

/// Static board background widget. Wrap in a RepaintBoundary for performance.
class SrsBoardBackground extends StatelessWidget {
  const SrsBoardBackground({super.key, required this.size, this.frame = true});

  final double size;
  final bool frame;

  @override
  Widget build(BuildContext context) {
    final colors = context.srs;
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.square(size),
        painter: SrsBoardBackgroundPainter(colors: colors, frame: frame),
      ),
    );
  }
}

/// Coordinates. Wide layouts draw them OUTSIDE the board (ink3, 11.5px); narrow layouts draw
/// them INSIDE the edge squares (ink2, 9.5px, with a halo). [whiteAtBottom] flips the order.
class SrsCoordinates {
  static const files = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];
}

class SrsBoardWithCoordinates extends StatelessWidget {
  const SrsBoardWithCoordinates({
    super.key,
    required this.size,
    required this.board,
    this.outside = true,
    this.whiteAtBottom = true,
  });
  final double size;
  final Widget board; // your Stack: background + chessboard + arrow overlay
  final bool outside;
  final bool whiteAtBottom;

  @override
  Widget build(BuildContext context) {
    final c = context.srs;
    final files = whiteAtBottom ? SrsCoordinates.files : SrsCoordinates.files.reversed.toList();
    final ranks = whiteAtBottom ? const [8, 7, 6, 5, 4, 3, 2, 1] : const [1, 2, 3, 4, 5, 6, 7, 8];

    if (!outside) {
      final style = TextStyle(
        fontFamily: SrsText.ui,
        fontSize: 9.5,
        fontWeight: FontWeight.w500,
        color: c.ink2,
        fontFeatures: SrsText.tabular,
        shadows: [
          Shadow(color: c.halo, blurRadius: 3),
          Shadow(color: c.halo, blurRadius: 3),
        ],
      );
      final sq = size / 8;
      return SizedBox(
        width: size,
        height: size,
        child: Stack(
          children: [
            board,
            for (var i = 0; i < 8; i++)
              Positioned(
                left: i * sq,
                top: 7 * sq,
                width: sq,
                height: sq,
                child: Padding(
                  padding: const EdgeInsets.only(right: 3, bottom: 2),
                  child: Align(
                    alignment: Alignment.bottomRight,
                    child: Text(files[i], style: style),
                  ),
                ),
              ),
            for (var i = 0; i < 8; i++)
              Positioned(
                left: 0,
                top: i * sq,
                width: sq,
                height: sq,
                child: Padding(
                  padding: const EdgeInsets.only(left: 3, top: 2),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Text('${ranks[i]}', style: style),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    final style = TextStyle(
      fontFamily: SrsText.ui,
      fontSize: 11.5,
      color: c.ink3,
      fontFeatures: SrsText.tabular,
    );
    final sq = size / 8;
    const gutter = SrsLayout.coordGutter;
    return SizedBox(
      width: gutter + size,
      height: size + gutter,
      child: Stack(
        children: [
          Positioned(left: gutter, top: 0, child: board),
          for (var i = 0; i < 8; i++)
            Positioned(
              left: 0,
              top: i * sq,
              width: gutter,
              height: sq,
              child: Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text('${ranks[i]}', style: style),
                ),
              ),
            ),
          for (var i = 0; i < 8; i++)
            Positioned(
              left: gutter + i * sq,
              top: size + 8,
              width: sq,
              child: Center(child: Text(files[i], style: style)),
            ),
        ],
      ),
    );
  }
}
