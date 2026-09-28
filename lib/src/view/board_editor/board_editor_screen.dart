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

/// Tools in a piece palette: the drag toggle, one per [Role], then erase.
///
/// `Role.values` is not a const expression, so this cannot be `const`; it is a top-level `final`
/// instead. There is one instance, and the count is read at most once per build.
final int _pieceMenuItemCount = Role.values.length + 2;

/// The palette's 1px border, drawn inside its own box, so its children must fit the inner extent.
const double _paletteBorderWidth = 1.0;

/// Gap between palette, board and palette.
const double _boardEditorSpacing = 8.0;

/// Width of the status panel when it sits beside the board in landscape.
///
/// 260 is the width at which the side-to-move segmented control fits on one line: at 220 it wrapped
/// "Black to play" onto a second row, which made the panel taller than the board beside it and
/// undid the reason for moving it out from under the board. The FEN then wraps to two lines, which
/// is what the panel has the height for.
const double _editorPanelWidth = 260.0;

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

                    final isTablet = isTabletOrLarger(context);
                    final direction = aspectRatio > 1 ? Axis.horizontal : Axis.vertical;

                    // The board is square, so it can only be as large as the *shorter* side allows --
                    // but the two palettes are rows of eight square tools laid along the cross axis,
                    // so each is one item deep on the main axis and claims height (portrait) or width
                    // (landscape) that the board has to be subtracted from. Sizing the board from the
                    // shortest side alone therefore overflows the column as soon as anything is added
                    // below it: the status panel cost ~90px, and a `Clip.hardEdge` then ate the bottom
                    // palette whole, with no overflow error. Subtract what the palettes claim.
                    //
                    // `shortestSide / count` bounds an item from above (the palette also caps itself
                    // at the board), so this over-reserves slightly and the board comes out a little
                    // smaller than strictly necessary. Reserving exactly would mean solving
                    // `board = extent - 2 * (board / count)`, which buys back a few px at the cost of
                    // arithmetic that has to be right.
                    final palettesClaim =
                        2 *
                            (constraints.biggest.shortestSide / _pieceMenuItemCount +
                                _paletteBorderWidth) +
                        2 * _boardEditorSpacing;
                    // Both bounds matter, and neither subsumes the other. Portrait: the board is
                    // limited by the width, and the palettes eat height. Landscape: the board is
                    // limited by the height, and the palettes eat width -- which is why landscape
                    // needs `maxWidth - palettesClaim` and not the same expression as portrait.
                    // Clamped at zero rather than at a floor: a floor larger than the space
                    // available produces a board that overflows its slot, and `Clip.hardEdge`
                    // then crops it into a non-square rectangle.
                    // Landscape has room beside the board but almost none below it, and the demo
                    // draws the editor as `.split` -- board left, side column right. So in landscape
                    // the status panel joins the Flex as a trailing column and claims width; in
                    // portrait it stays under the board and claims height. Stacking it either way
                    // costs a 390px-tall landscape phone 43% of its board, down to 104px.
                    final panelBeside = direction == Axis.horizontal;
                    final panelClaim = panelBeside ? _editorPanelWidth + _boardEditorSpacing : 0.0;
                    final boardSize = math.max(
                      0.0,
                      math.min(
                        constraints.biggest.shortestSide,
                        (direction == Axis.vertical
                                ? constraints.maxHeight
                                : constraints.maxWidth) -
                            palettesClaim -
                            panelClaim,
                      ),
                    );

                    return Flex(
                      direction: direction,
                      // `spaceEvenly` spread the leftover height into four *equal* ~51px gaps on a
                      // 390x844 phone, so the tool palettes floated as far from the board they act
                      // on as they did from the screen edge. A square board is width-bound and
                      // cannot claim the slack, so centre the block and keep the palette-to-board
                      // gap tight instead of equal.
                      mainAxisAlignment: MainAxisAlignment.center,
                      spacing: _boardEditorSpacing,
                      mainAxisSize: MainAxisSize.max,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _PieceMenu(
                          boardSize,
                          params: params,
                          direction: flipAxis(direction),
                          side: boardEditorState.orientation.opposite,
                          isTablet: isTablet,
                          maxPaletteWidth: direction == Axis.horizontal
                              ? constraints.maxHeight
                              : constraints.maxWidth,
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
                          maxPaletteWidth: direction == Axis.horizontal
                              ? constraints.maxHeight
                              : constraints.maxWidth,
                        ),
                        if (panelBeside)
                          SizedBox(
                            width: _editorPanelWidth,
                            child: _EditorStatusPanel(params: params, besideBoard: true),
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
      // In landscape the panel is a column beside the board, not a row under it -- see the
      // `panelBeside` decision in the layout above.
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!_isWideLayout(context)) _EditorStatusPanel(params: params),
          _BottomBar(params),
        ],
      ),
    );
  }
}

bool _isWideLayout(BuildContext context) => MediaQuery.sizeOf(context).aspectRatio > 1;

/// The demo `editor` side column's lower half, promoted out of the places it was buried in.
///
/// Side-to-move was reachable only through the Filters sheet, and the position's FEN only through
/// the edit dialog, so neither was visible while editing — the one thing a board editor is for is
/// seeing the position you built. This mirrors the demo's order: the side-to-move segmented
/// control, then the live FEN, then the actions row, which is where the demo puts its *Copy FEN*
/// pill. It is an addition: the Filters sheet keeps its own copy of side-to-move because it also
/// owns castling rights, and the FEN dialog is untouched.
class _EditorStatusPanel extends ConsumerWidget {
  const _EditorStatusPanel({required this.params, this.besideBoard = false});

