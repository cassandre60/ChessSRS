// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;

import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chess_srs/src/model/settings/board_preferences.dart';
import 'package:chess_srs/src/model/study/study_preferences.dart';
import 'package:chess_srs/src/review/review_controller.dart';
import 'package:chess_srs/src/utils/l10n_context.dart';
import 'package:chess_srs/src/view/analysis/analysis_options.dart';
import 'package:chess_srs/src/view/analysis/analysis_screen.dart';
import 'package:chess_srs/src/view/review/repertoire_import_dialog.dart';
import 'package:chess_srs/src/view/review/review_scope_drawer.dart';
import 'package:chess_srs/src/view/settings/srs_settings_screen.dart';
import 'package:chess_srs/src/widgets/board.dart';
import 'package:chess_srs/src/widgets/pgn_shapes.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Board-dominant Review screen for active spaced-repetition training.
class ReviewScreen extends ConsumerWidget {
  const ReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviewStateAsync = ref.watch(reviewControllerProvider);
    final c = context.srs;

    return Scaffold(
      backgroundColor: c.ground,
      body: SafeArea(
        child: reviewStateAsync.when(
          data: (state) {
            if (state.studies.isEmpty) {
              return const _NoStudiesView();
            }
            if (state.isComplete) {
              return _NothingDueView(state: state);
            }
            return _ActiveReviewView(state: state, prompt: state.currentPrompt!);
          },
          loading: () => Center(
            child: Text(
              'Loading…',
              style: TextStyle(fontFamily: SrsText.ui, fontSize: 15, color: c.ink2),
            ),
          ),
          error: (err, stack) => Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 36.0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Something went wrong.', style: SrsText.title(c.ink)),
                    const SizedBox(height: 12.0),
                    Text(
                      '$err',
                      style: TextStyle(
                        fontFamily: SrsText.ui,
                        fontSize: 15,
                        height: 1.45,
                        color: c.ink2,
                      ),
                    ),
                    const SizedBox(height: 24.0),
                    Wrap(
                      spacing: 18.0,
                      runSpacing: 10.0,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SrsPillButton(
                          label: 'Try again',
                          onPressed: () => ref.invalidate(reviewControllerProvider),
                        ),
                        SrsTextButton(
                          label: 'Copy details',
                          onPressed: () => Clipboard.setData(ClipboardData(text: '$err')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NoStudiesView extends StatefulWidget {
  const _NoStudiesView();

  @override
  State<_NoStudiesView> createState() => _NoStudiesViewState();
}

class _NoStudiesViewState extends State<_NoStudiesView> {
  Side? _trainSide;

  @override
  Widget build(BuildContext context) {
    final c = context.srs;
    final mediaQuery = MediaQuery.of(context);
    // Side-by-side needs 500 (copy) + 64 (gap) + ~412 (380 board plus outside coordinates) +
    // 80 (page padding) = ~1056, so the breakpoint sits at 1100 rather than 900: a 900px
    // desktop window showed the row overflowing by ~150px, which the captures never checked
    // (390 and 1440 only) and the suite never reported (it swallows RenderFlex errors).
    final isWide = mediaQuery.size.width >= 1100;
    final headlineSize = math.max(38.0, math.min(mediaQuery.size.width * 0.08, 56.0));

    final welcomeContent = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 500),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SrsLogoMark(size: 22),
              const SizedBox(width: 10),
              Text('ChessSRS', style: SrsText.wordmark(c.ink)),
            ],
          ),
          const SizedBox(height: 32.0),
          Text(
            context.l10n.mobileReviewNoStudiesHeadline,
            style: TextStyle(
              fontFamily: SrsText.ui,
              fontSize: headlineSize,
              fontWeight: FontWeight.w400,
              letterSpacing: -0.04 * headlineSize,
              height: 1.0,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 16.0),
          Text(
            context.l10n.mobileReviewNoStudiesSubtext,
            style: TextStyle(fontFamily: SrsText.ui, fontSize: 17, height: 1.45, color: c.ink2),
          ),
          const SizedBox(height: 28.0),
          CustomPaint(
            painter: _DashedBorderPainter(color: c.ink3, strokeWidth: 1.5, radius: 14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22.0, vertical: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.l10n.mobileReviewNoStudiesDropZone,
                    style: TextStyle(fontFamily: SrsText.ui, fontSize: 15.5, color: c.ink),
                  ),
                  const SizedBox(height: 16.0),
                  SrsPillButton(
                    label: context.l10n.mobileReviewNoStudiesChooseFile,
                    onPressed: () => RepertoireImportDialog.show(
                      context,
                      initialSource: ImportSource.file,
                      initialSide: _trainSide,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16.0),
          Wrap(
            spacing: 22.0,
            runSpacing: 8.0,
            children: [
              SrsTextButton(
                label: context.l10n.mobileReviewNoStudiesPastePgn,
                onPressed: () => RepertoireImportDialog.show(
                  context,
                  initialSource: ImportSource.file,
                  initialSide: _trainSide,
                ),
              ),
              SrsTextButton(
                label: context.l10n.mobileReviewNoStudiesImportLichess,
                onPressed: () => RepertoireImportDialog.show(
                  context,
                  initialSource: ImportSource.lichess,
                  initialSide: _trainSide,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24.0),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.l10n.mobileReviewNoStudiesTrainAs,
                style: TextStyle(fontFamily: SrsText.ui, fontSize: 14, color: c.ink2),
              ),
              const SizedBox(width: 12.0),
              SrsSegmented<Side?>(
                options: {
                  null: context.l10n.mobileReviewNoStudiesAuto,
                  Side.white: context.l10n.white,
                  Side.black: context.l10n.black,
                },
                value: _trainSide,
                onChanged: (val) => setState(() => _trainSide = val),
              ),
            ],
          ),
        ],
      ),
    );

    return Column(
      children: [
        SrsTopBar(
          activeSide: Side.white,
          dueCount: 0,
          onSidePressed: (side) => _openColourDrawer(context, side),
          onOverflowPressed: () => _openSettings(context),
        ),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: isWide ? 40.0 : 24.0, vertical: 24.0),
              child: isWide
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        welcomeContent,
                        const SizedBox(width: 64.0),
                        _AmbientFirstBoard(side: _trainSide),
                      ],
                    )
                  : welcomeContent,
            ),
          ),
        ),
      ],
    );
  }
}

