// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:chess_srs/src/styles/styles.dart';
import 'package:chess_srs/src/utils/share.dart';
import 'package:chess_srs/src/widgets/feedback.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

/// Modal dialog displaying generated PGN text with options to copy, save to file, or share.
class ExportPgnDialog extends StatelessWidget {
  const ExportPgnDialog({required this.title, required this.pgnText, this.subtitle, super.key});

  final String title;
  final String pgnText;
  final String? subtitle;

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String pgnText,
    String? subtitle,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => ExportPgnDialog(title: title, pgnText: pgnText, subtitle: subtitle),
    );
  }

  String get _safeFileName {
    final safe = title.replaceAll(RegExp(r'[^\w\s-]'), '').trim();
    return safe.isNotEmpty ? '$safe.pgn' : 'study.pgn';
  }

  Future<void> _saveToFile(BuildContext context) async {
    try {
      final fileName = _safeFileName;
      final bytes = Uint8List.fromList(utf8.encode(pgnText));

      final result = await FilePicker.saveFile(
        dialogTitle: 'Save PGN File',
        fileName: fileName,
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: ['pgn'],
      );

      if (result != null && context.mounted) {
        Navigator.of(context).pop();
        showSnackBar(context, 'Saved $fileName');
      }
    } catch (e) {
      if (context.mounted) {
        showSnackBar(context, 'Could not save file: $e', type: SnackBarType.error);
      }
    }
  }

  Future<void> _share(BuildContext context) async {
    try {
      final fileName = _safeFileName;
      final result = await launchShareDialog(
        context,
        ShareParams(text: pgnText, subject: fileName),
      );
      if (context.mounted) {
        Navigator.of(context).pop();
        if (result.status == ShareResultStatus.success) {
          showSnackBar(context, result.raw.isNotEmpty ? result.raw : 'Shared successfully');
        }
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
        showSnackBar(context, 'Sharing failed: $e', type: SnackBarType.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile =
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Symbols.description_rounded, color: Theme.of(context).colorScheme.primary, size: 24),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Export PGN',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: textShade(context, Styles.subtitleOpacity),
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: 11,
                    color: textShade(context, 0.7),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
            Container(
              constraints: const BoxConstraints(maxHeight: 280),
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  pgnText,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.4),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          icon: const Icon(Symbols.content_copy_rounded, size: 18),
          label: const Text('Copy'),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: pgnText));
            try {
              showSnackBar(context, 'PGN copied to clipboard');
            } catch (_) {}
            Navigator.of(context).pop();
          },
        ),
        FilledButton.tonalIcon(
          icon: const Icon(Symbols.save_alt_rounded, size: 18),
          label: const Text('Save File'),
          onPressed: () => _saveToFile(context),
        ),
        if (isMobile)
          FilledButton.icon(
            icon: const Icon(Symbols.share_rounded, size: 18),
            label: const Text('Share'),
            onPressed: () => _share(context),
          )
        else
          TextButton.icon(
            icon: const Icon(Symbols.share_rounded, size: 18),
            label: const Text('Share'),
            onPressed: () => _share(context),
          ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
      ],
    );
  }
}
