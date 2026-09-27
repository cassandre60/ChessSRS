// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/model/log/app_log_paginator.dart';
import 'package:chess_srs/src/model/log/app_log_service.dart';
import 'package:chess_srs/src/model/log/app_log_storage.dart';
import 'package:chess_srs/src/model/settings/log_preferences.dart';
import 'package:chess_srs/src/styles/styles.dart';
import 'package:chess_srs/src/utils/navigation.dart';
import 'package:chess_srs/src/utils/share.dart';
import 'package:chess_srs/src/widgets/adaptive_action_sheet.dart';
import 'package:chess_srs/src/widgets/adaptive_choice_picker.dart';
import 'package:chess_srs/src/widgets/feedback.dart';
import 'package:chess_srs/src/widgets/haptic_refresh_indicator.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

final Logger _logger = Logger('AppLogSettingsScreen');

final _logDateFormatter = DateFormat.yMd().add_Hms();

enum LogCategory {
  all('All', null),
  review('Review', 'Review'),
  repository('Repo / DB', 'StudyRepository'),
  importer('Import', 'StudyImporter'),
  network('Network', 'Http'),
  engine('Engine', 'fish');

  const LogCategory(this.label, this.filterKey);
  final String label;
  final String? filterKey;
}

class AppLogSettingsScreen extends ConsumerStatefulWidget {
  const AppLogSettingsScreen({super.key, this.initialCategory = LogCategory.all});

  final LogCategory initialCategory;

  static Route<dynamic> buildRoute({LogCategory initialCategory = LogCategory.all}) {
    return buildScreenRoute(screen: AppLogSettingsScreen(initialCategory: initialCategory));
  }

  @override
  ConsumerState<AppLogSettingsScreen> createState() => _AppLogSettingsScreenState();
}

