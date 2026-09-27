// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/constants.dart';
import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/model/log/http_log_paginator.dart';
import 'package:chess_srs/src/model/log/http_log_storage.dart';
import 'package:chess_srs/src/utils/navigation.dart';
import 'package:chess_srs/src/utils/share.dart';
import 'package:chess_srs/src/widgets/adaptive_action_sheet.dart';
import 'package:chess_srs/src/widgets/feedback.dart';
import 'package:chess_srs/src/widgets/haptic_refresh_indicator.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

class HttpLogScreen extends ConsumerStatefulWidget {
  const HttpLogScreen({super.key});

  static Route<dynamic> buildRoute() {
    return buildScreenRoute(screen: const HttpLogScreen());
  }

  @override
  ConsumerState<HttpLogScreen> createState() => _HttpLogScreenState();
}

class _HttpLogScreenState extends ConsumerState<HttpLogScreen> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey = GlobalKey<RefreshIndicatorState>();
  final TextEditingController _searchController = TextEditingController();
  String? _searchQuery;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_scrollListener);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _scrollListener() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 300) {
      final currentState = ref.read(httpLogPaginatorProvider(_searchQuery));
      if (currentState.hasValue && !currentState.isLoading && currentState.requireValue.hasMore) {
        ref.read(httpLogPaginatorProvider(_searchQuery).notifier).next();
      }
    }
  }

  Future<void> _onRefresh() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return await ref.read(httpLogPaginatorProvider(_searchQuery).notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final asyncState = ref.watch(httpLogPaginatorProvider(_searchQuery));
    final logs = asyncState.value?.logs.toList() ?? [];
    final c = context.srs;

    return Scaffold(
      backgroundColor: c.ground,
      body: SafeArea(
        child: Column(
          children: [
            SrsPageHead(
              label: 'HTTP logs',
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
                        ShareParams(text: logs.map(_formatHttpLogEntry).join('\n\n---\n\n')),
                      ),
                    ),
                  if (asyncState.value?.isDeleteButtonVisible == true)
                    SrsIconButton(
                      icon: Icons.delete_sweep,
                      tooltip: 'Clear all logs',
                      onPressed: () {
                        showConfirmDialog<dynamic>(
                          context,
                          title: const Text('Delete all logs'),
                          onConfirm: () =>
                              ref.read(httpLogPaginatorProvider(_searchQuery).notifier).deleteAll(),
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
            Expanded(
              child: _HttpLogList(
                scrollController: _scrollController,
                refreshIndicatorKey: _refreshIndicatorKey,
                logs: logs,
                onRefresh: _onRefresh,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HttpLogList extends ConsumerStatefulWidget {
  const _HttpLogList({
    required this.logs,
    required this.onRefresh,
    required this.scrollController,
    required this.refreshIndicatorKey,
  });

  final List<HttpLogEntry> logs;
  final ScrollController scrollController;
  final GlobalKey<RefreshIndicatorState> refreshIndicatorKey;
  final RefreshCallback onRefresh;

  @override
  ConsumerState<_HttpLogList> createState() => _HttpLogListState();
}

class _HttpLogListState extends ConsumerState<_HttpLogList> {
  @override
  Widget build(BuildContext context) {
    if (widget.logs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('No logs to show'),
            TextButton(onPressed: widget.onRefresh, child: const Text('Tap to refresh')),
          ],
        ),
      );
    }
    return HapticRefreshIndicator(
      key: widget.refreshIndicatorKey,
      onRefresh: widget.onRefresh,
      child: ListView.separated(
        controller: widget.scrollController,
        itemCount: widget.logs.length,
        separatorBuilder: (_, _) => const Divider(height: 1, thickness: 0),
        itemBuilder: (_, index) {
          if (index < 0 || index >= widget.logs.length) {
            return null;
          }

          return HttpLogTile(httpLog: widget.logs[index]);
        },
      ),
    );
  }
}

final _logDateFormatter = DateFormat.yMd().add_Hms();

String _formatElapsed(Duration elapsed) {
  if (elapsed.inMilliseconds < 1000) {
    return '${elapsed.inMilliseconds}ms';
  }
  return '${(elapsed.inMilliseconds / 1000).toStringAsFixed(1)}s';
}

String _formatHttpLogEntry(HttpLogEntry entry) {
  final buffer = StringBuffer(
    '[${_logDateFormatter.format(entry.requestDateTime)}] ${entry.requestMethod} ${entry.requestUrl}\n'
    'Status: ${entry.responseCode ?? "No response"} | Duration: ${entry.elapsed != null ? _formatElapsed(entry.elapsed!) : "N/A"}',
  );
  if (entry.errorMessage != null) {
    buffer.write('\nError: ${entry.errorMessage}');
  }
  return buffer.toString();
}

class HttpLogTile extends StatelessWidget {
  const HttpLogTile({super.key, required this.httpLog});

  final HttpLogEntry httpLog;

  String get endpoint =>
      (httpLog.requestUrl.host == kLichessHost || httpLog.requestUrl.host == 'lichess.org')
      ? Uri(path: httpLog.requestUrl.path, query: httpLog.requestUrl.query).toString()
      : httpLog.requestUrl.toString();

  @override
  Widget build(BuildContext context) {
    final isError =
        httpLog.errorMessage != null ||
        (httpLog.responseCode != null && httpLog.responseCode! >= 400);

    final c = context.srs;
    final errorColor = isError ? _severe : c.ink;

    // SrsSettingsRow has no long-press, and copy-URL-on-hold is the fastest way to get an
    // endpoint out of this screen, so the gesture is kept on a wrapper rather than dropped.
    return GestureDetector(
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: httpLog.requestUrl.toString()));
        showSnackBar(context, 'URL copied to clipboard');
      },
      child: SrsSettingsRow(
        leading: SizedBox(
          width: 44,
          child: httpLog.hasResponse
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      httpLog.responseCode!.toString(),
                      style: SrsText.rowName(
                        errorColor,
                      ).copyWith(fontFeatures: SrsText.tabular, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    if (httpLog.elapsed != null)
                      Text(
                        _formatElapsed(httpLog.elapsed!),
                        maxLines: 1,
                        style: SrsText.rowSub(
                          c.ink3,
                        ).copyWith(fontFeatures: SrsText.tabular, fontSize: 10),
                      ),
                  ],
                )
              : Icon(
                  isError ? Icons.error_outline : Icons.pending_outlined,
                  color: isError ? _severe : c.ink3,
                ),
        ),
        label: endpoint,
        // The method badge and the endpoint are one line, as in the app log: they are one fact.
        labelWidget: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: isError ? _severe.withValues(alpha: 0.15) : c.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                httpLog.requestMethod,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isError ? _severe : c.accent,
                ),
              ),
            ),
            Expanded(
              child: Text(
                endpoint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SrsText.rowName(errorColor),
              ),
            ),
          ],
        ),
        help: httpLog.errorMessage,
        value: _logDateFormatter.format(httpLog.requestDateTime),
        onTap: () => _showHttpLogDetails(context, httpLog),
      ),
    );
  }
}

