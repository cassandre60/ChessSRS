// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/model/common/id.dart';
import 'package:chess_srs/src/model/study/study_preferences.dart';
import 'package:chess_srs/src/review/review_controller.dart';
import 'package:chess_srs/src/view/review/export_pgn_dialog.dart';
import 'package:chess_srs/src/view/review/repertoire_import_dialog.dart';
import 'package:chess_srs/src/view/study/study_screen.dart';
import 'package:chess_srs/src/widgets/feedback.dart';
import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

/// Modal scope selector (hybrid of Diagram bottom sheet and rich repertoire list).
///
/// One drawer per repertoire colour, opened by the matching square in the top
/// bar. A drawer lists only the openings and studies that train the colour it
/// belongs to, so the colour is never spelled out inside it: the square that
/// opened it already says which one this is. The two drawers share no state
/// beyond that colour, and selecting anything in one leaves the other
/// untouched.
class ReviewScopeDrawer extends ConsumerStatefulWidget {
  const ReviewScopeDrawer({super.key, required this.side});

  /// The repertoire colour this drawer belongs to.
  final Side side;

  /// A colour's name. The top bar's squares use it as their tooltip and
  /// semantics label, and the study actions sheet uses it to name the drawer a
  /// study would be copied into, so the three can never disagree.
  static String sideLabel(Side side) =>
      side == Side.white ? 'White repertoire' : 'Black repertoire';

  /// Displays the scope selector sheet for [side].
  static Future<void> show(BuildContext context, Side side) {
    final c = context.srs;
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: c.scrim,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return ReviewScopeDrawer(side: side);
      },
      transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
        final isWide = MediaQuery.of(dialogContext).size.width >= 768;
        if (isWide) {
          return FadeTransition(opacity: animation, child: child);
        }
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(curved),
          child: FadeTransition(opacity: animation, child: child),
        );
      },
    );
  }

  @override
  ConsumerState<ReviewScopeDrawer> createState() => _ReviewScopeDrawerState();
}

