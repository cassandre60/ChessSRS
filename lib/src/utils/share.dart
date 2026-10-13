import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';
import 'package:share_plus/share_plus.dart';

/// See [launchShareDialog]; a share sheet that never opens needs to leave a trace.
final _logger = Logger('Share');

/// Shares the given [uri], [files], or [text].
///
/// Using this function is recommended over calling [SharePlus.instance.share] directly
/// in order to make it work on iPads.
///
/// On platforms without native share sheet support (e.g. Linux desktop), this gracefully
/// copies text or links to the system clipboard instead of failing.
Future<ShareResult> launchShareDialog(BuildContext context, ShareParams params) async {
  try {
    final isTest = !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null && box.hasSize ? box.localToGlobal(Offset.zero) & box.size : null;

    final isDesktop = !kIsWeb && (Platform.isLinux || Platform.isWindows);
    if ((isDesktop || isTest) && (params.files == null || params.files!.isEmpty)) {
      final copyText = params.text ?? params.uri?.toString();
      if (copyText != null && copyText.isNotEmpty) {
        Clipboard.setData(ClipboardData(text: copyText));
        return const ShareResult('Copied to clipboard', ShareResultStatus.success);
      }
    }

    return await SharePlus.instance.share(
      ShareParams(
        uri: params.uri,
        files: params.files,
        text: params.text,
        subject: params.subject,
        fileNameOverrides: params.fileNameOverrides,
        sharePositionOrigin: origin,
      ),
    );
  } catch (e, st) {
    // The share sheet is unavailable, which on Linux desktop is the normal case and not worth
    // alarming anyone about — but the copy is a substitute for what they asked for, and saying
    // "Copied to clipboard" left the impression they had shared it. Callers already surface
    // [ShareResult.raw] in a toast, so the honest text goes there rather than into a second,
    // competing notification.
    _logger.warning('Share unavailable, falling back to the clipboard.', e, st);
    final fallbackText = params.text ?? params.uri?.toString();
    if (fallbackText != null && fallbackText.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: fallbackText));
      return const ShareResult(
        'Sharing unavailable — copied to the clipboard instead',
        ShareResultStatus.success,
      );
    }
    return ShareResult.unavailable;
  }
}