/// Severity colours, outside the Diagram palette on purpose: a 4xx or 5xx is the one thing on
/// this screen that must not be mistaken for ordinary text.
const _severe = Color(0xFFC0392B);

void _showHttpLogDetails(BuildContext context, HttpLogEntry httpLog) {
  final statusText = httpLog.responseCode != null && httpLog.responseCode != 0
      ? '${httpLog.responseCode}'
      : (httpLog.errorMessage != null ? 'Failed' : 'Pending');
  final isError =
      httpLog.errorMessage != null ||
      (httpLog.responseCode != null && httpLog.responseCode! >= 400);

  showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return SrsDialog(
        titleWidget: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isError
                    ? Colors.red.withValues(alpha: 0.15)
                    : Colors.green.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                httpLog.requestMethod,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: isError ? Colors.red : Colors.green,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              statusText,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isError ? Colors.red : null,
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.heightOf(context) * 0.6),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Request URL',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                const SizedBox(height: 4),
                SelectableText(httpLog.requestUrl.toString(), style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 12),
                if (httpLog.elapsed != null) ...[
                  Row(
                    children: [
                      const Text(
                        'Duration: ',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                      Text(_formatElapsed(httpLog.elapsed!), style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                Row(
                  children: [
                    const Text(
                      'Time: ',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    Text(
                      _logDateFormatter.format(httpLog.requestDateTime),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
                if (httpLog.errorMessage != null) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Error Details',
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
                      httpLog.errorMessage!,
                      style: const TextStyle(fontSize: 12, color: Colors.red),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          SrsTextButton(
            label: 'Copy URL',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: httpLog.requestUrl.toString()));
              Navigator.of(dialogContext).pop();
              showSnackBar(context, 'URL copied to clipboard');
            },
          ),
          SrsTextButton(
            label: 'Copy all',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _formatHttpLogEntry(httpLog)));
              Navigator.of(dialogContext).pop();
              showSnackBar(context, 'Details copied to clipboard');
            },
          ),
          SrsTextButton(label: 'Close', onPressed: () => Navigator.of(dialogContext).pop()),
        ],
      );
    },
  );
}