class _AmbientFirstBoard extends ConsumerWidget {
  const _AmbientFirstBoard({required this.side});
  final Side? side;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.srs;
    final boardPrefs = ref.watch(boardPreferencesProvider);
    final orientation = side ?? Side.white;
    const boardSize = 380.0;

    final chessboardSettings = StaticChessboardSettings(
      pieceAssets: boardPrefs.pieceSet.assets,
      colorScheme: srsBoardColorScheme(c),
      brightness: boardPrefs.brightness,
      hue: boardPrefs.hue,
      enableCoordinates: false,
    );

    final board = Stack(
      children: [
        const SrsBoardBackground(size: boardSize),
        StaticChessboard(
          size: boardSize,
          fen: kInitialFEN,
          orientation: orientation,
          settings: chessboardSettings,
        ),
      ],
    );

    return SrsBoardWithCoordinates(
      size: boardSize,
      board: board,
      outside: true,
      whiteAtBottom: orientation == Side.white,
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({
    required this.color,
    required this.strokeWidth,
    required this.radius,
  });

  final Color color;
  final double strokeWidth;
  final double radius;
  static const double dashLength = 6.0;
  static const double gapLength = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    final half = strokeWidth / 2;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(half, half, size.width - strokeWidth, size.height - strokeWidth),
      Radius.circular(radius),
    );

    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final len = math.min(dashLength, metric.length - distance);
        final extract = metric.extractPath(distance, distance + len);
        canvas.drawPath(extract, paint);
        distance += dashLength + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.strokeWidth != strokeWidth || old.radius != radius;
}

class _NothingDueView extends ConsumerWidget {
  const _NothingDueView({required this.state});

  final ReviewScreenState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.srs;
    final mediaQuery = MediaQuery.of(context);
    final progress = state.activeScopeProgress;
    // The three INV-068 states, read straight off the progress record so they
    // partition the scope instead of being re-derived from `learned`, which put
    // every due-but-unlearned position in two segments at once.
    final retained = progress?.scheduledDecisions ?? 0;
    final learning = progress?.dueDecisions ?? 0;
    final fresh = progress?.freshDecisions ?? 0;

    // A scope holding only never-presented positions has nothing *due*, which
    // used to read as "Nothing due." over a bar showing thousands — when the
    // truth was that the user had simply not started. Name the other state
    // rather than letting an unstarted library look finished (INV-068).
    final hasFreshMaterial = state.totalFreshCount > 0;
    final displayTitle = state.isDailyLimitReached
        ? context.l10n.mobileReviewDailyLimitReached
        : hasFreshMaterial
        ? context.l10n.mobileReviewFreshOnlyTitle
        : context.l10n.mobileReviewNothingDueTitle;
    final headlineSize = math.max(44.0, math.min(mediaQuery.size.width * 0.09, 72.0));

