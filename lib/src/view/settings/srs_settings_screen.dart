// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:chess_srs/src/constants.dart';
import 'package:chess_srs/src/db/database.dart';
import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/model/auth/auth_controller.dart';
import 'package:chess_srs/src/model/settings/board_preferences.dart';
import 'package:chess_srs/src/model/settings/general_preferences.dart';
import 'package:chess_srs/src/model/study/study_preferences.dart';
import 'package:chess_srs/src/view/account/account_menu.dart';
import 'package:chess_srs/src/view/settings/app_log_settings_screen.dart';
import 'package:chess_srs/src/view/settings/board_settings_screen.dart';
import 'package:chess_srs/src/view/settings/engine_settings_screen.dart';
import 'package:chess_srs/src/view/settings/http_log_screen.dart';
import 'package:chess_srs/src/view/settings/sound_settings_screen.dart';
import 'package:chess_srs/src/view/settings/theme_settings_screen.dart';
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
  Widget _buildSectionHeader(String title, SrsColors c) {
    return Padding(
      padding: const EdgeInsets.only(top: 28, bottom: 8),
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
                      padding: const EdgeInsets.fromLTRB(24, 6, 24, 56),
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
                          const SizedBox(height: 12),

                          // 1. Section: Account
                          //
                          // The only entry point to the account cluster. It was reachable through
                          // a bottom-nav "More" tab until that shell was removed, and the row was
                          // not replaced, so signing in, signing out, the profile and the about
                          // page all sat in widgets nothing could navigate to. The import dialog
                          // offers sign-in in context for private studies; this is the way back
                          // for everything else, including signing out again.
                          _buildSectionHeader('Account', c),
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
                          const SizedBox(height: 28),

                          // 2. Section: Review & Spaced Repetition
                          _buildSectionHeader('Review & Spaced Repetition', c),
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

                          // 3. Section: Appearance & Theme
                          _buildSectionHeader('Appearance & Theme', c),
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
                                  label: 'Theme & appearance',
                                  help: 'AMOLED, board brightness, and hue.',
                                  value: generalPrefs.systemColors
                                      ? 'System'
                                      : (isDark ? 'Dark' : 'Light'),
                                  onTap: () =>
                                      Navigator.of(context).push(ThemeSettingsScreen.buildRoute()),
                                ),
                              ],
                            ),
                          ),

                          // 4. Section: Board & Pieces
                          _buildSectionHeader('Board & Pieces', c),
                          Container(
                            decoration: BoxDecoration(
                              border: Border(top: BorderSide(color: c.hairline)),
                            ),
                            child: Column(
                              children: [
                                _NavRow(
                                  label: 'Board & pieces',
                                  help: 'Board themes, piece sets, and move coordinates.',
                                  value:
                                      '${boardPrefs.boardTheme.label} / ${boardPrefs.pieceSet.label}',
                                  onTap: () =>
                                      Navigator.of(context).push(BoardSettingsScreen.buildRoute()),
                                ),
                              ],
                            ),
                          ),

                          // 5. Section: Sound & Audio
                          _buildSectionHeader('Sound & Audio', c),
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
                                _NavRow(
                                  label: 'Sound & audio details',
                                  help: 'Sound theme and master volume slider.',
                                  value:
                                      '${soundThemeL10n(context, generalPrefs.soundTheme)} (${volumeLabel(generalPrefs.masterVolume)})',
                                  onTap: () =>
                                      Navigator.of(context).push(SoundSettingsScreen.buildRoute()),
                                ),
                              ],
                            ),
                          ),

                          // 6. Section: Chess Engine
                          _buildSectionHeader('Chess Engine', c),
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

                          // 7. Section: Data & Diagnostics
                          _buildSectionHeader('Data & Diagnostics', c),
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
                                  onTap: () =>
                                      Navigator.of(context).push(AppLogSettingsScreen.buildRoute()),
                                ),
                              ],
                            ),
                          ),

                          // 8. Section: About & Licences
                          _buildSectionHeader('About', c),
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

class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.label, this.help, required this.control});

  final String label;
  final String? help;
  final Widget control;

  @override
  Widget build(BuildContext context) {
    final c = context.srs;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.hairlineSoft)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 520;
          final textColumn = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontFamily: SrsText.ui,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: c.ink,
                ),
              ),
              if (help != null) ...[
                const SizedBox(height: 3),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Text(
                    help!,
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

          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [textColumn, const SizedBox(height: 12), control],
            );
          }

          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: textColumn),
              const SizedBox(width: 24),
              control,
            ],
          );
        },
      ),
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
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.hairlineSoft)),
      ),
      child: SrsPressable(
        onPressed: onTap,
        radius: 8,
        builder: (context, hovered, _) => Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          color: hovered ? c.page : Colors.transparent,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontFamily: SrsText.ui,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: c.ink,
                      ),
                    ),
                    if (help != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        help!,
                        style: TextStyle(
                          fontFamily: SrsText.ui,
                          fontSize: 14,
                          color: c.ink2,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 16),
              if (value != null) ...[
                Text(
                  value!,
                  style: TextStyle(
                    fontFamily: SrsText.ui,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: c.ink2,
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
  }
}
