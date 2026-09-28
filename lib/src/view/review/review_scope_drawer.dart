// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/persistence/persistence.dart';
import 'package:chess_srs/src/review/review_controller.dart';
import 'package:chess_srs/src/view/review/export_pgn_dialog.dart';
import 'package:chess_srs/src/view/review/repertoire_import_dialog.dart';
import 'package:chess_srs/src/view/review/study_chapters_screen.dart';
import 'package:chess_srs/src/widgets/feedback.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

/// Modal scope selector (hybrid of Diagram bottom sheet and rich repertoire list).
/// Allows the user to select the review scope (all studies vs one study vs opening hub),
/// view study progress metrics, toggle active review pool status, or trigger a new PGN import.
class ReviewScopeDrawer extends ConsumerStatefulWidget {
  const ReviewScopeDrawer({super.key});

  /// Displays the scope selector sheet.
  static Future<void> show(BuildContext context) {
    final c = context.srs;
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: c.scrim,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return const ReviewScopeDrawer();
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

    final isAllSelected =
        reviewState.scope.studyId == null && reviewState.scope.openingFamily == null;

    final query = _searchQuery.trim().toLowerCase();
    // The row is labelled `All repertoires` (design/docs/01-identity.md), so match that.
    final showAllStudies = query.isEmpty || 'all repertoires'.contains(query);

    final filteredOpeningHubs = query.isEmpty
        ? reviewState.openingDueCounts.entries.toList()
        : reviewState.openingDueCounts.entries
              .where((entry) => entry.key.toLowerCase().contains(query))
              .toList();

    final filteredStudies = query.isEmpty
        ? reviewState.studies
        : reviewState.studies.where((study) => study.title.toLowerCase().contains(query)).toList();

    final hasNoResults =
        query.isNotEmpty &&
        !showAllStudies &&
        filteredOpeningHubs.isEmpty &&
        filteredStudies.isEmpty;

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
                                // Group: Everywhere (All repertoires)
                                if (showAllStudies) ...[
                                  _buildGroupHeader('Everywhere', c),
                                  _ScopeRow(
                                    name: 'All repertoires',
                                    semanticLabel:
                                        'All repertoires, ${reviewState.totalDueCount} due',
                                    dueCount: reviewState.totalDueCount,
                                    isPaused: false,
                                    isSelected: isAllSelected,
                                    progress: reviewState.totalProgress,
                                    onPressed: () {
                                      Navigator.of(context).pop();
                                      ref
                                          .read(reviewControllerProvider.notifier)
                                          .changeScope(const ReviewScope.all());
                                    },
                                  ),
                                ],

                                // Group: Openings
                                if (filteredOpeningHubs.isNotEmpty) ...[
                                  _buildGroupHeader('Openings', c),
                                  for (final entry in filteredOpeningHubs)
                                    Builder(
                                      builder: (context) {
                                        final progress =
                                            reviewState.openingProgress[entry.key] ??
                                            RepertoireProgress.zero;
                                        return _ScopeRow(
                                          name: entry.key,
                                          semanticLabel: '${entry.key} opening, ${entry.value} due',
                                          dueCount: entry.value,
                                          isPaused: false,
                                          isSelected: reviewState.scope.openingFamily == entry.key,
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

                                // Group: Repertoires
                                if (filteredStudies.isNotEmpty) ...[
                                  _buildGroupHeader('Repertoires', c),
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
                                          isSelected: reviewState.scope.studyId == study.id,
                                          progress: progress,
                                          onPressed: () {
                                            Navigator.of(context).pop();
                                            ref
                                                .read(reviewControllerProvider.notifier)
                                                .changeScope(ReviewScope.study(study.id));
                                          },
                                          onShowActions: () =>
                                              _showStudyActionsSheet(context, ref, study),
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
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragEnd: (details) {
            if ((details.primaryVelocity ?? 0) > 150) {
              Navigator.of(context).pop();
            }
          },
          child: content,
        ),
      ],
    );
  }

  /// design/docs/03-components.md §6.2: group titles are `12.5/500 ink3`, padding 14/18/4.
  Widget _buildGroupHeader(String title, SrsColors c) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18.0, 14.0, 18.0, 4.0),
      child: Text(title, style: SrsText.groupTitle(c.ink3)),
    );
  }

  void _showStudyActionsSheet(BuildContext context, WidgetRef ref, Study study) {
    final c = context.srs;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.ground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                child: Text(
                  study.title,
                  style: SrsText.titleSmall(c.ink),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(height: 1, color: c.hairlineSoft),
              // Pause moved here from the row itself: design/docs/03-components.md §6.4 keeps row
              // actions out of the list row, and the row still shows the paused state.
              ListTile(
                dense: true,
                leading: Icon(
                  study.isActive
                      ? Symbols.pause_circle_outline_rounded
                      : Symbols.play_circle_rounded,
                  color: c.ink,
                ),
                title: Text(
                  study.isActive ? 'Pause Study' : 'Resume Study',
                  style: SrsText.settingLabel(c.ink),
                ),
                subtitle: Text(
                  study.isActive
                      ? 'Remove from the review pool until you resume it'
                      : 'Add back to the review pool',
                  style: SrsText.settingHelp(c.ink3),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  ref
                      .read(reviewControllerProvider.notifier)
                      .toggleStudyActive(study.id, !study.isActive);
                },
              ),
              ListTile(
                dense: true,
                leading: Icon(Symbols.view_list_rounded, color: c.ink),
                title: Text('Chapters', style: SrsText.settingLabel(c.ink)),
                subtitle: Text(
                  'View and train specific chapters in this study',
                  style: SrsText.meta(c.ink3),
                ),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).pop();
                  final repo = await ref.read(srsStudyRepositoryProvider.future);
                  final chapters = await repo.getChaptersByStudy(study.id);
                  if (context.mounted) {
                    Navigator.of(
                      context,
                      rootNavigator: true,
                    ).push(StudyChaptersScreen.buildRoute(study: study, chapters: chapters));
                  }
                },
              ),
              ListTile(
                dense: true,
                leading: Icon(Symbols.explore_rounded, color: c.ink),
                title: Text('Analyze Study', style: SrsText.settingLabel(c.ink)),
                subtitle: Text(
                  'Browse moves, variations, and engine evaluation',
                  style: SrsText.meta(c.ink3),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).pop();
                  openStudyExplorer(context, ref, studyId: study.id);
                },
              ),
              ListTile(
                dense: true,
                leading: Icon(Symbols.fitness_center_rounded, color: c.ink),
                title: Text('Free Practice', style: SrsText.settingLabel(c.ink)),
                subtitle: Text(
                  'Drill lines on the board without altering SRS schedule',
                  style: SrsText.meta(c.ink3),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).pop();
                  ref
                      .read(reviewControllerProvider.notifier)
                      .startPracticeMode(scope: ReviewScope.study(study.id));
                },
              ),
              ListTile(
                dense: true,
                leading: Icon(Symbols.share_rounded, color: c.ink),
                title: Text('Export PGN', style: SrsText.settingLabel(c.ink)),
                subtitle: Text(
                  'Share or copy standard PGN notation for this study',
                  style: SrsText.meta(c.ink3),
                ),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  final pgn = await ref
                      .read(reviewControllerProvider.notifier)
                      .exportStudyPgn(study.id);
                  if (pgn == null || pgn.trim().isEmpty) {
                    if (context.mounted) {
                      showSnackBar(
                        context,
                        'No moves to export in this study',
                        type: SnackBarType.info,
                      );
                    }
                    return;
                  }
                  if (context.mounted) {
                    ExportPgnDialog.show(context, title: study.title, pgnText: pgn);
                  }
                },
              ),
              ListTile(
                dense: true,
                leading: Icon(Symbols.edit_rounded, color: c.ink),
                title: Text('Rename Study', style: SrsText.settingLabel(c.ink)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _showRenameDialog(context, ref, study);
                },
              ),
              ListTile(
                dense: true,
                leading: Icon(Symbols.delete_rounded, color: Theme.of(context).colorScheme.error),
                title: Text(
                  'Delete Study',
                  style: SrsText.settingLabel(Theme.of(context).colorScheme.error),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _showDeleteConfirmDialog(context, ref, study);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showRenameDialog(BuildContext context, WidgetRef ref, Study study) {
    final c = context.srs;
    final controller = TextEditingController(text: study.title);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.ground,
        title: Text('Rename Study', style: SrsText.titleSmall(c.ink)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: SrsText.body(false, c.ink),
          decoration: InputDecoration(
            labelText: 'Study Name',
            labelStyle: SrsText.meta(c.ink3),
            isDense: true,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: SrsText.meta(c.ink2)),
          ),
          FilledButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty && newName != study.title) {
                Navigator.of(ctx).pop();
                await ref.read(reviewControllerProvider.notifier).renameStudy(study.id, newName);
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmDialog(BuildContext context, WidgetRef ref, Study study) {
    final c = context.srs;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.ground,
        title: Text('Delete Study', style: SrsText.titleSmall(c.ink)),
        content: Text(
          'Are you sure you want to delete "${study.title}" and all its saved review progress? This cannot be undone.',
          style: SrsText.body(false, c.ink2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: SrsText.meta(c.ink2)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await ref.read(reviewControllerProvider.notifier).deleteStudy(study.id);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
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
  final VoidCallback? onShowActions;

  @override
  Widget build(BuildContext context) {
    final c = context.srs;
    final actions = onShowActions;
    return SrsPressable(
      onPressed: onPressed,
      onLongPress: actions,
      onSecondaryTap: actions,
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
                        onPressed: actions,
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
