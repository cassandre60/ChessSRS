import 'dart:math' as math;

import 'package:chess_srs/src/constants.dart';
import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/model/analysis/analysis_controller.dart';
import 'package:chess_srs/src/model/board_editor/board_editor_controller.dart';
import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chess_srs/src/model/common/chess960.dart';
import 'package:chess_srs/src/model/common/id.dart';
import 'package:chess_srs/src/model/settings/board_preferences.dart';
import 'package:chess_srs/src/styles/styles.dart';
import 'package:chess_srs/src/utils/l10n_context.dart';
import 'package:chess_srs/src/utils/navigation.dart';
import 'package:chess_srs/src/utils/screen.dart';
import 'package:chess_srs/src/utils/share.dart';
import 'package:chess_srs/src/view/analysis/analysis_screen.dart';
import 'package:chess_srs/src/view/board_editor/board_editor_filters.dart';
import 'package:chess_srs/src/view/board_editor/board_editor_positions.dart';
import 'package:chess_srs/src/view/offline_computer/offline_computer_game_screen.dart';
import 'package:chess_srs/src/widgets/adaptive_action_sheet.dart';
import 'package:chess_srs/src/widgets/adaptive_choice_picker.dart';
import 'package:chess_srs/src/widgets/buttons.dart';
import 'package:chess_srs/src/widgets/feedback.dart';
import 'package:chess_srs/src/widgets/platform.dart';
import 'package:chess_srs/src/widgets/variant_app_bar_title.dart';
import 'package:chessground/chessground.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

class BoardEditorScreen extends ConsumerWidget {
  const BoardEditorScreen({super.key, this.params});

  final BoardEditorControllerParams? params;

  static Route<dynamic> buildRoute(BoardEditorControllerParams? params) {
    return buildScreenRoute(screen: BoardEditorScreen(params: params));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boardEditorState = ref.watch(boardEditorControllerProvider(params));
    final c = context.srs;

    // Quiet scene-title line under the header (demo meta treatment).
    // Carries the variant name the old app bar title showed as an icon.
    final sceneTitle = boardEditorState.variant == Variant.standard
        ? context.l10n.boardEditor
        : '${boardEditorState.variant.label(context.l10n)} • ${context.l10n.boardEditor}';

    return Scaffold(
      backgroundColor: c.ground,
      body: SafeArea(
        child: Column(
          children: [
            SrsPageHead(
              label: 'Review',
              onBack: () => Navigator.of(context).pop(),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit),
                    tooltip: 'FEN',
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => _FenDialog(
                        onFenLoaded: (fen) =>
                            ref.read(boardEditorControllerProvider(params).notifier).loadFen(fen),
                      ),
                    ),
                  ),
                  SemanticIconButton(
                    semanticsLabel: context.l10n.mobileSharePositionAsFEN,
                    onPressed: () =>
                        launchShareDialog(context, ShareParams(text: boardEditorState.fen)),
                    icon: const PlatformShareIcon(),
                  ),
                ],
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 2, 24, 8),
                child: Text(
                  sceneTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SrsText.meta(c.ink2),
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final aspectRatio = constraints.biggest.aspectRatio;

                    final defaultBoardSize = constraints.biggest.shortestSide;
                    final isTablet = isTabletOrLarger(context);
                    final boardSize = defaultBoardSize;

                    final direction = aspectRatio > 1 ? Axis.horizontal : Axis.vertical;

                    return Flex(
                      direction: direction,
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      mainAxisSize: MainAxisSize.max,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _PieceMenu(
                          boardSize,
                          params: params,
                          direction: flipAxis(direction),
                          side: boardEditorState.orientation.opposite,
                          isTablet: isTablet,
                        ),
                        _BoardEditor(
                          boardSize,
                          params: params,
                          orientation: boardEditorState.orientation,
                          isTablet: isTablet,
                          // unlockView is safe because chessground will never modify the pieces
                          pieces: boardEditorState.pieces.unlockView,
                        ),
                        _PieceMenu(
                          boardSize,
                          params: params,
                          direction: flipAxis(direction),
                          side: boardEditorState.orientation,
                          isTablet: isTablet,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _BottomBar(params),
    );
  }
}

class _BoardEditor extends ConsumerWidget {
  const _BoardEditor(
    this.boardSize, {
    required this.params,
    required this.isTablet,
    required this.orientation,
    required this.pieces,
  });

  final BoardEditorControllerParams? params;
  final double boardSize;
  final bool isTablet;
  final Side orientation;
  final Pieces pieces;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editorState = ref.watch(boardEditorControllerProvider(params));
    final boardPrefs = ref.watch(boardPreferencesProvider);
    final srsColors = SrsTheme.maybeOf(context);

    final settings = boardPrefs
        .toBoardSettings(editorState.variant, srsColors: srsColors)
        .copyWith(
          borderRadius: isTablet ? Styles.boardBorderRadius : BorderRadius.zero,
          boxShadow: isTablet ? boardShadows : const <BoxShadow>[],
        );

    final editor = ChessboardEditor(
      size: boardSize,
      pieces: pieces,
      orientation: orientation,
      settings: settings,
      pointerMode: editorState.editorPointerMode,
      onDiscardedPiece: (Square square) =>
          ref.read(boardEditorControllerProvider(params).notifier).discardPiece(square),
      onDroppedPiece: (Square? origin, Square dest, Piece piece) =>
          ref.read(boardEditorControllerProvider(params).notifier).movePiece(origin, dest, piece),
      onEditedSquare: (Square square) =>
          ref.read(boardEditorControllerProvider(params).notifier).editSquare(square),
    );

    if (srsColors != null && settings.colorScheme.lightSquare.a == 0) {
      return Stack(
        children: [
          SrsBoardBackground(size: boardSize),
          editor,
        ],
      );
    }
    return editor;
  }
}

class _PieceMenu extends ConsumerStatefulWidget {
  const _PieceMenu(
    this.boardSize, {
    required this.params,
    required this.direction,
    required this.side,
    required this.isTablet,
  });