    // Cross-colour continuation: automatic colour review that runs dry offers
    // the other colour's dues, which live in a separate session (INV-030).
    // Narrowed scopes (study/opening/chapter), practice mode, and an exhausted
    // global daily quota (INV-031) never offer it: switching then could only
    // land on another empty board.
    final isAutoSideScope =
        state.scope.side != null &&
        state.scope.studyId == null &&
        state.scope.chapterId == null &&
        state.scope.openingFamily == null;
    final otherSide = state.scope.side == Side.white ? Side.black : Side.white;
    final otherSideDue = state.sideProgress[otherSide]?.dueDecisions ?? 0;
    final showCrossSideButton =
        isAutoSideScope && !state.isPracticeMode && !state.isDailyLimitReached && otherSideDue > 0;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyP): () {
          ref.read(reviewControllerProvider.notifier).startPracticeMode();
        },
      },
      child: Focus(
        autofocus: true,
        child: Column(
          children: [
            SrsTopBar(
              activeSide: state.activeSide,
              dueCount: 0,
              isPracticeMode: state.isPracticeMode,
              onSidePressed: (side) => _openColourDrawer(context, side),
              onOverflowPressed: () => _openSettings(context),
              onExitPractice: state.isPracticeMode
                  ? () => ref.read(reviewControllerProvider.notifier).exitPracticeMode()
                  : null,
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 36.0),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          displayTitle,
                          style: TextStyle(
                            fontFamily: SrsText.ui,
                            fontSize: headlineSize,
                            fontWeight: FontWeight.w400,
                            letterSpacing: -0.045 * headlineSize,
                            height: 0.98,
                            color: c.ink,
                          ),
                        ),
                        const SizedBox(height: 18.0),
                        if (state.isDailyLimitReached)
                          Text(
                            context.l10n.mobileReviewDailyProgress(
                              state.dailyReviewedCount.toString(),
                              state.maxDailyReviews.toString(),
                            ),
                            style: TextStyle(fontFamily: SrsText.ui, fontSize: 18, color: c.ink2),
                          )
                        else if (hasFreshMaterial)
                          Text(
                            context.l10n.mobileReviewFreshOnlySubtext(
                              state.totalFreshCount.toString(),
                            ),
                            style: TextStyle(fontFamily: SrsText.ui, fontSize: 18, color: c.ink2),
                          )
                        else if (state.timeUntilNextReview != null)
                          Text(
                            context.l10n.mobileReviewNextReviewTime(state.timeUntilNextReview!),
                            style: TextStyle(fontFamily: SrsText.ui, fontSize: 18, color: c.ink2),
                          )
                        else
                          Text(
                            context.l10n.mobileReviewNextReviewAutomatic,
                            style: TextStyle(fontFamily: SrsText.ui, fontSize: 18, color: c.ink2),
                          ),
                        const SizedBox(height: 38.0),
                        SrsMemoryBar(
                          retained: retained,
                          learning: learning,
                          fresh: fresh,
                          height: 10,
                          gap: 3,
                          radius: 2,
                        ),
                        const SizedBox(height: 14.0),
                        Wrap(
                          spacing: 22,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _LegendItem(
                              shape: Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: c.ink,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              count: retained,
                              label: context.l10n.mobileReviewLegendRetained,
                            ),
                            _LegendItem(
                              shape: Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(2),
                                  border: Border.all(color: c.ink3, width: 1),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(1),
                                  child: CustomPaint(
                                    painter: HatchPainter(color: c.ink, gap: 3.2, width: 1.2),
                                  ),
                                ),
                              ),
                              count: learning,
                              label: context.l10n.mobileReviewLegendLearning,
                            ),
                            _LegendItem(
                              shape: Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(2),
                                  border: Border.all(color: c.ink3, width: 1),
                                ),
                              ),
                              count: fresh,
                              label: context.l10n.mobileReviewLegendNew,
                            ),
                          ],
                        ),
                        const SizedBox(height: 36.0),
                        Wrap(
                          spacing: 18.0,
                          runSpacing: 10.0,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (showCrossSideButton)
                              SrsPillButton(
                                label: context.l10n.mobileReviewCrossSideButton(
                                  otherSide == Side.white ? context.l10n.white : context.l10n.black,
                                  otherSideDue.toString(),
                                ),
                                onPressed: () {
                                  ref.read(reviewControllerProvider.notifier).selectSide(otherSide);
                                },
                              ),
                            SrsPillButton(
                              label: context.l10n.practice,
                              shortcut: 'P',
                              onPressed: () {
                                ref.read(reviewControllerProvider.notifier).startPracticeMode();
                              },
                            ),
                            SrsTextButton(
                              label: context.l10n.mobileReviewNothingDueChooseRepertoire,
                              // Opens the live colour's drawer rather than
                              // switching colour: this button is about choosing
                              // what to review next, and the squares are what
                              // change colour.
                              onPressed: () =>
                                  ReviewScopeDrawer.show(context, state.scope.side ?? Side.white),
                            ),
                            if (state.isDailyLimitReached)
                              SrsTextButton(
                                label: context.l10n.mobileReviewNothingDueChangeDailyLimit,
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute<void>(
                                    builder: (_) => const SrsSettingsScreen(),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 18.0),
                        Text(
                          state.isDailyLimitReached
                              ? context.l10n.mobileReviewNothingDuePracticeStillAvailable
                              : context.l10n.mobileReviewNothingDuePracticeDoesNotChangeSchedule,
                          style: TextStyle(fontFamily: SrsText.ui, fontSize: 13.5, color: c.ink3),
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
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.shape, required this.count, required this.label});

  final Widget shape;
  final int count;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.srs;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        shape,
        const SizedBox(width: 8),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$count ',
                style: TextStyle(
                  fontFamily: SrsText.ui,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: c.ink,
                  fontFeatures: SrsText.tabular,
                ),
              ),
              TextSpan(
                text: label,
                style: TextStyle(fontFamily: SrsText.ui, fontSize: 14, color: c.ink2),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActiveReviewView extends ConsumerStatefulWidget {
  const _ActiveReviewView({required this.state, required this.prompt});

  final ReviewScreenState state;
  final ReviewPrompt prompt;

  @override
  ConsumerState<_ActiveReviewView> createState() => _ActiveReviewViewState();
}

class _ActiveReviewViewState extends ConsumerState<_ActiveReviewView> {
  ChessboardController? _controller;
  final FocusNode _focusNode = FocusNode();
  GameData? _prewarmedGameData;
  String? _prewarmedFen;
  PlayerSide? _prewarmedPlayerSide;
  Move? _prewarmedLastMove;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  void _initController() {
    final gameData = _buildGameData();
    _controller = ChessboardController(game: gameData);
    _prewarmNextPosition();
  }

  @override
  void didUpdateWidget(_ActiveReviewView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final ctrl = _controller;
    if (ctrl == null) return;

    final newGameData = _buildGameData();
    ctrl.updatePosition(newGameData);
    _prewarmNextPosition();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller?.dispose();
    super.dispose();
  }

  GameData _buildGameData() {
    final boardPrefs = ref.read(boardPreferencesProvider);
    final pos = widget.state.boardPosition ?? Chess.initial;
    final playerSide = widget.state.isAwaitingAdvance
        ? PlayerSide.none
        : (widget.state.boardOrientation == Side.white ? PlayerSide.white : PlayerSide.black);
    final lastMove = widget.state.lastMove;

    final prewarmed = _prewarmedGameData;
    if (prewarmed != null &&
        _prewarmedFen == pos.fen &&
        _prewarmedPlayerSide == playerSide &&
        _prewarmedLastMove == lastMove) {
      _prewarmedGameData = null;
      _prewarmedFen = null;
      _prewarmedPlayerSide = null;
      _prewarmedLastMove = null;
      return prewarmed;
    }

    return buildGameData(
      fen: pos.fen,
      variant: Variant.standard,
      position: pos,
      playerSide: playerSide,
      castlingMethod: boardPrefs.castlingMethod,
      boardHighlights: boardPrefs.boardHighlights,
      lastMove: lastMove,
    );
  }

  void _prewarmNextPosition() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final expected = widget.prompt.expectedMoves.firstOrNull;
      final pos = widget.state.boardPosition;
      if (expected == null || pos == null) return;
      try {
        final parsedMove = Move.parse(expected.uci);
        if (parsedMove == null) return;
        final playedPos = pos.play(parsedMove);
        final playerSide = widget.state.boardOrientation == Side.white
            ? PlayerSide.white
            : PlayerSide.black;
        final boardPrefs = ref.read(boardPreferencesProvider);
        _prewarmedFen = playedPos.fen;
        _prewarmedPlayerSide = playerSide;
        _prewarmedLastMove = parsedMove;
        _prewarmedGameData = buildGameData(
          fen: playedPos.fen,
          variant: Variant.standard,
          position: playedPos,
          playerSide: playerSide,
          castlingMethod: boardPrefs.castlingMethod,
          boardHighlights: boardPrefs.boardHighlights,
          lastMove: parsedMove,
        );
      } catch (_) {
        _prewarmedGameData = null;
        _prewarmedFen = null;
        _prewarmedPlayerSide = null;
        _prewarmedLastMove = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final prompt = widget.prompt;
    final boardPrefs = ref.watch(boardPreferencesProvider);
    final srsColors = SrsTheme.maybeOf(context);

    final showComments = ref.watch(studyPreferencesProvider.select((p) => p.showPgnComments));
    final showAnnotations = ref.watch(studyPreferencesProvider.select((p) => p.showAnnotations));
    final showDiagnostics = ref.watch(studyPreferencesProvider.select((p) => p.srsDiagnostics));
    final showMoveHistory = ref.watch(studyPreferencesProvider.select((p) => p.showMoveHistory));

    final isLapse = state.feedback == ReviewFeedback.incorrect;
    final isAnswerRevealed = isLapse || state.revealedComment != null || state.isAwaitingAdvance;

    final rawComment = state.revealedComment ?? prompt.comment;
    final comment = showComments && rawComment != null && rawComment.isNotEmpty
        ? PgnComment.fromPgn(rawComment).text
        : null;

    final shapes = <Shape>{};
    if (showAnnotations && isAnswerRevealed) {
      if (prompt.comment != null && prompt.comment!.isNotEmpty) {
        final promptPgn = PgnComment.fromPgn(prompt.comment!);
        for (final pgnShape in promptPgn.shapes) {
          shapes.add(pgnShape.chessground);
        }
      }
      if (state.revealedComment != null && state.revealedComment!.isNotEmpty) {
        final revealedPgn = PgnComment.fromPgn(state.revealedComment!);
        for (final pgnShape in revealedPgn.shapes) {
          shapes.add(pgnShape.chessground);
        }
      }
    }

    void onContinue() {
      if (state.isAwaitingAdvance) {
        ref.read(reviewControllerProvider.notifier).continueAdvancement();
      } else {
        ref.read(reviewControllerProvider.notifier).acknowledgeLapse();
      }
    }

    void onSkip() => ref.read(reviewControllerProvider.notifier).skip();

    /// Plays the study move on the learner's behalf and continues through the normal
    /// retry path — the lapse already stands, so this changes the flow, not the grade.
    /// Only offered in the correction state, where recall has already failed and a bare
    /// "Skip" mislabels what is left to do.
    void onRevealAnswer() {
      final expected = state.expectedMove;
      if (expected == null) return;
      ref
          .read(reviewControllerProvider.notifier)
          .onUserMove(
            NormalMove(
              from: Square.fromName(expected.from),
              to: Square.fromName(expected.to),
              promotion: switch (expected.promotion) {
                'q' => Role.queen,
                'r' => Role.rook,
                'b' => Role.bishop,
                'n' => Role.knight,
                _ => null,
              },
            ),
          );
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): () {
          if (state.isAwaitingAdvance) onContinue();
        },
        const SingleActivator(LogicalKeyboardKey.enter): () {
          if (state.isAwaitingAdvance) onContinue();
        },
        const SingleActivator(LogicalKeyboardKey.numpadEnter): () {
          if (state.isAwaitingAdvance) onContinue();
        },
        const SingleActivator(LogicalKeyboardKey.arrowRight): () {
          if (state.isAwaitingAdvance) onContinue();
        },
        const SingleActivator(LogicalKeyboardKey.keyS): () {
          if (state.isAwaitingAdvance) return;
          if (isLapse && state.expectedMove != null) {
            onRevealAnswer();
          } else {
            onSkip();
          }
        },
      },
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        child: SrsReviewLayout(
          whiteAtBottom: state.boardOrientation == Side.white,
          topBar: SrsTopBar(
            activeSide: state.activeSide,
            dueCount: state.totalDueCount,
            isPracticeMode: state.isPracticeMode,
            onSidePressed: (side) => _openColourDrawer(context, side),
            onOverflowPressed: () => _openSettings(context),
            onExitPractice: state.isPracticeMode
                ? () => ref.read(reviewControllerProvider.notifier).exitPracticeMode()
                : null,
          ),
          board: (context, size, wide) => GestureDetector(
            behavior: HitTestBehavior.translucent,
            // A tap landing inside the opponent pre-move animation window
            // addresses undraggable pieces and would die silently: snap the
            // board to the live prompt first so the gesture that follows
            // reaches a position the user can actually move on. No-op once
            // the board agrees (see cancelPreMoveAnimation).
            onTapDown: (_) => ref.read(reviewControllerProvider.notifier).cancelPreMoveAnimation(),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                RepaintBoundary(
                  child: Semantics(
                    container: true,
                    label: _boardSemanticsLabel(prompt, state.boardOrientation),
                    child: BoardWidget(
                      size: size,
                      orientation: state.boardOrientation,
                      settings: boardPrefs
                          .toBoardSettings(Variant.standard, srsColors: srsColors)
                          .copyWith(enableCoordinates: false),
                      controller: _controller!,
                      onMove: (move, {viaDragAndDrop}) {
                        ref.read(reviewControllerProvider.notifier).onUserMove(move);
                      },
                      onTouchedSquare: (sq) {
                        ref.read(reviewControllerProvider.notifier).prewarmMoveCandidate(sq);
                      },
                      shapes: shapes,
                    ),
                  ),
                ),
                if (isLapse && state.expectedMove != null)
                  Positioned.fill(
                    child: SrsMoveArrow(
                      from: state.expectedMove!.from,
                      to: state.expectedMove!.to,
                      whiteAtBottom: state.boardOrientation == Side.white,
                    ),
                  ),
                if (state.isAwaitingAdvance)
                  Positioned.fill(
                    child: Semantics(
                      container: true,
                      button: true,
                      label: 'Continue to next position',
                      onTap: onContinue,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: onContinue,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          side: (context, wide, appWidth) => SrsReviewSide(
            wide: wide,
            lineFontSize: wide ? 28.0 : 24.0,
            meta: _MetaView(
              contextLabel: prompt.chapterTitle ?? prompt.studyTitle ?? '',
              orientation: state.boardOrientation,
              wide: wide,
            ),
            line: showMoveHistory
                ? SrsNotationLine(
                    moves: prompt.moveHistory,
                    answerSan: isAnswerRevealed ? prompt.expectedMoves.firstOrNull?.san : null,
                    showBlank: !isAnswerRevealed,
                    wide: wide,
                    wideWidth: appWidth,
                  )
                : null,
            slot: _buildSlotContent(
              context,
              wide: wide,
              isLapse: isLapse,
              expectedMoveSan: prompt.expectedMoves.firstOrNull?.san ?? state.expectedMove?.san,
              comment: comment,
              showDiagnostics: showDiagnostics,
              state: state,
            ),
            actions: _buildActions(
              context,
              isAwaitingAdvance: state.isAwaitingAdvance,
              isLapse: isLapse,
              canReveal: state.expectedMove != null,
              onSkip: onSkip,
              onRevealAnswer: onRevealAnswer,
              onContinue: onContinue,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSlotContent(
    BuildContext context, {
    required bool wide,
    required bool isLapse,
    required String? expectedMoveSan,
    required String? comment,
    required bool showDiagnostics,
    required ReviewScreenState state,
  }) {
    Widget content = const SizedBox.shrink();

    if (isLapse && expectedMoveSan != null) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _AnswerSlot(san: expectedMoveSan, wide: wide),
          if (comment != null && comment.trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            _NoteSlot(comment: comment.trim(), wide: wide),
          ],
          _OpenInAnalysisButton(state: state),
        ],
      );
    } else if (state.isAwaitingAdvance && comment != null && comment.trim().isNotEmpty) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _NoteSlot(comment: comment.trim(), wide: wide),
          _OpenInAnalysisButton(state: state),
        ],
      );
    }

    final verdict = _verdictAnnouncement(state, expectedMoveSan: expectedMoveSan);
    if (verdict != null) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [_VerdictLiveRegion(verdict), content],
      );
    }

    if (state.pendingUnlock != null) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _UnlockBranchBanner(pending: state.pendingUnlock!),
          if (content is! SizedBox) content,
        ],
      );
    }

    if (showDiagnostics) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _SrsDiagnosticsOverlay(state: state),
          if (content is! SizedBox) ...[const SizedBox(height: 12), content],
        ],
      );
    }

    return content;
  }

  /// The name a screen reader gives the board region.
  ///
  /// The board is a custom-rendered widget with no text alternative, and
  /// design/docs/04-screens-and-flows.md §6 asks it to expose the current
  /// position. The facts available at this level are the chapter the position
  /// belongs to and the side to move — the same two the meta view prints above
  /// it, so a user who lands on the board directly hears where they are.
  String _boardSemanticsLabel(ReviewPrompt prompt, Side orientation) {
    final context = (prompt.chapterTitle ?? prompt.studyTitle)?.trim();
    return [
      if (context != null && context.isNotEmpty) context,
      if (orientation == Side.white) 'White to play' else 'Black to play',
      'Chessboard',
    ].join('. ');
  }

  /// The sentence a screen reader hears after an answer, or null while the question is still open.
  ///
  /// design/docs/04-screens-and-flows.md §6 requires announcing position changes through a live
  /// region, and design/docs/01-identity.md gives the wording: `Correct. {san}.` and `Not this
  /// move. The study move is {san}.` The demo does this through a visually hidden
  /// `aria-live` node; this is the same thing.
  ///
  /// It matters most exactly where it is least visible. A wrong answer already puts the study
  /// move on screen in large letters, so a sighted player is told. A *correct* answer shows
  /// nothing at all — the product is deliberately quiet on success — which left a screen-reader user
  /// with no confirmation that they had got it right, and no way to tell a right answer from a
  /// wrong one.
  ///
  /// On a correct answer this announces the move that was played rather than the expected one,
  /// because `expectedMoves` is a list: a transposition can make an alternative equally correct, and
  /// then the study move is not the move the player made.
  String? _verdictAnnouncement(ReviewScreenState state, {required String? expectedMoveSan}) {
    // `lastStepResult` is the signal, not `isAwaitingAdvance`. A lapse does not set the latter: the
    // review is waiting for the mistake to be acknowledged, not for a Continue. The controller
    // clears `lastStepResult` on advancing, acknowledging and skipping alike, so it is exactly the
    // "the answer has been graded and not yet moved past" window.
    final result = state.lastStepResult;
    if (result == null) return null;
    if (result.isCorrect) {
      final played = result.movePlayed.san;
      return played == null || played.isEmpty
          ? context.l10n.mobileReviewVerdictCorrectBare
          : context.l10n.mobileReviewVerdictCorrectMove(played);
    }
    if (expectedMoveSan == null || expectedMoveSan.isEmpty) {
      return context.l10n.mobileReviewVerdictWrongBare;
    }
    return context.l10n.mobileReviewVerdictWrongMove(expectedMoveSan);
  }

  Widget _buildActions(
    BuildContext context, {
    required bool isAwaitingAdvance,
    required bool isLapse,
    required bool canReveal,
    required VoidCallback onSkip,
    required VoidCallback onRevealAnswer,
    required VoidCallback onContinue,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        if (!isAwaitingAdvance)
          if (isLapse && canReveal)
            // Recall has already failed, so "Skip" mislabels what is left: revealing the
            // study move by playing it on the learner's behalf through the retry path.
            SrsTextButton(
              label: context.l10n.mobileReviewRevealAnswer,
              shortcut: 'S',
              onPressed: onRevealAnswer,
            )
          else
            SrsTextButton(label: context.l10n.mobileReviewSkip, shortcut: 'S', onPressed: onSkip)
        else
          const SizedBox.shrink(),
        if (isAwaitingAdvance)
          SrsPillButton(
            label: context.l10n.mobileReviewContinue,
            shortcut: 'Space',
            onPressed: onContinue,
          )
        else
          const SizedBox.shrink(),
      ],
    );
  }
}