class _AppLogSettingsScreenState extends ConsumerState<AppLogSettingsScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  String? _searchQuery;
  late LogCategory _selectedCategory;

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory;
    _scrollController.addListener(_scrollListener);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  String? get _effectiveSearchQuery {
    if (_searchQuery != null && _searchQuery!.isNotEmpty) {
      return _searchQuery;
    }
    return _selectedCategory.filterKey;
  }

  void _scrollListener() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 300) {
      final currentState = ref.read(appLogPaginatorProvider(_effectiveSearchQuery));
      if (currentState.hasValue && !currentState.isLoading && currentState.requireValue.hasMore) {
        ref.read(appLogPaginatorProvider(_effectiveSearchQuery).notifier).next();
      }
    }
  }

  Future<void> _onRefresh() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return await ref.read(appLogPaginatorProvider(_effectiveSearchQuery).notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final currentLevel = ref.watch(logPreferencesProvider.select((prefs) => prefs.level));
    final asyncState = ref.watch(appLogPaginatorProvider(_effectiveSearchQuery));
    final logs = asyncState.value?.logs ?? [];
    final c = context.srs;

    return Scaffold(
      backgroundColor: c.ground,
      body: SafeArea(
        child: Column(
          children: [
            SrsPageHead(
              label: 'App Logs',
              onBack: () => Navigator.of(context).maybePop(),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (logs.isNotEmpty)
                    SrsIconButton(
                      icon: Icons.share,
                      tooltip: 'Export logs',
                      onPressed: () => launchShareDialog(
                        context,
                        ShareParams(text: logs.map(_formatLogEntry).join('\n\n---\n\n')),
                      ),
                    ),
                  if (asyncState.value?.isDeleteButtonVisible == true)
                    SrsIconButton(
                      icon: Icons.delete_sweep,
                      tooltip: 'Delete all logs',
                      onPressed: () {
                        showConfirmDialog<dynamic>(
                          context,
                          title: const Text('Delete all logs'),
                          onConfirm: () {
                            ref.read(appLogServiceProvider).clear();
                            ref
                                .read(appLogPaginatorProvider(_effectiveSearchQuery).notifier)
                                .deleteAll();
                          },
                        );
                      },
                    ),
                ],
              ),
            ),
            SrsSearchField(
              controller: _searchController,
              placeholder: 'Search logs',
              onChanged: (value) => setState(() {
                _searchQuery = value.isEmpty ? null : value;
              }),
              onClear: () => setState(() {
                _searchQuery = null;
                _searchController.clear();
              }),
            ),
            // Wrapping rather than a horizontal ListView: the design forbids horizontal
            // scrolling, and at 11px the whole set fits two lines on a phone anyway.
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 4),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final category in LogCategory.values)
                    SrsPillButton(
                      label: category.label,
                      selected: _selectedCategory == category,
                      onPressed: () => setState(() => _selectedCategory = category),
                    ),
                  SrsPillButton(
                    label: currentLevel.name,
                    onPressed: () => showChoicePicker<Level>(
                      context,
                      choices: kLogPreferencesAvailableLevels,
                      selectedItem: currentLevel,
                      labelBuilder: (Level l) => Text(l.name),
                      onSelectedItemChanged: (Level value) {
                        _logger.fine('Changing log level to ${value.name}');
                        ref.read(logPreferencesProvider.notifier).setLogLevel(value);
                      },
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: switch (asyncState) {
                AsyncData(:final value) when value.logs.isEmpty => _Empty(
                  // The search filtered server-side, so "no logs" and "no logs match" were
                  // the same sentence. The design gives the second its own words.
                  message: _searchQuery == null
                      ? 'No logs to show'
                      : 'Nothing matches \u201c$_searchQuery\u201d.',
                  onRefresh: _onRefresh,
                ),
                AsyncData(:final value) => HapticRefreshIndicator(
                  onRefresh: _onRefresh,
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 32),
                    itemCount: value.logs.length,
                    itemBuilder: (_, index) => _LogTile(entry: value.logs[index]),
                  ),
                ),
                AsyncError(:final error) => Center(
                  child: Padding(
                    padding: Styles.bodySectionPadding,
                    child: Text('Failed to load logs: $error', style: SrsText.body(false, c.ink2)),
                  ),
                ),
                _ => const Center(child: CircularProgressIndicator.adaptive()),
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// The design's empty state: one sentence in `ink2`, and a way out if there is one.
class _Empty extends StatelessWidget {
  const _Empty({required this.message, this.onRefresh});

  final String message;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final c = context.srs;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, style: SrsText.body(false, c.ink2)),
          if (onRefresh != null) ...[
            const SizedBox(height: 12),
            SrsTextButton(label: 'Refresh', onPressed: onRefresh),
          ],
        ],
      ),
    );
  }
}

String _formatLogEntry(AppLogEntry entry) {
  final buffer = StringBuffer(
    '[${_logDateFormatter.format(entry.logTime)}] [${entry.loggerName}] [${entry.levelName}] ${entry.message}',
  );
  final error = entry.error;
  final stackTrace = entry.stackTrace;
  if (error != null) {
    buffer.write('\nError: $error');
  }
  if (stackTrace != null) {
    buffer.write('\nStack trace:\n$stackTrace');
  }
  return buffer.toString();
}

