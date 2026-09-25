// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:chess_srs/src/db/database.dart';
import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/model/settings/board_preferences.dart';
import 'package:chess_srs/src/model/settings/general_preferences.dart';
import 'package:chess_srs/src/model/study/study_preferences.dart';
import 'package:chess_srs/src/view/settings/app_log_settings_screen.dart';
import 'package:chess_srs/src/view/settings/board_settings_screen.dart';
import 'package:chess_srs/src/view/settings/engine_settings_screen.dart';
import 'package:chess_srs/src/view/settings/http_log_screen.dart';
import 'package:chess_srs/src/view/settings/sound_settings_screen.dart';
import 'package:chess_srs/src/view/settings/srs_settings_copy.dart';
import 'package:chess_srs/src/view/settings/theme_settings_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

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

                          // The design has one continuous group of rows under the title,
                          // separated by hairlines, with no section headers: see
                          // design/docs/03-components.md §11 and the demo's
                          // `#viewSettings`. The rows below follow that order.
                          DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border(top: BorderSide(color: c.hairline)),
                            ),
                            child: Column(
                              children: [
                                _SettingRow(
                                  label: kSrsSettingDailyLimit,
                                  help: kSrsSettingDailyLimitHelp,
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
                                  label: kSrsSettingTargetRetention,
                                  help: kSrsSettingTargetRetentionHelp,
                                  control: SrsSegmented<double>(
                                    options: <double, String>{
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
                                  label: kSrsSettingShowNotation,
                                  help: kSrsSettingShowNotationHelp,
                                  control: SrsSwitch(
                                    value: studyPrefs.showMoveHistory,
                                    semanticLabel: kSrsSettingShowNotation,
                                    onChanged: (_) => studyNotifier.toggleShowMoveHistory(),
                                  ),
                                ),
                                _SettingRow(
                                  label: kSrsSettingShowNotes,
                                  help: kSrsSettingShowNotesHelp,
                                  control: SrsSwitch(
                                    value: studyPrefs.showPgnComments,
                                    semanticLabel: kSrsSettingShowNotes,
                                    onChanged: (_) => studyNotifier.togglePgnComments(),
                                  ),
                                ),
                                _SettingRow(
                                  label: kSrsSettingShowAnnotations,
                                  help: kSrsSettingShowAnnotationsHelp,
                                  control: SrsSwitch(
                                    value: studyPrefs.showAnnotations,
                                    semanticLabel: kSrsSettingShowAnnotations,
                                    onChanged: (_) => studyNotifier.toggleAnnotations(),
                                  ),
                                ),
                                _SettingRow(
                                  label: kSrsSettingAccent,
                                  help: kSrsSettingAccentHelp,
                                  control: SrsAccentDots(
                                    value: accent,
                                    onChanged: (newAccent) {
                                      ref.read(srsAccentProvider.notifier).accent = newAccent;
                                    },
                                  ),
                                ),
                                _SettingRow(
                                  label: kSrsSettingTheme,
                                  control: SrsSegmented<bool>(
                                    options: const {false: 'Light', true: 'Dark'},
                                    value: isDark,
                                    onChanged: (dark) => generalNotifier.setBackgroundThemeMode(
                                      dark ? BackgroundThemeMode.dark : BackgroundThemeMode.light,
                                    ),
                                  ),
                                ),
                                _SettingRow(
                                  label: kSrsSettingSound,
                                  help: kSrsSettingSoundHelp,
                                  control: SrsSwitch(
                                    value: isSoundOn,
                                    semanticLabel: kSrsSettingSound,
                                    onChanged: (_) => generalNotifier.toggleSoundEnabled(),
                                  ),
                                ),

                                // The design hides the algorithm and the diagnostics switch
                                // behind one collapsed disclosure, so the default view stays
                                // to eight rows.
                                SrsDisclosure(
                                  title: kSrsSettingAdvanced,
                                  child: Column(
                                    children: [
                                      _SettingRow(
                                        label: kSrsSettingScheduler,
                                        help: kSrsSettingSchedulerHelp,
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
                                      if (studyPrefs.schedulerType ==
                                          SchedulerType.easeScaling) ...[
                                        _SettingRow(
                                          label: 'Initial ease factor',
                                          help: 'Multiplier applied on first success.',
                                          control: SrsSegmented<double>(
                                            options: <double, String>{
                                              2.0: '2.0',
                                              2.5: '2.5',
                                              3.0: '3.0',
                                            },
                                            value: studyPrefs.schedulerEase,
                                            onChanged: (val) => studyNotifier.setSchedulerEase(val),
                                          ),
                                        ),
                                        _SettingRow(
                                          label: 'Interval scaling',
                                          help: 'Growth multiplier for subsequent reviews.',
                                          control: SrsSegmented<double>(
                                            options: <double, String>{
                                              1.3: '1.3x',
                                              1.5: '1.5x',
                                              1.8: '1.8x',
                                            },
                                            value: studyPrefs.schedulerScaling,
                                            onChanged: (val) =>
                                                studyNotifier.setSchedulerScaling(val),
                                          ),
                                        ),
                                      ],
                                      _SettingRow(
                                        label: kSrsSettingDiagnostics,
                                        help: kSrsSettingDiagnosticsHelp,
                                        control: SrsSwitch(
                                          value: studyPrefs.srsDiagnostics,
                                          semanticLabel: kSrsSettingDiagnostics,
                                          onChanged: (_) => studyNotifier.toggleSrsDiagnostics(),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 8),

                          // Settings the design does not cover. They are kept, because
                          // removing them would strand real features; design/docs/03 §12
                          // says to keep anything outside the prototype in the same family
                          // and ask the owner. This group is that open question.
                          DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border(top: BorderSide(color: c.hairline)),
                            ),
                            child: Column(
                              children: [
                                _NavRow(
                                  label: 'Theme & appearance',
                                  help: 'Background wallpaper, AMOLED, board brightness, and hue.',
                                  value: generalPrefs.backgroundColor != null
                                      ? generalPrefs.backgroundColor!.$1.label
                                      : generalPrefs.backgroundImage != null
                                      ? 'Custom image'
                                      : generalPrefs.systemColors
                                      ? 'System'
                                      : (isDark ? 'Dark' : 'Light'),
                                  onTap: () =>
                                      Navigator.of(context).push(ThemeSettingsScreen.buildRoute()),
                                ),
                                _NavRow(
                                  label: 'Board & pieces',
                                  help: 'Board themes, piece sets, and move coordinates.',
                                  value:
                                      '${boardPrefs.boardTheme.label} / ${boardPrefs.pieceSet.label}',
                                  onTap: () =>
                                      Navigator.of(context).push(BoardSettingsScreen.buildRoute()),
                                ),
                                _NavRow(
                                  label: 'Sound & audio details',
                                  help: 'Sound theme and master volume slider.',
                                  value:
                                      '${soundThemeL10n(context, generalPrefs.soundTheme)} (${volumeLabel(generalPrefs.masterVolume)})',
                                  onTap: () =>
                                      Navigator.of(context).push(SoundSettingsScreen.buildRoute()),
                                ),
                                _NavRow(
                                  label: 'Chess engine',
                                  help: 'Threads, hash memory, search time, and multi-PV lines.',
                                  onTap: () =>
                                      Navigator.of(context).push(EngineSettingsScreen.buildRoute()),
                                ),
                                _SettingRow(
                                  label: 'Local database size',
                                  help: 'Storage used by local database files.',
                                  control: Text(
                                    dbSize.hasValue && dbSize.value != null
                                        ? '${(dbSize.value! / (1024 * 1024)).toStringAsFixed(2)} MB'
                                        : '...',
                                    style: TextStyle(
                                      fontFamily: SrsText.ui,
                                      fontSize: 13,
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