class _MetaView extends StatelessWidget {
  const _MetaView({required this.contextLabel, required this.orientation, required this.wide});

  final String contextLabel;
  final Side orientation;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final c = context.srs;
    final isWhite = orientation == Side.white;
    final turnText = isWhite
        ? context.l10n.mobileReviewWhiteToPlay
        : context.l10n.mobileReviewBlackToPlay;

    final turnWidget = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isWhite ? const Color(0x00000000) : c.ink,
            border: Border.all(color: c.ink, width: 1.5),
          ),
        ),
        const SizedBox(width: 8),
        Text(turnText, style: SrsText.meta(c.ink2)),
      ],
    );

    final labelWidget = Text(
      contextLabel,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: SrsText.meta(c.ink2),
    );

    if (wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [labelWidget, const SizedBox(height: 8), turnWidget],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(child: labelWidget),
        const SizedBox(width: 12),
        turnWidget,
      ],
    );
  }
}

/// Carries the answer's verdict to a screen reader, and nothing at all to the eye.
///
/// A live region announces when its label changes, which is the behaviour the design asks for: the
/// verdict is spoken once, as it happens, rather than being something the user has to go and find.
/// `container: true` forces the node to exist even though the child has no size. `ExcludeSemantics`
/// covers only that empty child — the visible answer text stays in the tree for exploration, and
/// is not announced a second time because only label *changes* speak, not static text.
class _VerdictLiveRegion extends StatelessWidget {
  const _VerdictLiveRegion(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: message,
      child: const ExcludeSemantics(child: SizedBox.shrink()),
    );
  }
}

