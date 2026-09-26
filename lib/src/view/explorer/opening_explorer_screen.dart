import 'package:chess_srs/src/constants.dart';
import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/model/analysis/analysis_controller.dart';
import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chess_srs/src/model/explorer/opening_explorer.dart';
import 'package:chess_srs/src/model/explorer/opening_explorer_preferences.dart';
import 'package:chess_srs/src/styles/styles.dart';
import 'package:chess_srs/src/utils/immersive_mode.dart';
import 'package:chess_srs/src/utils/l10n_context.dart';
import 'package:chess_srs/src/utils/navigation.dart';
import 'package:chess_srs/src/utils/screen.dart';
import 'package:chess_srs/src/utils/share.dart';
import 'package:chess_srs/src/view/analysis/analysis_share_screen.dart';
import 'package:chess_srs/src/view/analysis/game_analysis_board.dart';
import 'package:chess_srs/src/view/explorer/opening_explorer_settings.dart';
import 'package:chess_srs/src/view/explorer/opening_explorer_view.dart';
import 'package:chess_srs/src/widgets/adaptive_action_sheet.dart';
import 'package:chess_srs/src/widgets/buttons.dart';
import 'package:chess_srs/src/widgets/move_list.dart';
import 'package:chess_srs/src/widgets/platform.dart';
import 'package:collection/collection.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

class OpeningExplorerScreen extends ConsumerWidget {
  const OpeningExplorerScreen({required this.options});

  final AnalysisOptions options;

