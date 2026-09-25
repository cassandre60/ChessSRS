// Collapsible group, for the settings screen's `Advanced` section.
//
// Design source: the demo's `details.adv` — a summary row at the same rhythm as a setting
// row (16/500, padding 18/0) with a 14px chevron in `ink3` that rotates 180° when open,
// and the contents separated only by hairlines. No card, no fill, no shadow.
//
// Kept in the design system because the rotation, the focus ring and the 44px touch
// target are the same contract everywhere it is used.
import 'dart:math' as math;

import 'package:chess_srs/src/design/primitives.dart';
import 'package:chess_srs/src/design/tokens.dart';
import 'package:flutter/widgets.dart';

class SrsDisclosure extends StatefulWidget {
  const SrsDisclosure({
    super.key,
    required this.title,
    required this.child,
    this.initiallyExpanded = false,
    this.help,
  });

  final String title;
  final Widget child;
  final bool initiallyExpanded;

  /// Optional second line under the title, at the setting-help size.
  final String? help;

  @override
  State<SrsDisclosure> createState() => _SrsDisclosureState();
}

class _SrsDisclosureState extends State<SrsDisclosure> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final c = context.srs;

    final header = Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.title, style: SrsText.settingLabel(c.ink)),
              if (widget.help != null) ...[
                const SizedBox(height: 3),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Text(widget.help!, style: SrsText.settingHelp(c.ink2)),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        CustomPaint(
          size: const Size(14, 14),
          painter: _ChevronDownPainter(color: c.ink3, expanded: _expanded),
        ),
      ],
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.hairlineSoft)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SrsPressable(
            onPressed: () => setState(() => _expanded = !_expanded),
            semanticLabel: widget.title,
            semanticsToggled: _expanded,
            radius: 10,
            builder: (context, hovered, _) => Container(
              constraints: const BoxConstraints(minHeight: SrsLayout.minTouchTarget),
              padding: const EdgeInsets.symmetric(vertical: 18),
              color: hovered ? c.hairlineSoft : const Color(0x00000000),
              child: header,
            ),
          ),
          // Offstage rather than absent: the design collapses content, and removing the
          // subtree would discard the controls' state on every open.
          Offstage(
            offstage: !_expanded,
            child: Semantics(
              hidden: !_expanded,
              child: Padding(padding: const EdgeInsets.only(bottom: 4), child: widget.child),
            ),
          ),
        ],
      ),
    );
  }
}

/// 14x14 chevron that points down when closed and up when open.
class _ChevronDownPainter extends CustomPainter {
  const _ChevronDownPainter({required this.color, required this.expanded});

  final Color color;
  final bool expanded;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Draw pointing down, then rotate the whole thing when open, so the two states are
    // the same path and cannot drift apart.
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    if (expanded) canvas.rotate(math.pi);
    canvas.translate(-size.width / 2, -size.height / 2);

    final path = Path()
      ..moveTo(size.width * 0.22, size.height * 0.375)
      ..lineTo(size.width * 0.5, size.height * 0.625)
      ..lineTo(size.width * 0.78, size.height * 0.375);
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ChevronDownPainter old) => old.color != color || old.expanded != expanded;
}