class _UnlockBranchBanner extends ConsumerWidget {
  const _UnlockBranchBanner({required this.pending});

  final ({String decisionId, String chapterId, String moveSan}) pending;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final srsColors = SrsTheme.maybeOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: srsColors?.surface ?? Colors.black12,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: srsColors?.hairline ?? Colors.white24),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'New branch played: ${pending.moveSan}. Add to review queue?',
                style: TextStyle(color: srsColors?.ink, fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => ref
                  .read(reviewControllerProvider.notifier)
                  .unlockBranch(pending.decisionId, pending.chapterId),
              child: const Text('Add to SRS'),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => ref.read(reviewControllerProvider.notifier).dismissUnlockPrompt(),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnswerSlot extends StatelessWidget {
  const _AnswerSlot({required this.san, required this.wide});

  final String san;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final c = context.srs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SrsSan(san, style: SrsText.answerMove(wide, c.accent)),
        const SizedBox(height: 8),
        Text(
          context.l10n.mobileReviewPlayThisMoveToContinue,
          style: SrsText.answerHelp(wide, c.ink2),
        ),
      ],
    );
  }
}

class _NoteSlot extends StatelessWidget {
  const _NoteSlot({required this.comment, required this.wide});

  final String comment;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final c = context.srs;
    return Container(
      padding: const EdgeInsets.only(left: 16),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: c.accentMid, width: 2.0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(comment, style: SrsText.note(c.ink)),
          const SizedBox(height: 10),
          Text(context.l10n.mobileReviewFromYourStudy, style: SrsText.noteSource(c.ink3)),
        ],
      ),
    );
  }
}

