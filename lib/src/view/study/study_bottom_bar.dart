// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/model/account/account_repository.dart';
import 'package:chess_srs/src/model/analysis/analysis_controller.dart';
import 'package:chess_srs/src/model/chat/chat.dart';
import 'package:chess_srs/src/model/common/id.dart';
import 'package:chess_srs/src/model/engine/evaluation_preferences.dart';
import 'package:chess_srs/src/model/study/study_controller.dart';
import 'package:chess_srs/src/utils/l10n_context.dart';
import 'package:chess_srs/src/view/analysis/analysis_actions.dart';
import 'package:chess_srs/src/view/analysis/analysis_screen.dart';
import 'package:chess_srs/src/view/chat/chat_screen.dart';
import 'package:chess_srs/src/view/engine/engine_button.dart';
import 'package:chess_srs/src/view/study/create_study_chapter_bottom_sheet.dart';
import 'package:chess_srs/src/view/study/study_settings.dart';
import 'package:chess_srs/src/widgets/adaptive_action_sheet.dart';
import 'package:chess_srs/src/widgets/buttons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class StudyBottomBar extends ConsumerWidget {
  const StudyBottomBar({required this.options});

  final StudyOptions options;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gamebook = ref.watch(
      studyControllerProvider(options).select((s) => s.requireValue.gamebookActive),
    );

    return gamebook ? _GamebookBottomBar(options: options) : _AnalysisBottomBar(options: options);
  }
}

class _AnalysisBottomBar extends ConsumerWidget {
  const _AnalysisBottomBar({required this.options});

  final StudyOptions options;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(studyControllerProvider(options)).value;
    if (state == null) {
      return const SizedBox.shrink();
    }

    final onGoForward = state.canGoNext
        ? ref.read(studyControllerProvider(options).notifier).userNext
        : null;
    final onGoBack = state.canGoBack
        ? ref.read(studyControllerProvider(options).notifier).userPrevious
        : null;

    // Plain text actions, like the analysis and editor bars: Menu, Chapters, engine,
    // Back, Forward. No icons, no Cupertino chevrons.
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      child: Wrap(
        spacing: 10,
        runSpacing: 0,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _StudyMenuButton(options: options),
          _ChapterButton(options: options),
          if (state.isComputerAnalysisAllowed)
            Builder(
              builder: (context) {
                Future<void>? toggleFuture;
                return FutureBuilder(
                  future: toggleFuture,
                  builder: (context, snapshot) {
                    return EngineButton(
                      filters: (context: state.evaluationContext, path: state.currentPath),
                      savedEval: state.currentNode.eval,
                      onTap: snapshot.connectionState != ConnectionState.waiting
                          ? () async {
                              toggleFuture = ref
                                  .read(studyControllerProvider(options).notifier)
                                  .toggleEngine();
                              try {
                                await toggleFuture;
                              } finally {
                                toggleFuture = null;
                              }
                            }
                          : null,
                      goDeeper: () => ref
                          .read(studyControllerProvider(options).notifier)
                          .requestEval(goDeeper: true),
                    );
                  },
                );
              },
            ),
          _NextChapterButton(
            options: options,
            chapterId: state.study.chapter.id,
            hasNextChapter: state.hasNextChapter,
          ),
          RepeatButton(
            onLongPress: state.canGoBack
                ? () => ref
                      .read(studyControllerProvider(options).notifier)
                      .userPrevious(fastSeek: true)
                : null,
            child: SrsTextButton(
              key: const ValueKey('goto-previous'),
              label: context.l10n.studyBack,
              onPressed: onGoBack,
            ),
          ),
          RepeatButton(
            onLongPress: state.canGoNext
                ? () => ref.read(studyControllerProvider(options).notifier).userNext(fastSeek: true)
                : null,
            child: SrsTextButton(
              key: const ValueKey('goto-next'),
              label: context.l10n.studyNext,
              onPressed: onGoForward,
            ),
          ),
        ],
      ),
    );
  }
}

class _GamebookBottomBar extends ConsumerWidget {
  const _GamebookBottomBar({required this.options});

  final StudyOptions options;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(studyControllerProvider(options)).requireValue;
    final notifier = ref.read(studyControllerProvider(options).notifier);

