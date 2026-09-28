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
    this.onLongPress,
    this.onSecondaryTap,
  });
  final VoidCallback? onPressed;
  final Widget Function(BuildContext context, bool hovered, bool pressed) builder;
  final String? semanticLabel;
  final double radius;
  final double pressScale;
  final bool? semanticsToggled;

  /// Optional secondary entry points, for the rows that keep their actions off the row body
  /// (design/docs/03-components.md §6.4: a long-press, or a secondary click on desktop).
  final VoidCallback? onLongPress;
  final VoidCallback? onSecondaryTap;

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
          // Both live on this one detector on purpose. Wrapping a separate GestureDetector around
          // the pressable instead loses the gesture arena to [onTap], so a long-press arrives as a
          // tap and selects the row instead of opening its actions.
          onLongPress: widget.onLongPress,
          onSecondaryTap: widget.onSecondaryTap,
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
  const SrsPillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.shortcut,
    this.selected = false,
    this.expand = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final String? shortcut;

  /// Marks the pill as the current one in a set of mutually exclusive options, and turns it from
  /// a command into a toggle. Unselected pills go to a hairline outline so the set reads as a
  /// group; a filled pill next to outlined ones would read as the only action.
  final bool selected;

  /// Fills the width it is given, for the pill that is the only action on a sheet.
  ///
  /// Wrapping the pill in a `SizedBox(width: double.infinity)` does not achieve this: the pressable
  /// builds its child inside a `Stack`, which hands it loose constraints, so the pill shrink-wraps
  /// to its label however wide its parent is. The width has to be asked for here.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final c = context.srs;
    return SrsPressable(
      onPressed: onPressed,
      semanticLabel: label,
      semanticsToggled: selected,
      pressScale: SrsMotion.pressScale,
      builder: (_, _, _) => Container(
        width: expand ? double.infinity : null,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        decoration: BoxDecoration(
          color: selected ? c.accent : c.ink,
          borderRadius: BorderRadius.circular(999),
          border: selected ? null : Border.all(color: c.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Excluded: SrsPressable already announces `label`.
            //
            // `ground` in both states, not `ink` when unselected: the background is `ink` (or
            // `accent`) either way, so an `ink` label renders ink on ink and the button reads as
            // an empty black pill.
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
  /// Single-select. [onChanged] reports the chosen key.
  const SrsSegmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  }) : values = null,
       onToggled = null;

  /// Multi-select, for the settings where more than one option can be on at once -- the opening
  /// explorer's speeds, ratings and game modes. [onToggled] reports the key and whether it is now
  /// on, so the caller owns the set rather than this control re-deriving it.
  ///
  /// The design specifies a segmented control only for the exclusive case, so this is the same
  /// control in the same appearance rather than a second one. The alternative was leaving Material
  /// filter chips in the middle of an otherwise-Diagram sheet.
  const SrsSegmented.multi({
    super.key,
    required this.options,
    required this.values,
    required this.onToggled,
  }) : value = null,
       onChanged = null;

  // `values` is an Iterable rather than a Set because the preferences that reach here hold
  // `ISet`, which implements Iterable and not Set. Membership is a linear scan over at most nine
  // options, so nothing is lost by not insisting on a Set.

  final Map<T, String> options;

  /// The selected key, in the single-select form. Null in the multi-select form.
  final T? value;

  /// The selected keys, in the multi-select form. Null in the single-select form.
  final Iterable<T>? values;

  final ValueChanged<T>? onChanged;
  final void Function(T key, bool on)? onToggled;

  bool _isOn(T key) => values != null ? values!.contains(key) : key == value;

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
            Builder(
              builder: (context) {
                final isOn = _isOn(e.key);
                return SrsPressable(
                  onPressed: () => values == null ? onChanged!(e.key) : onToggled!(e.key, !isOn),
                  semanticLabel: e.value,
                  semanticsToggled: isOn,
                  builder: (_, hover, _) => Container(
                    constraints: const BoxConstraints(minWidth: 38),
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                    decoration: BoxDecoration(
                      color: isOn ? c.ink : const Color(0x00000000),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Center(
                      widthFactor: 1,
                      child: Text(
                        e.value,
                        style: SrsText.seg(isOn ? c.ground : (hover ? c.ink : c.ink2)),
                      ),
                    ),
                  ),
                );
              },
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
// SrsSettingsRow — one row in a settings list
//
// Extracted from the private copy in `srs_settings_screen.dart` so the whole settings tree can
// share one row. Two shapes, from the same widget: a control on the right (a switch, a segmented
// control) and a navigation row with an optional value.
//
// Reflows rather than overflowing: below 520 the trailing control drops under the text, which is
// what design/docs/03-components.md asks for ("the settings rows stack under 520") and what
// design/docs/04-screens-and-flows.md §6 requires ("nothing requires horizontal scrolling").
// ---------------------------------------------------------------------------
class SrsSettingsRow extends StatelessWidget {
  const SrsSettingsRow({
    super.key,
    required this.label,
    this.labelWidget,
    this.leading,
    this.help,
    this.value,
    this.control,
    this.preview,
    this.selected,
    this.onTap,
    this.enabled = true,
    this.destructive = false,
  });

  final String label;

  /// Richer label, for the rows whose label is not plain text -- a colour swatch beside a name,
  /// say. Takes precedence over [label], which is then only the accessibility label.
  final Widget? labelWidget;

  /// Sits at the left of the row. Reserved for a mark that carries data -- a log entry's
  /// severity -- rather than a category icon, which the design's text-led rows do not use.
  final Widget? leading;

  /// Second line under the label. Wrapped at 360px so a long sentence cannot stretch the row.
  final String? help;

  /// Right-hand text for a navigation row, e.g. the current setting's name.
  final String? value;

  /// Right-hand control for a setting row: a switch, a segmented control, a picker.
  final Widget? control;

  /// Rendered under the label, full width. For the choice rows that show what an option looks
  /// like -- a board thumbnail, a piece set.
  final Widget? preview;

  /// Draws the selected marker on a choice row. Null leaves the row unmarked.
  final bool? selected;

  final VoidCallback? onTap;

  final bool enabled;

  /// Renders the label in the warning colour, for sign-out and delete.
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final c = context.srs;
    // No danger token exists in the palette, and the demo's own `.warn` is plain `ink2` at a
    // smaller size -- a destructive action is signalled by its wording and its confirm dialog,
    // not by painting the label red. `destructive` therefore only reserves the intent for
    // callers; it deliberately does not recolour the row.
    final labelColor = enabled ? c.ink : c.ink3;

    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(child: labelWidget ?? Text(label, style: SrsText.rowName(labelColor))),
            if (selected ?? false) ...[
              const SizedBox(width: 12),
              // A filled dot rather than a tick: the design marks selection with the accent, and
              // a tick next to a switch reads as "enabled" rather than "chosen".
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
              ),
            ],
          ],
        ),
        if (help != null) ...[
          const SizedBox(height: 3),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Text(help!, style: SrsText.rowSub(c.ink2).copyWith(height: 1.4)),
          ),
        ],
        if (preview != null) ...[const SizedBox(height: 12), preview!],
      ],
    );

    final trailing =
        control ?? (value != null ? Text(value!, style: SrsText.rowSub(c.ink2)) : null);

    final row = LayoutBuilder(
      builder: (context, constraints) {
        final stacked = trailing != null && constraints.maxWidth < 520;
        if (trailing == null) return text;
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [text, const SizedBox(height: 12), trailing],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: text),
            const SizedBox(width: 16),
            trailing,
          ],
        );
      },
    );

    final withLeading = leading == null
        ? row
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              leading!,
              const SizedBox(width: 14),
              Expanded(child: row),
            ],
          );

    final body = Padding(padding: const EdgeInsets.symmetric(vertical: 18), child: withLeading);

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.hairlineSoft)),
      ),
      child: onTap == null
          ? body
          : SrsPressable(
              onPressed: enabled ? onTap : null,
              semanticLabel: label,
              radius: 0,
              builder: (context, hovered, _) => ColoredBox(
                color: hovered ? c.hairlineSoft : const Color(0x00000000),
                child: body,
              ),
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// SrsGroupHeader — the uppercase label above a group of settings rows
// ---------------------------------------------------------------------------
class SrsGroupHeader extends StatelessWidget {
  const SrsGroupHeader(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final c = context.srs;
    return Padding(
      padding: const EdgeInsets.only(top: 28, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: SrsText.groupTitle(c.ink3).copyWith(letterSpacing: 1.1),
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

// ---------------------------------------------------------------------------
// SrsIconButton — a square action in a page head
//
// design/docs/03-components.md gives the size rule rather than a component: touch targets are
// 44px (02 §6), so the box is `minTouchTarget` square with the icon centred and no visible
// chrome until hover. It exists because the log screens need head actions and the only
// alternative was a Material `IconButton` inside a Diagram head.
// ---------------------------------------------------------------------------
class SrsIconButton extends StatelessWidget {
  const SrsIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.tint,
  });

  final IconData icon;

  /// Doubles as the accessibility name: a bare icon button has nothing else to announce.
  final String tooltip;

  final VoidCallback? onPressed;

  /// Overrides the icon colour, for a destructive action.
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final c = context.srs;
    return SrsPressable(
      onPressed: onPressed,
      semanticLabel: tooltip,
      radius: 10,
      builder: (context, hovered, _) => Container(
        constraints: const BoxConstraints(
          minWidth: SrsLayout.minTouchTarget,
          minHeight: SrsLayout.minTouchTarget,
        ),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: hovered ? c.hairlineSoft : const Color(0x00000000),
          borderRadius: BorderRadius.circular(10),
        ),
        child: ExcludeSemantics(
          child: Icon(icon, size: 20, color: tint ?? (hovered ? c.ink : c.ink2)),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SrsSheetRow — a text row for the Library and study-actions sheets
// ---------------------------------------------------------------------------

/// One text row of a sheet: a label, an optional sub line, an optional trailing widget.
///
/// design/docs/03-components.md §7 gives the Library sheet's rows as `16/500` with `14/20`
/// padding, and §12 puts the study actions in "a Library-style sheet of text rows (16/500, no
/// icons)". Both sheets build from this so they cannot drift apart — they were separate
/// hand-rolled `InkWell`s, and one of them had already moved to 15.5 while the other had not.
///
/// The trailing slot is left to the caller because the two sheets disagree on purpose: §7 gives
/// every Library row a 14px chevron, while §12's action rows carry no icon at all.
class SrsSheetRow extends StatelessWidget {
  const SrsSheetRow({
    super.key,
    required this.label,
    required this.onPressed,
    this.subtitle,
    this.trailing,
  });

  final String label;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.srs;
    return SrsPressable(
      onPressed: onPressed,
      semanticLabel: label,
      radius: 10,
      builder: (context, hovered, pressed) => Container(
        color: hovered ? c.hairlineSoft : const Color(0x00000000),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: SrsText.settingLabel(c.ink)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: SrsText.sheetSub(c.ink3)),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
          ],
        ),
      ),
    );
  }
}