  static Route<dynamic> buildRoute(AnalysisOptions options) {
    return buildScreenRoute(screen: OpeningExplorerScreen(options: options));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrlProvider = analysisControllerProvider(options);
    final c = context.srs;

    final body = switch (ref.watch(ctrlProvider)) {
      AsyncData(value: final state) => _Body(options: options, state: state),
      AsyncError(:final error) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Something went wrong.', style: SrsText.title(c.ink)),
                const SizedBox(height: 12),
                Text(
                  error.toString(),
                  style: TextStyle(
                    fontFamily: SrsText.ui,
                    fontSize: 15,
                    height: 1.45,
                    color: c.ink2,
                  ),
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 18.0,
                  runSpacing: 10.0,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SrsPillButton(
                      label: 'Try again',
                      onPressed: () => ref.invalidate(ctrlProvider),
                    ),
                    SrsTextButton(
                      label: 'Copy details',
                      onPressed: () => Clipboard.setData(ClipboardData(text: error.toString())),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      _ => Center(
        child: Text(
          'Loading…',
          style: TextStyle(fontFamily: SrsText.ui, fontSize: 15, color: c.ink2),
        ),
      ),
    };
    return WakelockWidget(
      child: Scaffold(
        backgroundColor: c.ground,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              SrsPageHead(
                label: 'Review',
                onBack: () => Navigator.of(context).pop(),
                trailing: SemanticIconButton(
                  semanticsLabel: context.l10n.studyShareAndExport,
                  onPressed: () => _showShareMenu(context, ref),
                  icon: const PlatformShareIcon(),
                ),
              ),
              _MoveList(options: options),
              Expanded(child: body),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showShareMenu(BuildContext context, WidgetRef ref) {
    return showAdaptiveActionSheet(
      context: context,
      actions: [
        BottomSheetAction(
          makeLabel: (context) => Text(context.l10n.mobileShareGamePGN),
          onPressed: () {
            Navigator.of(context).push(AnalysisShareScreen.buildRoute(options: options));
          },
        ),
        BottomSheetAction(
          makeLabel: (context) => Text(context.l10n.mobileSharePositionAsFEN),
          onPressed: () {
            final analysisState = ref.read(analysisControllerProvider(options)).requireValue;
            launchShareDialog(context, ShareParams(text: analysisState.currentPosition.fen));
          },
        ),
      ],
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.options, required this.state});

  final AnalysisOptions options;
  final AnalysisState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isTablet = isTabletOrLarger(context);

    // No SafeArea here: the screen shell above already insets all sides.
    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final orientation = constraints.maxWidth > constraints.maxHeight
                  ? Orientation.landscape
                  : Orientation.portrait;
              if (orientation == Orientation.landscape) {
                final sideWidth =
                    constraints.biggest.longestSide - constraints.biggest.shortestSide;
                final defaultBoardSize =
                    constraints.biggest.shortestSide - (kTabletBoardTableSidePadding * 2);
                final boardSize = sideWidth >= 250
                    ? defaultBoardSize
                    : constraints.biggest.longestSide / kGoldenRatio -
                          (kTabletBoardTableSidePadding * 2);
                return Row(
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(
                        left: kTabletBoardTableSidePadding,
                        top: kTabletBoardTableSidePadding,
                        bottom: kTabletBoardTableSidePadding,
                      ),
                      child: GameAnalysisBoard(
                        options: options,
                        boardSize: boardSize,
                        boardRadius: isTablet ? Styles.boardBorderRadius : null,
                        shouldReplaceChildOnUserMove: true,
                      ),
                    ),
                    Flexible(
                      fit: FlexFit.loose,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Card(
                              clipBehavior: Clip.hardEdge,
                              margin: const EdgeInsets.all(kTabletBoardTableSidePadding),
                              semanticContainer: false,
                              child: OpeningExplorerView(
                                pov: options.orientation,
                                position: state.currentPosition,
                                opening: state.currentNode.isRoot
                                    ? LightOpening(eco: '', name: context.l10n.startPosition)
                                    : state.currentNode.opening ?? state.currentBranchOpening,
                                onMoveSelected: (move) {
                                  ref
                                      .read(analysisControllerProvider(options).notifier)
                                      .onUserMove(move);
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              } else {
                final defaultBoardSize = constraints.biggest.shortestSide;
                final remainingHeight = constraints.maxHeight - defaultBoardSize;
                final isSmallScreen = remainingHeight < kSmallHeightMinusBoard;
                final boardSize = isTablet || isSmallScreen
                    ? defaultBoardSize - kTabletBoardTableSidePadding * 2
                    : defaultBoardSize;

                return ListView(
                  padding: isTablet
                      ? const EdgeInsets.symmetric(horizontal: kTabletBoardTableSidePadding)
                      : EdgeInsets.zero,
                  children: [
                    Center(
                      child: GestureDetector(
                        // disable scrolling when dragging the board
                        onVerticalDragStart: (_) {},
                        child: GameAnalysisBoard(
                          options: options,
                          boardSize: boardSize,
                          shouldReplaceChildOnUserMove: true,
                        ),
                      ),
                    ),
                    ConstrainedBox(
                      constraints: BoxConstraints(minHeight: remainingHeight),
                      child: OpeningExplorerView(
                        pov: options.orientation,
                        position: state.currentPosition,
                        opening: state.currentNode.isRoot
                            ? LightOpening(eco: '', name: context.l10n.startPosition)
                            : state.currentNode.opening ?? state.currentBranchOpening,
                        onMoveSelected: (move) {
                          ref.read(analysisControllerProvider(options).notifier).onUserMove(move);
                        },
                        scrollable: false,
                      ),
                    ),
                  ],
                );
              }
            },
          ),
        ),
        _BottomBar(options: options),
      ],
    );
  }
}

class _MoveList extends ConsumerWidget {
  const _MoveList({required this.options});

  final AnalysisOptions options;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrlProvider = analysisControllerProvider(options);

    switch (ref.watch(ctrlProvider)) {
      case AsyncData(value: final state):
        final slicedMoves = state.root.mainline
            .map((e) => e.sanMove.san)
            .toList()
            .asMap()
            .entries
            .slices(2);
        final currentMoveIndex = state.currentNode.position.ply;

        return MoveList(
          type: MoveListType.inline,
          slicedMoves: slicedMoves,
          currentMoveIndex: currentMoveIndex,
          onSelectMove: (index) {
            ref.read(ctrlProvider.notifier).jumpToNthNodeOnMainline(index - 1);
          },
        );
      case _:
        return const SizedBox.shrink();
    }
  }
}

class _BottomBar extends ConsumerWidget {
  const _BottomBar({required this.options});

  final AnalysisOptions options;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(openingExplorerPreferencesProvider.select((value) => value.db));
    final ctrlProvider = analysisControllerProvider(options);
    final canGoBack = ref.watch(ctrlProvider.select((value) => value.requireValue.canGoBack));
    final canGoNext = ref.watch(ctrlProvider.select((value) => value.requireValue.canGoNext));

    final dbLabel = switch (db) {
      OpeningDatabase.master => 'Masters',
      OpeningDatabase.lichess => 'Lichess',
      OpeningDatabase.player => context.l10n.player,
      OpeningDatabase.chessdb => 'ChessDB',
    };

    // Diagram actions replacing the legacy bottom bar: same features,
    // plain text buttons. Database/Flip/Back/Forward all survive the move.
    // Wrap mirrors the demo's wrapping rows: single line when it fits,
    // two lines on narrow screens or large text rather than overflowing.
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
      child: Wrap(
        spacing: 14,
        runSpacing: 6,
        children: [
          RepeatButton(
            onLongPress: canGoBack ? () => _moveBackward(ref) : null,
            child: SrsTextButton(
              key: const ValueKey('goto-previous'),
              label: 'Back',
              onPressed: canGoBack ? () => _moveBackward(ref) : null,
            ),
          ),
          RepeatButton(
            onLongPress: canGoNext ? () => _moveForward(ref) : null,
            child: SrsTextButton(
              key: const ValueKey('goto-next'),
              label: 'Forward',
              onPressed: canGoNext ? () => _moveForward(ref) : null,
            ),
          ),
          SrsTextButton(
            label: dbLabel,
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              isDismissible: true,
              builder: (_) => const OpeningExplorerSettings(),
            ),
          ),
          SrsTextButton(
            label: 'Flip',
            onPressed: () => ref.read(ctrlProvider.notifier).toggleBoard(),
          ),
        ],
      ),
    );
  }

  void _moveForward(WidgetRef ref) =>
      ref.read(analysisControllerProvider(options).notifier).userNext();
  void _moveBackward(WidgetRef ref) =>
      ref.read(analysisControllerProvider(options).notifier).userPrevious();
}
