import 'dart:async';

import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/model/analysis/analysis_controller.dart';
import 'package:chess_srs/src/model/analysis/analysis_preferences.dart';
import 'package:chess_srs/src/model/auth/auth_controller.dart';
import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chess_srs/src/model/common/eval.dart';
import 'package:chess_srs/src/model/engine/evaluation_preferences.dart';
import 'package:chess_srs/src/model/engine/position_evaluator.dart';
import 'package:chess_srs/src/model/game/player.dart';
import 'package:chess_srs/src/utils/focus_detector.dart';
import 'package:chess_srs/src/utils/immersive_mode.dart';
import 'package:chess_srs/src/utils/l10n_context.dart';
import 'package:chess_srs/src/utils/navigation.dart';
import 'package:chess_srs/src/utils/share.dart';
import 'package:chess_srs/src/view/analysis/analysis_actions.dart';
import 'package:chess_srs/src/view/analysis/analysis_layout.dart';
import 'package:chess_srs/src/view/analysis/analysis_player_widget.dart';
import 'package:chess_srs/src/view/analysis/analysis_settings_screen.dart';
import 'package:chess_srs/src/view/analysis/analysis_share_screen.dart';
import 'package:chess_srs/src/view/analysis/game_analysis_board.dart';
import 'package:chess_srs/src/view/analysis/server_analysis.dart';
import 'package:chess_srs/src/view/analysis/tree_view.dart';
import 'package:chess_srs/src/view/engine/engine_button.dart';
import 'package:chess_srs/src/view/engine/engine_gauge.dart';
import 'package:chess_srs/src/view/engine/engine_lines.dart';
import 'package:chess_srs/src/view/explorer/explorer_view.dart';
import 'package:chess_srs/src/view/game/exported_game_title.dart';
import 'package:chess_srs/src/view/game/game_common_widgets.dart';
import 'package:chess_srs/src/view/user/user_or_profile_screen.dart';
import 'package:chess_srs/src/widgets/adaptive_action_sheet.dart';
import 'package:chess_srs/src/widgets/adaptive_choice_picker.dart';
import 'package:chess_srs/src/widgets/buttons.dart';
import 'package:chess_srs/src/widgets/feedback.dart';
import 'package:chess_srs/src/widgets/move_times_chart.dart';
import 'package:chess_srs/src/widgets/user.dart';
import 'package:chess_srs/src/widgets/variant_app_bar_title.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

final _logger = Logger('AnalysisScreen');

class AnalysisScreen extends StatelessWidget {
  const AnalysisScreen({required this.options, super.key});

  final AnalysisOptions options;

  static Route<dynamic> buildRoute(AnalysisOptions options) {
    return buildScreenRoute(screen: AnalysisScreen(options: options));
  }

  @override
  Widget build(BuildContext context) {
    return _AnalysisScreen(options: options);
  }
}

class _AnalysisScreen extends ConsumerStatefulWidget {
  const _AnalysisScreen({required this.options});

  final AnalysisOptions options;

