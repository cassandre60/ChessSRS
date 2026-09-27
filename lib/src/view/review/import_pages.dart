// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/import/lichess_study_importer.dart';
import 'package:chess_srs/src/review/review_controller.dart';
import 'package:chess_srs/src/utils/navigation.dart';
import 'package:chess_srs/src/widgets/feedback.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart'
    show AppBar, InputDecoration, Scaffold, TextField, UnderlineInputBorder;

/// Dedicated Paste PGN page (matches `paste` in `chesssrs-design-demo.html`).
///
/// Diagram `.pg` layout: large title, lede, underline PGN field,
/// Train-as segmented control, and Import / Cancel actions.
class PastePgnPage extends ConsumerStatefulWidget {
  const PastePgnPage({this.initialSide, this.initialText, this.suggestedTitle, super.key});

  final Side? initialSide;

  /// Prefills the PGN field (e.g. from a picked `.pgn` file).
  final String? initialText;

  /// Used as the study title on import when non-empty (e.g. file name).
  final String? suggestedTitle;

  static Route<dynamic> buildRoute({
    Side? initialSide,
    String? initialText,
    String? suggestedTitle,
  }) {
    return buildScreenRoute(
      screen: PastePgnPage(
        initialSide: initialSide,
        initialText: initialText,
        suggestedTitle: suggestedTitle,
      ),
    );
  }

  @override
  ConsumerState<PastePgnPage> createState() => _PastePgnPageState();
}

