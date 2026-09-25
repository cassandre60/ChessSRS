// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chess_srs/src/model/settings/board_preferences.dart';
import 'package:chess_srs/src/model/study/study_preferences.dart';
import 'package:chess_srs/src/review/review_controller.dart';
import 'package:chess_srs/src/view/review/library_sheet.dart';
import 'package:chess_srs/src/view/review/repertoire_import_dialog.dart';
import 'package:chess_srs/src/view/review/review_copy.dart';
import 'package:chess_srs/src/view/review/review_scope_drawer.dart';
import 'package:chess_srs/src/view/review/review_states.dart';
import 'package:chess_srs/src/view/settings/srs_settings_screen.dart';
import 'package:chess_srs/src/widgets/board.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

export 'package:chess_srs/src/view/review/study_chapters_screen.dart';

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
          loading: () => const SrsLoadingView(),
          error: (err, stack) => SrsErrorView(
            detail: kSrsReviewLoadFailedDetail,
            onRetry: () => ref.invalidate(reviewControllerProvider),
            onCopyDetails: () => copySrsErrorDetails('${err.runtimeType}: $err\n\n$stack'),
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
    final isWide = mediaQuery.size.width >= 900;
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
            kSrsBringYourRepertoire,
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
            kSrsFirstLaunchLede,
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
                    kSrsDropPgnHere,
                    style: TextStyle(fontFamily: SrsText.ui, fontSize: 15.5, color: c.ink),
                  ),
                  const SizedBox(height: 16.0),
                  SrsPillButton(
                    label: 'Choose file',
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
                label: 'Paste PGN text',
                onPressed: () => RepertoireImportDialog.show(
                  context,
                  initialSource: ImportSource.file,
                  initialSide: _trainSide,
                ),
              ),
              SrsTextButton(
                label: 'Import a Lichess study',
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
                'Train as',
                style: TextStyle(fontFamily: SrsText.ui, fontSize: 14, color: c.ink2),
              ),
              const SizedBox(width: 12.0),
              SrsSegmented<Side?>(
                options: const {null: 'Auto', Side.white: 'White', Side.black: 'Black'},
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
          scopeTitle: 'ChessSRS',
          dueCount: 0,
          onScopePressed: () => ReviewScopeDrawer.show(context),
          onOverflowPressed: () => _showOverflowSheet(context),
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
    final totalDecisions = progress?.totalDecisions ?? 0;
    final learnedDecisions = progress?.learnedDecisions ?? 0;
    final dueDecisions = progress?.dueDecisions ?? 0;
    final retained = (learnedDecisions - dueDecisions).clamp(0, totalDecisions);
    final learning = dueDecisions;
    final fresh = (totalDecisions - learnedDecisions).clamp(0, totalDecisions);

    final displayTitle = state.isDailyLimitReached
        ? kSrsDailyLimitReachedTitle
        : kSrsNothingDueTitle;
    final headlineSize = math.max(44.0, math.min(mediaQuery.size.width * 0.09, 72.0));

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
              scopeTitle: _computeScopeTitle(state),
              dueCount: 0,
              isPracticeMode: state.isPracticeMode,
              onScopePressed: () => ReviewScopeDrawer.show(context),
              onOverflowPressed: () => _showOverflowSheet(context),
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
                          Text.rich(
                            TextSpan(
                              style: TextStyle(fontFamily: SrsText.ui, fontSize: 18, color: c.ink2),
                              children: [
                                const TextSpan(text: 'You reviewed '),
                                TextSpan(
                                  text: '${state.dailyReviewedCount}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: c.ink,
                                    fontFeatures: SrsText.tabular,
                                  ),
                                ),
                                const TextSpan(text: ' of '),
                                TextSpan(
                                  text: '${state.maxDailyReviews}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: c.ink,
                                    fontFeatures: SrsText.tabular,
                                  ),
                                ),
                                const TextSpan(text: ' positions today.'),
                              ],
                            ),
                          )
                        else if (state.timeUntilNextReview != null)
                          Text.rich(
                            TextSpan(
                              style: TextStyle(fontFamily: SrsText.ui, fontSize: 18, color: c.ink2),
                              children: [
                                // `timeUntilNextReview` already carries its own
                                // "in ..." prefix (see review_controller.dart), so
                                // this renders the demo's `Next review in {x}.`
                                const TextSpan(text: kSrsNextReviewPrefix),
                                TextSpan(
                                  text: state.timeUntilNextReview,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: c.ink,
                                    fontFeatures: SrsText.tabular,
                                  ),
                                ),
                                const TextSpan(text: '.'),
                              ],
                            ),
                          )
                        else
                          Text(
                            kSrsNoNextReview,
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
                              label: 'retained',
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
                              label: 'learning',
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
                              label: 'new',
                            ),
                          ],
                        ),
                        const SizedBox(height: 36.0),
                        Wrap(
                          spacing: 18.0,
                          runSpacing: 10.0,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            SrsPillButton(
                              label: 'Practice',
                              shortcut: 'P',
                              onPressed: () {
                                ref.read(reviewControllerProvider.notifier).startPracticeMode();
                              },
                            ),
                            SrsTextButton(
                              label: 'Choose a repertoire',
                              onPressed: () => ReviewScopeDrawer.show(context),
                            ),
                            if (state.isDailyLimitReached)
                              SrsTextButton(
                                label: kSrsAdjustLimitLabel,
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
                          kSrsPracticeFootnote,
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

  @override
  void initState() {
    super.initState();
    _initController();
  }

  void _initController() {
    final gameData = _buildGameData();
    _controller = ChessboardController(game: gameData);
  }

  @override
  void didUpdateWidget(_ActiveReviewView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final ctrl = _controller;
    if (ctrl == null) return;

    final newGameData = _buildGameData();
    ctrl.updatePosition(newGameData);
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

    return buildGameData(
      fen: pos.fen,
      variant: Variant.standard,
      position: pos,
      playerSide: playerSide,
      castlingMethod: boardPrefs.castlingMethod,
      boardHighlights: boardPrefs.boardHighlights,
      lastMove: widget.state.lastMove,
    );
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

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.space): () {
            if (state.isAwaitingAdvance) onContinue();
          },
          const SingleActivator(LogicalKeyboardKey.keyS): () {
            if (!state.isAwaitingAdvance) onSkip();
          },
        },
        child: SrsReviewLayout(
          whiteAtBottom: state.boardOrientation == Side.white,
          topBar: SrsTopBar(
            scopeTitle: _computeScopeTitle(state),
            dueCount: state.totalDueCount,
            isPracticeMode: state.isPracticeMode,
            onScopePressed: () => ReviewScopeDrawer.show(context),
            onOverflowPressed: () => _showOverflowSheet(context),
            onExitPractice: state.isPracticeMode
                ? () => ref.read(reviewControllerProvider.notifier).exitPracticeMode()
                : null,
          ),
          board: (context, size, wide) => Stack(
            clipBehavior: Clip.none,
            children: [
              BoardWidget(
                size: size,
                orientation: state.boardOrientation,
                settings: boardPrefs
                    .toBoardSettings(Variant.standard, srsColors: srsColors)
                    .copyWith(enableCoordinates: false),
                controller: _controller!,
                onMove: (move, {viaDragAndDrop}) {
                  ref.read(reviewControllerProvider.notifier).onUserMove(move);
                },
                shapes: shapes,
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
                  child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: onContinue),
                ),
            ],
          ),
          side: (context, wide, appWidth) => SrsReviewSide(
            wide: wide,
            lineFontSize: wide ? 28.0 : 22.0,
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
              onSkip: onSkip,
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
        ],
      );
    } else if (state.isAwaitingAdvance && comment != null && comment.trim().isNotEmpty) {
      content = _NoteSlot(comment: comment.trim(), wide: wide);
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

  Widget _buildActions(
    BuildContext context, {
    required bool isAwaitingAdvance,
    required VoidCallback onSkip,
    required VoidCallback onContinue,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        if (!isAwaitingAdvance)
          SrsTextButton(label: 'Skip', shortcut: 'S', onPressed: onSkip)
        else
          const SizedBox.shrink(),
        if (isAwaitingAdvance)
          SrsPillButton(label: 'Continue', shortcut: 'Space', onPressed: onContinue)
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
    final turnText = isWhite ? 'White to play' : 'Black to play';

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
        Text(kSrsAnswerHelpText, style: SrsText.answerHelp(wide, c.ink2)),
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
          Text(kSrsNoteAttribution, style: SrsText.noteSource(c.ink3)),
        ],
      ),
    );
  }
}

void _showOverflowSheet(BuildContext context) {
  SrsLibrarySheet.show(context);
}

String _computeScopeTitle(ReviewScreenState state) {
  if (state.scope.openingFamily != null) {
    return state.scope.openingFamily!;
  }
  if (state.scope.studyId != null) {
    final study = state.studies.firstWhere(
      (s) => s.id == state.scope.studyId,
      orElse: () => const Study(id: '', title: 'Study'),
    );
    if (state.scope.chapterId != null && state.currentPrompt?.chapterTitle != null) {
      return '${study.title} • ${state.currentPrompt!.chapterTitle}';
    }
    return study.title;
  }
  return 'All Studies';
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

extension on PgnCommentShape {
  Shape get chessground {
    final shapeColor = switch (color) {
      CommentShapeColor.green => ShapeColor.green,
      CommentShapeColor.red => ShapeColor.red,
      CommentShapeColor.blue => ShapeColor.blue,
      CommentShapeColor.yellow => ShapeColor.yellow,
    };
    return from != to
        ? Arrow(color: shapeColor.color, orig: from, dest: to)
        : Circle(color: shapeColor.color, orig: from);
  }
}
