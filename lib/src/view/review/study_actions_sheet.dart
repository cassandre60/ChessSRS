// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/persistence/study_repository.dart';
import 'package:chess_srs/src/review/review_controller.dart';
import 'package:chess_srs/src/view/review/export_pgn_dialog.dart';
import 'package:chess_srs/src/view/review/study_chapters_screen.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart'
    show InkWell, InputDecoration, Material, TextField, UnderlineInputBorder;

/// Modal Study Actions Sheet (matches `#sheetActs` in `chesssrs-design-demo.html`).
/// Provides actions for a specific study: Chapters, Analyze, Practice, Export PGN,
/// Pause/Resume, Rename, and Delete.
class SrsStudyActionsSheet extends ConsumerWidget {
  const SrsStudyActionsSheet({required this.study, super.key});

  final Study study;

  /// Displays the study actions sheet.
  static Future<void> show(BuildContext context, Study study) {
    final c = context.srs;
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: c.scrim,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder:
          (
            BuildContext dialogContext,
            Animation<double> animation,
            Animation<double> secondaryAnimation,
          ) {
            return SrsStudyActionsSheet(study: study);
          },
      transitionBuilder:
          (
            BuildContext dialogContext,
            Animation<double> animation,
            Animation<double> secondaryAnimation,
            Widget child,
          ) {
            final isWide = MediaQuery.of(dialogContext).size.width >= 768;
            if (isWide) {
              return FadeTransition(
                opacity: CurvedAnimation(parent: animation, curve: SrsMotion.ease),
                child: ScaleTransition(
                  scale: Tween<double>(
                    begin: 0.95,
                    end: 1.0,
                  ).animate(CurvedAnimation(parent: animation, curve: SrsMotion.ease)),
                  child: child,
                ),
              );
            } else {
              return SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 1),
                  end: Offset.zero,
                ).animate(CurvedAnimation(parent: animation, curve: SrsMotion.ease)),
                child: child,
              );
            }
          },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.srs;
    final mediaQuery = MediaQuery.of(context);
    final isWide = mediaQuery.size.width >= 768;
    // Capture the container before any pop: sheet's `ref` is unsafe after unmount.
    final container = ProviderScope.containerOf(context);

    final maxWidth = isWide ? 420.0 : mediaQuery.size.width;
    final maxHeight = mediaQuery.size.height * (isWide ? 0.82 : 0.88);

    final content = Material(
      color: c.surface,
      borderRadius: BorderRadius.vertical(
        top: const Radius.circular(22),
        bottom: Radius.circular(isWide ? 18 : 0),
      ),
      child: SafeArea(
        top: false,
        bottom: !isWide,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!isWide) ...[
                const SizedBox(height: 8),
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: c.hairline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ] else
                const SizedBox(height: 12),

              // Title and study name header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                child: Text(
                  'Actions',
                  style: TextStyle(
                    fontFamily: SrsText.ui,
                    fontSize: 12.0,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                    color: c.ink3,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  study.title,
                  style: TextStyle(
                    fontFamily: SrsText.ui,
                    fontSize: 18.0,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                    color: c.ink,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              Container(height: 1, color: c.hairlineSoft),

              // Group 1: Study navigation & drilling
              _buildRow(
                c: c,
                title: 'Chapters',
                subtitle: 'View and train specific chapters',
                showChevron: true,
                onTap: () async {
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
              _buildRow(
                c: c,
                title: 'Analyze',
                subtitle: 'Browse moves and variations',
                showChevron: true,
                onTap: () {
                  Navigator.of(context).pop();
                  openStudyExplorer(context, ref, studyId: study.id);
                },
              ),
              _buildRow(
                c: c,
                title: 'Practice',
                subtitle: 'Drill lines without changing your schedule',
                showChevron: false,
                onTap: () {
                  Navigator.of(context).pop();
                  ref
                      .read(reviewControllerProvider.notifier)
                      .startPracticeMode(scope: ReviewScope.study(study.id));
                },
              ),

              _buildDivider(c),

              // Group 2: Export & Active state
              _buildRow(
                c: c,
                title: 'Export PGN',
                subtitle: 'Share or copy standard PGN notation',
                showChevron: false,
                onTap: () async {
                  Navigator.of(context).pop();
                  final pgn = await ref
                      .read(reviewControllerProvider.notifier)
                      .exportStudyPgn(study.id);
                  if (context.mounted) {
                    // Empty repertoires render the in-dialog empty state.
                    ExportPgnDialog.show(
                      context,
                      title: study.title,
                      pgnText: pgn ?? '',
                      subtitle: 'Repertoire export',
                    );
                  }
                },
              ),
              _buildRow(
                c: c,
                title: study.isActive ? 'Pause' : 'Resume',
                subtitle: study.isActive
                    ? 'Suspend from active review pool'
                    : 'Activate in review pool',
                showChevron: false,
                onTap: () {
                  Navigator.of(context).pop();
                  ref
                      .read(reviewControllerProvider.notifier)
                      .toggleStudyActive(study.id, !study.isActive);
                },
              ),

              _buildDivider(c),

              // Group 3: Manage
              _buildRow(
                c: c,
                title: 'Rename',
                subtitle: 'Change repertoire title',
                showChevron: false,
                onTap: () {
                  Navigator.of(context).pop();
                  _showRenameDialog(context, container, study);
                },
              ),
              _buildRow(
                c: c,
                title: 'Delete',
                subtitle: 'Permanently remove from this device',
                showChevron: false,
                isDanger: true,
                onTap: () {
                  Navigator.of(context).pop();
                  _showDeleteConfirmDialog(context, container, study);
                },
              ),

              const SizedBox(height: 12),
            ],
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
        Align(
          alignment: isWide ? Alignment.topRight : Alignment.bottomCenter,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onVerticalDragEnd: (details) {
              if ((details.primaryVelocity ?? 0) > 150) {
                Navigator.of(context).pop();
              }
            },
            child: Container(
              width: maxWidth,
              constraints: BoxConstraints(maxHeight: maxHeight),
              margin: isWide
                  ? const EdgeInsets.only(top: 56, right: 26, bottom: 24)
                  : EdgeInsets.zero,
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.vertical(
                  top: const Radius.circular(22),
                  bottom: Radius.circular(isWide ? 18 : 0),
                ),
                border: Border.all(color: c.hairline, width: 1),
                boxShadow: [BoxShadow(color: c.scrim, blurRadius: 30, offset: const Offset(0, 8))],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.vertical(
                  top: const Radius.circular(22),
                  bottom: Radius.circular(isWide ? 18 : 0),
                ),
                child: content,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDivider(SrsColors c) {
    return Container(
      height: 1,
      color: c.hairlineSoft,
      margin: const EdgeInsets.symmetric(vertical: 4),
    );
  }

  Widget _buildRow({
    required SrsColors c,
    required String title,
    String? subtitle,
    required bool showChevron,
    bool isDanger = false,
    required VoidCallback onTap,
  }) {
    final titleColor = isDanger ? const Color(0xFFB3261E) : c.ink;
    return InkWell(
      onTap: onTap,
      splashColor: c.hairlineSoft,
      highlightColor: c.hairlineSoft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: SrsText.ui,
                      fontSize: 15.0,
                      fontWeight: FontWeight.w500,
                      color: titleColor,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontFamily: SrsText.ui,
                        fontSize: 12.0,
                        color: isDanger ? const Color(0xFFB3261E).withValues(alpha: 0.8) : c.ink3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (showChevron) ...[
              const SizedBox(width: 8),
              Icon(Symbols.chevron_right_rounded, size: 16, color: c.ink3),
            ],
          ],
        ),
      ),
    );
  }

  void _showRenameDialog(BuildContext context, ProviderContainer container, Study study) {
    final controller = TextEditingController(text: study.title);
    SrsDialog.show<void>(
      context: context,
      builder: (BuildContext ctx) {
        final c = ctx.srs;
        return SrsDialog(
          title: 'Rename repertoire',
          content: TextField(
            controller: controller,
            autofocus: true,
            style: TextStyle(fontFamily: SrsText.ui, fontSize: 16, color: c.ink),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Repertoire name',
              hintStyle: TextStyle(fontFamily: SrsText.ui, color: c.ink3),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: c.hairline)),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: c.accent, width: 1.5),
              ),
            ),
          ),
          actions: [
            SrsTextButton(label: 'Cancel', onPressed: () => Navigator.of(ctx).pop()),
            SrsPillButton(
              label: 'Rename',
              onPressed: () async {
                final newName = controller.text.trim();
                if (newName.isNotEmpty && newName != study.title) {
                  Navigator.of(ctx).pop();
                  await container
                      .read(reviewControllerProvider.notifier)
                      .renameStudy(study.id, newName);
                }
              },
            ),
          ],
        );
      },
    );
  }

  void _showDeleteConfirmDialog(BuildContext context, ProviderContainer container, Study study) {
    SrsDialog.show<void>(
      context: context,
      builder: (BuildContext ctx) {
        return SrsDialog(
          title: 'Delete repertoire?',
          body:
              'This will delete all moves and training history for this repertoire. This cannot be undone.',
          actions: [
            SrsTextButton(label: 'Cancel', onPressed: () => Navigator.of(ctx).pop()),
            SrsPillButton(
              label: 'Delete',
              onPressed: () async {
                Navigator.of(ctx).pop();
                await container.read(reviewControllerProvider.notifier).deleteStudy(study.id);
              },
            ),
          ],
        );
      },
    );
  }
}