class _ReviewScopeDrawerState extends ConsumerState<ReviewScopeDrawer> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.srs;
    final mediaQuery = MediaQuery.of(context);
    final isWide = mediaQuery.size.width >= 768;
    final maxHeight = math.min(mediaQuery.size.height * 0.82, 720.0);
    final maxWidth = isWide ? math.min(470.0, mediaQuery.size.width - 52.0) : double.infinity;

    final reviewStateAsync = ref.watch(reviewControllerProvider);
    final reviewState = reviewStateAsync.value;

    if (reviewState == null) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).pop(),
        child: Center(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: Container(
              width: maxWidth,
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(isWide ? 16 : 22),
              ),
              child: CircularProgressIndicator(strokeWidth: 2, color: c.ink),
            ),
          ),
        ),
      );
    }

    // A drawer belongs to one colour and lists only that colour's material. The
    // membership comes from the summary rather than from the current scope: the
    // scope may be a single study or a single opening by the time the drawer is
    // reopened, and a study's own colour is not always the scope's.
    final side = widget.side;
    final activeScope = reviewState.scope;

    final query = _searchQuery.trim().toLowerCase();
    // While searching, every match shows regardless of collapse: the query,
    // not the persisted state, decides what is visible.
    final searching = query.isNotEmpty;
    final collapsedGroups = ref.watch(
      studyPreferencesProvider.select((p) => p.collapsedScopeGroups),
    );
    // Master switch: with collapsing off, headers are plain titles and every
    // group always expanded, whatever the persisted per-group state says.
    final collapseEnabled =
        ref.watch(studyPreferencesProvider.select((p) => p.collapsibleScopeGroups)) && !searching;

    final myOpenings = reviewState.openingsBySide[side] ?? const <String>[];
    final myStudyIds = reviewState.studyIdsBySide[side] ?? const <String>[];

    final filteredOpeningHubs = myOpenings
        .where((name) => query.isEmpty || name.toLowerCase().contains(query))
        .map((name) => MapEntry(name, reviewState.openingDueCounts[name] ?? 0))
        .toList();

    final filteredStudies = reviewState.studies
        .where((s) => myStudyIds.contains(s.id))
        .where((s) => query.isEmpty || s.title.toLowerCase().contains(query))
        .toList();

    final hasNoResults = query.isNotEmpty && filteredOpeningHubs.isEmpty && filteredStudies.isEmpty;

    final content = Align(
      alignment: isWide ? Alignment.topLeft : Alignment.bottomCenter,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: Container(
          width: maxWidth,
          constraints: BoxConstraints(maxHeight: maxHeight),
          margin: isWide
              ? const EdgeInsets.only(top: 56, left: 26, bottom: 24)
              : const EdgeInsets.fromLTRB(8, 0, 8, 8),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(isWide ? 18 : 22),
            border: Border.all(color: c.hairline, width: 1),
            boxShadow: [BoxShadow(color: c.scrim, blurRadius: 30, offset: const Offset(0, 8))],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(isWide ? 18 : 22),
            child: Material(
              color: c.surface,
              child: SafeArea(
                top: false,
                bottom: !isWide,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Grab handle (mobile only)
                    if (!isWide) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: c.hairline,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],

                    // Search field matching demo (.search)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: c.hairlineSoft)),
                      ),
                      child: Row(
                        children: [
                          Icon(Symbols.search_rounded, size: 20, color: c.ink3),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              autofocus: isWide,
                              style: TextStyle(
                                fontFamily: SrsText.ui,
                                fontSize: 15.5,
                                color: c.ink,
                              ),
                              decoration: InputDecoration(
                                // design/docs/01-identity.md: the scope search placeholder is
                                // `Search`, and the demo's longer string is the field's accessible
                                // name rather than its visible hint.
                                hintText: 'Search',
                                hintStyle: TextStyle(
                                  fontFamily: SrsText.ui,
                                  fontSize: 15.5,
                                  color: c.ink3,
                                ),
                                isDense: true,
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                              ),
                              onChanged: (text) => setState(() => _searchQuery = text),
                            ),
                          ),
                          if (_searchQuery.isNotEmpty)
                            IconButton(
                              icon: Icon(Symbols.close_rounded, size: 18, color: c.ink3),
                              tooltip: 'Clear search',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            ),
                        ],
                      ),
                    ),
                    Container(height: 1, color: c.hairline),

                    // Scope list
                    Expanded(
                      child: hasNoResults
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(28.0),
                                child: Text(
                                  // design/docs/01-identity.md: `Nothing matches "{query}".`
                                  'Nothing matches \u201c$_searchQuery\u201d.',
                                  style: TextStyle(
                                    fontFamily: SrsText.ui,
                                    fontSize: 15,
                                    color: c.ink2,
                                  ),
                                ),
                              ),
                            )
                          : ListView(
                              padding: const EdgeInsets.symmetric(vertical: 4.0),
                              children: [
                                // Group: Openings
                                if (filteredOpeningHubs.isNotEmpty) ...[
                                  _buildGroupHeader(
                                    ref,
                                    c,
                                    group: 'openings',
                                    title: 'Openings',
                                    collapsed: collapsedGroups.contains('openings'),
                                    plain: !collapseEnabled,
                                  ),
                                  if (!collapseEnabled || !collapsedGroups.contains('openings'))
                                    for (final entry in filteredOpeningHubs)
                                      Builder(
                                        builder: (context) {
                                          final progress =
                                              reviewState.openingProgress[entry.key] ??
                                              RepertoireProgress.zero;
                                          return _ScopeRow(
                                            name: entry.key,
                                            semanticLabel:
                                                '${entry.key} opening, ${entry.value} due',
                                            dueCount: entry.value,
                                            isPaused: false,
                                            isSelected: activeScope.openingFamily == entry.key,
                                            progress: progress,
                                            onPressed: () {
                                              Navigator.of(context).pop();
                                              ref
                                                  .read(reviewControllerProvider.notifier)
                                                  .changeScope(ReviewScope.opening(entry.key));
                                            },
                                          );
                                        },
                                      ),
                                ],

                                // Group: Studies
                                if (filteredStudies.isNotEmpty) ...[
                                  _buildGroupHeader(
                                    ref,
                                    c,
                                    group: 'studies',
                                    title: 'Studies',
                                    collapsed: collapsedGroups.contains('studies'),
                                    plain: !collapseEnabled,
                                  ),
                                  if (!collapseEnabled || !collapsedGroups.contains('studies'))
                                    for (final study in filteredStudies)
                                      Builder(
                                        builder: (context) {
                                          final due = reviewState.studyDueCounts[study.id] ?? 0;
                                          final progress =
                                              reviewState.studyProgress[study.id] ??
                                              RepertoireProgress.zero;
                                          return _ScopeRow(
                                            name: study.title,
                                            semanticLabel:
                                                '${study.title}, $due due'
                                                '${study.isActive ? '' : ', paused'}',
                                            dueCount: due,
                                            isPaused: !study.isActive,
                                            isSelected: activeScope.studyId == study.id,
                                            progress: progress,
                                            onPressed: () {
                                              Navigator.of(context).pop();
                                              ref
                                                  .read(reviewControllerProvider.notifier)
                                                  .changeScope(ReviewScope.study(study.id));
                                            },
                                            onShowActions: (anchor) => _showStudyActionsSheet(
                                              context,
                                              ref,
                                              study,
                                              side: side,
                                              anchor: anchor,
                                            ),
                                          );
                                        },
                                      ),
                                ],
                              ],
                            ),
                    ),

                    // Bottom action: Import PGN
                    Container(height: 1, color: c.hairlineSoft),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 10.0),
                      child: SizedBox(
                        width: double.infinity,
                        child: SrsPillButton(
                          label: 'Import PGN',
                          expand: true,
                          onPressed: () {
                            Navigator.of(context).pop();
                            RepertoireImportDialog.show(context);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pop(),
          ),
        ),
        SrsSheetDismissible(child: content),
      ],
    );
  }

  /// design/docs/03-components.md §6.2: group titles are `12.5/500 ink3`, padding 14/18/4.
  /// Tapping a header collapses its group; the state persists per group in
  /// [StudyPrefs.collapsedScopeGroups] and survives drawer closes and restarts.
  /// Without collapsing (master switch off, or while searching), headers are
  /// plain titles and every match shows.
  Widget _buildGroupHeader(
    WidgetRef ref,
    SrsColors c, {
    required String group,
    required String title,
    required bool collapsed,
    required bool plain,
  }) {
    final label = Text(title, style: SrsText.groupTitle(c.ink3));
    if (plain) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(18.0, 14.0, 18.0, 4.0),
        child: label,
      );
    }
    return SrsPressable(
      onPressed: () => ref.read(studyPreferencesProvider.notifier).toggleScopeGroupCollapsed(group),
      semanticLabel: collapsed ? 'Expand $title section' : 'Collapse $title section',
      semanticsToggled: !collapsed,
      radius: 10,
      builder: (_, hover, _) => Container(
        constraints: const BoxConstraints(minHeight: SrsLayout.minTouchTarget),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 4.0),
        decoration: BoxDecoration(
          color: hover ? c.hairlineSoft : const Color(0x00000000),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            ExcludeSemantics(child: label),
            const Spacer(),
            Icon(
              collapsed ? Symbols.expand_more_rounded : Symbols.expand_less_rounded,
              size: 14,
              color: c.ink3,
            ),
          ],
        ),
      ),
    );
  }

  /// The study actions sheet.
  ///
  /// design/docs/03-components.md §12: "a Library-style sheet of text rows (16/500, no icons),
  /// anchored to the row that opened it on wide layouts". The rows come from [SrsSheetRow], which
  /// the Library sheet also uses, so the two stay in the same family; the placement differs because
  /// §7 pins the Library sheet top-right while §12 pins these to their row.
  ///
  /// [anchor] is the row's global rect, or null when it could not be measured, in which case a wide
  /// layout falls back to the same top-right placement the Library sheet uses.
  void _showStudyActionsSheet(
    BuildContext context,
    WidgetRef ref,
    Study study, {
    required Side side,
    Rect? anchor,
  }) {
    final c = context.srs;

    Future<void> show() => showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: c.scrim,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, animation, secondaryAnimation) => StudyActionsSheet(
        study: study,
        side: side,
        anchor: anchor,
        onDismiss: () => Navigator.of(dialogContext).pop(),
        onTogglePause: () {
          Navigator.of(dialogContext).pop();
          ref.read(reviewControllerProvider.notifier).toggleStudyActive(study.id, !study.isActive);
        },
        onAnalyze: () {
          final navigator = Navigator.of(context, rootNavigator: true);
          Navigator.of(dialogContext).pop();
          Navigator.of(context).pop();
          navigator.push(StudyScreen.buildRoute((id: StudyId(study.id), initialChapter: null)));
        },
        onPractice: () {
          Navigator.of(dialogContext).pop();
          Navigator.of(context).pop();
          ref
              .read(reviewControllerProvider.notifier)
              .startPracticeMode(scope: ReviewScope.study(study.id));
        },
        onCreateOpposite: () {
          Navigator.of(dialogContext).pop();
          final other = side == Side.white ? Side.black : Side.white;
          ref
              .read(reviewControllerProvider.notifier)
              .createStudyInSide(study.id, other)
              .then((created) {
                if (!context.mounted) return;
                if (created == null) {
                  showSnackBar(
                    context,
                    'Already in the ${ReviewScopeDrawer.sideLabel(other).toLowerCase()}',
                    type: SnackBarType.info,
                  );
                } else {
                  showSnackBar(
                    context,
                    'Created ${ReviewScopeDrawer.sideLabel(other).toLowerCase()}',
                    type: SnackBarType.success,
                  );
                }
              })
              .catchError((Object e) {
                if (!context.mounted) return null;
                showSnackBar(context, 'Could not create it: $e', type: SnackBarType.error);
                return null;
              });
        },
        onExport: () async {
          Navigator.of(dialogContext).pop();
          final pgn = await ref.read(reviewControllerProvider.notifier).exportStudyPgn(study.id);
          if (pgn == null || pgn.trim().isEmpty) {
            if (context.mounted) {
              showSnackBar(context, 'No moves to export in this study', type: SnackBarType.info);
            }
            return;
          }
          if (context.mounted) {
            ExportPgnDialog.show(context, title: study.title, pgnText: pgn);
          }
        },
        onRename: () {
          Navigator.of(dialogContext).pop();
          _showRenameDialog(context, ref, study);
        },
        onDelete: () {
          Navigator.of(dialogContext).pop();
          _showDeleteConfirmDialog(context, ref, study);
        },
      ),
      transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
        final isWide = MediaQuery.of(dialogContext).size.width >= 768;
        if (isWide) return FadeTransition(opacity: animation, child: child);
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(curved),
          child: FadeTransition(opacity: animation, child: child),
        );
      },
    );

    show();
  }

  /// The rename dialog. design/docs/03-components.md §12: a centred card, title 20/600, a bare
  /// 16px input, then Cancel and Rename. The demo titles it `Rename study` and toasts
  /// `Renamed to "{v}".`.
  ///
  /// The dialog returns the new name rather than renaming itself, so the rename and its toast run
  /// against the drawer's context, which is still mounted, instead of one that has just been
  /// popped. The controller is owned by [_RenameDialogBody] so it is disposed with the dialog
  /// rather than at some point during its exit animation.
  Future<void> _showRenameDialog(BuildContext context, WidgetRef ref, Study study) async {
    final newName = await SrsDialog.show<String>(
      context: context,
      builder: (ctx) => _RenameDialogBody(initial: study.title),
    );
    if (newName == null || newName.isEmpty || newName == study.title) return;
    await ref.read(reviewControllerProvider.notifier).renameStudy(study.id, newName);
    if (context.mounted) {
      showSnackBar(context, 'Renamed to \u201c$newName\u201d.', type: SnackBarType.success);
    }
  }

  /// The delete confirmation. §12 gives the copy verbatim and forbids red: "Destructive copy must
  /// name the item: `Delete "{name}" and its {n} positions? This cannot be undone.`", with the
  /// confirm label `Delete`.
  Future<void> _showDeleteConfirmDialog(BuildContext context, WidgetRef ref, Study study) async {
    final positions =
        ref.read(reviewControllerProvider).value?.studyProgress[study.id]?.totalDecisions ?? 0;
    final confirmed = await SrsDialog.show<bool>(
      context: context,
      builder: (ctx) => SrsDialog(
        title: 'Delete study?',
        body:
            'Delete \u201c${study.title}\u201d and its $positions positions? This cannot be undone.',
        actions: [
          SrsTextButton(label: 'Cancel', onPressed: () => Navigator.of(ctx).pop(false)),
          SrsPillButton(label: 'Delete', onPressed: () => Navigator.of(ctx).pop(true)),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(reviewControllerProvider.notifier).deleteStudy(study.id);
    if (context.mounted) {
      showSnackBar(context, 'Deleted \u201c${study.title}\u201d.', type: SnackBarType.success);
    }
  }
}

/// One row of the scope list, built to design/docs/03-components.md §6.3 and the demo's `.row`:
/// a full-width button with 9/18 padding and a 14px gap, the name over a sub line on the left, and
/// the due numeral on the right. Hover fills `hairlineSoft`; the current scope fills `accentSoft`
/// and carries a 3px accent bar down its left edge.
///
/// §6.4 keeps row actions out of the row body. All three of the routes it offers are wired: a
/// long-press, a secondary click, and the `…`. The `…` is left permanently visible rather than
/// revealed on hover, because hover does not exist on the touch screens this app mostly runs on
/// and a control that appears only under a pointer the device does not have is a control that is
/// missing for most of the people using it.
class _ScopeRow extends StatelessWidget {
  const _ScopeRow({
    required this.name,
    required this.semanticLabel,
    required this.dueCount,
    required this.isPaused,
    required this.isSelected,
    required this.progress,
    required this.onPressed,
    this.onShowActions,
  });

  final String name;
  final String semanticLabel;
  final int dueCount;

  /// A suspended study: `ink3` for the name and the numeral, and `Paused` instead of a count.
  final bool isPaused;
  final bool isSelected;

  /// Drives both the `{n} positions` figure and the segments of the memory mini-bar.
  final RepertoireProgress progress;

  final VoidCallback onPressed;

  /// Opens the row's actions, handed the row's global rect so a wide sheet can anchor to it.
  final void Function(Rect? anchor)? onShowActions;

  @override
  Widget build(BuildContext context) {
    final c = context.srs;
    final actions = onShowActions;
    // §12 puts the study actions "anchored to the row that opened it on wide layouts", so the
    // row's own box is what the sheet positions itself against. The Builder's context is the row's
    // element, which is the only one whose render object is the row rather than the drawer.
    return Builder(
      builder: (rowContext) {
        void showActions() {
          final box = rowContext.findRenderObject() as RenderBox?;
          actions?.call(box == null ? null : box.localToGlobal(Offset.zero) & box.size);
        }

        return SrsPressable(
          onPressed: onPressed,
          onLongPress: showActions,
          onSecondaryTap: showActions,
          semanticLabel: semanticLabel,
          radius: 8,
          builder: (context, hovered, pressed) {
            final label = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SrsText.rowName(isPaused ? c.ink3 : c.ink),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    SrsMemoryBar(
                      width: 96,
                      height: 5,
                      gap: 2,
                      radius: 1,
                      retained: (progress.learnedDecisions - progress.dueDecisions).clamp(
                        0,
                        progress.totalDecisions,
                      ),
                      learning: progress.dueDecisions,
                      fresh: progress.unlearnedDecisions.clamp(0, progress.totalDecisions),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        isPaused ? 'Paused' : '${progress.totalDecisions} positions',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SrsText.rowSub(c.ink3),
                      ),
                    ),
                  ],
                ),
              ],
            );

            return DecoratedBox(
              decoration: BoxDecoration(
                color: isSelected
                    ? c.accentSoft
                    : hovered
                    ? c.hairlineSoft
                    : const Color(0x00000000),
              ),
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                    child: Row(
                      children: [
                        Expanded(child: label),
                        const SizedBox(width: 14),
                        _DueCell(count: dueCount, isActive: !isPaused),
                        if (actions != null) ...[
                          const SizedBox(width: 2),
                          SrsIconButton(
                            icon: Symbols.more_vert_rounded,
                            tooltip: 'Study options',
                            onPressed: showActions,
                          ),
                        ],
                      ],
                    ),
                  ),
                  // The current scope carries a 3px accent bar, inset to the row's own padding.
                  if (isSelected)
                    Positioned(
                      left: 0,
                      top: 9,
                      bottom: 9,
                      width: 3,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: c.accent,
                          borderRadius: const BorderRadius.horizontal(right: Radius.circular(2)),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// The right-hand side of a scope row: the due numeral, then `due`, on a shared baseline.
///
/// design/docs/03-components.md §6.3, and the demo's `.row-due`: the numeral is `17/600` with
/// tabular figures and `due` is `12.5 ink3`, 5px apart. Zero due drops the numeral to `ink3` at
/// weight 500; a paused scope only recolours it.
class _DueCell extends StatelessWidget {
  const _DueCell({required this.count, required this.isActive});

  final int count;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final c = context.srs;
    final isZero = count == 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          '$count',
          style: SrsText.rowDue(
            isZero || !isActive ? c.ink3 : c.ink,
          ).copyWith(fontWeight: isZero ? FontWeight.w500 : FontWeight.w600),
        ),
        const SizedBox(width: 5),
        // The demo sets tabular figures on `.row-sub` for the figure, not on the word beside it.
        Text('due', style: SrsText.rowSub(c.ink3).copyWith(fontFeatures: null)),
      ],
    );
  }
}

