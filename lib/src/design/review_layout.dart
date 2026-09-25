// Review screen skeleton: one responsive layout, fixed regions, no layout shift between states.
// Adapted from design/flutter/review_layout.dart.
import 'package:chess_srs/src/design/board_background.dart';
import 'package:chess_srs/src/design/tokens.dart';
import 'package:flutter/widgets.dart';

/// Wrap the caller in SafeArea first: [LayoutBuilder] constraints here are the usable app area.
class SrsReviewLayout extends StatelessWidget {
  const SrsReviewLayout({
    super.key,
    required this.topBar,
    required this.board,
    required this.side,
    this.whiteAtBottom = true,
  });

  final Widget topBar;
  final bool whiteAtBottom;

  /// Build the board Stack (SrsBoardBackground + chessground + SrsMoveArrow) at exactly [size].
  final Widget Function(BuildContext context, double size, bool wide) board;

  /// Build the right/lower region with [SrsReviewSide].
  final Widget Function(BuildContext context, bool wide, double appWidth) side;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final wide = SrsLayout.isWide(box.maxWidth);
        final topH = wide ? SrsLayout.topbarWide : SrsLayout.topbarNarrow;
        final content = Size(box.maxWidth, box.maxHeight - topH);
        final b = SrsLayout.boardSize(content);

        final bar = SizedBox(
          height: topH,
          child: Padding(
            padding: wide
                ? const EdgeInsets.fromLTRB(SrsLayout.topbarPadLeftWide, 0, 20, 0)
                : const EdgeInsets.fromLTRB(16, 0, 4, 0),
            child: topBar,
          ),
        );

        if (wide) {
          return Column(
            children: [
              bar,
              Expanded(
                child: Padding(
                  padding: SrsLayout.reviewPaddingWide,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SrsBoardWithCoordinates(
                        size: b,
                        outside: true,
                        whiteAtBottom: whiteAtBottom,
                        board: board(context, b, true),
                      ),
                      const SizedBox(width: SrsLayout.wideColumnGap),
                      Expanded(
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: SrsLayout.wideSideMaxWidth),
                            // side column is exactly as tall as the board
                            child: SizedBox(height: b, child: side(context, true, box.maxWidth)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }

        return Column(
          children: [
            bar,
            Expanded(
              child: Padding(
                padding: SrsLayout.reviewPaddingNarrow,
                child: Column(
                  children: [
                    Center(
                      child: SrsBoardWithCoordinates(
                        size: b,
                        outside: false,
                        whiteAtBottom: whiteAtBottom,
                        board: board(context, b, false),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(6, 12, 6, 0),
                        child: side(context, false, box.maxWidth),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Fixed regions, top to bottom: meta, notation line (min height = 2 lines), slot (scrolls), actions.
/// The slot holds AT MOST ONE of: nothing | answer (correction) | note. It never changes the
/// height of the other regions, which is what keeps the board still.
class SrsReviewSide extends StatelessWidget {
  const SrsReviewSide({
    super.key,
    required this.wide,
    required this.lineFontSize,
    required this.meta,
    this.line,
    required this.slot,
    required this.actions,
    this.announcement,
  });

  final bool wide;
  final double lineFontSize;
  final Widget meta; // context label + "White to play" (stacked when wide, one row when narrow)
  final Widget? line; // SrsNotationLine or null if disabled
  final Widget slot; // answer OR note OR SizedBox.shrink()
  final Widget actions; // Skip on the left, Continue on the right; min height 56

  /// Optional polite live region, laid out with no effect on the fixed regions.
  /// See SrsLiveRegion and design/docs/04-screens-and-flows.md §6.
  final Widget? announcement;

  @override
  Widget build(BuildContext context) {
    final lineH = lineFontSize * (wide ? 1.3 : 1.36);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: wide ? 2 : 0),
          child: meta,
        ),
        if (line != null) ...[
          SizedBox(height: wide ? 22 : 8),
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: lineH * 2),
            child: line,
          ),
        ],
        Expanded(
          child: wide
              ? Padding(
                  padding: EdgeInsets.only(top: line != null ? 26 : 14),
                  child: SingleChildScrollView(child: slot),
                )
              : _BottomFade(
                  child: Padding(
                    padding: EdgeInsets.only(top: line != null ? 10 : 8, bottom: 22),
                    child: SingleChildScrollView(child: slot),
                  ),
                ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(padding: const EdgeInsets.fromLTRB(0, 6, 0, 4), child: actions),
        ),
        // Zero-size: present for assistive technology, absent from the layout.
        ?announcement,
      ],
    );
  }
}

/// Narrow layouts fade the last 22px of the slot instead of hard-clipping long notes.
class _BottomFade extends StatelessWidget {
  const _BottomFade({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final h = box.maxHeight;
      final stop = h.isFinite && h > 22 ? (h - 22) / h : 1.0;
      return ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (r) => LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [Color(0xFF000000), Color(0xFF000000), Color(0x00000000)],
          stops: [0, stop, 1],
        ).createShader(r),
        child: child,
      );
    },
  );
}