  final BoardEditorControllerParams? params;

  /// True when this panel is a column to the right of the board rather than a row beneath it.
  final bool besideBoard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.srs;
    final editorState = ref.watch(boardEditorControllerProvider(params));
    final notifier = ref.read(boardEditorControllerProvider(params).notifier);

    return Padding(
      padding: EdgeInsets.fromLTRB(besideBoard ? 0 : 20, besideBoard ? 0 : 10, 20, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SrsSegmented<Side>(
              // l10n rather than the demo's literals: these two strings already exist for the
              // Filters sheet, and hardcoding them here would be a second, untranslated copy.
              options: {Side.white: context.l10n.whitePlays, Side.black: context.l10n.blackPlays},
              value: editorState.sideToPlay,
              onChanged: notifier.setSideToPlay,
            ),
          ),
          const SizedBox(height: 10),
          // `12.5/1.5, ink2` from `code.fen` in the demo. The demo's font stack starts at
          // `ui-monospace`, a CSS generic with no Flutter equivalent, and no monospace face is
          // bundled -- so `fontFamily: 'monospace'` renders as tofu boxes here and in the captures.
          // The UI face with tabular figures keeps FEN digits column-aligned, which is the part of
          // monospace that matters for reading a position at a glance. Selectable, because a FEN you
          // cannot select is a FEN you cannot copy out by hand.
          SelectableText(
            editorState.fen,
            style: TextStyle(
              fontFamily: SrsText.ui,
              fontSize: 12.5,
              height: 1.5,
              color: c.ink2,
              fontFeatures: SrsText.tabular,
            ),
          ),
        ],
      ),
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
    required this.maxPaletteWidth,
  });

  final BoardEditorControllerParams? params;

  final double boardSize;

  /// Width the palette may occupy along [direction]. The palette is a row of square tools rather
  /// than a view of the board, so it is sized to the space it is actually given instead of to
  /// the board -- that is what keeps the erase button from being clipped off the end.
  final double maxPaletteWidth;

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

    final c = context.srs;
    final isDragActive = editorState.editorPointerMode == EditorPointerMode.drag;
    final isDeleteActive = editorState.deletePiecesActive;

    // The palette draws a 1px border inside its own box, so its eight children have to fit the
    // *inner* width. Sizing them from the outer width overflowed by 2px and the ancestor's
    // Clip.hardEdge silently ate the erase button -- no overflow error, no test failure, and the
    // control was simply unreachable on a phone.
    final itemSize =
        math.min(
          widget.boardSize,
          math.max(0.0, widget.maxPaletteWidth - 2 * _paletteBorderWidth),
        ) /
        _pieceMenuItemCount;

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
            width: itemSize,
            height: itemSize,
            child: ColoredBox(
              key: Key('drag-button-${widget.side.name}'),
              color: isDragActive ? c.accentSoft : Colors.transparent,
              child: GestureDetector(
                onTap: () => ref.read(editorController.notifier).updateMode(EditorPointerMode.drag),
                child: Icon(
                  CupertinoIcons.hand_draw,
                  size: 0.8 * itemSize,
                  color: isDragActive ? c.accent : c.ink2,
                ),
              ),
            ),
          ),
          ...Role.values.map((role) {
            final piece = Piece(role: role, color: widget.side);
            final isPieceActive =
                ref.read(boardEditorControllerProvider(widget.params)).activePieceOnEdit == piece;
            final pieceWidget = PieceWidget(piece: piece, size: itemSize, pieceAssets: pieceAssets);

            return ColoredBox(
              key: Key('piece-button-${piece.color.name}-${piece.role.name}'),
              color: isPieceActive ? c.accentSoft : Colors.transparent,
              child: GestureDetector(
                child: Draggable(
                  data: Piece(role: role, color: widget.side),
                  feedback: PieceDragFeedback(
                    piece: piece,
                    squareSize: itemSize,
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
            width: itemSize,
            height: itemSize,
            child: ColoredBox(
              // Demo erase tool: active state is accent, never red.
              color: isDeleteActive ? c.accentSoft : Colors.transparent,
              child: GestureDetector(
                onTap: () =>
                    ref.read(editorController.notifier).updateMode(EditorPointerMode.edit, null),
                child: Icon(
                  CupertinoIcons.delete,
                  size: 0.75 * itemSize,
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
    // The text actions wrap on a narrow phone; the pill stays on its own line, as the demo's
    // actions row does (`<span></span><button class="pill">`), where the pill is the one
    // affirmative action and belongs at the end of the row rather than among the labels.
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 14,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
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
                        onPressed: () => _showContinueFromHereMenu(
                          context,
                          editorState.variant,
                          editorState.fen,
                        ),
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
          // The demo's actions row ends with a *Copy FEN* pill and nothing after it, so the pill
          // sits on its own line right-aligned rather than among the labels: it is the row's one
          // affirmative action. A clipboard write is not undoable from the screen, so it confirms
          // itself with a toast.
          Align(
            alignment: Alignment.centerRight,
            child: SrsPillButton(
              label: 'Copy FEN',
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: editorState.fen));
                if (context.mounted) {
                  showSnackBar(context, 'FEN copied.');
                }
              },
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
