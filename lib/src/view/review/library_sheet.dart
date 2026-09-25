// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/model/analysis/analysis_controller.dart';
import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chess_srs/src/view/analysis/analysis_screen.dart';
import 'package:chess_srs/src/view/board_editor/board_editor_screen.dart';
import 'package:chess_srs/src/view/review/repertoire_import_dialog.dart';
import 'package:chess_srs/src/view/review/review_copy.dart';
import 'package:chess_srs/src/view/review/review_scope_drawer.dart';
import 'package:chess_srs/src/view/settings/srs_settings_screen.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

/// Modal Library sheet (replaces overflow menu and legacy "More" tab).
/// Anchored top-right on wide layouts and sliding from bottom on narrow layouts.
class SrsLibrarySheet extends ConsumerWidget {
  const SrsLibrarySheet({super.key});

  /// Displays the Library sheet.
  static Future<void> show(BuildContext context) {
    final c = context.srs;
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: c.scrim,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return const SrsLibrarySheet();
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
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.srs;
    final mediaQuery = MediaQuery.of(context);
    final isWide = mediaQuery.size.width >= 768;

    final content = isWide
        ? Align(
            alignment: Alignment.topRight,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: Container(
                width: 310,
                margin: const EdgeInsets.only(top: 56, right: 20, bottom: 24),
                constraints: BoxConstraints(maxHeight: mediaQuery.size.height - 80),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: c.scrim, blurRadius: 24, offset: const Offset(0, 8)),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Material(color: c.surface, child: _buildContent(context, ref, c, isWide)),
                ),
              ),
            ),
          )
        : Align(
            alignment: Alignment.bottomCenter,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.all(8),
                constraints: BoxConstraints(
                  maxHeight: math.min(mediaQuery.size.height * 0.82, 720),
                ),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(color: c.scrim, blurRadius: 24, offset: const Offset(0, 8)),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Material(
                    color: c.surface,
                    child: SafeArea(top: false, child: _buildContent(context, ref, c, isWide)),
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

  Widget _buildContent(BuildContext context, WidgetRef ref, SrsColors c, bool isWide) {
    return SingleChildScrollView(
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
            const SizedBox(height: 8),

          // Group 1: Add repertoire
          _buildRow(
            c: c,
            title: 'Import PGN',
            subtitle: 'From a file, pasted text or a Lichess study',
            onTap: () {
              Navigator.pop(context);
              RepertoireImportDialog.show(context);
            },
          ),
          _buildRow(
            c: c,
            title: 'Studies & Repertoires',
            subtitle: 'Choose active study or opening hub',
            onTap: () {
              Navigator.pop(context);
              ReviewScopeDrawer.show(context);
            },
          ),

          _buildDivider(c),

          // Group 2: Explore
          _buildGroupHeader('Explore', c),
          _buildRow(
            c: c,
            title: kSrsAnalysisBoardLabel,
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context, rootNavigator: true).push(
                AnalysisScreen.buildRoute(
                  const AnalysisOptions.standalone(variant: Variant.standard),
                ),
              );
            },
          ),
          _buildRow(
            c: c,
            title: 'Board editor',
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context, rootNavigator: true).push(
                BoardEditorScreen.buildRoute((
                  initialVariant: Variant.standard,
                  initialFen: null,
                  initialOrientation: Side.white,
                )),
              );
            },
          ),
          _buildDivider(c),

          // Group 3: Preferences & Settings
          _buildGroupHeader('Preferences', c),
          _buildRow(
            c: c,
            title: kSrsSettingsLabel,
            subtitle: 'Review, board, engine, and sound',
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const SrsSettingsScreen()),
              );
            },
          ),
          _buildRow(
            c: c,
            title: kSrsAboutLabel,
            onTap: () {
              Navigator.pop(context);
              showLicensePage(context: context, applicationName: 'Chess Repertoire SRS');
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildGroupHeader(String title, SrsColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
      child: Text(
        title,
        style: TextStyle(
          fontFamily: SrsText.ui,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: c.ink3,
        ),
      ),
    );
  }

  Widget _buildDivider(SrsColors c) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Container(height: 1, color: c.hairlineSoft),
    );
  }

  Widget _buildRow({
    required SrsColors c,
    required String title,
    String? subtitle,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
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
                      fontSize: 15.5,
                      fontWeight: FontWeight.w500,
                      color: c.ink,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontFamily: SrsText.ui,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w400,
                        color: c.ink3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            trailing ?? Icon(Symbols.chevron_right_rounded, size: 16, color: c.ink3),
          ],
        ),
      ),
    );
  }
}
