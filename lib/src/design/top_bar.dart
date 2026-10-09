// Top bar: colour squares, due count, spacer, overflow button.
// Follows design/docs/03-components.md §2 and reference/index.html.
import 'package:chess_srs/src/design/primitives.dart';
import 'package:chess_srs/src/design/tokens.dart';
import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter/material.dart' show Tooltip;
import 'package:flutter/widgets.dart';

/// Top bar with the two colour switches, due count, and overflow menu.
///
/// The opener is a white square and a black square rather than the scope's
/// name: the app trains one repertoire colour at a time, and a name would have
/// to change as the user moved between them ("All studies", "French Defence",
/// a study title). The squares say the same two things forever.
class SrsTopBar extends StatelessWidget {
  const SrsTopBar({
    super.key,
    this.wordmark,
    this.activeSide,
    this.onSidePressed,
    this.dueCount = 0,
    this.showScopeAndDue = true,
    this.isPracticeMode = false,
    this.onOverflowPressed,
    this.onExitPractice,
    this.wide = false,
  });

  /// Shown in place of the squares on a screen with no scope to switch, such as
  /// first launch, where the two colours would be an offer with nothing behind
  /// it.
  final String? wordmark;

  /// The colour whose drawer is open and whose positions are being reviewed.
  /// Null when the current scope names neither colour, which only happens
  /// before the first study is loaded.
  final Side? activeSide;

  /// Called with the square that was tapped. Selecting the colour already
  /// active re-opens its drawer rather than doing nothing.
  final void Function(Side side)? onSidePressed;

  final int dueCount;
  final bool showScopeAndDue;
  final bool isPracticeMode;
  final VoidCallback? onOverflowPressed;
  final VoidCallback? onExitPractice;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final c = context.srs;

    return Row(
      children: [
        if (showScopeAndDue) ...[
          // 1. Colour squares
          Transform.translate(
            offset: const Offset(-10, 0),
            child: wordmark != null
                ? Text(wordmark!, style: SrsText.scopeName(c.ink))
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ColourSquare(
                        side: Side.white,
                        isActive: activeSide == Side.white,
                        onPressed: onSidePressed,
                      ),
                      const SizedBox(width: 2),
                      _ColourSquare(
                        side: Side.black,
                        isActive: activeSide == Side.black,
                        onPressed: onSidePressed,
                      ),
                    ],
                  ),
          ),

          const SizedBox(width: 6),

          // 2. Due count
          if (isPracticeMode) ...[
            // The `Practice` label is itself the way out. It used to be inert text with a separate
            // 12px `Exit Practice` button beside it -- a 168x16px target for the only exit from a
            // mode the user opted into, against the minimum target in 03-components.md §6 (now
            // `SrsLayout.minTouchTarget`, 48), and two controls where one says the same thing.
            // `SrsPressable` enforces no minimum of its own, so the size is asked for here.
            SrsPressable(
              onPressed: onExitPractice,
              semanticLabel: 'Exit practice',
              radius: 8,
              builder: (_, hover, _) => Container(
                constraints: const BoxConstraints(minHeight: SrsLayout.minTouchTarget),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: hover ? c.hairlineSoft : const Color(0x00000000),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ExcludeSemantics(
                  // Excluded for the same reason as [SrsTextButton] and [SrsPillButton]: the
                  // pressable already announces `Exit practice`, and without this the visible text
                  // merges with it and a screen reader says "Exit practice Practice".
                  child: Text(
                    'Practice',
                    style: SrsText.due(c.accent).copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ] else
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '$dueCount', style: SrsText.dueNumber(c.ink)),
                  TextSpan(text: ' due', style: SrsText.due(c.ink2)),
                ],
              ),
            ),
        ],

        const Spacer(),

        // 3. Overflow button (Settings)
        Tooltip(
          message: 'Settings',
          child: SrsPressable(
            onPressed: onOverflowPressed,
            semanticLabel: 'Settings',
            radius: 999,
            builder: (context, hovered, pressed) => Container(
              // Was a hardcoded 44. The token it should have read went to 48, and this is the one
              // control the change walked straight past: a literal, in a file the token also lives
              // in. It now reads the token like its neighbours, so the two cannot drift again.
              width: SrsLayout.minTouchTarget,
              height: SrsLayout.minTouchTarget,
              decoration: BoxDecoration(
                color: hovered ? c.hairlineSoft : const Color(0x00000000),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: CustomPaint(
                  size: const Size(20, 20),
                  painter: _ThreeDotsPainter(color: c.ink),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// One square of the colour switch: white or black, ringed when it is the
/// colour being reviewed.
///
/// The white square is light in both light and dark themes (with a hairline
/// border so it stays distinct on a light bar). The black square is dark in
/// both themes (with a hairline border so it stays distinct on a dark bar).
/// The active square carries an accent ring (width 2).
class _ColourSquare extends StatelessWidget {
  const _ColourSquare({required this.side, required this.isActive, this.onPressed});

  final Side side;
  final bool isActive;
  final void Function(Side side)? onPressed;

  static const double _edge = 20;
  static const double _radius = 5;

  @override
  Widget build(BuildContext context) {
    final c = context.srs;
    final label = side == Side.white ? 'White repertoire' : 'Black repertoire';
    final fillColor = side == Side.white
        ? (c.isDark ? const Color(0xFFECEEF1) : const Color(0xFFFFFFFF))
        : (c.isDark ? const Color(0xFF10141B) : const Color(0xFF151A22));

    return Tooltip(
      message: label,
      child: SrsPressable(
        onPressed: onPressed == null ? null : () => onPressed!(side),
        semanticLabel: label,
        semanticsToggled: isActive,
        radius: 8,
        builder: (context, hovered, pressed) => Container(
          // The padding is what carries the square up to the minimum target
          // (`03-components.md` §6); the square itself stays small so the two
          // read as a pair rather than as two buttons.
          padding: const EdgeInsets.all((SrsLayout.minTouchTarget - _edge) / 2),
          decoration: BoxDecoration(
            color: hovered ? c.hairlineSoft : const Color(0x00000000),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: fillColor,
              borderRadius: BorderRadius.circular(_radius),
              border: Border.all(color: isActive ? c.accent : c.hairline, width: isActive ? 2 : 1),
            ),
            child: const SizedBox(width: _edge, height: _edge),
          ),
        ),
      ),
    );
  }
}

/// 20x20 horizontal 3-dots painter (dots r=1.7 at x=4, 10, 16, y=10).
class _ThreeDotsPainter extends CustomPainter {
  const _ThreeDotsPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    const r = 1.7;
    final cy = size.height / 2;
    canvas.drawCircle(Offset(size.width * 0.2, cy), r, paint);
    canvas.drawCircle(Offset(size.width * 0.5, cy), r, paint);
    canvas.drawCircle(Offset(size.width * 0.8, cy), r, paint);
  }

  @override
  bool shouldRepaint(_ThreeDotsPainter old) => old.color != color;
}