  @override
  ConsumerState<_AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends ConsumerState<_AnalysisScreen> {
  @override
  Widget build(BuildContext context) {
    final ctrlProvider = analysisControllerProvider(widget.options);
    final asyncState = ref.watch(ctrlProvider);
    final c = context.srs;

    switch (asyncState) {
      case AsyncData(:final value):
        final studyName = value.pgnHeaders['Study'];
        final chapterName = value.pgnHeaders['Chapter'] ?? value.pgnHeaders['Event'];
        final displayTitle = studyName != null
            ? (chapterName != null && chapterName != studyName && chapterName != '?'
                  ? '$studyName • $chapterName'
                  : studyName)
            : (chapterName != null &&
                      chapterName != '?' &&
                      chapterName != 'Standard' &&
                      chapterName != 'Untitled Study'
                  ? chapterName
                  : null);

        final appBarTitle = displayTitle != null
            ? VariantAppBarTitle(variant: value.variant, title: displayTitle)
            : (value.archivedGame != null
                  ? ExportedGameTitle(
                      meta: value.archivedGame!.meta,
                      lastMoveAt: value.archivedGame!.data.lastMoveAt,
                      isImport: value.archivedGame!.source.isImport,
                      importDate: value.archivedGame!.data.importDate,
                    )
                  : VariantAppBarTitle(variant: value.variant, title: context.l10n.analysis));

        // Quiet scene-title line under the header (demo meta treatment).
        //
        // Only rendered when it says something the header does not. A bare "Analysis" for a
        // standalone board is just the screen's own name, and on a phone it costs a line of
        // vertical space the moves tree and the charts need.
        final Widget? titleLine = displayTitle != null
            ? Text(
                displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SrsText.meta(c.ink2),
              )
            : (value.archivedGame != null ? appBarTitle : null);

        return WakelockWidget(
          child: Scaffold(
            resizeToAvoidBottomInset: false,
            backgroundColor: c.ground,
            body: SafeArea(
              child: Column(
                children: [
                  SrsPageHead(
                    label: 'Review',
                    onBack: () => Navigator.of(context).pop(),
                    trailing: _AnalysisMenu(options: widget.options),
                  ),
                  if (titleLine != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 2, 24, 8),
                        child: titleLine,
                      ),
                    ),
                  Expanded(
                    child: _TabbedBody(
                      options: widget.options,
                      // Move times can only be shown for games played with a clock.
                      showMoveTimes: value.chartClocks.isNotEmpty,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      case AsyncError(:final error, :final stackTrace):
        _logger.severe('Cannot load analysis:', error, stackTrace);
        return Scaffold(
          resizeToAvoidBottomInset: false,
          backgroundColor: c.ground,
          body: SafeArea(
            child: Column(
              children: [
                SrsPageHead(label: 'Review', onBack: () => Navigator.of(context).pop()),
                Expanded(
                  child: SingleChildScrollView(
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
                              '$error',
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
                                  onPressed: () => Clipboard.setData(ClipboardData(text: '$error')),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      case _:
        return Scaffold(
          resizeToAvoidBottomInset: false,
          backgroundColor: c.ground,
          body: SafeArea(
            child: Column(
              children: [
                SrsPageHead(label: 'Review', onBack: () => Navigator.of(context).pop()),
                Expanded(
                  child: Center(
                    child: Text(
                      'Loading…',
                      style: TextStyle(fontFamily: SrsText.ui, fontSize: 15, color: c.ink2),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
    }
  }
}

/// Owns the tab list and its controller.
///
/// Which tabs are available depends on the loaded game, so the list can only be built once the
/// analysis state is available.
class _TabbedBody extends StatefulWidget {
  const _TabbedBody({required this.options, required this.showMoveTimes});

  final AnalysisOptions options;
  final bool showMoveTimes;

  @override
  State<_TabbedBody> createState() => _TabbedBodyState();
}

class _TabbedBodyState extends State<_TabbedBody> with SingleTickerProviderStateMixin {
  late final List<AnalysisTab> tabs;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();

    tabs = [
      AnalysisTab.explorer,
      AnalysisTab.moves,
      if (widget.options case ArchivedGame()) AnalysisTab.summary,
      if (widget.showMoveTimes) AnalysisTab.moveTimes,
    ];

    _tabController = TabController(
      vsync: this,
      initialIndex: tabs.indexOf(AnalysisTab.moves),
      length: tabs.length,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _Body(options: widget.options, controller: _tabController, tabs: tabs);
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.options, required this.controller, required this.tabs});

  final TabController controller;
  final AnalysisOptions options;
  final List<AnalysisTab> tabs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analysisPrefs = ref.watch(analysisPreferencesProvider);
    final enginePrefs = ref.watch(engineEvaluationPreferencesProvider);
    final showEvaluationGauge = analysisPrefs.showEvaluationGauge;
    final numEvalLines = enginePrefs.numEvalLines;

    final ctrlProvider = analysisControllerProvider(options);
    final analysisState = ref.watch(ctrlProvider).requireValue;

    final isEngineAvailable = analysisState.isEngineAvailable(enginePrefs);
    final currentNode = analysisState.currentNode;
    final pov = analysisState.pov;

    Widget? boardFooter;
    Widget? boardHeader;
    if (analysisState.archivedGame != null) {
      final hasClock =
          analysisState.isOnMainline &&
          analysisState.currentPosition.ply < analysisState.archivedGame!.steps.length;
      final footerPlayer = analysisState.archivedGame!.playerOf(pov);
      final headerPlayer = analysisState.archivedGame!.playerOf(pov.opposite);
      final footerClock = hasClock
          ? analysisState.archivedGame!.archivedClockOf(pov, analysisState.currentPosition.ply)
          : null;
      final headerClock = hasClock
          ? analysisState.archivedGame!.archivedClockOf(
              pov.opposite,
              analysisState.currentPosition.ply,
            )
          : null;
      final resultString = analysisState.pgnHeaders.get('Result');
      final result = resultString != null
          ? AnalysisGameResult.resultFromPgnResult(resultString)
          : null;
      boardFooter = AnalysisPlayerWidget(
        playerNameWidget: _PlayerName(player: footerPlayer),
        clock: footerClock,
        isSideToMove: analysisState.currentPosition.turn == pov,
        result: result,
        side: pov,
      );
      boardHeader = AnalysisPlayerWidget(
        playerNameWidget: _PlayerName(player: headerPlayer),
        clock: headerClock,
        isSideToMove: analysisState.currentPosition.turn == pov.opposite,
        result: result,
        side: pov.opposite,
      );
    } else if (options case Pgn()) {
      final playerWidgets = playerWidgetsFromPgnHeaders(
        pgnHeaders: analysisState.pgnHeaders,
        sideToMove: analysisState.currentPosition.turn,
        whiteClock: analysisState.currentPosition.turn == Side.white
            ? analysisState.clocks?.parentClock
            : analysisState.clocks?.clock,
        blackClock: analysisState.currentPosition.turn == Side.black
            ? analysisState.clocks?.parentClock
            : analysisState.clocks?.clock,
      );

      (boardFooter, boardHeader) = pov == Side.white
          ? (playerWidgets.white, playerWidgets.black)
          : (playerWidgets.black, playerWidgets.white);
    }

    return FocusDetector(
      onFocusRegained: () {
        if (context.mounted) {
          ref.read(analysisControllerProvider(options).notifier).onFocusRegained();
        }
      },
      child: AnalysisLayout(
        tabs: tabs,
        tabController: controller,
        pov: pov,
        sideToMove: analysisState.currentPosition.turn,
        boardBuilder: (context, boardSize, borderRadius) =>
            GameAnalysisBoard(options: options, boardSize: boardSize, boardRadius: borderRadius),
        smallBoard: analysisPrefs.smallBoard,
        boardHeader: boardHeader,
        boardFooter: boardFooter,
        engineGaugeBuilder: showEvaluationGauge && analysisState.hasAvailableEval(enginePrefs)
            ? (context) {
                return EngineGauge(params: analysisState.engineGaugeParams(enginePrefs));
              }
            : null,
        engineLines: isEngineAvailable && numEvalLines > 0 && analysisPrefs.showEngineLines
            ? EngineLines(
                filters: (
                  context: analysisState.evaluationContext,
                  path: analysisState.currentPath,
                ),
                onTapMove: ref.read(ctrlProvider.notifier).onUserMove,
                analysisState: analysisState,
              )
            : null,
        bottomBar: _BottomBar(options: options, tabController: controller),
        pockets: analysisState.currentPosition.pockets,
        children: [
          ExplorerView(
            pov: pov,
            isComputerAnalysisAllowed: analysisState.isComputerAnalysisAllowed,
            position: currentNode.position,
            opening: explorerOpening(
              context,
              variant: analysisState.variant,
              isRootNode: analysisState.currentNode.isRoot,
              nodeOpening: analysisState.currentNode.opening,
              branchOpening: analysisState.currentBranchOpening,
            ),
            onMoveSelected: (move) {
              ref.read(ctrlProvider.notifier).onUserMove(move);
            },
          ),
          AnalysisTreeView(options),
          if (options case ArchivedGame())
            ServerAnalysisSummary(
              serverAnalysisSource: analysisState.serverAnalysisSource,
              playersAnalysis: analysisState.playersAnalysis,
              pgnHeaders: analysisState.pgnHeaders,
              whiteUser: analysisState.archivedGame?.white.user,
              blackUser: analysisState.archivedGame?.black.user,
              acplChartParams: analysisState.acplChartData != null
                  ? (
                      acplChartData: analysisState.acplChartData!,
                      division: analysisState.division,
                      rootPly: analysisState.root.position.ply,
                      currentNodePly: analysisState.currentPosition.ply,
                      isOnMainline: analysisState.isOnMainline,
                      onJumpToNode: ref
                          .read(analysisControllerProvider(options).notifier)
                          .jumpToNthNodeOnMainline,
                    )
                  : null,
              onRequestServerAnalysis: ref.read(ctrlProvider.notifier).requestServerAnalysis,
            ),
          if (tabs.contains(AnalysisTab.moveTimes))
            ListView(
              children: [
                MoveTimesChart(
                  params: (
                    moveTimes: analysisState.chartMoveTimes,
                    clocks: analysisState.chartClocks,
                    division: analysisState.division,
                    rootPly: analysisState.root.position.ply,
                    currentNodePly: analysisState.currentPosition.ply,
                    isOnMainline: analysisState.isOnMainline,
                    onJumpToNode: ref
                        .read(analysisControllerProvider(options).notifier)
                        .jumpToNthNodeOnMainline,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _PlayerName extends StatelessWidget {
  const _PlayerName({required this.player});

  final Player player;

  @override
  Widget build(BuildContext context) {
    return player.user != null
        ? UserFullNameWidget.player(
            user: player.user,
            name: player.name,
            rating: player.rating,
            ratingDiff: player.ratingDiff,
            provisional: player.provisional,
            aiLevel: player.aiLevel,
            style: const TextStyle(fontWeight: FontWeight.bold),
            onTap: () => Navigator.of(context).push(UserOrProfileScreen.buildRoute(player.user!)),
          )
        : Text(player.fullName(context.l10n));
  }
}

class _BottomBar extends ConsumerWidget {
  const _BottomBar({required this.options, required this.tabController});

  final AnalysisOptions options;
  final TabController tabController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrlProvider = analysisControllerProvider(options);
    final analysisState = ref.watch(ctrlProvider).requireValue;
    final notifier = ref.read(ctrlProvider.notifier);

    // Engine controls as individual wrap items rather than one atomic Row: inside a `Wrap` an
    // atomic child that does not fit the remaining space claims a whole line by itself, which is
    // how this row ended up three lines tall.
    final engineControls = <Widget>[];
    if (analysisState.isComputerAnalysisAllowed) {
      final filters = (context: analysisState.evaluationContext, path: analysisState.currentPath);
      // Whether a deeper search is offered is decided inside _EnginePopup, which owns the action
      // now; the row only supplies the callback.
      ref.watch(engineEvaluationProvider(filters));
      engineControls.addAll([
        const SrsRowRule(),
        // No 'Engine' label and no switch (owner report 2026-09-29): the
        // button taps to toggle the engine off/on, so both were redundant
        // chrome crowding the wrap row into extra lines.
        _EngineToggleButton(
          filters: filters,
          savedEval: analysisState.currentNode.eval,
          enabled: analysisState.isEngineAllowed,
          onToggle: notifier.toggleEngine,
          goDeeper: () => notifier.requestEval(goDeeper: true),
        ),
        // No "Deeper" button here. _EnginePopup already offers it (engine_button.dart), and
        // long-pressing the engine button is the gesture that opens it -- so a second copy in
        // this row duplicated the same action.
        //
        // The width mattered: this row's items totalled 669px plus 90px of spacing against 360px
        // available, so it needed three lines at 390px wide, which left the tab viewport 93px for
        // a 143px move-times chart. The chart then overflowed its clipping viewport and taps below
        // the fold were dropped -- the same failure mode as the viewport crush fixed in #15, still
        // live for archived games. Removing the duplicate takes the row to 635px, inside the 720px
        // two lines allow.
      ]);
    }

    // Diagram actions replacing the legacy bottom bar: same features as the old icon bar, as plain
    // text buttons. Menu/Flip/Back/Forward all survive the move, and the engine controls join them.
    //
    // `Wrap`, never a horizontal scroll: design/docs/04-screens-and-flows.md §6 requires that
    // nothing requires horizontal scrolling at any supported width. Controls reflow onto a second
    // line instead of hiding behind a scroll gesture.
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      child: Wrap(
        spacing: 10,
        runSpacing: 0,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          RepeatButton(
            onLongPress: analysisState.canGoBack ? () => _moveBackward(ref, fastSeek: true) : null,
            child: SrsTextButton(
              key: const ValueKey('goto-previous'),
              label: 'Back',
              onPressed: analysisState.canGoBack ? () => _moveBackward(ref) : null,
            ),
          ),
          RepeatButton(
            onLongPress: analysisState.canGoNext ? () => _moveForward(ref, fastSeek: true) : null,
            child: SrsTextButton(
              key: const ValueKey('goto-next'),
              label: 'Forward',
              onPressed: analysisState.canGoNext ? () => _moveForward(ref) : null,
            ),
          ),
          ...engineControls,
          // The engine group already opens with a rule, so a second one here would only cost
          // 31px. With no engine group there is nothing to separate, so it gets the rule instead.
          if (engineControls.isEmpty) const SrsRowRule(),
          SrsTextButton(label: 'Menu', onPressed: () => _showAnalysisMenu(context, ref)),
          SrsTextButton(label: 'Flip', onPressed: () => notifier.toggleBoard()),
        ],
      ),
    );
  }

  void _moveForward(WidgetRef ref, {bool fastSeek = false}) =>
      ref.read(analysisControllerProvider(options).notifier).userNext(fastSeek: fastSeek);

  void _moveBackward(WidgetRef ref, {bool fastSeek = false}) =>
      ref.read(analysisControllerProvider(options).notifier).userPrevious(fastSeek: fastSeek);

  Future<void> _showAnalysisMenu(BuildContext context, WidgetRef ref) {
    final analysisState = ref.read(analysisControllerProvider(options)).requireValue;
    final evalPrefs = ref.watch(engineEvaluationPreferencesProvider);
    final authUser = ref.read(authControllerProvider);

    return showAdaptiveActionSheet(
      context: context,
      actions: [
        BottomSheetAction(
          makeLabel: (context) => Text(context.l10n.settingsSettings),
          onPressed: () =>
              Navigator.of(context).push(AnalysisSettingsScreen.buildRoute(options: options)),
        ),
        if (options case Standalone()) ...[
          BottomSheetAction(
            makeLabel: (context) => Text(context.l10n.clearSavedMoves),
            onPressed: () => ref
                .read(analysisControllerProvider(options).notifier)
                .clearSavedStandaloneAnalysis(),
          ),
          // Only allow changing the variant if this is standalone analysis entered from the home screen,
          // but not for any other case like puzzle analysis or an active correspondence game.
          BottomSheetAction(
            makeLabel: (context) => Text(context.l10n.variant),
            onPressed: () => showChoicePicker<Variant>(
              context,
              choices: readSupportedVariants
                  .where(
                    (variant) => variant != Variant.fromPosition && variant != Variant.chess960,
                  )
                  .toList(),
              selectedItem: analysisState.variant,
              labelBuilder: (variant) => VariantLabel(variant),
              onSelectedItemChanged: (Variant variant) =>
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    ref
                        .read(analysisControllerProvider(options).notifier)
                        .clearSavedStandaloneAnalysis();
                    Navigator.of(context, rootNavigator: true).pushReplacement(
                      buildScreenRoute<dynamic>(
                        screen: AnalysisScreen(
                          options: (options as Standalone).copyWith(variant: variant),
                        ),
                        transitionDuration: Duration.zero,
                      ),
                    );
                  }),
            ),
          ),
        ],
        if (analysisState.isEngineAvailable(evalPrefs) && analysisState.canShowThreat)
          BottomSheetAction(
            makeLabel: (context) => Text(
              analysisState.engineInThreatMode
                  ? context.l10n.mobileStopShowingThreat
                  : context.l10n.showThreat,
            ),
            onPressed: () =>
                ref.read(analysisControllerProvider(options).notifier).toggleEngineThreatMode(),
          ),
        if (options case ArchivedGame())
          if (analysisState.canRequestServerAnalysis)
            BottomSheetAction(
              makeLabel: (context) => Text(context.l10n.requestAComputerAnalysis),
              onPressed: () {
                if (authUser == null) {
                  showSnackBar(context, context.l10n.youNeedAnAccountToDoThat);
                  return;
                }
                ref
                    .read(analysisControllerProvider(options).notifier)
                    .requestServerAnalysis()
                    .catchError((Object e) {
                      if (context.mounted) {
                        showSnackBar(context, e.toString(), type: SnackBarType.error);
                      }
                    });
                tabController.animateTo(2);
              },
            ),
        // board editor can be used to quickly analyze a position, so engine must be allowed to access
        if (analysisState.isComputerAnalysisAllowed)
          BottomSheetAction(
            makeLabel: (context) => Text(context.l10n.boardEditor),
            onPressed: () => openBoardEditor(
              context,
              analysisState.variant,
              analysisState.currentPosition.fen,
              analysisState.pov,
            ),
          ),
        if (analysisState.isComputerAnalysisAllowed)
          BottomSheetAction(
            makeLabel: (context) => Text(context.l10n.continueFromHere),
            onPressed: () => showContinueFromHereMenu(
              context,
              analysisState.variant,
              analysisState.currentPosition.fen,
            ),
          ),
      ],
    );
  }
}

/// Engine on/off button that stays disabled while a toggle is in flight.
///
/// A previous revision kept the in-flight future in a `Builder` local and
/// read it through a `FutureBuilder`: the builder captured null at build time
/// and nothing ever rebuilt it, so the waiting guard never engaged and rapid
/// double-taps fired concurrent `toggleEngine` calls. Holding the future in
/// state makes the guard real.
class _EngineToggleButton extends StatefulWidget {
  const _EngineToggleButton({
    required this.filters,
    required this.enabled,
    required this.onToggle,
    required this.goDeeper,
    this.savedEval,
  });

  final EngineEvaluationFilters filters;
  final ClientEval? savedEval;
  final bool enabled;
  final Future<void> Function() onToggle;
  final VoidCallback goDeeper;

  @override
  State<_EngineToggleButton> createState() => _EngineToggleButtonState();
}

class _EngineToggleButtonState extends State<_EngineToggleButton> {
  Future<void>? _toggleFuture;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _toggleFuture,
      builder: (context, snapshot) {
        return EngineButton(
          filters: widget.filters,
          savedEval: widget.savedEval,
          onTap: widget.enabled && snapshot.connectionState != ConnectionState.waiting
              ? () async {
                  final future = widget.onToggle();
                  setState(() => _toggleFuture = future);
                  try {
                    await future;
                  } finally {
                    if (mounted) setState(() => _toggleFuture = null);
                  }
                }
              : null,
          goDeeper: widget.goDeeper,
        );
      },
    );
  }
}

/// App bar menu holding the game actions: bookmark, share and export.
class _AnalysisMenu extends ConsumerWidget {
  const _AnalysisMenu({required this.options});

  final AnalysisOptions options;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analysisState = ref.watch(analysisControllerProvider(options)).value;
    if (analysisState == null) return const SizedBox.shrink();

    final archivedGame = analysisState.archivedGame;

    // The Diagram action sheet rather than `ContextMenuIconButton`, which on iOS was a
    // long-press preview menu in Cupertino colours and on every other platform a Material popup --
    // the same top-bar button looking like two different things. `00-agent-brief.md` open decision
    // 4, resolved 2026-09-28. The share icon is no longer platform-conditional for the same reason.
    return IconButton(
      icon: const Icon(Icons.more_horiz),
      tooltip: context.l10n.menu,
      onPressed: () => showAdaptiveActionSheet<void>(
        context: context,
        actions: [
          if (archivedGame != null)
            BottomSheetAction(
              leading: archivedGame.data.bookmarked == true
                  ? const Icon(Icons.bookmark_remove_outlined, size: 20)
                  : const Icon(Icons.bookmark_add_outlined, size: 20),
              makeLabel: (_) => Text(
                archivedGame.data.bookmarked == true
                    ? context.l10n.mobileRemoveBookmark
                    : context.l10n.bookmarkThisGame,
              ),
              onPressed: () =>
                  ref.read(analysisControllerProvider(options).notifier).toggleBookmark(),
            ),
          if (analysisState.gameId != null || analysisState.isComputerAnalysisAllowed)
            BottomSheetAction(
              leading: const Icon(Icons.share_outlined, size: 20),
              makeLabel: (_) => Text(context.l10n.studyShareAndExport),
              onPressed: () => _showShareMenu(context, ref),
            ),
        ],
      ),
    );
  }

  Future<void> _showShareMenu(BuildContext context, WidgetRef ref) {
    final analysisState = ref.read(analysisControllerProvider(options)).requireValue;
    final archivedGame = analysisState.archivedGame;
    return showAdaptiveActionSheet(
      context: context,
      actions: [
        // Share the original game from the server: URL, GIF and PGN downloads.
        if (archivedGame != null)
          ...makeFinishedGameShareBottomSheetActions(
            context,
            ref,
            gameId: archivedGame.id,
            orientation: analysisState.pov,
            finished: archivedGame.finished,
          ),
        // share position as FEN can be used to quickly analyze a position, so engine must be allowed to access
        if (analysisState.isComputerAnalysisAllowed)
          BottomSheetAction(
            makeLabel: (context) => Text(context.l10n.mobileSharePositionAsFEN),
            onPressed: () {
              final currentState = ref.read(analysisControllerProvider(options)).requireValue;
              launchShareDialog(context, ShareParams(text: currentState.currentPosition.fen));
            },
          ),
        // Shares the current PGN, including local analysis and edited tags. Can be
        // used to quickly analyze a position, so the engine must be allowed to access.
        if (analysisState.isComputerAnalysisAllowed)
          BottomSheetAction(
            // TODO: l10n
            makeLabel: (context) => const Text('Share local analysis PGN'),
            onPressed: () {
              Navigator.of(context).push(AnalysisShareScreen.buildRoute(options: options));
            },
          ),
      ],
    );
  }
}
