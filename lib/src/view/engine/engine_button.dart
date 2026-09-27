import 'dart:math' as math;

import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/model/common/eval.dart';
import 'package:chess_srs/src/model/engine/engine_utils.dart';
import 'package:chess_srs/src/model/engine/evaluation_preferences.dart';
import 'package:chess_srs/src/model/engine/position_evaluator.dart';
import 'package:chess_srs/src/utils/l10n_context.dart';
import 'package:chess_srs/src/widgets/buttons.dart';
import 'package:chess_srs/src/widgets/popover.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:material_ui/material_ui.dart';

/// A button to toggle engine evaluation and show engine depth.
class EngineButton extends ConsumerStatefulWidget {
  const EngineButton({required this.filters, this.onTap, this.savedEval, this.goDeeper});

  final EngineEvaluationFilters filters;

  final ClientEval? savedEval;

  final VoidCallback? onTap;

  final VoidCallback? goDeeper;

  @override
  ConsumerState<EngineButton> createState() => _EngineButtonState();
}

class _EngineButtonState extends ConsumerState<EngineButton> {
  late Color fromChipColor;
  Color? toChipColor;

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(engineEvaluationPreferencesProvider);
    final (:engine, :engineSpec, eval: localEval, :isComputing, currentWork: _) = ref.watch(
      engineEvaluationProvider(widget.filters),
    );
    final eval = pickBestClientEval(localEval: localEval, savedEval: widget.savedEval);

    final srs = SrsTheme.maybeOf(context);
    final accent = srs?.accent ?? ColorScheme.of(context).primary;
    final inactiveColor =
        srs?.ink2 ?? IconTheme.of(context).color ?? TextTheme.of(context).bodyMedium!.color!;

    final newChipColor = prefs.isEnabled
        ? isComputing
              ? accent
              : accent.withValues(alpha: 0.65)
        : inactiveColor;

    fromChipColor = toChipColor ?? newChipColor;
    toChipColor = newChipColor;

    final textColor = prefs.isEnabled ? accent : inactiveColor;

    final loadingIndicator = SpinKitFadingFour(color: textColor.withValues(alpha: 0.7), size: 10);

