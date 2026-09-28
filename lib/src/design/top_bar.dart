// Top bar: Scope button, due count, spacer, overflow button.
// Follows design/docs/03-components.md §2 and reference/index.html.
import 'package:chess_srs/src/design/primitives.dart';
import 'package:chess_srs/src/design/tokens.dart';
import 'package:flutter/material.dart' show Tooltip;
import 'package:flutter/widgets.dart';

/// Top bar with Scope selector, due count, and overflow menu.
class SrsTopBar extends StatelessWidget {
  const SrsTopBar({
    super.key,
    this.scopeTitle = '',
    this.dueCount = 0,
    this.showScopeAndDue = true,
    this.isPracticeMode = false,
    this.onScopePressed,
    this.onOverflowPressed,
    this.onExitPractice,
    this.isScopeExpanded = false,
    this.wide = false,
  });

  final String scopeTitle;
  final int dueCount;
  final bool showScopeAndDue;
  final bool isPracticeMode;
  final VoidCallback? onScopePressed;
  final VoidCallback? onOverflowPressed;
  final VoidCallback? onExitPractice;
  final bool isScopeExpanded;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final c = context.srs;

    return Row(
      children: [
        if (showScopeAndDue) ...[
          // 1. Scope button
          Flexible(
            fit: FlexFit.loose,
            child: Transform.translate(
              offset: const Offset(-10, 0),
              child: Tooltip(
                message: 'Studies & Scope',
                child: SrsPressable(
                  onPressed: onScopePressed,
                  semanticLabel: scopeTitle,
                  semanticsToggled: isScopeExpanded,
                  radius: 10,
                  builder: (context, hovered, pressed) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: hovered ? c.hairlineSoft : const Color(0x00000000),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            scopeTitle,
                            style: SrsText.scopeName(c.ink),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        CustomPaint(
                          size: const Size(12, 12),
                          painter: _ChevronPainter(color: c.ink2, isExpanded: isScopeExpanded),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(width: 6),

          // 2. Due count
          if (isPracticeMode) ...[
            // The `Practice` label is itself the way out. It used to be inert text with a separate
            // 12px `Exit Practice` button beside it -- a 168x16px target for the only exit from a
            // mode the user opted into, against the 44x44 minimum in 03-components.md §6, and two
            // controls where one says the same thing. `SrsPressable` enforces no minimum of its
            // own, so the 44px is asked for here.
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

        // 3. Overflow button (Library & Settings)
        Tooltip(
          message: 'Library and settings',
          child: SrsPressable(
            onPressed: onOverflowPressed,
            semanticLabel: 'Library and settings',
            radius: 999,
            builder: (context, hovered, pressed) => Container(
              width: 44,
              height: 44,
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

/// 12x12 chevron-down icon with stroke width 1.8.
class _ChevronPainter extends CustomPainter {
  const _ChevronPainter({required this.color, required this.isExpanded});
  final Color color;
  final bool isExpanded;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final path = Path();
    if (isExpanded) {
      // Chevron up: 2.5 7.5 -> 6 4 -> 9.5 7.5
      path.moveTo(size.width * 0.21, size.height * 0.62);
      path.lineTo(size.width * 0.5, size.height * 0.33);
      path.lineTo(size.width * 0.79, size.height * 0.62);
    } else {
      // Chevron down: 2.5 4.5 -> 6 8 -> 9.5 4.5
      path.moveTo(size.width * 0.21, size.height * 0.38);
      path.lineTo(size.width * 0.5, size.height * 0.67);
      path.lineTo(size.width * 0.79, size.height * 0.38);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ChevronPainter old) => old.color != color || old.isExpanded != isExpanded;
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
