// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:chess_srs/src/constants.dart';
import 'package:chess_srs/src/db/database.dart';
import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/domain/review/review_order.dart';
import 'package:chess_srs/src/domain/review/transpose_scope.dart';
import 'package:chess_srs/src/model/auth/auth_controller.dart';
import 'package:chess_srs/src/model/settings/board_preferences.dart';
import 'package:chess_srs/src/model/settings/general_preferences.dart';
import 'package:chess_srs/src/model/study/study_preferences.dart';
import 'package:chess_srs/src/view/account/account_menu.dart';
import 'package:chess_srs/src/view/settings/app_log_settings_screen.dart';
import 'package:chess_srs/src/view/settings/board_choice_screen.dart';
import 'package:chess_srs/src/view/settings/engine_settings_screen.dart';
import 'package:chess_srs/src/view/settings/http_log_screen.dart';
import 'package:chess_srs/src/view/settings/piece_set_screen.dart';
import 'package:chess_srs/src/view/settings/sound_settings_screen.dart';
import 'package:chessground/chessground.dart' show PieceShiftMethod;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// Diagram visual settings screen with unified daily limits, target retention,
/// study display toggles, theme, accent swatches, and advanced FSRS algorithms.
class SrsSettingsScreen extends ConsumerStatefulWidget {
  const SrsSettingsScreen({super.key});

  static Route<dynamic> buildRoute() {
    return MaterialPageRoute<void>(builder: (_) => const SrsSettingsScreen());
  }

  @override
  ConsumerState<SrsSettingsScreen> createState() => _SrsSettingsScreenState();
}

