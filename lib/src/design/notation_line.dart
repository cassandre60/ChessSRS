// Notation line: move numbers + SAN with figurines, and a dashed blank.
// Each move PAIR is one WidgetSpan so numbers never wrap away from their move.
// Adapted from design/flutter/notation_line.dart.
// Uses flutter_svg for figurines.
import 'package:chess_srs/src/design/tokens.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

class SrsFigurine extends StatelessWidget {
  const SrsFigurine(this.kind, {super.key, required this.color, required this.fontSize});
  final String kind; // K Q R B N (no pawn figurine)
  final Color color;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(right: fontSize * 0.03),
      child: Transform.translate(
        offset: Offset(0, fontSize * 0.12),
        child: SvgPicture.asset(
          'assets/figurines/$kind.svg',
          width: fontSize * 0.82,
          height: fontSize * 0.96,
          colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
        ),
      ),
    );
  }
}

/// One SAN token: replaces a leading piece letter with its figurine.
class SrsSan extends StatelessWidget {
  const SrsSan(this.san, {super.key, required this.style});
  final String san;
  final TextStyle style;

  static const _pieces = 'KQRBN';

  @override
  Widget build(BuildContext context) {
    final color = style.color ?? const Color(0xFF000000);
    if (san.isNotEmpty && _pieces.contains(san[0])) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          SrsFigurine(san[0], color: color, fontSize: style.fontSize ?? 16),
          Text(san.substring(1), style: style),
        ],
      );
    }
    return Text(san, style: style);
  }
}

/// The dashed blank that represents the answer slot.
class SrsDashedBlank extends StatelessWidget {
  const SrsDashedBlank({super.key, required this.fontSize});
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final c = context.srs;
    return SizedBox(
      width: fontSize * 2.3,
      height: fontSize * 1.05,
      child: CustomPaint(painter: _DashPainter(color: c.ink3)),
    );
  }
}

class _DashPainter extends CustomPainter {
  const _DashPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
    const dashLen = 6.0;
    const gapLen = 4.0;
    final y = size.height - 1;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, y), Offset((x + dashLen).clamp(0, size.width), y), paint);
      x += dashLen + gapLen;
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}

/// 240 ms fade + 3px rise when the answer fills the blank.
class _FillIn extends StatefulWidget {
  const _FillIn({required this.child});
  final Widget child;

  @override
  State<_FillIn> createState() => _FillInState();
}

class _FillInState extends State<_FillIn> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<double> _rise;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 240));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _rise = Tween<double>(
      begin: 3.0,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final duration = SrsMotion.resolve(context, const Duration(milliseconds: 240));
    _ctrl.duration = duration == Duration.zero ? const Duration(milliseconds: 1) : duration;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) => Opacity(
        opacity: _fade.value,
        child: Transform.translate(offset: Offset(0, _rise.value), child: child),
      ),
      child: widget.child,
    );
  }
}

/// Completed pair before the decision.
class SrsMovePair {
  const SrsMovePair(this.number, this.white, [this.black]);
  final int number;
  final String white;
  final String? black;
}

/// Builds a notation line from a list of moves leading to the current position.
class SrsNotationLine extends StatelessWidget {
  const SrsNotationLine({
    super.key,
    required this.moves,
    this.answerSan,
    this.showBlank = true,
    this.wide = false,
    this.wideWidth = 0,
  });

  /// List of SAN strings leading up to the current decision (plies 0..N-1).
  final List<String> moves;

  /// The answered SAN string if user played or revealed the move.
  final String? answerSan;

  /// Whether to show the decision slot (dashed blank or filled answer).
  final bool showBlank;

  final bool wide;
  final double wideWidth;

  @override
  Widget build(BuildContext context) {
    final c = context.srs;
    final fontSize = SrsText.lineSize(wide: wide, wideWidth: wideWidth);
    final moveStyle = SrsText.lineMove(fontSize, c.ink);
    final numStyle = SrsText.lineNumber(fontSize, c.ink3);
    final gapEm = fontSize * 0.42;
    final numGap = fontSize * 0.22;

    // Truncate long lines to at most the last 8 plies before current decision
    // (03-components.md:116). Starting on an even ply keeps the line on a move number rather
    // than mid-pair, which is what the leading ellipsis is there to explain.
    final int startPly;
    final List<String> visibleMoves;
    if (moves.length > 8) {
      final excess = moves.length - 8;
      startPly = excess.isEven ? excess : excess - 1;
      visibleMoves = moves.sublist(startPly);
    } else {
      startPly = 0;
      visibleMoves = moves;
    }

    final isStartTruncated = startPly > 0;
    final spans = <InlineSpan>[];

    if (isStartTruncated) {
      spans.add(TextSpan(text: '… ', style: numStyle));
    }

    // Build pairs from visibleMoves
    final int n = visibleMoves.length;
    final bool blackToMove = n.isOdd;
    final int completedCount = blackToMove ? n - 1 : n;

    for (var i = 0; i < completedCount; i += 2) {
      final pairNumber = ((startPly + i) ~/ 2) + 1;
      final whiteMove = visibleMoves[i];
      final blackMove = (i + 1 < n) ? visibleMoves[i + 1] : null;

      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: Padding(
            padding: EdgeInsets.only(right: gapEm),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('$pairNumber.', style: numStyle),
                SizedBox(width: numGap),
                SrsSan(whiteMove, style: moveStyle),
                if (blackMove != null) ...[
                  SizedBox(width: gapEm),
                  SrsSan(blackMove, style: moveStyle),
                ],
              ],
            ),
          ),
        ),
      );
    }

    // Decision pair (current ply)
    if (showBlank || answerSan != null) {
      final decisionNumber = ((startPly + n) ~/ 2) + 1;
      final Widget decisionChild;
      if (answerSan != null) {
        decisionChild = _FillIn(
          child: SrsSan(answerSan!, style: moveStyle.copyWith(color: c.accent)),
        );
      } else {
        decisionChild = SrsDashedBlank(fontSize: fontSize);
      }

      if (blackToMove) {
        // White move was visibleMoves.last
        final whiteMove = visibleMoves.last;
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: Padding(
              padding: EdgeInsets.only(right: gapEm),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('$decisionNumber.', style: numStyle),
                  SizedBox(width: numGap),
                  SrsSan(whiteMove, style: moveStyle),
                  SizedBox(width: gapEm),
                  decisionChild,
                ],
              ),
            ),
          ),
        );
      } else {
        // White to move
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: Padding(
              padding: EdgeInsets.only(right: gapEm),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('$decisionNumber.', style: numStyle),
                  SizedBox(width: numGap),
                  decisionChild,
                ],
              ),
            ),
          ),
        );
      }
    }

    final minHeight = fontSize * (wide ? 1.3 : 1.36) * 2;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: Text.rich(TextSpan(children: spans)),
    );
  }
}