/// The study actions sheet's presentation: a title, a rule, and text rows.
///
/// Presentation only, and it takes callbacks rather than a `WidgetRef`, so it can be mounted on its
/// own. That is what lets the screenshot harness capture it — a pushed route falls outside the
/// capture's `RepaintBoundary` — and it is what would let a sibling sheet reuse it.
class StudyActionsSheet extends StatelessWidget {
  const StudyActionsSheet({
    required this.study,
    required this.side,
    required this.onDismiss,
    required this.onTogglePause,
    required this.onAnalyze,
    required this.onPractice,
    required this.onExport,
    required this.onRename,
    required this.onDelete,
    required this.onCreateOpposite,
    this.anchor,
  });

  final Study study;

  /// The colour of the drawer this study was opened from, which decides which
  /// colour "the opposite one" is.
  final Side side;

  /// The row's global rect, on wide layouts. Null falls back to the Library sheet's placement.
  final Rect? anchor;

  final VoidCallback onDismiss;
  final VoidCallback onTogglePause;
  final VoidCallback onAnalyze;
  final VoidCallback onPractice;
  final VoidCallback onExport;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  /// Creates this same study's positions in the other colour, which is where
  /// most imports go wrong: a whole repertoire imported as White when the lines
  /// are replies.
  final VoidCallback onCreateOpposite;