class _SrsSettingsScreenState extends ConsumerState<SrsSettingsScreen> {
  Widget _buildSectionHeader(String title, SrsColors c, {required bool compact}) {
    return Padding(
      padding: EdgeInsets.only(top: compact ? 16 : 28, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontFamily: SrsText.ui,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: c.ink3,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.srs;
    final mediaQuery = MediaQuery.of(context);
    final studyPrefs = ref.watch(studyPreferencesProvider);
    final studyNotifier = ref.read(studyPreferencesProvider.notifier);
    final generalPrefs = ref.watch(generalPreferencesProvider);
    final generalNotifier = ref.read(generalPreferencesProvider.notifier);
    final boardPrefs = ref.watch(boardPreferencesProvider);
    final dbSize = ref.watch(getDbSizeInBytesProvider);
    final accent = ref.watch(srsAccentProvider);
    final authUser = ref.watch(authControllerProvider);

    final isDark =
        generalPrefs.themeMode == BackgroundThemeMode.dark ||
        generalPrefs.themeMode == BackgroundThemeMode.amoled;
    final isSoundOn = generalPrefs.isSoundEnabled;

    final compact = mediaQuery.size.width < 520;
    final headlineSize = math.max(38.0, math.min(mediaQuery.size.width * 0.08, 56.0));

    return Scaffold(
      backgroundColor: c.ground,
      body: SafeArea(
        child: Column(
          children: [
            // Top head with Review back button
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.centerLeft,
              child: SrsPressable(
                onPressed: () => Navigator.of(context).pop(),
                semanticLabel: 'Review',
                radius: 10,
                builder: (context, hovered, _) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: hovered ? c.hairlineSoft : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CustomPaint(
                        size: const Size(16, 16),
                        painter: _ChevronLeftPainter(color: c.ink),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Review',
                        style: TextStyle(
                          fontFamily: SrsText.ui,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: c.ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Scrollable settings body
            Expanded(
              child: SingleChildScrollView(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 660),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(compact ? 16 : 24, 6, compact ? 16 : 24, 56),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Settings',
                            style: TextStyle(
                              fontFamily: SrsText.ui,
                              fontSize: headlineSize,
                              fontWeight: FontWeight.w400,
                              letterSpacing: -0.04 * headlineSize,
                              height: 1.0,
                              color: c.ink,
                            ),
                          ),
                          SizedBox(height: compact ? 4 : 12),

                          // 1. Section: Account
                          //
                          // The only entry point to the account cluster. It was reachable through
                          // a bottom-nav "More" tab until that shell was removed, and the row was
                          // not replaced, so signing in, signing out, the profile and the about
                          // page all sat in widgets nothing could navigate to. The import dialog
                          // offers sign-in in context for private studies; this is the way back
                          // for everything else, including signing out again.
                          _buildSectionHeader('Account', c, compact: compact),
                          Container(
                            decoration: BoxDecoration(
                              border: Border(top: BorderSide(color: c.hairline)),
                            ),
                            child: _NavRow(
                              label: 'Lichess account',
                              help: 'Sign in to import private and unlisted studies.',
                              value: authUser == null ? 'Not signed in' : authUser.user.name,
                              onTap: () =>
                                  Navigator.of(context).push(AccountMenuScreen.buildRoute(context)),
                            ),
                          ),
                          SizedBox(height: compact ? 4 : 28),

                          // 2. Section: Review & Spaced Repetition
                          _buildSectionHeader('Review & Spaced Repetition', c, compact: compact),
                          Container(
                            decoration: BoxDecoration(
                              border: Border(top: BorderSide(color: c.hairline)),
                            ),
                            child: Column(
                              children: [
                                _SettingRow(
                                  label: 'Daily limit',
                                  help: 'Positions reviewed per day.',
                                  control: SrsSegmented<int>(
                                    options: const {
                                      25: '25',
                                      50: '50',
                                      100: '100',
                                      150: '150',
                                      200: '200',
                                      0: 'None',
                                    },
                                    value: studyPrefs.maxDailyReviews,
                                    onChanged: (val) => studyNotifier.setMaxDailyReviews(val),
                                  ),
                                ),
                                _SettingRow(
                                  label: 'Target retention',
                                  help:
                                      'Higher means more reviews. 88% suits most players; 95% is for tournament preparation.',
                                  control: SrsSegmented<double>(
                                    options: {
                                      0.80: '80%',
                                      0.85: '85%',
                                      0.88: '88%',
                                      0.90: '90%',
                                      0.95: '95%',
                                    },
                                    value: studyPrefs.targetRetention,
                                    onChanged: (val) => studyNotifier.setTargetRetention(val),
                                  ),
                                ),
                                _SettingRow(
                                  label: 'Scheduling algorithm',
                                  help: 'FSRS adapts to how well you remember each position.',
                                  control: SrsSegmented<SchedulerType>(
                                    options: const {
                                      SchedulerType.fsrs: 'FSRS',
                                      SchedulerType.simple: 'Simple',
                                      SchedulerType.easeScaling: 'Ease',
                                    },
                                    value: studyPrefs.schedulerType,
                                    onChanged: (algo) => studyNotifier.setSchedulerType(algo),
                                  ),
                                ),
                                _SettingRow(
                                  label: 'Review order',
                                  help:
                                      'Same due cards in every mode. Due date serves the most overdue first; By line walks each line in order; Random shuffles the queue.',
                                  control: SrsSegmented<ReviewOrder>(
                                    options: const {
                                      ReviewOrder.dueDate: 'Due date',
                                      ReviewOrder.byLine: 'By line',
                                      ReviewOrder.random: 'Random',
                                    },
                                    value: studyPrefs.reviewOrder,
                                    onChanged: (order) => studyNotifier.setReviewOrder(order),
                                  ),
                                ),
                                _SettingRow(
                                  label: 'Transposed moves',
                                  help:
                                      'A move from another reviewed line counts as correct and review jumps there. Within study limits it to the same study; Off requires the expected line\u2019s moves.',
                                  control: SrsSegmented<TransposeScope>(
                                    options: const {
                                      TransposeScope.off: 'Off',
                                      TransposeScope.withinStudy: 'Within study',
                                      TransposeScope.inScope: 'In scope',
                                    },
                                    value: studyPrefs.transposeScope,
                                    onChanged: (scope) => studyNotifier.setTransposeScope(scope),
                                  ),
                                ),
                                if (studyPrefs.schedulerType == SchedulerType.easeScaling) ...[
                                  _SettingRow(
                                    label: 'Initial ease factor',
                                    help: 'Multiplier applied on first success.',
                                    control: SrsSegmented<double>(
                                      options: {2.0: '2.0', 2.5: '2.5', 3.0: '3.0'},
                                      value: studyPrefs.schedulerEase,
                                      onChanged: (val) => studyNotifier.setSchedulerEase(val),
                                    ),
                                  ),
                                  _SettingRow(
                                    label: 'Interval scaling',
                                    help: 'Growth multiplier for subsequent reviews.',
                                    control: SrsSegmented<double>(
                                      options: {1.3: '1.3x', 1.5: '1.5x', 1.8: '1.8x'},
                                      value: studyPrefs.schedulerScaling,
                                      onChanged: (val) => studyNotifier.setSchedulerScaling(val),
                                    ),
                                  ),
                                ],
                                _SettingRow(
                                  label: 'Show move notation',
                                  help:
                                      'Display preceding moves (e.g. 1. e4 e5) in the review screen.',
                                  control: SrsSwitch(
                                    value: studyPrefs.showMoveHistory,
                                    semanticLabel: 'Show move notation',
                                    onChanged: (_) => studyNotifier.toggleShowMoveHistory(),
                                  ),
                                ),
                                _SettingRow(
                                  // The design's words, verbatim (01-identity.md). The row
                                  // gates studyPrefs.showAnnotations, inherited from Lichess.
                                  label: 'Show arrows and circles',
                                  help: 'Drawn from your study, only after you answer.',
                                  control: SrsSwitch(
                                    value: studyPrefs.showAnnotations,
                                    semanticLabel: 'Show arrows and circles',
                                    onChanged: (_) => studyNotifier.toggleAnnotations(),
                                  ),
                                ),
                                _SettingRow(
                                  label: 'Show notes after a move',
                                  help: 'Comments from your study appear once you have answered.',
                                  control: SrsSwitch(
                                    value: studyPrefs.showPgnComments,
                                    semanticLabel: 'Show notes after a move',
                                    onChanged: (_) => studyNotifier.togglePgnComments(),
                                  ),
                                ),
                                _SettingRow(
                                  label: 'Collapsible list groups',
                                  help:
                                      'Let the Everywhere, Openings and Studies headers fold away in the scope list.',
                                  control: SrsSwitch(
                                    value: studyPrefs.collapsibleScopeGroups,
                                    semanticLabel: 'Collapsible list groups',
                                    onChanged: (_) => studyNotifier.toggleCollapsibleScopeGroups(),
                                  ),
                                ),
                                _SettingRow(
                                  label: 'Review Diagnostics HUD',
                                  help:
                                      'Show real-time FSRS retrievability, stability, and difficulty HUD in review.',
                                  control: SrsSwitch(
                                    value: studyPrefs.srsDiagnostics,
                                    semanticLabel: 'Review Diagnostics HUD',
                                    onChanged: (_) => studyNotifier.toggleSrsDiagnostics(),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // 3. Section: Appearance
                          _buildSectionHeader('Appearance', c, compact: compact),
                          Container(
                            decoration: BoxDecoration(
                              border: Border(top: BorderSide(color: c.hairline)),
                            ),
                            child: Column(
                              children: [
                                _SettingRow(
                                  label: 'Theme',
                                  control: SrsSegmented<bool>(
                                    options: const {false: 'Light', true: 'Dark'},
                                    value: isDark,
                                    onChanged: (dark) => generalNotifier.setBackgroundThemeMode(
                                      dark ? BackgroundThemeMode.dark : BackgroundThemeMode.light,
                                    ),
                                  ),
                                ),
                                _SettingRow(
                                  label: 'Accent',
                                  help: 'Colour of the correct move arrow and selection.',
                                  control: SrsAccentDots(
                                    value: accent,
                                    onChanged: (newAccent) {
                                      ref.read(srsAccentProvider.notifier).accent = newAccent;
                                    },
                                  ),
                                ),
                                _NavRow(
                                  label: 'Board theme',
                                  value: boardPrefs.boardTheme.label,
                                  onTap: () =>
                                      Navigator.of(context).push(BoardChoiceScreen.buildRoute()),
                                ),
                                _NavRow(
                                  label: 'Piece set',
                                  value: boardPrefs.pieceSet.label,
                                  onTap: () =>
                                      Navigator.of(context).push(PieceSetScreen.buildRoute()),
                                ),
                                _SettingRow(
                                  label: 'Board coordinates',
                                  control: SrsSwitch(
                                    value: boardPrefs.coordinates,
                                    semanticLabel: 'Board coordinates',
                                    onChanged: (_) => ref
                                        .read(boardPreferencesProvider.notifier)
                                        .toggleCoordinates(),
                                  ),
                                ),
                                _SettingRow(
                                  label: 'Piece animation',
                                  control: SrsSwitch(
                                    value: boardPrefs.pieceAnimation,
                                    semanticLabel: 'Piece animation',
                                    onChanged: (_) => ref
                                        .read(boardPreferencesProvider.notifier)
                                        .togglePieceAnimation(),
                                  ),
                                ),
                                _SettingRow(
                                  label: 'Board highlights',
                                  control: SrsSwitch(
                                    value: boardPrefs.boardHighlights,
                                    semanticLabel: 'Board highlights',
                                    onChanged: (_) => ref
                                        .read(boardPreferencesProvider.notifier)
                                        .toggleBoardHighlights(),
                                  ),
                                ),
                                _SettingRow(
                                  label: 'Shape drawing',
                                  help: 'Draw arrows and circles with two fingers.',
                                  control: SrsSwitch(
                                    value: boardPrefs.enableShapeDrawings,
                                    semanticLabel: 'Shape drawing',
                                    onChanged: (_) => ref
                                        .read(boardPreferencesProvider.notifier)
                                        .toggleEnableShapeDrawings(),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // 4. Section: Game behaviour
                          _buildSectionHeader('Game behaviour', c, compact: compact),
                          Container(
                            decoration: BoxDecoration(
                              border: Border(top: BorderSide(color: c.hairline)),
                            ),
                            child: Column(
                              children: [
                                _SettingRow(
                                  label: 'Premoves',
                                  control: SrsSwitch(
                                    value: boardPrefs.premoves,
                                    semanticLabel: 'Premoves',
                                    onChanged: (_) => ref
                                        .read(boardPreferencesProvider.notifier)
                                        .togglePremoves(),
                                  ),
                                ),
                                _SettingRow(
                                  label: 'How you move pieces',
                                  control: SrsSegmented<PieceShiftMethod>(
                                    options: const {
                                      PieceShiftMethod.either: 'Either',
                                      PieceShiftMethod.drag: 'Drag',
                                      PieceShiftMethod.tapTwoSquares: 'Tap',
                                    },
                                    value: boardPrefs.pieceShiftMethod,
                                    onChanged: (val) => ref
                                        .read(boardPreferencesProvider.notifier)
                                        .setPieceShiftMethod(val),
                                  ),
                                ),
                                _SettingRow(
                                  label: 'Move on release',
                                  help: 'Commit a drag move when you lift your finger.',
                                  control: SrsSwitch(
                                    value: boardPrefs.moveOnRelease,
                                    semanticLabel: 'Move on release',
                                    onChanged: (_) => ref
                                        .read(boardPreferencesProvider.notifier)
                                        .toggleMoveOnRelease(),
                                  ),
                                ),
                                _SettingRow(
                                  label: 'Castling method',
                                  control: SrsSegmented<CastlingMethod>(
                                    options: const {
                                      CastlingMethod.kingOverRook: 'King over rook',
                                      CastlingMethod.kingTwoSquares: 'Two squares',
                                    },
                                    value: boardPrefs.castlingMethod,
                                    onChanged: (val) => ref
                                        .read(boardPreferencesProvider.notifier)
                                        .setCastlingMethod(val),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // 5. Section: Sound
                          _buildSectionHeader('Sound', c, compact: compact),
                          Container(
                            decoration: BoxDecoration(
                              border: Border(top: BorderSide(color: c.hairline)),
                            ),
                            child: Column(
                              children: [
                                _SettingRow(
                                  label: 'Sound',
                                  control: SrsSwitch(
                                    value: isSoundOn,
                                    semanticLabel: 'Sound',
                                    onChanged: (_) => generalNotifier.toggleSoundEnabled(),
                                  ),
                                ),
                                _SettingRow(
                                  label: 'Volume',
                                  control: SizedBox(
                                    width: 160,
                                    child: Slider(
                                      value: generalPrefs.masterVolume,
                                      max: 1,
                                      divisions: 10,
                                      label: volumeLabel(generalPrefs.masterVolume),
                                      onChanged: (value) => generalNotifier.setMasterVolume(value),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // 6. Section: Chess Engine
                          _buildSectionHeader('Chess Engine', c, compact: compact),
                          Container(
                            decoration: BoxDecoration(
                              border: Border(top: BorderSide(color: c.hairline)),
                            ),
                            child: Column(
                              children: [
                                _NavRow(
                                  label: 'Chess engine',
                                  help: 'Threads, hash memory, search time, and multi-PV lines.',
                                  onTap: () =>
                                      Navigator.of(context).push(EngineSettingsScreen.buildRoute()),
                                ),
                              ],
                            ),
                          ),

                          // 7. Section: Data & Diagnostics (debug/beta only)
                          if (kDebugMode) ...[
                            _buildSectionHeader('Data & Diagnostics', c, compact: compact),
                            Container(
                              decoration: BoxDecoration(
                                border: Border(top: BorderSide(color: c.hairline)),
                              ),
                              child: Column(
                                children: [
                                  _SettingRow(
                                    label: 'Local database size',
                                    help: 'Storage used by local database files.',
                                    control: Text(
                                      dbSize.hasValue && dbSize.value != null
                                          ? '${(dbSize.value! / (1024 * 1024)).toStringAsFixed(2)} MB'
                                          : '...',
                                      style: TextStyle(
                                        fontFamily: SrsText.ui,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: c.ink2,
                                      ),
                                    ),
                                  ),
                                  _NavRow(
                                    label: 'HTTP network logs',
                                    help: 'Inspect raw HTTP requests and responses.',
                                    onTap: () =>
                                        Navigator.of(context).push(HttpLogScreen.buildRoute()),
                                  ),
                                  _NavRow(
                                    label: 'App diagnostics logs',
                                    help: 'Application error and debug traces.',
                                    onTap: () => Navigator.of(
                                      context,
                                    ).push(AppLogSettingsScreen.buildRoute()),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          // 8. Section: About & Licences
                          _buildSectionHeader('About', c, compact: compact),
                          Container(
                            decoration: BoxDecoration(
                              border: Border(top: BorderSide(color: c.hairline)),
                            ),
                            child: Column(
                              children: [
                                // Was on the legacy settings screen, which no user could reach
                                // because its buildRoute forwarded here. Restored rather than
                                // dropped: the capability is worth having, and this is the screen
                                // the app actually shows. The store ids come from constants.dart,
                                // which app_store_links_test guards.
                                SrsSettingsRow(
                                  label: 'Rate this app',
                                  help: 'Open the store listing for Chess Repertoire SRS.',
                                  onTap: () async {
                                    final isAndroid =
                                        Theme.of(context).platform == TargetPlatform.android;
                                    final links = androidAppStoreLinks();
                                    final launched = await launchUrl(
                                      isAndroid
                                          ? links.native
                                          : appStoreListingUrl(isAndroid: false),
                                      mode: LaunchMode.externalApplication,
                                    );
                                    if (!launched && isAndroid) {
                                      await launchUrl(
                                        links.web,
                                        mode: LaunchMode.externalApplication,
                                      );
                                    }
                                  },
                                ),
                                _NavRow(
                                  label: 'Licences & open source',
                                  help: 'GPL-3.0, chessground, dartchess, and third-party notices.',
                                  onTap: () => showLicensePage(
                                    context: context,
                                    applicationName: 'Chess Repertoire SRS',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
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

/// Keeps long explanations on demand on phones without removing them or
/// shrinking the text. Desktop retains the original always-visible descriptions.
class _SettingsLabel extends StatefulWidget {
  const _SettingsLabel({required this.label, this.help, required this.compact});

  final String label;
  final String? help;
  final bool compact;

  @override
  State<_SettingsLabel> createState() => _SettingsLabelState();
}

class _SettingsLabelState extends State<_SettingsLabel> {
  bool expanded = false;

  @override
  void didUpdateWidget(_SettingsLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Conditional scheduler rows can shift the elements below them.
    if (oldWidget.label != widget.label) expanded = false;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.srs;
    final help = widget.help;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                widget.label,
                style: TextStyle(
                  fontFamily: SrsText.ui,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: c.ink,
                ),
              ),
            ),
            if (widget.compact && help != null)
              IconButton(
                tooltip: expanded ? 'Hide details for ${widget.label}' : 'About ${widget.label}',
                // The 44dp target is also usable when the label is on a tight row.
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                padding: EdgeInsets.zero,
                iconSize: 18,
                icon: Icon(expanded ? Icons.info : Icons.info_outline, color: c.ink2),
                onPressed: () => setState(() => expanded = !expanded),
              ),
          ],
        ),
        if (help != null && (!widget.compact || expanded)) ...[
          const SizedBox(height: 3),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Text(
              help,
              style: TextStyle(
                fontFamily: SrsText.ui,
                fontSize: 14,
                color: c.ink2,
                height: 1.4,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.label, this.help, required this.control});

  final String label;
  final String? help;
  final Widget control;

  @override
  Widget build(BuildContext context) {
    final c = context.srs;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        final text = _SettingsLabel(label: label, help: help, compact: compact);
        // Only bounded, short controls belong beside the text on a phone.
        // Segments and colour pickers need the full width so they can wrap.
        final inline = control is SrsSwitch || control is SizedBox || control is Text;
        return Container(
          padding: EdgeInsets.symmetric(vertical: compact ? 8 : 18),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.hairlineSoft)),
          ),
          child: compact && !inline
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [text, const SizedBox(height: 6), control],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: text),
                    SizedBox(width: compact ? 12 : 24),
                    control,
                  ],
                ),
        );
      },
    );
  }
}

class _ChevronLeftPainter extends CustomPainter {
  const _ChevronLeftPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..moveTo(size.width * 0.62, size.height * 0.2)
      ..lineTo(size.width * 0.32, size.height * 0.5)
      ..lineTo(size.width * 0.62, size.height * 0.8);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ChevronLeftPainter oldDelegate) => color != oldDelegate.color;
}

class _ChevronRightPainter extends CustomPainter {
  const _ChevronRightPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..moveTo(size.width * 0.35, size.height * 0.22)
      ..lineTo(size.width * 0.65, size.height * 0.5)
      ..lineTo(size.width * 0.35, size.height * 0.78);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ChevronRightPainter oldDelegate) => color != oldDelegate.color;
}

class _NavRow extends StatelessWidget {
  const _NavRow({required this.label, this.help, this.value, required this.onTap});

  final String label;
  final String? help;
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.srs;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        return Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.hairlineSoft)),
          ),
          child: SrsPressable(
            onPressed: onTap,
            radius: 8,
            builder: (context, hovered, _) => Container(
              padding: EdgeInsets.symmetric(vertical: compact ? 8 : 18),
              color: hovered ? c.page : Colors.transparent,
              child: Row(
                children: [
                  Expanded(child: _SettingsLabel(label: label, help: help, compact: compact)),
                  const SizedBox(width: 12),
                  if (value != null) ...[
                    Flexible(
                      child: Text(
                        value!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: SrsText.ui,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: c.ink2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  CustomPaint(
                    size: const Size(14, 14),
                    painter: _ChevronRightPainter(color: c.ink3),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