    // The Lichess bar pulsed the contextual action (blink) to draw the eye. The design has
    // no pulsing anywhere: availability is signalled by the button being there at all.
    Widget backButton(VoidCallback? onTap) =>
        SrsTextButton(label: context.l10n.studyBack, onPressed: onTap);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      child: Wrap(
        spacing: 10,
        runSpacing: 0,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _StudyMenuButton(options: options),
          _ChapterButton(options: options),
          ...switch (state.gamebookState) {
            GamebookState.findTheMove => [
              backButton(!state.currentNode.isRoot ? notifier.reset : null),
              SrsTextButton(
                label: context.l10n.viewTheSolution,
                onPressed: notifier.showGamebookSolution,
              ),
            ],
            GamebookState.startLesson || GamebookState.correctMove => [
              backButton(!state.currentNode.isRoot ? notifier.reset : null),
              SrsTextButton(label: context.l10n.studyNext, onPressed: notifier.userNext),
            ],
            GamebookState.incorrectMove => [
              backButton(!state.currentNode.isRoot ? notifier.reset : null),
              SrsTextButton(label: context.l10n.retry, onPressed: notifier.userPrevious),
            ],
            GamebookState.lessonComplete => [
              if (!state.isIntroductoryChapter)
                SrsTextButton(label: context.l10n.studyPlayAgain, onPressed: notifier.reset),
              _NextChapterButton(
                options: options,
                chapterId: state.study.chapter.id,
                hasNextChapter: state.hasNextChapter,
              ),
              if (!state.isIntroductoryChapter)
                SrsTextButton(
                  label: context.l10n.analysis,
                  onPressed: () => Navigator.of(context, rootNavigator: true).push(
                    AnalysisScreen.buildRoute(
                      AnalysisOptions.pgn(
                        id: options.id,
                        orientation: state.pov,
                        pgn: state.pgn,
                        isComputerAnalysisAllowed: true,
                        variant: state.variant,
                      ),
                    ),
                  ),
                ),
            ],
          },
        ],
      ),
    );
  }
}

class _NextChapterButton extends ConsumerStatefulWidget {
  const _NextChapterButton({
    required this.options,
    required this.chapterId,
    required this.hasNextChapter,
  });

  final StudyOptions options;
  final StudyChapterId chapterId;
  final bool hasNextChapter;

  @override
  ConsumerState<_NextChapterButton> createState() => _NextChapterButtonState();
}

class _NextChapterButtonState extends ConsumerState<_NextChapterButton> {
  bool isLoading = false;

  @override
  void didUpdateWidget(_NextChapterButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chapterId != widget.chapterId) {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      // The head carries progress rather than the screen showing a spinner with nothing
      // to attach it to — same pattern as the settings heads.
      return const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return SrsTextButton(
      label: context.l10n.studyNextChapter,
      onPressed: widget.hasNextChapter
          ? () {
              ref.read(studyControllerProvider(widget.options).notifier).nextChapter();
              setState(() => isLoading = true);
            }
          : null,
    );
  }
}

/// Menu holding the study actions that don't fit in the bottom bar.
class _StudyMenuButton extends ConsumerWidget {
  const _StudyMenuButton({required this.options});