    const microChipSize = 28.0;
    final iconTextStyle = TextStyle(
      color: textColor,
      fontFeatures: const [FontFeature.tabularFigures()],
      fontWeight: FontWeight.w600,
      fontSize: 11,
    );

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        SemanticIconButton(
          semanticsLabel: context.l10n.toggleLocalEvaluation,
          onPressed: widget.onTap,
          onLongPress: () {
            showPopover(
              context: context,
              bodyBuilder: (_) {
                return _EnginePopup(goDeeper: widget.goDeeper, filters: widget.filters);
              },
              direction: PopoverDirection.top,
              width: 250,
              backgroundColor:
                  srs?.surface ??
                  DialogTheme.of(context).backgroundColor ??
                  ColorScheme.of(context).surfaceContainerHigh,
              transitionDuration: Duration.zero,
              popoverTransitionBuilder: (_, child) => child,
            );
          },
          icon: Badge(
            offset: const Offset(4, -7),
            backgroundColor: ColorScheme.of(context).tertiaryContainer,
            textColor: ColorScheme.of(context).onTertiaryContainer,
            label: prefs.isEnabled && eval is CloudEval ? const Text('CLOUD') : null,
            textStyle: const TextStyle(fontSize: 8),
            isLabelVisible: prefs.isEnabled && eval is CloudEval,
            child: Stack(
              alignment: Alignment.center,
              children: [
                TweenAnimationBuilder<Color?>(
                  curve: Curves.easeInOut,
                  tween: ColorTween(begin: fromChipColor, end: toChipColor),
                  duration: const Duration(milliseconds: 300),
                  builder: (BuildContext context, Color? color, Widget? _) {
                    return CustomPaint(
                      size: const Size(microChipSize, microChipSize),
                      painter: MicroChipPainter(color ?? toChipColor!),
                    );
                  },
                ),
                SizedBox(
                  width: microChipSize,
                  height: microChipSize,
                  child: RepaintBoundary(
                    child: Center(
                      child: prefs.isEnabled
                          ? eval is CloudEval
                                ? Text('${math.min(99, eval.depth)}', style: iconTextStyle)
                                : switch (engine) {
                                    // No engine has been asked for yet.
                                    null => Text('-', style: iconTextStyle),
                                    AsyncError() => Text('!', style: iconTextStyle),
                                    AsyncValue(isLoading: true) => loadingIndicator,
                                    _ =>
                                      eval?.depth != null
                                          ? Text(
                                              '${math.min(99, eval!.depth)}',
                                              style: iconTextStyle,
                                            )
                                          : loadingIndicator,
                                  }
                          : const SizedBox.shrink(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // The readout is a `Positioned` child, so it never contributes to this Stack's size --
        // the 48px chip does. Offsetting it by -6 therefore painted it *outside* the box, on top
        // of whatever sits below. That was harmless when the button sat at the foot of a column
        // with empty space beneath, but the Diagram action row puts a second row directly under
        // it. Sitting it at bottom: 0 keeps the same visual (it still tucks under the icon, in
        // the clear space at the foot of the 48px box) while moving it inside the button's own
        // bounds -- and costs no layout, which matters because the action row in the archived
        // game is already three lines tall and six extra pixels tips it.
        Positioned(
          bottom: 0,
          child: Text(
            engineShortLabel(engine?.value, spec: engineSpec) ?? prefs.enginePref.shortLabel,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: textColor.withValues(alpha: 0.8),
            ),
          ),
        ),
      ],
    );
  }
}

class MicroChipPainter extends CustomPainter {
  const MicroChipPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const pinLength = 3.5;
    const pinRadius = Radius.circular(1);
    const innerRimWidth = 1.0;
    const outerRimWidth = 1.5;

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final outerStrokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = outerRimWidth;

    final innerStrokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = innerRimWidth;

    final innerSquareSize = size.width - pinLength - innerRimWidth - outerRimWidth;

    final innerSquarePath = Path()
      ..addRRect(
        RRect.fromLTRBR(
          pinLength + innerRimWidth + outerRimWidth,
          pinLength + innerRimWidth + outerRimWidth,
          innerSquareSize,
          innerSquareSize,
          const Radius.circular(2),
        ),
      );

    final outerRimPath = Path()
      ..addRRect(
        RRect.fromLTRBR(
          pinLength,
          pinLength,
          size.width - pinLength,
          size.height - pinLength,
          const Radius.circular(4),
        ),
      );

    final pinsPath = Path();
    final chipSide = size.width - pinLength * 2;
    final pinsMargin = (chipSide - chipSide * 0.6) / 2;
    final pinWidth = chipSide / 10;
    final pinSpacing = (chipSide - (pinsMargin * 2) - 3 * pinWidth) / 2;
    // draw left pins
    for (var i = 0; i < 3; i++) {
      pinsPath.addRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(
            0,
            pinLength + pinsMargin + i * (pinWidth + pinSpacing),
            pinLength,
            pinWidth,
          ),
          topLeft: pinRadius,
          bottomLeft: pinRadius,
        ),
      );
    }
    // draw right pins
    for (var i = 0; i < 3; i++) {
      pinsPath.addRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(
            size.width - pinLength,
            pinLength + pinsMargin + i * (pinWidth + pinSpacing),
            pinLength,
            pinWidth,
          ),
          topRight: pinRadius,
          bottomRight: pinRadius,
        ),
      );
    }
    // draw top pins
    for (var i = 0; i < 3; i++) {
      pinsPath.addRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(
            pinLength + pinsMargin + i * (pinWidth + pinSpacing),
            0,
            pinWidth,
            pinLength,
          ),
          topLeft: pinRadius,
          topRight: pinRadius,
        ),
      );
    }
    // draw bottom pins
    for (var i = 0; i < 3; i++) {
      pinsPath.addRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(
            pinLength + pinsMargin + i * (pinWidth + pinSpacing),
            size.height - pinLength,
            pinWidth,
            pinLength,
          ),
          bottomLeft: pinRadius,
          bottomRight: pinRadius,
        ),
      );
    }

    canvas.drawPath(outerRimPath, outerStrokePaint);
    canvas.drawPath(pinsPath, fillPaint);
    canvas.drawPath(innerSquarePath, innerStrokePaint);
  }

  @override
  bool shouldRepaint(covariant MicroChipPainter oldDelegate) => color != oldDelegate.color;
}

class _EnginePopup extends ConsumerWidget {
  const _EnginePopup({this.goDeeper, required this.filters});

  final VoidCallback? goDeeper;
  final EngineEvaluationFilters filters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (:engine, :engineSpec, currentWork: work, eval: evalStateEval, :isComputing) = ref.watch(
      engineEvaluationProvider(filters),
    );
    final bool canGoDeeper =
        goDeeper != null && !isComputing && (work == null || work.isDeeper != true);

    final currentEval = engine?.hasValue == true ? evalStateEval : null;
    final c = context.srs;

    Widget row({Widget? leading, required String title, String? subtitle}) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        child: Row(
          children: [
            if (leading != null) ...[leading, const SizedBox(width: 14)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: SrsText.settingLabel(c.ink)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontFamily: SrsText.ui,
                        fontSize: 14,
                        color: c.ink2,
                        fontFeatures: SrsText.tabular,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (canGoDeeper) SrsTextButton(label: context.l10n.goDeeper, onPressed: goDeeper),
          ],
        ),
      );
    }

    if (currentEval is CloudEval) {
      return row(
        title: context.l10n.cloudAnalysis,
        subtitle: context.l10n.depthX('${currentEval!.depth}'),
      );
    }

    final knps = isComputing ? ', ${evalStateEval?.knps.round()}kn/s' : '';

    final displayName = engineDisplayName(engine?.value, spec: engineSpec);

    return row(
      leading: Image.asset('assets/images/stockfish/icon.webp', width: 44, height: 44),
      title: displayName,
      subtitle: currentEval != null ? context.l10n.depthX('${currentEval.depth}$knps') : null,
    );
  }
}