Color _loggerBadgeColor(String loggerName) {
  if (loggerName.contains('Review') || loggerName.contains('Fsrs')) {
    return Colors.blue;
  }
  if (loggerName.contains('Repository') || loggerName.contains('Database')) {
    return Colors.purple;
  }
  if (loggerName.contains('Import')) {
    return Colors.teal;
  }
  if (loggerName.contains('Http') || loggerName.contains('Socket')) {
    return Colors.orange;
  }
  if (loggerName.contains('Engine') ||
      loggerName.contains('Stockfish') ||
      loggerName.contains('Lc0')) {
    return Colors.indigo;
  }
  return Colors.blueGrey;
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.entry});

  final AppLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final c = context.srs;
    final timestamp = _logDateFormatter.format(entry.logTime);

    final isSevere = entry.levelValue >= Level.SEVERE.value;
    final isWarning = entry.levelValue >= Level.WARNING.value;

    final (levelIcon, levelColor) = isSevere
        ? (Icons.error_outline, _severe)
        : isWarning
        ? (Icons.warning_amber_outlined, _warning)
        : (Icons.info_outline, c.ink3);

    final badgeColor = _loggerBadgeColor(entry.loggerName);

    // SrsSettingsRow has no long-press, and copy-on-hold is the fastest way to get an entry
    // out of this screen, so the gesture is kept on a wrapper rather than dropped.
    return GestureDetector(
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: _formatLogEntry(entry)));
        showSnackBar(context, 'Log entry copied to clipboard');
      },
      child: SrsSettingsRow(
        leading: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(levelIcon, size: 20, color: levelColor),
        ),
        label: entry.message,
        // The badge and the message are one line: the badge says which subsystem logged it and
        // the message says what, and separating them costs a row's worth of height per entry.
        labelWidget: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                entry.loggerName,
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: badgeColor),
              ),
            ),
            Expanded(
              child: Text(
                entry.message,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SrsText.rowName(c.ink),
              ),
            ),
          ],
        ),
        help: entry.error,
        value: timestamp,
        onTap: () => _showLogDetails(context, entry),
      ),
    );
  }
}

/// Severity colours. Outside the Diagram palette on purpose: the palette has no warning or
/// error hue, and a log's severity is the one thing on this screen that must not be mistaken
/// for ordinary text. They are also the only red on the screen, so a severe entry is findable
/// by colour alone when scanning.
const _severe = Color(0xFFC0392B);
const _warning = Color(0xFFB26A00);

void _showLogDetails(BuildContext context, AppLogEntry entry) {
  final isSevere = entry.levelValue >= Level.SEVERE.value;
  final isWarning = entry.levelValue >= Level.WARNING.value;
  final levelColor = isSevere
      ? Colors.red
      : isWarning
      ? Colors.orange
      : Colors.blueGrey;

  final badgeColor = _loggerBadgeColor(entry.loggerName);

  showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return SrsDialog(
        titleWidget: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: levelColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                entry.levelName,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: levelColor),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                entry.loggerName,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: badgeColor),
              ),
            ),
          ],
        ),
        // Capped so a long stack trace scrolls inside the card instead of running off it.
        content: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.heightOf(context) * 0.6),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _logDateFormatter.format(entry.logTime),
                  style: TextStyle(color: textShade(context, 0.7), fontSize: 11),
                ),
                const SizedBox(height: 10),
                const Text('Message', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 4),
                SelectableText(entry.message, style: const TextStyle(fontSize: 13)),
                if (entry.error != null) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Error',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.red),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                    ),
                    child: SelectableText(
                      entry.error!,
                      style: const TextStyle(fontSize: 12, color: Colors.red),
                    ),
                  ),
                ],
                if (entry.stackTrace != null) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Stack Trace',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: SelectableText(
                      entry.stackTrace!,
                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          SrsTextButton(
            label: 'Copy message',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: entry.message));
              Navigator.of(dialogContext).pop();
              showSnackBar(context, 'Message copied to clipboard');
            },
          ),
          if (entry.error != null || entry.stackTrace != null)
            SrsTextButton(
              label: 'Copy error',
              onPressed: () {
                final errText = [entry.error, entry.stackTrace].whereType<String>().join('\n');
                Clipboard.setData(ClipboardData(text: errText));
                Navigator.of(dialogContext).pop();
                showSnackBar(context, 'Error copied to clipboard');
              },
            ),
          SrsTextButton(
            label: 'Copy all',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _formatLogEntry(entry)));
              Navigator.of(dialogContext).pop();
              showSnackBar(context, 'Full log entry copied');
            },
          ),
          SrsTextButton(label: 'Close', onPressed: () => Navigator.of(dialogContext).pop()),
        ],
      );
    },
  );
}
