import 'package:chess_srs/src/constants.dart';
import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chess_srs/src/model/settings/board_preferences.dart';
import 'package:chess_srs/src/model/settings/general_preferences.dart';
import 'package:chess_srs/src/styles/styles.dart';
import 'package:chess_srs/src/utils/color_palette.dart';
import 'package:chess_srs/src/utils/l10n_context.dart';
import 'package:chess_srs/src/utils/navigation.dart';
import 'package:chess_srs/src/utils/screen.dart';
import 'package:chess_srs/src/view/settings/board_choice_screen.dart';
import 'package:chess_srs/src/view/settings/piece_set_screen.dart';
import 'package:chess_srs/src/widgets/adaptive_choice_picker.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class ThemeSettingsScreen extends ConsumerWidget {
  const ThemeSettingsScreen({super.key});

  static Route<dynamic> buildRoute() {
    return buildScreenRoute(screen: const ThemeSettingsScreen());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.mobileTheme), animateColor: true),
      body: const _Body(),
    );
  }
}

String shapeColorL10n(ShapeColor shapeColor) => switch (shapeColor) {
  ShapeColor.green => 'Green',
  ShapeColor.red => 'Red',
  ShapeColor.blue => 'Blue',
  ShapeColor.yellow => 'Yellow',
};

class _Body extends ConsumerStatefulWidget {
  const _Body();

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  late double brightness;
  late double hue;

  bool openAdjustColorSection = false;

  @override
  void initState() {
    super.initState();
    final boardPrefs = ref.read(boardPreferencesProvider);
    brightness = boardPrefs.brightness;
    hue = boardPrefs.hue;
  }

  @override
  Widget build(BuildContext context) {
    final generalPrefs = ref.watch(generalPreferencesProvider);
    final boardPrefs = ref.watch(boardPreferencesProvider);

    final bool hasAjustedColors =
        brightness != kBoardDefaultBrightnessFilter || hue != kBoardDefaultHueFilter;

    final boardSize = isTabletOrLarger(context) ? 350.0 : 200.0;

    return SafeArea(
      top: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 20),
            child: _BoardPreview(
              size: boardSize,
              boardPrefs: boardPrefs,
              brightness: brightness,
              hue: hue,
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              children: [
                if (getSystemCorePalettes() != null)
                  SrsSettingsRow(
                    label: context.l10n.mobileSystemColors,
                    control: SrsSwitch(
                      value: generalPrefs.systemColors,
                      semanticLabel: context.l10n.mobileSystemColors,
                      onChanged: (value) {
                        ref.read(generalPreferencesProvider.notifier).toggleSystemColors();
                      },
                    ),
                  ),
                SrsSettingsRow(
                  label: context.l10n.board,
                  value: boardPrefs.boardTheme.label,
                  onTap: () {
                    Navigator.of(context).push(BoardChoiceScreen.buildRoute());
                  },
                ),
                SrsSettingsRow(
                  label: context.l10n.pieceSet,
                  value: boardPrefs.pieceSet.label,
                  onTap: () {
                    Navigator.of(context).push(PieceSetScreen.buildRoute());
                  },
                ),
                SrsSettingsRow(
                  label: 'Drawn shape color',
                  help: 'This color is only used for shapes drawn by hand using two fingers.',
                  value: shapeColorL10n(boardPrefs.shapeColor),
                  onTap: () {
                    showChoicePicker(
                      context,
                      choices: ShapeColor.values,
                      selectedItem: boardPrefs.shapeColor,
                      labelBuilder: (t) => Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: shapeColorL10n(t)),
                            const TextSpan(text: '   '),
                            WidgetSpan(child: Container(width: 15, height: 15, color: t.color)),
                          ],
                        ),
                      ),
                      onSelectedItemChanged: (ShapeColor? value) {
                        ref
                            .read(boardPreferencesProvider.notifier)
                            .setShapeColor(value ?? ShapeColor.green);
                      },
                    );
                  },
                ),
                SrsSettingsRow(
                  label: context.l10n.preferencesBoardCoordinates,
                  control: SrsSwitch(
                    value: boardPrefs.coordinates,
                    semanticLabel: context.l10n.preferencesBoardCoordinates,
                    onChanged: (value) {
                      ref.read(boardPreferencesProvider.notifier).toggleCoordinates();
                    },
                  ),
                ),
                SrsSettingsRow(
                  label: 'Show border',
                  control: SrsSwitch(
                    value: boardPrefs.showBorder,
                    semanticLabel: 'Show border',
                    onChanged: (value) {
                      ref.read(boardPreferencesProvider.notifier).toggleBorder();
                    },
                  ),
                ),
                const SrsGroupHeader('Board colors'),
                // The two sliders were bare `ListTile(title: Slider)` with an icon as the only
                // label, so they reached a screen reader as an unnamed slider. Each now carries
                // the name it adjusts and its current value.
                SrsSettingsRow(
                  label: 'Brightness',
                  value: '${(brightness * 100).round()}%',
                  preview: Slider(
                    min: 0.2,
                    max: 1.4,
                    value: brightness,
                    onChanged: (value) {
                      setState(() {
                        brightness = value;
                      });
                    },
                    onChangeEnd: (value) {
                      ref
                          .read(boardPreferencesProvider.notifier)
                          .adjustColors(brightness: brightness);
                    },
                  ),
                ),
                SrsSettingsRow(
                  label: 'Hue',
                  value: '${hue.round()}\u00b0',
                  preview: Slider(
                    min: 0.0,
                    max: 360.0,
                    value: hue,
                    onChanged: (value) {
                      setState(() {
                        hue = value;
                      });
                    },
                    onChangeEnd: (value) {
                      ref.read(boardPreferencesProvider.notifier).adjustColors(hue: hue);
                    },
                  ),
                ),
                SrsSettingsRow(
                  label: context.l10n.boardReset,
                  enabled: hasAjustedColors,
                  onTap: hasAjustedColors
                      ? () {
                          setState(() {
                            brightness = kBoardDefaultBrightnessFilter;
                            hue = kBoardDefaultHueFilter;
                          });
                          ref
                              .read(boardPreferencesProvider.notifier)
                              .adjustColors(brightness: brightness, hue: hue);
                        }
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BoardPreview extends StatelessWidget {
  const _BoardPreview({
    required this.size,
    required this.boardPrefs,
    required this.brightness,
    required this.hue,
  });

  final BoardPrefs boardPrefs;
  final double brightness;
  final double hue;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: StaticChessboard(
        size: size,
        orientation: Side.white,
        lastMove: const NormalMove(from: Square.e2, to: Square.e4),
        fen: 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1',
        shapes: {
          Circle(color: boardPrefs.shapeColor.color, orig: Square.fromName('b8')),
          Arrow(
            color: boardPrefs.shapeColor.color,
            orig: Square.fromName('b8'),
            dest: Square.fromName('c6'),
          ),
        },
        settings: StaticChessboardSettings.fromBoardSettings(
          boardPrefs
              .toBoardSettings(Variant.standard)
              .copyWith(
                brightness: brightness,
                hue: hue,
                borderRadius: Styles.boardBorderRadius,
                boxShadow: boardShadows,
              ),
        ),
      ),
    );
  }
}