void _openSettings(BuildContext context) {
  Navigator.of(context).push(SrsSettingsScreen.buildRoute());
}

/// Quiet bridge from a drill position into the analysis board, for the "why is this the
/// move?" moment. Shown under the correction answer and under study notes — never in the
/// prompt state, where it would leak a way out of recall, and never in the actions row,
/// which owns exactly Skip/Continue. Reuses the hub's position options so the board that
/// opens is the one the hub would open for the same FEN.
class _OpenInAnalysisButton extends StatelessWidget {
  const _OpenInAnalysisButton({required this.state});

  final ReviewScreenState state;

  @override
  Widget build(BuildContext context) {
    final fen = state.boardPosition?.fen;
    if (fen == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SrsTextButton(
        label: context.l10n.mobileReviewOpenInAnalysis,
        onPressed: () => Navigator.of(context, rootNavigator: true).push(
          AnalysisScreen.buildRoute(
            analysisOptionsForReviewPosition(fen: fen, orientation: state.boardOrientation),
          ),
        ),
      ),
    );
  }
}

/// Switches to [side]'s colour and opens its drawer.
///
/// The drawer opens first and the scope reload lands behind it: the reload
/// walks the whole library (slow on large collections), and making the sheet
/// wait for it reads as the squares being broken. The drawer watches the
/// controller, so its highlight and counts refresh when the reload publishes;
/// a scope picked inside meanwhile supersedes the in-flight load by
/// generation, so nothing can publish over it.
Future<void> _openColourDrawer(BuildContext context, Side side) async {
  final container = ProviderScope.containerOf(context);
  unawaited(container.read(reviewControllerProvider.notifier).selectSide(side));
  if (!context.mounted) return;
  await ReviewScopeDrawer.show(context, side);
}

