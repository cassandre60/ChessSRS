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
    final showAllStudies = query.isEmpty || 'all studies'.contains(query);

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
                                hintText: 'Search repertoires & hubs...',
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
                                // Group: Everywhere (All Studies)
                                if (showAllStudies) ...[
                                  _buildGroupHeader('Everywhere', c),
                                  ListTile(
                                    selected: isAllSelected,
                                    selectedTileColor: c.accentSoft,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 18.0,
                                      vertical: 2.0,
                                    ),
                                    leading: Icon(
                                      Symbols.all_inclusive_rounded,
                                      size: 20,
                                      color: isAllSelected ? c.accent : c.ink,
                                    ),
                                    title: Text(
                                      'All Studies',
                                      style: TextStyle(
                                        fontFamily: SrsText.ui,
                                        fontSize: 15.5,
                                        fontWeight: FontWeight.w500,
                                        color: c.ink,
                                      ),
                                    ),
                                    subtitle: reviewState.totalProgress.totalDecisions > 0
                                        ? Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const SizedBox(height: 2),
                                              Text(
                                                '${reviewState.totalProgress.learnedDecisions}/${reviewState.totalProgress.totalDecisions} learned (${reviewState.totalProgress.progressPercentage}%)',
                                                style: TextStyle(
                                                  fontFamily: SrsText.ui,
                                                  fontSize: 12.0,
                                                  color: c.ink3,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              SrsMemoryBar(
                                                width: 96,
                                                height: 5,
                                                gap: 2,
                                                radius: 1,
                                                retained:
                                                    (reviewState.totalProgress.learnedDecisions -
                                                            reviewState.totalProgress.dueDecisions)
                                                        .clamp(
                                                          0,
                                                          reviewState.totalProgress.totalDecisions,
                                                        ),
                                                learning: reviewState.totalProgress.dueDecisions,
                                                fresh:
                                                    (reviewState.totalProgress.totalDecisions -
                                                            reviewState
                                                                .totalProgress
                                                                .learnedDecisions)
                                                        .clamp(
                                                          0,
                                                          reviewState.totalProgress.totalDecisions,
                                                        ),
                                              ),
                                            ],
                                          )
                                        : Text(
                                            'Combined pool of all active repertoires',
                                            style: TextStyle(
                                              fontFamily: SrsText.ui,
                                              fontSize: 12.5,
                                              color: c.ink3,
                                            ),
                                          ),
                                    trailing: _buildDueNumeral(reviewState.totalDueCount, true, c),
                                    onTap: () {
                                      Navigator.of(context).pop();
                                      ref
                                          .read(reviewControllerProvider.notifier)
                                          .changeScope(const ReviewScope.all());
                                    },
                                  ),
                                ],

                                // Group: Opening Hubs
                                if (filteredOpeningHubs.isNotEmpty) ...[
                                  _buildGroupHeader('Opening Hubs', c),
                                  for (final entry in filteredOpeningHubs)
                                    ListTile(
                                      selected: reviewState.scope.openingFamily == entry.key,
                                      selectedTileColor: c.accentSoft,
                                      contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 18.0,
                                        vertical: 2.0,
                                      ),
                                      leading: Icon(
                                        Symbols.category_rounded,
                                        size: 20,
                                        color: reviewState.scope.openingFamily == entry.key
                                            ? c.accent
                                            : c.ink2,
                                      ),
                                      title: Text(
                                        entry.key,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontFamily: SrsText.ui,
                                          fontSize: 15.5,
                                          fontWeight: FontWeight.w500,
                                          color: c.ink,
                                        ),
                                      ),
                                      subtitle: Builder(
                                        builder: (context) {
                                          final progress = reviewState.openingProgress[entry.key];
                                          return Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                'Opening Hub',
                                                style: TextStyle(
                                                  fontFamily: SrsText.ui,
                                                  fontSize: 12.5,
                                                  color: c.ink3,
                                                ),
                                              ),
                                              if (progress != null &&
                                                  progress.totalDecisions > 0) ...[
                                                const SizedBox(height: 2),
                                                Text(
                                                  '${progress.learnedDecisions}/${progress.totalDecisions} learned (${progress.progressPercentage}%)',
                                                  style: TextStyle(
                                                    fontFamily: SrsText.ui,
                                                    fontSize: 12.0,
                                                    color: c.ink3,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                SrsMemoryBar(
                                                  width: 96,
                                                  height: 5,
                                                  gap: 2,
                                                  radius: 1,
                                                  retained:
                                                      (progress.learnedDecisions -
                                                              progress.dueDecisions)
                                                          .clamp(0, progress.totalDecisions),
                                                  learning: progress.dueDecisions,
                                                  fresh:
                                                      (progress.totalDecisions -
                                                              progress.learnedDecisions)
                                                          .clamp(0, progress.totalDecisions),
                                                ),
                                              ],
                                            ],
                                          );
                                        },
                                      ),
                                      trailing: _buildDueNumeral(entry.value, true, c),
                                      onTap: () {
                                        Navigator.of(context).pop();
                                        ref
                                            .read(reviewControllerProvider.notifier)
                                            .changeScope(ReviewScope.opening(entry.key));
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
                                        final progress = reviewState.studyProgress[study.id];
                                        final isSelected = reviewState.scope.studyId == study.id;
                                        return ListTile(
                                          selected: isSelected,
                                          selectedTileColor: c.accentSoft,
                                          contentPadding: const EdgeInsets.symmetric(
                                            horizontal: 18.0,
                                            vertical: 2.0,
                                          ),
                                          leading: IconButton(
                                            icon: Icon(
                                              study.isActive
                                                  ? Symbols.check_circle_rounded
                                                  : Symbols.pause_circle_outline_rounded,
                                              size: 20,
                                              color: study.isActive ? c.accent : c.ink3,
                                            ),
                                            tooltip: study.isActive
                                                ? 'Active in review pool (tap to suspend)'
                                                : 'Suspended from review pool (tap to activate)',
                                            onPressed: () {
                                              ref
                                                  .read(reviewControllerProvider.notifier)
                                                  .toggleStudyActive(study.id, !study.isActive);
                                            },
                                          ),
                                          title: Text(
                                            study.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontFamily: SrsText.ui,
                                              fontSize: 15.5,
                                              fontWeight: FontWeight.w500,
                                              color: study.isActive ? c.ink : c.ink3,
                                            ),
                                          ),
                                          subtitle: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (progress != null &&
                                                  progress.totalDecisions > 0) ...[
                                                const SizedBox(height: 2),
                                                Text(
                                                  '${progress.learnedDecisions}/${progress.totalDecisions} learned (${progress.progressPercentage}%)',
                                                  style: TextStyle(
                                                    fontFamily: SrsText.ui,
                                                    fontSize: 12.0,
                                                    color: c.ink3,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                SrsMemoryBar(
                                                  width: 96,
                                                  height: 5,
                                                  gap: 2,
                                                  radius: 1,
                                                  retained:
                                                      (progress.learnedDecisions -
                                                              progress.dueDecisions)
                                                          .clamp(0, progress.totalDecisions),
                                                  learning: progress.dueDecisions,
                                                  fresh:
                                                      (progress.totalDecisions -
                                                              progress.learnedDecisions)
                                                          .clamp(0, progress.totalDecisions),
                                                ),
                                              ] else
                                                Text(
                                                  study.isActive ? 'No positions' : 'Paused',
                                                  style: TextStyle(
                                                    fontFamily: SrsText.ui,
                                                    fontSize: 12.5,
                                                    color: c.ink3,
                                                  ),
                                                ),
                                            ],
                                          ),
                                          trailing: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              _buildDueNumeral(due, study.isActive, c),
                                              IconButton(
                                                icon: Icon(
                                                  Symbols.more_vert_rounded,
                                                  size: 20,
                                                  color: c.ink2,
                                                ),
                                                tooltip: 'Study options',
                                                onPressed: () =>
                                                    _showStudyActionsSheet(context, ref, study),
                                              ),
                                            ],
                                          ),
                                          onTap: () {
                                            Navigator.of(context).pop();
                                            ref
                                                .read(reviewControllerProvider.notifier)
                                                .changeScope(ReviewScope.study(study.id));
                                          },
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

  Widget _buildGroupHeader(String title, SrsColors c) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20.0, 14.0, 20.0, 6.0),
      child: Text(
        title,
        style: TextStyle(
          fontFamily: SrsText.ui,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.9,
          color: c.ink3,
        ),
      ),
    );
  }

  Widget _buildDueNumeral(int count, bool isActive, SrsColors c) {
    final isZero = count == 0;
    return Text(
      '$count',
      style: TextStyle(
        fontFamily: SrsText.ui,
        fontSize: 15.0,
        fontWeight: isZero || !isActive ? FontWeight.w400 : FontWeight.w600,
        color: isZero || !isActive ? c.ink3 : c.ink,
        fontFeatures: SrsText.tabular,
      ),
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