  static const double _wideBreakpoint = 768;
  static const double _popoverWidth = 300;

  @override
  Widget build(BuildContext context) {
    final c = context.srs;
    final size = MediaQuery.sizeOf(context);
    final isWide = size.width >= _wideBreakpoint && anchor != null;

    // The demo's `openActs`: three hairline-separated groups, in this order, with these labels and
    // sub lines. §12 says "no icons", so no row carries the chevron the Library sheet's rows do.
    Widget group(List<Widget> rows) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(mainAxisSize: MainAxisSize.min, children: rows),
    );

    // The two drawers are independent, so a study in one has no counterpart in
    // the other until the user makes one. This is the row that does that, and it
    // is first: a repertoire in the wrong colour is the most common reason the
    // other drawer is empty, and it is a one-tap fix.
    final otherLabel = ReviewScopeDrawer.sideLabel(side == Side.white ? Side.black : Side.white);

    final rows = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        group([
          SrsSheetRow(
            label: 'Create $otherLabel',
            subtitle: 'Same positions, in the other drawer',
            onPressed: onCreateOpposite,
          ),
        ]),
        Container(height: 1, color: c.hairline),
        group([
          SrsSheetRow(
            label: 'Analyze',
            subtitle: 'Browse moves and variations',
            onPressed: onAnalyze,
          ),
          SrsSheetRow(
            label: 'Practice',
            subtitle: 'Drill lines without changing your schedule',
            onPressed: onPractice,
          ),
        ]),
        Container(height: 1, color: c.hairline),
        group([
          SrsSheetRow(
            label: 'Export PGN',
            subtitle: 'Share or copy standard PGN notation',
            onPressed: onExport,
          ),
          SrsSheetRow(
            label: study.isActive ? 'Pause' : 'Resume',
            subtitle: study.isActive
                ? 'Suspend from active review pool'
                : 'Activate in review pool',
            onPressed: onTogglePause,
          ),
        ]),
        Container(height: 1, color: c.hairline),
        group([
          SrsSheetRow(label: 'Rename', onPressed: onRename),
          // §12 is explicit that the dialogs carry no red, and this row only opens one.
          SrsSheetRow(label: 'Delete', onPressed: onDelete),
        ]),
      ],
    );

    // No title. The sheet is anchored to the row that opened it, and that row
    // already carries the study name one row-height above — repeating it here
    // spent a line of a short popover to say nothing (owner report 2026-10-05).
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!isWide) const SrsSheetGrabber(),
        // Scrollable so the last rows (Rename/Delete) stay reachable on small
        // phones: the previous plain Column clipped them once the content
        // exceeded the sheet's maxHeight with no way to scroll (owner report
        // 2026-09-29 Q8). Flexible bounds the scroll to the sheet's maxHeight.
        Flexible(
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [rows],
              ),
            ),
          ),
        ),
      ],
    );

    // The popover's band: the whole strip it may occupy, clear of the top bar
    // and the window's bottom edge. The sheet is laid out *inside* this band
    // rather than positioned by a top edge of its own, so it cannot end up
    // taller than the space it was given — which is what used to push the last
    // row off the bottom of a wide window with no way to reach it (owner report
    // 2026-10-05).
    const bandTop = 56.0;
    const bandBottomMargin = 16.0;
    final bandHeight = math.max(0.0, size.height - bandTop - bandBottomMargin);

    final sheet = SrsSheetSurface(
      radius: isWide ? 16 : 22,
      // The popover needs an explicit width: anchored with only a left and a top, its constraints
      // are loose, and the stretching column inside then lays out against an unbounded width.
      width: isWide ? _popoverWidth : null,
      maxHeight: isWide ? bandHeight : math.min(size.height * 0.82, 720),
      child: body,
    );

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onDismiss),
        ),
        // Finger-tracking drag-to-dismiss, shared with the Library/scope/import
        // sheets (owner report 2026-09-29): this dialog previously had no swipe
        // handling at all.
        if (isWide)
          Positioned(
            left: _popoverLeft(size),
            top: bandTop,
            height: bandHeight,
            width: _popoverWidth,
            // Hangs off whichever end of the band the row is nearer, which is
            // what §12's "anchored to the row" means on a list that scrolls:
            // a row in the top half gets a sheet below it, a row near the bottom
            // gets one above, and either way all of it is on screen.
            child: Align(
              alignment: _popoverAlignment(size),
              child: SrsSheetDismissible(child: sheet),
            ),
          )
        else
          Positioned(left: 8, right: 8, bottom: 8, child: SrsSheetDismissible(child: sheet)),
      ],
    );
  }

  /// Which end of the band the sheet should hang from: below the row when the row
  /// is in the upper half, above it when it is in the lower half.
  Alignment _popoverAlignment(Size size) {
    final a = anchor!;
    // Measured against the row's own middle, not its top: a row straddling the
    // middle opens downwards, where the space is.
    return a.center.dy < size.height / 2 ? Alignment.topLeft : Alignment.bottomLeft;
  }

  /// Beside the row that opened the sheet, on whichever side has room.
  double _popoverLeft(Size size) {
    final a = anchor!;
    const gap = 8.0;
    final right = a.right + gap;
    if (right + _popoverWidth <= size.width - 20) return right;
    final left = a.left - gap - _popoverWidth;
    return math.max(20.0, left);
  }
}

/// The rename dialog's card. Owns the text controller so it is disposed with the widget, and pops
/// with the trimmed name rather than performing the rename itself.
class _RenameDialogBody extends StatefulWidget {
  const _RenameDialogBody({required this.initial});

  final String initial;

  @override
  State<_RenameDialogBody> createState() => _RenameDialogBodyState();
}

class _RenameDialogBodyState extends State<_RenameDialogBody> {
  late final TextEditingController _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return SrsDialog(
      title: 'Rename study',
      content: SrsTextInput(
        controller: _controller,
        autofocus: true,
        semanticLabel: 'Study name',
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        SrsTextButton(label: 'Cancel', onPressed: () => Navigator.of(context).pop()),
        SrsPillButton(label: 'Rename', onPressed: _submit),
      ],
    );
  }
}