class _SrsDiagnosticsOverlay extends StatelessWidget {
  const _SrsDiagnosticsOverlay({required this.state});

  final ReviewScreenState state;

  @override
  Widget build(BuildContext context) {
    final c = context.srs;
    final prompt = state.currentPrompt;
    if (prompt == null) return const SizedBox.shrink();

    final session = state.session;
    final dec = prompt.decision;
    final reviewState = session?.reviewStates[dec.canonicalId] ?? session?.reviewStates[dec.id];
    final now = session?.clock.now() ?? DateTime.now();

    final isNew = reviewState == null || reviewState.isNew || reviewState.stability <= 0;
    final reps = reviewState?.repetitionCount ?? 0;
    final lapses = reviewState?.lapseCount ?? 0;
    final diff = reviewState != null && reviewState.difficulty > 0
        ? reviewState.difficulty.toStringAsFixed(1)
        : '5.0';

    final stabilityDays = (reviewState?.stability ?? 0) / 86400000;
    final stabStr = stabilityDays > 0
        ? (stabilityDays >= 10
              ? '${stabilityDays.round()}d'
              : '${stabilityDays.toStringAsFixed(1)}d')
        : 'Cold';

    final double retrievability;
    if (isNew) {
      retrievability = 1.0;
    } else {
      final elapsedDays = reviewState.lastReviewedAt != null
          ? now.difference(reviewState.lastReviewedAt!).inMilliseconds / 86400000
          : 0.0;
      retrievability = fsrsRetrievability(elapsedDays, stabilityDays);
    }
    final rPercent = (retrievability * 100).round();

    final isPractice = state.isPracticeMode;
    final lastResult = state.lastStepResult;
    final expectedMovesStr = prompt.expectedMoves
        .map((m) => m.san ?? '${m.from}${m.to}')
        .join(' / ');
    final shortNodeId = prompt.nodeId.length > 8 ? prompt.nodeId.substring(0, 8) : prompt.nodeId;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 2.0),
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
      decoration: BoxDecoration(
        color: c.hairlineSoft,
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: c.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${isNew ? 'New' : (isPractice ? 'Practice' : 'Recall')} · expected $expectedMovesStr · node $shortNodeId',
            style: TextStyle(
              fontFamily: SrsText.ui,
              fontSize: 11.0,
              fontWeight: FontWeight.w500,
              color: c.ink2,
            ),
          ),
          const SizedBox(height: 4.0),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'R: $rPercent% (${isNew ? "New" : "Recall"})',
                style: TextStyle(
                  fontFamily: SrsText.ui,
                  fontSize: 11.0,
                  fontWeight: FontWeight.w600,
                  color: c.ink,
                  fontFeatures: SrsText.tabular,
                ),
              ),
              Text(
                'S: $stabStr',
                style: TextStyle(
                  fontFamily: SrsText.ui,
                  fontSize: 11.0,
                  fontWeight: FontWeight.w600,
                  color: c.ink,
                  fontFeatures: SrsText.tabular,
                ),
              ),
              Text(
                'D: $diff/10',
                style: TextStyle(
                  fontFamily: SrsText.ui,
                  fontSize: 11.0,
                  fontWeight: FontWeight.w600,
                  color: c.ink,
                  fontFeatures: SrsText.tabular,
                ),
              ),
              Text(
                'Reps: $reps | Lapses: $lapses',
                style: TextStyle(
                  fontFamily: SrsText.ui,
                  fontSize: 11.0,
                  color: c.ink2,
                  fontFeatures: SrsText.tabular,
                ),
              ),
            ],
          ),
          if (lastResult != null) ...[
            const SizedBox(height: 3.0),
            Builder(
              builder: (context) {
                return Text(
                  lastResult.isCorrect
                      ? 'Last: passed · next due in ${(lastResult.updatedState.stability / 86400000).toStringAsFixed(1)} days'
                            '${lastResult.sideEffectStates.isNotEmpty ? " (+${lastResult.sideEffectStates.length} related)" : ""}'
                      : 'Last: not recalled · will come back soon',
                  style: TextStyle(
                    fontFamily: SrsText.ui,
                    fontSize: 10.0,
                    color: c.ink2,
                    fontWeight: FontWeight.w500,
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
