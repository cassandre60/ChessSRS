// Minimal, Material-free primitives: pill button, text button, segmented
// control, switch, keyboard chip, accent dots.
// Only package:flutter/widgets.dart.
// Adapted from design/flutter/primitives.dart.
import 'package:chess_srs/src/design/hatch.dart';
import 'package:chess_srs/src/design/tokens.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

bool get _isDesktopPlatform =>
    defaultTargetPlatform == TargetPlatform.linux ||
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.windows;

// ---------------------------------------------------------------------------
// SrsPressable — base interactive wrapper
// ---------------------------------------------------------------------------
class SrsPressable extends StatefulWidget {
  const SrsPressable({
    super.key,
    required this.onPressed,
    required this.builder,
    this.semanticLabel,
    this.radius = 999,
    this.pressScale = 1,
    this.semanticsToggled,
  });
  final VoidCallback? onPressed;
  final Widget Function(BuildContext context, bool hovered, bool pressed) builder;
  final String? semanticLabel;
  final double radius;
  final double pressScale;
  final bool? semanticsToggled;

  @override
  State<SrsPressable> createState() => _SrsPressableState();
}

class _SrsPressableState extends State<SrsPressable> {
  bool _hover = false;
  bool _down = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final c = context.srs;
    final enabled = widget.onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      toggled: widget.semanticsToggled,
      label: widget.semanticLabel,
      // The tap action and the label are declared here rather than inherited, so the
      // node this control exposes is exactly one: a button whose label is announced
      // once. Without [excludeSemantics] the builder's own `Text` labels the node a
      // second time ("Continue, Continue") and the inner [GestureDetector] adds a
      // duplicate tap action.
      onTap: enabled ? widget.onPressed : null,
      excludeSemantics: true,
      child: FocusableActionDetector(
        enabled: enabled,
        mouseCursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onShowHoverHighlight: (v) => setState(() => _hover = v),
        onShowFocusHighlight: (v) => setState(() => _focus = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed?.call();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled ? (_) => setState(() => _down = true) : null,
          onTapCancel: () => setState(() => _down = false),
          onTapUp: (_) => setState(() => _down = false),
          onTap: widget.onPressed,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedScale(
                scale: _down ? widget.pressScale : 1,
                duration: SrsMotion.resolve(context, SrsMotion.press),
                curve: SrsMotion.ease,
                child: widget.builder(context, _hover, _down),
              ),
              if (_focus)
                Positioned(
                  left: -2,
                  top: -2,
                  right: -2,
                  bottom: -2,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(widget.radius + 2),
                        border: Border.all(color: c.accent, width: 2),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SrsPillButton — filled ink pill, 46dp tall
// ---------------------------------------------------------------------------
class SrsPillButton extends StatelessWidget {
  const SrsPillButton({super.key, required this.label, required this.onPressed, this.shortcut});
  final String label;
  final VoidCallback? onPressed;
  final String? shortcut;

  @override
  Widget build(BuildContext context) {
    final c = context.srs;
    return SrsPressable(
      onPressed: onPressed,
      semanticLabel: label,
      pressScale: SrsMotion.pressScale,
      builder: (_, _, _) => Container(
        height: SrsLayout.pillHeight,
        padding: const EdgeInsets.symmetric(horizontal: SrsLayout.pillPaddingH),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(999)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Excluded: SrsPressable already announces `label`.
            ExcludeSemantics(child: Text(label, style: SrsText.button(c.ground))),
            if (shortcut != null && _isDesktopPlatform) ...[
              const SizedBox(width: 12),
              SrsKbd(shortcut!, onInk: true),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SrsTextButton — borderless text action
// ---------------------------------------------------------------------------
class SrsTextButton extends StatelessWidget {
  const SrsTextButton({super.key, required this.label, required this.onPressed, this.shortcut});
  final String label;
  final VoidCallback? onPressed;
  final String? shortcut;

  @override
  Widget build(BuildContext context) {
    final c = context.srs;
    return SrsPressable(
      onPressed: onPressed,
      semanticLabel: label,
      radius: 10,
      builder: (_, hover, _) => Container(
        constraints: const BoxConstraints(minHeight: SrsLayout.minTouchTarget),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: hover ? c.hairlineSoft : const Color(0x00000000),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Excluded: SrsPressable already announces `label`.
            ExcludeSemantics(child: Text(label, style: SrsText.textButton(hover ? c.ink : c.ink2))),
            if (shortcut != null && _isDesktopPlatform) ...[
              const SizedBox(width: 10),
              SrsKbd(shortcut!),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SrsKbd — keyboard-hint chip
// ---------------------------------------------------------------------------
class SrsKbd extends StatelessWidget {
  const SrsKbd(this.text, {super.key, this.onInk = false});
  final String text;
  final bool onInk;

  @override
  Widget build(BuildContext context) {
    if (!_isDesktopPlatform) {
      return const SizedBox.shrink();
    }
    final c = context.srs;
    final fg = onInk ? c.ground : c.ink2;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: onInk ? c.ground.withValues(alpha: 0.16) : c.hairlineSoft,
        borderRadius: BorderRadius.circular(5),
        border: onInk ? null : Border.all(color: c.hairline, width: 1),
      ),
      child: Text(text, style: SrsText.kbd(fg)),
    );
  }
}

// ---------------------------------------------------------------------------
// SrsSegmented — pill segmented control
// ---------------------------------------------------------------------------
class SrsSegmented<T> extends StatelessWidget {
  const SrsSegmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });
  final Map<T, String> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.srs;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.hairlineSoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.hairline, width: 1),
      ),
      child: Wrap(
        children: [
          for (final e in options.entries)
            SrsPressable(
              onPressed: () => onChanged(e.key),
              semanticLabel: e.value,
              semanticsToggled: e.key == value,
              builder: (_, hover, _) => Container(
                constraints: const BoxConstraints(minWidth: 38),
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                decoration: BoxDecoration(
                  color: e.key == value ? c.ink : const Color(0x00000000),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Center(
                  widthFactor: 1,
                  child: Text(
                    e.value,
                    style: SrsText.seg(e.key == value ? c.ground : (hover ? c.ink : c.ink2)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SrsSwitch — 44×26 toggle
// ---------------------------------------------------------------------------
class SrsSwitch extends StatelessWidget {
  const SrsSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
  });
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.srs;
    final d = SrsMotion.resolve(context, SrsMotion.toggle);
    final enabled = onChanged != null;
    return SrsPressable(
      onPressed: enabled ? () => onChanged!(!value) : null,
      semanticLabel: semanticLabel,
      semanticsToggled: value,
      radius: 13,
      builder: (_, _, _) => Container(
        // Demo `.tog::before` expands the hit area to 44px tall.
        width: 44,
        height: 44,
        alignment: Alignment.center,
        child: AnimatedContainer(
          duration: d,
          curve: SrsMotion.ease,
          width: 44,
          height: 26,
          decoration: BoxDecoration(
            color: value ? c.ink : c.hairline,
            borderRadius: BorderRadius.circular(13),
          ),
          child: AnimatedAlign(
            duration: d,
            curve: SrsMotion.ease,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: value ? c.ground : c.surface,
                  border: value ? null : Border.all(color: c.hairline, width: 1),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SrsRowRule — vertical hairline separating groups inside a horizontal control row
// ---------------------------------------------------------------------------
class SrsRowRule extends StatelessWidget {
  const SrsRowRule({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.srs;
    return Container(
      width: 1,
      height: 20,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: c.hairline,
    );
  }
}

// ---------------------------------------------------------------------------
// SrsAccentDots — accent colour picker
// ---------------------------------------------------------------------------
class SrsAccentDots extends StatelessWidget {
  const SrsAccentDots({super.key, required this.value, required this.onChanged});
  final SrsAccent value;
  final ValueChanged<SrsAccent> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.srs;
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: c.hairlineSoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.hairline, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final a in SrsAccent.values) ...[
            SrsPressable(
              onPressed: () => onChanged(a),
              semanticLabel: a.name,
              semanticsToggled: a == value,
              builder: (_, _, _) {
                final color = c.isDark ? kSrsAccents[a]!.dark : kSrsAccents[a]!.light;
                return SizedBox(
                  width: 24,
                  height: 24,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                        ),
                      ),
                      if (a == value)
                        Positioned(
                          left: -3.5,
                          top: -3.5,
                          right: -3.5,
                          bottom: -3.5,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: c.ink, width: 1.5),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
            if (a != SrsAccent.values.last) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SrsLogoMark — 22x22 geometric ChessSRS square mark with diagonal hatching
// ---------------------------------------------------------------------------
class SrsLogoMark extends StatelessWidget {
  const SrsLogoMark({super.key, this.size = 22, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.srs;
    final markColor = color ?? c.ink;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _SrsLogoPainter(color: markColor)),
    );
  }
}

class _SrsLogoPainter extends CustomPainter {
  const _SrsLogoPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 22.0;
    final strokeWidth = 1.5 * scale;

    final borderPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    final half = strokeWidth / 2;
    canvas.drawRect(
      Rect.fromLTWH(half, half, size.width - strokeWidth, size.height - strokeWidth),
      borderPaint,
    );

    final qW = 9.5 * scale;
    final qH = 9.5 * scale;

    final trRect = Rect.fromLTWH(11.0 * scale, 1.5 * scale, qW, qH);
    canvas.save();
    canvas.clipRect(trRect);
    paintHatch(
      canvas,
      Size(size.width, size.height),
      color: color,
      gap: 2.4 * scale,
      width: 0.9 * scale,
    );
    canvas.restore();

    final blRect = Rect.fromLTWH(1.5 * scale, 11.0 * scale, qW, qH);
    canvas.save();
    canvas.clipRect(blRect);
    paintHatch(
      canvas,
      Size(size.width, size.height),
      color: color,
      gap: 2.4 * scale,
      width: 0.9 * scale,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SrsLogoPainter old) => old.color != color;
}

// ---------------------------------------------------------------------------
// SrsPageHead — demo `.set-head` page header
// ---------------------------------------------------------------------------
/// Demo `.set-head`: a horizontal bar (padding 8/12) holding a back
/// text-button — a painted 16px chevron (stroke 1.8, round caps) plus the
/// destination label — with an optional trailing action.
class SrsPageHead extends StatelessWidget {
  const SrsPageHead({super.key, required this.label, required this.onBack, this.trailing});

  /// Destination named in words, e.g. `Review`, `Library`.
  final String label;
  final VoidCallback? onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.srs;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          SrsPressable(
            onPressed: onBack,
            semanticLabel: 'Back to $label',
            radius: 10,
            builder: (_, hover, _) => Container(
              constraints: const BoxConstraints(minHeight: SrsLayout.minTouchTarget),
              padding: const EdgeInsets.only(left: 8, right: 12, top: 10, bottom: 10),
              decoration: BoxDecoration(
                color: hover ? c.hairlineSoft : const Color(0x00000000),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CustomPaint(
                    size: const Size(16, 16),
                    painter: SrsBackChevronPainter(color: hover ? c.ink : c.ink2),
                  ),
                  const SizedBox(width: 2),
                  // Excluded: SrsPressable already announces the destination.
                  ExcludeSemantics(
                    child: Text(label, style: SrsText.textButton(hover ? c.ink : c.ink2)),
                  ),
                ],
              ),
            ),
          ),
          if (trailing != null) ...[const Spacer(), trailing!],
        ],
      ),
    );
  }
}

/// Painted back chevron matching the demo's `.set-head` svg:
/// `M10 3 L5 8 L10 13` in a 16px box, stroke 1.8, round caps and joins.
class SrsBackChevronPainter extends CustomPainter {
  const SrsBackChevronPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 16;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.8 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
    canvas.drawPath(
      Path()
        ..moveTo(10 * s, 3 * s)
        ..lineTo(5 * s, 8 * s)
        ..lineTo(10 * s, 13 * s),
      paint,
    );
  }

  @override
  bool shouldRepaint(SrsBackChevronPainter old) => old.color != color;
}