class _PastePgnPageState extends ConsumerState<PastePgnPage> {
  late final TextEditingController _pgnController;
  Side? _side;
  String? _error;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _pgnController = TextEditingController(text: widget.initialText);
    _side = widget.initialSide;
  }

  @override
  void dispose() {
    _pgnController.dispose();
    super.dispose();
  }

  Future<void> _handleImport() async {
    final text = _pgnController.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Paste a PGN first.');
      return;
    }
    // A Lichess link pasted here routes to the Lichess flow (as the old
    // import dialog did via auto-detection).
    final lichessStudyId = extractLichessStudyId(text);
    if (lichessStudyId != null && !RegExp(r'\d+\s*\.').hasMatch(text)) {
      if (!mounted) return;
      Navigator.of(
        context,
      ).push(LichessImportPage.buildRoute(initialSide: _side, initialUrl: text));
      return;
    }
    if (!RegExp(r'\d+\s*\.').hasMatch(text)) {
      if (!mounted) return;
      Navigator.of(context).push(
        ImportErrorPage.buildRoute(
          message: 'No moves were found in that text. Check that it is PGN and try again.',
        ),
      );
      return;
    }
    setState(() {
      _error = null;
      _importing = true;
    });
    try {
      final container = ProviderScope.containerOf(context);
      final suggestedTitle = widget.suggestedTitle?.trim();
      final result = await container
          .read(reviewControllerProvider.notifier)
          .importPgnText(
            pgnText: text,
            title: suggestedTitle != null && suggestedTitle.isNotEmpty ? suggestedTitle : null,
            repertoireSide: _side,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      if (result.errors.isNotEmpty) {
        // Moves were dropped. A plain success here is how a repertoire silently loses lines.
        showSnackBar(
          context,
          'Imported ${result.decisions.length} positions, but ${result.errors.length} '
          'problem${result.errors.length == 1 ? '' : 's'} meant some moves were skipped.',
          type: SnackBarType.error,
        );
      } else {
        showSnackBar(
          context,
          result.isDuplicate
              ? 'Repertoire "${result.study.title}" is already imported and up to date'
              : 'Imported ${result.decisions.length} positions from pasted text.',
          type: result.isDuplicate ? SnackBarType.info : SnackBarType.success,
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).push(ImportErrorPage.buildRoute(message: 'Import failed: $e'));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.srs;
    return Scaffold(
      backgroundColor: c.ground,
      appBar: AppBar(backgroundColor: c.surface, foregroundColor: c.ink, elevation: 0),
      body: SingleChildScrollView(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 660),
            padding: const EdgeInsets.fromLTRB(24, 6, 24, 56),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Paste PGN text', style: SrsText.display(40, c.ink)),
                const SizedBox(height: 14),
                Text(
                  'Paste one game or a whole study in PGN format.',
                  style: TextStyle(fontFamily: SrsText.ui, fontSize: 16, color: c.ink2),
                ),
                const SizedBox(height: 26),
                TextField(
                  controller: _pgnController,
                  maxLines: 8,
                  style: TextStyle(fontFamily: SrsText.ui, fontSize: 14.5, color: c.ink),
                  decoration: InputDecoration(
                    hintText: '1. e4 d5 2. exd5 Qxd5 3. Nc3 Qa5',
                    hintStyle: TextStyle(fontFamily: SrsText.ui, color: c.ink3),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: c.hairline)),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: c.accent, width: 1.5),
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: TextStyle(
                      fontFamily: SrsText.ui,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: c.ink2,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    Text('Train as', style: SrsText.settingLabel(c.ink)),
                    const Spacer(),
                    SrsSegmented<Side?>(
                      options: const {null: 'Auto', Side.white: 'White', Side.black: 'Black'},
                      value: _side,
                      onChanged: (side) => setState(() => _side = side),
                    ),
                  ],
                ),
                const SizedBox(height: 26),
                Row(
                  children: [
                    SrsPillButton(
                      label: _importing ? 'Importing...' : 'Import',
                      onPressed: _importing ? null : _handleImport,
                    ),
                    const SizedBox(width: 18),
                    SrsTextButton(label: 'Cancel', onPressed: () => Navigator.of(context).pop()),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dedicated Lichess study import page (matches `lichess` in `chesssrs-design-demo.html`).
class LichessImportPage extends ConsumerStatefulWidget {
  const LichessImportPage({this.initialSide, this.initialUrl, super.key});

  final Side? initialSide;

  /// Prefills the study-link field.
  final String? initialUrl;

  static Route<dynamic> buildRoute({Side? initialSide, String? initialUrl}) {
    return buildScreenRoute(
      screen: LichessImportPage(initialSide: initialSide, initialUrl: initialUrl),
    );
  }

  @override
  ConsumerState<LichessImportPage> createState() => _LichessImportPageState();
}

class _LichessImportPageState extends ConsumerState<LichessImportPage> {
  late final TextEditingController _urlController;
  Side? _side;
  String? _error;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.initialUrl);
    _side = widget.initialSide;
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _handleImport() async {
    final input = _urlController.text.trim();
    if (!RegExp(r'lichess\.org/study/\w+').hasMatch(input) &&
        extractLichessStudyId(input) == null) {
      setState(() => _error = 'That link is not a Lichess study.');
      return;
    }
    setState(() {
      _error = null;
      _importing = true;
    });
    try {
      final container = ProviderScope.containerOf(context);
      final result = await container
          .read(reviewControllerProvider.notifier)
          .importLichessStudy(studyIdOrUrl: input, repertoireSide: _side);
      if (!mounted) return;
      Navigator.of(context).pop();
      showSnackBar(
        context,
        result.isDuplicate
            ? 'Repertoire "${result.study.title}" is already imported and up to date'
            : 'Imported "${result.study.title}" (${result.decisions.length} recall positions across ${result.chapters.length} chapters)',
        type: result.isDuplicate ? SnackBarType.info : SnackBarType.success,
      );
    } on FormatException catch (e) {
      if (!mounted) return;
      Navigator.of(context).push(ImportErrorPage.buildRoute(message: e.message));
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).push(ImportErrorPage.buildRoute(message: 'Import failed: $e'));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.srs;
    return Scaffold(
      backgroundColor: c.ground,
      appBar: AppBar(backgroundColor: c.surface, foregroundColor: c.ink, elevation: 0),
      body: SingleChildScrollView(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 660),
            padding: const EdgeInsets.fromLTRB(24, 6, 24, 56),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Import a Lichess study', style: SrsText.display(40, c.ink)),
                const SizedBox(height: 14),
                Text(
                  'Paste the link to the study. Its chapters are imported as one repertoire.',
                  style: TextStyle(fontFamily: SrsText.ui, fontSize: 16, color: c.ink2),
                ),
                const SizedBox(height: 26),
                TextField(
                  controller: _urlController,
                  style: TextStyle(fontFamily: SrsText.ui, fontSize: 16, color: c.ink),
                  decoration: InputDecoration(
                    hintText: 'lichess.org/study/…',
                    hintStyle: TextStyle(fontFamily: SrsText.ui, color: c.ink3),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: c.hairline)),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: c.accent, width: 1.5),
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: TextStyle(
                      fontFamily: SrsText.ui,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: c.ink2,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    Text('Train as', style: SrsText.settingLabel(c.ink)),
                    const Spacer(),
                    SrsSegmented<Side?>(
                      options: const {null: 'Auto', Side.white: 'White', Side.black: 'Black'},
                      value: _side,
                      onChanged: (side) => setState(() => _side = side),
                    ),
                  ],
                ),
                const SizedBox(height: 26),
                Row(
                  children: [
                    SrsPillButton(
                      label: _importing ? 'Importing...' : 'Import study',
                      onPressed: _importing ? null : _handleImport,
                    ),
                    const SizedBox(width: 18),
                    SrsTextButton(label: 'Cancel', onPressed: () => Navigator.of(context).pop()),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dedicated import error page (matches `error` in `chesssrs-design-demo.html`).
class ImportErrorPage extends StatelessWidget {
  const ImportErrorPage({this.message, this.details, super.key});

  final String? message;
  final String? details;

  static Route<dynamic> buildRoute({String? message, String? details}) {
    return buildScreenRoute(
      screen: ImportErrorPage(message: message, details: details),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.srs;
    return Scaffold(
      backgroundColor: c.ground,
      appBar: AppBar(backgroundColor: c.surface, foregroundColor: c.ink, elevation: 0),
      body: SingleChildScrollView(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 660),
            padding: const EdgeInsets.fromLTRB(24, 56, 24, 56),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Something went wrong.', style: SrsText.title(c.ink)),
                const SizedBox(height: 12),
                Text(
                  message ?? 'The file could not be read. Nothing was imported.',
                  style: TextStyle(fontFamily: SrsText.ui, fontSize: 16, color: c.ink2),
                ),
                const SizedBox(height: 26),
                Row(
                  children: [
                    SrsPillButton(label: 'Try again', onPressed: () => Navigator.of(context).pop()),
                    const SizedBox(width: 18),
                    SrsTextButton(
                      label: 'Copy details',
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: details ?? 'import: no moves found'),
                        );
                        if (context.mounted) {
                          showSnackBar(context, 'Details copied.');
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
