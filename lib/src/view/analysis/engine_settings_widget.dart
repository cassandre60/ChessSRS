import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/model/engine/engine_utils.dart';
import 'package:chess_srs/src/model/engine/evaluation_preferences.dart';
import 'package:chess_srs/src/utils/l10n_context.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// A bounded slider over a fixed set of values, as a design row.
///
/// `SliderSettingsTile` showed its value only in the drag bubble, so search time, evaluation
/// lines and CPU count had no readable value at all until you were already dragging one. The
/// value sits in the row here, which is also the only way a screen reader can announce it.
///
/// The drag is snapped to the nearest allowed value and only the released value is written, so
/// a drag across the track does not persist a hundred intermediate settings. That is what the
/// inherited tile did with a private index; keeping the index in state is what makes the row's
/// text follow the knob instead of waiting for the write.
class SrsSliderRow extends StatefulWidget {
  const SrsSliderRow({
    super.key,
    required this.label,
    required this.value,
    required this.values,
    required this.format,
    required this.onChangeEnd,
  });

  final String label;

  /// The current setting. Must be one of [values].
  final double value;

  /// Ascending, and at least two long.
  final List<double> values;

  /// How a value reads in the row, e.g. `12s` or a bare count.
  final String Function(double value) format;

  final ValueChanged<double> onChangeEnd;

  @override
  State<SrsSliderRow> createState() => _SrsSliderRowState();
}

class _SrsSliderRowState extends State<SrsSliderRow> {
  late double _preview = widget.value;

  @override
  void didUpdateWidget(SrsSliderRow old) {
    super.didUpdateWidget(old);
    // The write comes back through the parent, so accept it -- but only when it is not the
    // value being dragged, which would fight the finger.
    if (widget.value != old.value) _preview = widget.value;
  }

  double _snap(double raw) {
    var best = widget.values.first;
    var bestDistance = (raw - best).abs();
    for (final candidate in widget.values) {
      final distance = (raw - candidate).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        best = candidate;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.srs;
    return SrsSettingsRow(
      label: widget.label,
      // Derived from the same number the slider shows, so the two cannot drift apart.
      value: widget.format(_preview),
      preview: SliderTheme(
        // The design gives the slider no spec of its own, so the platform control is kept and
        // only its colours are taken from the palette.
        data: SliderTheme.of(context).copyWith(
          activeTrackColor: c.accent,
          inactiveTrackColor: c.hairlineSoft,
          thumbColor: c.accent,
          overlayColor: c.accentSoft,
        ),
        child: Slider(
          value: _preview,
          min: widget.values.first,
          max: widget.values.last,
          // One division per gap, so the knob lands on a value in `values` and nowhere else.
          // Without it the row would state a number the slider cannot reach -- the same defect
          // the sound volume slider had.
          divisions: widget.values.length - 1,
          label: widget.format(_preview),
          onChanged: (raw) => setState(() => _preview = _snap(raw)),
          onChangeEnd: (raw) => widget.onChangeEnd(_snap(raw)),
        ),
      ),
    );
  }
}

class EngineSettingsWidget extends ConsumerWidget {
  const EngineSettingsWidget({
    this.onToggleLocalEvaluation,
    required this.onSetEngineSearchTime,
    this.onSetNumEvalLines,
    required this.onSetEngineCores,
    super.key,
  });

  final VoidCallback? onToggleLocalEvaluation;
  final void Function(Duration) onSetEngineSearchTime;
  final void Function(int)? onSetNumEvalLines;
  final void Function(int) onSetEngineCores;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(engineEvaluationPreferencesProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onToggleLocalEvaluation != null)
          SrsSettingsRow(
            label: context.l10n.toggleLocalEvaluation,
            control: SrsSwitch(
              value: prefs.isEnabled,
              semanticLabel: context.l10n.toggleLocalEvaluation,
              onChanged: (_) => onToggleLocalEvaluation!.call(),
            ),
          ),
        const SrsGroupHeader('Stockfish'),
        SrsSliderRow(
          label: 'Search time',
          value: prefs.engineSearchTime.inSeconds.toDouble(),
          values: kAvailableEngineSearchTimes.map((e) => e.inSeconds.toDouble()).toList(),
          format: (value) =>
              value == kMaxEngineSearchTime.inSeconds.toDouble() ? '∞' : '${value.toInt()}s',
          onChangeEnd: (value) => onSetEngineSearchTime(Duration(seconds: value.toInt())),
        ),
        if (onSetNumEvalLines != null)
          SrsSliderRow(
            label: context.l10n.multipleLines,
            value: prefs.numEvalLines.toDouble(),
            values: const [0, 1, 2, 3],
            format: (value) => value.toInt().toString(),
            onChangeEnd: (value) => onSetNumEvalLines!.call(value.toInt()),
          ),
        if (maxEngineCores > 1)
          SrsSliderRow(
            label: context.l10n.cpus,
            value: prefs.numEngineCores.toDouble(),
            values: List.generate(
              maxEngineCores,
              (index) => index + 1,
            ).map((e) => e.toDouble()).toList(),
            format: (value) => value.toInt().toString(),
            onChangeEnd: (value) => onSetEngineCores(value.toInt()),
          ),
      ],
    );
  }
}
