import 'dart:convert';

import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/model/analysis/analysis_controller.dart';
import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chess_srs/src/model/common/id.dart';
import 'package:chess_srs/src/utils/l10n_context.dart';
import 'package:chess_srs/src/utils/navigation.dart';
import 'package:chess_srs/src/view/analysis/analysis_screen.dart';
import 'package:chess_srs/src/view/analysis/pgn_games_list_screen.dart';
import 'package:chess_srs/src/widgets/feedback.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// A provider for picking PGN files. Can be overridden in tests.
final pickPgnFileProvider = Provider<Future<PlatformFile?> Function()>((ref) {
  return () => FilePicker.pickFile(type: .custom, allowedExtensions: ['pgn']);
});

class ImportPgnScreen extends StatelessWidget {
  const ImportPgnScreen({super.key});

  static Route<dynamic> buildRoute() {
    return buildScreenRoute(screen: const ImportPgnScreen());
  }

  static void handlePgnText(BuildContext context, String text) {
    try {
      final games = PgnGame.parseMultiGameLazy(text);

      if (games.isEmpty) {
        showSnackBar(context, context.l10n.invalidPgn, type: .error);
        return;
      }

      if (games.length == 1) {
        final game = games.first;
        final rule = Rule.fromPgn(game.headers['Variant']);

        Navigator.of(context, rootNavigator: true).push(
          AnalysisScreen.buildRoute(
            AnalysisOptions.pgn(
              id: const StringId('pgn_import_single_game'),
              orientation: .white,
              pgn: text,
              isComputerAnalysisAllowed: true,
              initialMoveCursor: 1,
              variant: rule != null ? Variant.fromRule(rule) : .standard,
            ),
          ),
        );
      } else {
        Navigator.of(context, rootNavigator: true).push(PgnGamesListScreen.buildRoute(games.lock));
      }
    } catch (_) {
      showSnackBar(context, context.l10n.invalidPgn, type: .error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.srs.ground,
      body: SafeArea(
        child: Column(
          children: [
            SrsPageHead(
              label: context.l10n.importPgn,
              onBack: () => Navigator.of(context).maybePop(),
            ),
            const Expanded(child: _Body()),
          ],
        ),
      ),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body();

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.max,
        children: [
          // What used to be a 500-line read-only field: an empty box with a paste icon in its
          // corner and no way to type into it. Tapping it pasted the clipboard, which is what
          // the button below does too -- only now it says so.
          Text(
            'Paste a PGN from the clipboard, or pick a file.',
            style: SrsText.body(false, context.srs.ink2),
          ),
          const Spacer(),
          SrsPillButton(expand: true, label: 'Paste from clipboard', onPressed: _getClipboardData),
          const SizedBox(height: 4),
          SrsTextButton(label: context.l10n.mobileOrImportPgnFile, onPressed: _pickPgnFile),
        ],
      ),
    );
  }

  Future<void> _getClipboardData() async {
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text == null) return;
    if (!mounted) return;

    final text = data!.text!.trim();
    if (text.isEmpty) {
      // The old field silently did nothing here, and with no field on screen a tap that
      // produces no visible change reads as a broken button.
      showSnackBar(context, 'The clipboard is empty.');
      return;
    }

    ImportPgnScreen.handlePgnText(context, text);
  }

  Future<void> _pickPgnFile() async {
    try {
      final file = await ref.read(pickPgnFileProvider)();

      if (file != null) {
        final content = await const Utf8Decoder(
          allowMalformed: true,
        ).bind(file.readAsByteStream()).join();
        if (mounted) {
          ImportPgnScreen.handlePgnText(context, content);
        }
      }
    } catch (e) {
      if (mounted) {
        showSnackBar(context, 'Error loading file: $e', type: SnackBarType.error);
      }
    }
  }
}