  final StudyOptions options;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SrsTextButton(label: context.l10n.menu, onPressed: () => _showStudyMenu(context, ref));
  }

  Future<void> _showStudyMenu(BuildContext context, WidgetRef ref) {
    final state = ref.read(studyControllerProvider(options)).requireValue;
    final evalPrefs = ref.read(engineEvaluationPreferencesProvider);
    final isKidMode = ref.read(kidModeProvider).value == true;

    final chatOptions = state.study.chat != null
        ? StudyChatOptions(options: options, writeable: state.study.chat!.writeable)
        : null;

    // showAdaptiveActionSheet is the Srs sheet on every platform (no Cupertino fork).
    return showAdaptiveActionSheet(
      context: context,
      actions: [
        BottomSheetAction(
          makeLabel: (context) => Text(context.l10n.settingsSettings),
          onPressed: () => Navigator.of(context).push(StudySettingsScreen.buildRoute(options)),
        ),
        BottomSheetAction(
          makeLabel: (context) => Text(context.l10n.flipBoard),
          onPressed: () => ref.read(studyControllerProvider(options).notifier).toggleBoard(),
        ),
        if (chatOptions != null && !isKidMode)
          BottomSheetAction(
            makeLabel: (context) => Text(context.l10n.chatRoom),
            onPressed: () =>
                Navigator.of(context).push(ChatScreen.buildRoute(options: chatOptions)),
          ),
        if (state.isEngineAvailable(evalPrefs) && state.canShowThreat)
          BottomSheetAction(
            makeLabel: (context) => Text(
              state.engineInThreatMode
                  ? context.l10n.mobileStopShowingThreat
                  : context.l10n.showThreat,
            ),
            onPressed: () =>
                ref.read(studyControllerProvider(options).notifier).toggleEngineThreatMode(),
          ),
        if (state.isComputerAnalysisAllowed && state.currentPosition != null) ...[
          BottomSheetAction(
            makeLabel: (context) => Text(context.l10n.boardEditor),
            onPressed: () =>
                openBoardEditor(context, state.variant, state.currentPosition!.fen, state.pov),
          ),
          BottomSheetAction(
            makeLabel: (context) => Text(context.l10n.continueFromHere),
            onPressed: () =>
                showContinueFromHereMenu(context, state.variant, state.currentPosition!.fen),
          ),
        ],
      ],
    );
  }
}

class _ChapterButton extends ConsumerWidget {
  const _ChapterButton({required this.options});

  final StudyOptions options;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nbChapters = ref.watch(
      studyControllerProvider(options).select((s) => s.requireValue.study.chapters.length),
    );
    return SrsTextButton(
      label: context.l10n.studyNbChapters(nbChapters),
      onPressed: () =>
          showSrsSheet<void>(context, SrsSheetSurface(child: _StudyChaptersMenu(options: options))),
    );
  }
}

class _StudyChaptersMenu extends ConsumerStatefulWidget {
  const _StudyChaptersMenu({required this.options});

  final StudyOptions options;

  @override
  ConsumerState<_StudyChaptersMenu> createState() => _StudyChaptersMenuState();
}

class _StudyChaptersMenuState extends ConsumerState<_StudyChaptersMenu> {
  final currentChapterKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(studyControllerProvider(widget.options)).requireValue;

    // Scroll to the current chapter.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (currentChapterKey.currentContext != null) {
        Scrollable.ensureVisible(currentChapterKey.currentContext!, alignment: 0.5);
      }
    });

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SrsSheetGrabber(),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SrsGroupHeader(context.l10n.studyNbChapters(state.study.chapters.length)),
                for (final chapter in state.study.chapters)
                  SrsSettingsRow(
                    key: chapter.id == state.currentChapter.id ? currentChapterKey : null,
                    label: '${state.study.getChapterIndex(chapter.id) + 1} ${chapter.name}',
                    selected: chapter.id == state.currentChapter.id,
                    onTap: () {
                      ref
                          .read(studyControllerProvider(widget.options).notifier)
                          .goToChapter(chapter.id);
                      Navigator.of(context).pop();
                    },
                  ),
                if (state.canIContribute) ...[
                  const SizedBox(height: 12),
                  SrsPillButton(
                    expand: true,
                    label: context.l10n.studyNewChapter,
                    onPressed: () {
                      final studyNotifier = ref.read(
                        studyControllerProvider(widget.options).notifier,
                      );
                      Navigator.of(context).pop();
                      if (!context.mounted) return;

                      // Still the legacy form for now; its own migration converts content
                      // and presentation together.
                      showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        useRootNavigator: true,
                        builder: (context) => CreateStudyChapterBottomSheet(
                          params: CreateChapterOfExistingStudy(state.study.id),
                          chapterNumber: state.study.chapters.length + 1,
                          onChaptersCreated: (_, chapters) {
                            // The server always answers with the created chapters, but the
                            // response mapper tolerates an empty list, and this runs after
                            // the sheet was popped: an exception here would surface as an
                            // unhandled error.
                            final chapterId = chapters.firstOrNull;
                            if (chapterId != null) {
                              studyNotifier.goToChapter(chapterId);
                            }
                          },
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