  final BoardEditorControllerParams? params;

  final double boardSize;

  final Axis direction;

  final Side side;

  final bool isTablet;

  @override
  ConsumerState<_PieceMenu> createState() => _PieceMenuState();
}

class _PieceMenuState extends ConsumerState<_PieceMenu> {
  @override
  Widget build(BuildContext context) {
    final boardPrefs = ref.watch(boardPreferencesProvider);
    final editorController = boardEditorControllerProvider(widget.params);
    final editorState = ref.watch(editorController);
    final srsColors = SrsTheme.maybeOf(context);
    final pieceAssets = boardPrefs
        .toBoardSettings(Variant.standard, srsColors: srsColors)
        .pieceAssets;

    final squareSize = widget.boardSize / 8;
    final c = context.srs;
    final isDragActive = editorState.editorPointerMode == EditorPointerMode.drag;
    final isDeleteActive = editorState.deletePiecesActive;

    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: widget.isTablet ? BorderRadius.circular(12) : BorderRadius.circular(8),
        border: Border.all(color: c.hairline),
        boxShadow: widget.isTablet ? boardShadows : const <BoxShadow>[],
      ),
      child: Flex(
        direction: widget.direction,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: squareSize,
            height: squareSize,
            child: ColoredBox(
              key: Key('drag-button-${widget.side.name}'),
              color: isDragActive ? c.accentSoft : Colors.transparent,
              child: GestureDetector(
                onTap: () => ref.read(editorController.notifier).updateMode(EditorPointerMode.drag),
                child: Icon(
                  CupertinoIcons.hand_draw,
                  size: 0.8 * squareSize,
                  color: isDragActive ? c.accent : c.ink2,
                ),
              ),
            ),
          ),
          ...Role.values.map((role) {
            final piece = Piece(role: role, color: widget.side);
            final isPieceActive =
                ref.read(boardEditorControllerProvider(widget.params)).activePieceOnEdit == piece;
            final pieceWidget = PieceWidget(
              piece: piece,
              size: squareSize,
              pieceAssets: pieceAssets,
            );

            return ColoredBox(
              key: Key('piece-button-${piece.color.name}-${piece.role.name}'),
              color: isPieceActive ? c.accentSoft : Colors.transparent,
              child: GestureDetector(
                child: Draggable(
                  data: Piece(role: role, color: widget.side),
                  feedback: PieceDragFeedback(
                    piece: piece,
                    squareSize: squareSize,
                    pieceAssets: pieceAssets,
                  ),
                  child: pieceWidget,
                  onDragEnd: (_) =>
                      ref.read(editorController.notifier).updateMode(EditorPointerMode.drag),
                ),
                onTap: () =>
                    ref.read(editorController.notifier).updateMode(EditorPointerMode.edit, piece),
              ),
            );
          }),
          SizedBox(
            key: Key('delete-button-${widget.side.name}'),
            width: squareSize,
            height: squareSize,
            child: ColoredBox(
              // Demo erase tool: active state is accent, never red.
              color: isDeleteActive ? c.accentSoft : Colors.transparent,
              child: GestureDetector(
                onTap: () =>
                    ref.read(editorController.notifier).updateMode(EditorPointerMode.edit, null),
                child: Icon(
                  CupertinoIcons.delete,
                  size: 0.75 * squareSize,
                  color: isDeleteActive ? c.accent : c.ink3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomBar extends ConsumerWidget {
  const _BottomBar(this.params);

  final BoardEditorControllerParams? params;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editorController = boardEditorControllerProvider(params);
    final editorState = ref.watch(editorController);
    final pieceCount = editorState.pieces.length;

    // Diagram actions replacing the legacy bottom bar: same features,
    // plain text buttons. Menu sheet, Flip, Analyze and Filters all survive.
    // Wrap mirrors the demo's wrapping editor rows on narrow screens.
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
      child: Wrap(
        spacing: 14,
        runSpacing: 6,
        children: [
          SrsTextButton(
            label: context.l10n.menu,
            onPressed: () => showAdaptiveActionSheet<void>(
              context: context,
              actions: [
                if (editorState.variant != Variant.chess960 &&
                    editorState.variant != Variant.fromPosition)
                  BottomSheetAction(
                    makeLabel: (context) => Text(context.l10n.startPosition),
                    onPressed: () {
                      ref
                          .read(editorController.notifier)
                          .loadFen(editorState.variant.initialPosition.fen);
                    },
                  ),
                if (editorState.variant == .chess960)
                  BottomSheetAction(
                    makeLabel: (context) => const Text('Chess960 Position'),
                    onPressed: () {
                      showDialog<void>(
                        context: context,
                        builder: (_) => _Chess960PositionDialog(
                          onFenLoaded: (fen) {
                            ref.read(editorController.notifier).loadFen(fen);
                          },
                        ),
                      );
                    },
                  ),
                if (editorState.variant == .standard)
                  BottomSheetAction(
                    makeLabel: (context) => Text(context.l10n.loadPosition),
                    onPressed: () {
                      final notifier = ref.read(editorController.notifier);
                      Navigator.of(context).push(
                        BoardEditorPositionsScreen.buildRoute(
                          onPositionSelected: (position) => {
                            notifier.loadFen(position.fen),
                            Navigator.of(context).pop(),
                          },
                        ),
                      );
                    },
                  ),
                BottomSheetAction(
                  makeLabel: (context) => Text(context.l10n.variant),
                  onPressed: () => showChoicePicker<Variant>(
                    context,
                    choices: readSupportedVariants
                        .where((variant) => variant != .fromPosition)
                        .toList(),
                    selectedItem: editorState.variant,
                    labelBuilder: (variant) => VariantLabel(variant),
                    onSelectedItemChanged: (Variant variant) {
                      if (variant != editorState.variant) {
                        ref.read(editorController.notifier).setVariant(variant);
                      }
                    },
                  ),
                ),
                if (editorState.pgn != null && pieceCount > 0 && pieceCount <= 32)
                  BottomSheetAction(
                    makeLabel: (context) => Text(context.l10n.continueFromHere),
                    onPressed: () =>
                        _showContinueFromHereMenu(context, editorState.variant, editorState.fen),
                  ),
                BottomSheetAction(
                  makeLabel: (context) => Text(context.l10n.clearBoard),
                  onPressed: () {
                    ref.read(editorController.notifier).clearBoard();
                  },
                ),
              ],
            ),
          ),
          SrsTextButton(
            key: const Key('flip-button'),
            // Diagram's terse row labels, not the tooltip-length l10n strings. "Flip board" and
            // "Analysis board" are 174px and 234px wide at 15px, which is what pushed this row
            // onto three lines on a 390px phone and cost the board its height.
            label: 'Flip',
            onPressed: ref.read(boardEditorControllerProvider(params).notifier).flipBoard,
          ),
          SrsTextButton(
            key: const Key('analysis-board-button'),
            label: 'Analyse',
            // The evaluator uses Fairy-Stockfish for nonstandard material.
            onPressed: editorState.pgn != null && pieceCount > 0
                ? () {
                    Navigator.of(context).push(
                      AnalysisScreen.buildRoute(
                        AnalysisOptions.pgn(
                          id: const StringId('board_editor_position'),
                          orientation: editorState.orientation,
                          pgn: editorState.pgn!,
                          isComputerAnalysisAllowed: true,
                          variant: editorState.variant,
                        ),
                      ),
                    );
                  }
                : null,
          ),
          SrsTextButton(
            label: 'Filters',
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              builder: (BuildContext context) => BoardEditorFilters(params: params),
              showDragHandle: true,
              constraints: BoxConstraints(minHeight: MediaQuery.heightOf(context) * 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showContinueFromHereMenu(BuildContext context, Variant variant, String fen) {
    return showAdaptiveActionSheet(
      context: context,
      actions: [
        BottomSheetAction(
          makeLabel: (context) => Text(context.l10n.playAgainstComputer),
          onPressed: () => Navigator.of(
            context,
          ).push(OfflineComputerGameScreen.buildRoute(initialVariant: variant, initialFen: fen)),
        ),
      ],
    );
  }
}

class _FenDialog extends StatefulWidget {
  const _FenDialog({required this.onFenLoaded});

  final void Function(String fen) onFenLoaded;

  @override
  State<_FenDialog> createState() => _FenDialogState();
}

class _FenDialogState extends State<_FenDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text == null || !mounted) return;

    final text = data!.text!.trim();
    if (text.isEmpty) return;

    _controller.text = text;
    try {
      final pos = Chess.fromSetup(Setup.parseFen(text));
      widget.onFenLoaded(pos.fen);
    } catch (_) {
      showSnackBar(context, context.l10n.invalidFen, type: SnackBarType.error);
    } finally {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: TextField(
        controller: _controller,
        readOnly: true,
        onTap: _pasteFromClipboard,
        decoration: InputDecoration(
          hintText: context.l10n.pasteTheFenStringHere,
          suffixIcon: IconButton(
            icon: const Icon(Icons.paste),
            onPressed: _pasteFromClipboard,
            tooltip: 'Paste from clipboard',
          ),
        ),
      ),
    );
  }
}

class _Chess960PositionDialog extends StatefulWidget {
  const _Chess960PositionDialog({required this.onFenLoaded});

  final void Function(String fen) onFenLoaded;

  @override
  State<_Chess960PositionDialog> createState() => _Chess960PositionDialogState();
}

class _Chess960PositionDialogState extends State<_Chess960PositionDialog> {
  final _controller = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _generateRandom() {
    final randomId = math.Random().nextInt(960);
    setState(() {
      _controller.text = randomId.toString();
      _errorText = null;
    });
  }

  void _validateInput(String value) {
    final id = int.tryParse(value);
    setState(() {
      if (id != null && id > 959) {
        _errorText = 'Max ID is 959';
      } else {
        _errorText = null;
      }
    });
  }

  void _loadPosition() {
    final id = int.tryParse(_controller.text);
    if (id == null) return;

    final fen = chess960Position(id).fen;
    widget.onFenLoaded(fen);
    Navigator.of(context, rootNavigator: true).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Chess960 Position'),
      content: Column(
        mainAxisSize: .min,
        children: [
          TextField(
            controller: _controller,
            keyboardType: .number,
            onChanged: _validateInput,
            decoration: InputDecoration(
              hintText: 'Position ID (0-959)',
              errorText: _errorText,
              suffixIcon: IconButton(
                icon: const Icon(Icons.casino_outlined),
                onPressed: _generateRandom,
                tooltip: context.l10n.randomChess960Position,
              ),
            ),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onSubmitted: (_) => _loadPosition(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
          child: Text(context.l10n.cancel),
        ),
        TextButton(
          onPressed: _errorText == null && _controller.text.isNotEmpty ? _loadPosition : null,
          child: Text(context.l10n.loadPosition),
        ),
      ],
    );
  }
}
