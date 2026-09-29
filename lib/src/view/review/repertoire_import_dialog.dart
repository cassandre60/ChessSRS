// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io' as io;
import 'dart:math' as math;

import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/import/lichess_study_importer.dart';
import 'package:chess_srs/src/model/auth/auth_controller.dart';
import 'package:chess_srs/src/review/review_controller.dart';
import 'package:chess_srs/src/view/auth/sign_in_error.dart';
import 'package:chess_srs/src/view/auth/sign_in_options.dart';
import 'package:chess_srs/src/view/more/import_pgn_screen.dart';
import 'package:chess_srs/src/widgets/feedback.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

enum ImportSource { lichess, file }

/// Bottom sheet dialog for importing a repertoire PGN or Lichess study.
class RepertoireImportDialog extends ConsumerStatefulWidget {
  const RepertoireImportDialog({
    super.key,
    this.initialSource = ImportSource.lichess,
    this.initialSide,
  });

  final ImportSource initialSource;
  final Side? initialSide;

  static Future<void> show(
    BuildContext context, {
    ImportSource initialSource = ImportSource.lichess,
    Side? initialSide,
  }) {
    final c = context.srs;
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: c.scrim,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, animation, secondaryAnimation) =>
          RepertoireImportDialog(initialSource: initialSource, initialSide: initialSide),
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
  ConsumerState<RepertoireImportDialog> createState() => _RepertoireImportDialogState();
}

class _RepertoireImportDialogState extends ConsumerState<RepertoireImportDialog> {
  late ImportSource _importSource;
  late Side? _repertoireSide;
  final _lichessUrlController = TextEditingController();
  final _pgnController = TextEditingController();
  final _titleController = TextEditingController();
  final _scrollController = ScrollController();
  bool _isImporting = false;

  /// Lichess 404'd a study id while signed out, so the study may be private rather than missing.
  ///
  /// Drives the inline sign-in prompt instead of an error toast. Reset as soon as the import is
  /// retried, because a successful retry means the guess was right and there is nothing to explain.
  bool _studyMayBePrivate = false;

  @override
  void initState() {
    super.initState();
    _importSource = widget.initialSource;
    _repertoireSide = widget.initialSide;
  }

  @override
  void dispose() {
    _lichessUrlController.dispose();
    _pgnController.dispose();
    _titleController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _pickPgnFile() async {
    final picker = ref.read(pickPgnFileProvider);
    final file = await picker();
    if (file != null && file.path != null) {
      final content = await io.File(file.path!).readAsString();
      setState(() {
        _pgnController.text = content;
        if (_titleController.text.isEmpty) {
          _titleController.text = file.name.replaceAll(RegExp(r'\.pgn$', caseSensitive: false), '');
        }
      });
    }
  }

  Future<void> _handleLichessImport() async {
    final input = _lichessUrlController.text.trim();
    if (input.isEmpty) {
      showSnackBar(
        context,
        'Please enter a Lichess study URL or study ID',
        type: SnackBarType.error,
      );
      return;
    }

    final studyId = extractLichessStudyId(input);
    if (studyId == null) {
      showSnackBar(
        context,
        'Invalid Lichess study URL or ID. Example: https://lichess.org/study/xxxxxx',
        type: SnackBarType.error,
      );
      return;
    }

    setState(() {
      _isImporting = true;
      // Retrying supersedes the explanation: if it works this time, the study was private and
      // the prompt has nothing left to say.
      _studyMayBePrivate = false;
    });
    try {
      final customTitle = _titleController.text.trim();
      final result = await ref
          .read(reviewControllerProvider.notifier)
          .importLichessStudy(
            studyIdOrUrl: input,
            title: customTitle.isNotEmpty ? customTitle : null,
            repertoireSide: _repertoireSide,
          );

      if (mounted) {
        Navigator.of(context).pop();
        if (result.isDuplicate) {
          showSnackBar(
            context,
            'Repertoire "${result.study.title}" is already imported and up to date',
            type: SnackBarType.info,
          );
        } else {
          showSnackBar(
            context,
            'Imported "${result.study.title}" (${result.decisions.length} recall positions across ${result.chapters.length} chapters)',
            type: SnackBarType.success,
          );
        }
      }
    } on StudyNotFoundException catch (e) {
      // Before FormatException: this is a subclass, and the specific case is the one that
      // deserves different handling.
      if (!mounted) return;
      if (ref.read(isLoggedInProvider)) {
        // Signed in and still a 404, so it genuinely is not there. The toast's advice holds.
        showSnackBar(context, e.message, type: SnackBarType.error);
      } else {
        // Signed out, 404 cannot distinguish private from non-existent. Offering sign-in and a
        // retry costs nothing if the study really is missing, whereas the toast's "ensure it is
        // public or unlisted" tells the user to check something that was never the problem.
        setState(() => _studyMayBePrivate = true);
        // The user pressed Fetch at the bottom of a scrolled form, and the notice explaining
        // what happened sits at the top. Without this the explanation and its action open
        // above the viewport, so a failure with a known cause and a known fix looks like a
        // failure with neither. Only the vertical axis: the body is already scrolled to the
        // left, and an animated jump on a short surface would read as a glitch.
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      }
    } on FormatException catch (e) {
      if (mounted) {
        showSnackBar(context, e.message, type: SnackBarType.error);
      }
    } catch (e) {
      if (mounted) {
        showSnackBar(context, 'Lichess import failed: $e', type: SnackBarType.error);
      }
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  Future<void> _handleFileImport() async {
    final pgn = _pgnController.text.trim();
    if (pgn.isEmpty) {
      showSnackBar(context, 'Please enter or select PGN content', type: SnackBarType.error);
      return;
    }

    // Auto-detect Lichess URL entered in PGN text area
    final lichessStudyId = extractLichessStudyId(pgn);
    if (lichessStudyId != null && !pgn.contains('1.')) {
      _lichessUrlController.text = pgn;
      await _handleLichessImport();
      return;
    }

    setState(() => _isImporting = true);
    try {
      final title = _titleController.text.trim().isNotEmpty
          ? _titleController.text.trim()
          : 'Imported Repertoire';

      final result = await ref
          .read(reviewControllerProvider.notifier)
          .importPgnText(pgnText: pgn, title: title, repertoireSide: _repertoireSide);

      if (mounted) {
        Navigator.of(context).pop();
        if (result.isDuplicate) {
          showSnackBar(
            context,
            'Repertoire "${result.study.title}" is already imported and up to date',
            type: SnackBarType.info,
          );
        } else {
          showSnackBar(
            context,
            'Imported "${result.study.title}" (${result.decisions.length} recall positions)',
            type: SnackBarType.success,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        showSnackBar(context, 'Import failed: $e', type: SnackBarType.error);
      }
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.srs;
    final mediaQuery = MediaQuery.of(context);
    final isWide = mediaQuery.size.width >= 768;
    final bottomInset = mediaQuery.viewInsets.bottom;
    final maxWidth = isWide ? math.min(520.0, mediaQuery.size.width - 48.0) : double.infinity;
    final isSignedIn = ref.watch(isLoggedInProvider);

    // `showSignInOptions` fires the browser flow with `.ignore()`, so nothing reports a failure
    // unless the caller listens for it. Without this a refused or cancelled sign-in is silent.
    ref.listen(signInMutation, (_, next) => showSignInErrorSnackBar(context, next));

    // Signing in is the answer to "this study is private", so resume the import the user was
    // already doing rather than making them retype the URL and press the button again.
    ref.listen(isLoggedInProvider, (previous, next) {
      if (!(previous ?? false) && next && _studyMayBePrivate && mounted) {
        _handleLichessImport();
      }
    });

    final content = Align(
      alignment: isWide ? Alignment.center : Alignment.bottomCenter,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: Container(
          width: maxWidth,
          constraints: BoxConstraints(maxHeight: mediaQuery.size.height * 0.88),
          margin: isWide ? const EdgeInsets.all(24) : const EdgeInsets.fromLTRB(8, 0, 8, 8),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(isWide ? 20 : 22),
            border: Border.all(color: c.hairline, width: 1),
            boxShadow: [BoxShadow(color: c.scrim, blurRadius: 28, offset: const Offset(0, 8))],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(isWide ? 20 : 22),
            child: Material(
              color: c.surface,
              child: SafeArea(
                top: false,
                bottom: !isWide,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: EdgeInsets.only(
                    left: 20.0,
                    right: 20.0,
                    top: 16.0,
                    bottom: bottomInset + 20.0,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!isWide) ...[
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
                        const SizedBox(height: 12),
                      ],
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Import Repertoire', style: SrsText.titleSmall(c.ink)),
                          IconButton(
                            icon: Icon(Symbols.close_rounded, color: c.ink2),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                      // Pinned above the scroll view, not below the form. The dialog's body is
                      // taller than a landscape phone, so anything placed after the fields
                      // starts below the fold exactly when it matters: the explanation of a
                      // failed import, and the way to recover from it, were both invisible on
                      // an 844x390 surface without the user scrolling to find them.
                      if (_studyMayBePrivate) ...[
                        _PrivateStudyNotice(onSignIn: () => showSignInOptions(context, ref)),
                        const SizedBox(height: 14.0),
                      ],
                      const SizedBox(height: 14.0),
                      SrsSegmented<ImportSource>(
                        options: const {
                          ImportSource.lichess: 'Lichess Study',
                          ImportSource.file: 'PGN Text / File',
                        },
                        value: _importSource,
                        onChanged: (source) => setState(() => _importSource = source),
                      ),
                      const SizedBox(height: 16.0),
                      if (_importSource == ImportSource.lichess) ...[
                        TextField(
                          controller: _lichessUrlController,
                          decoration: InputDecoration(
                            labelText: 'Lichess Study URL or ID',
                            hintText: 'https://lichess.org/study/... or 8-char ID',
                            prefixIcon: Icon(Symbols.link_rounded, color: c.ink2),
                            suffixIcon: IconButton(
                              icon: Icon(Symbols.content_paste_rounded, color: c.ink2),
                              tooltip: 'Paste from clipboard',
                              onPressed: () async {
                                final data = await Clipboard.getData(Clipboard.kTextPlain);
                                if (data?.text != null && mounted) {
                                  setState(() => _lichessUrlController.text = data!.text!.trim());
                                }
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 14.0),
                        Row(
                          children: [
                            Text(
                              'Train as:',
                              style: TextStyle(
                                fontFamily: SrsText.ui,
                                fontWeight: FontWeight.w500,
                                color: c.ink,
                              ),
                            ),
                            const Spacer(),
                            SrsSegmented<Side?>(
                              options: const {
                                null: 'Auto',
                                Side.white: 'White',
                                Side.black: 'Black',
                              },
                              value: _repertoireSide,
                              onChanged: (side) => setState(() => _repertoireSide = side),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14.0),
                        TextField(
                          controller: _titleController,
                          decoration: const InputDecoration(
                            labelText: 'Study Title (optional)',
                            hintText: 'Derived from Lichess if left blank',
                          ),
                        ),
                        const SizedBox(height: 18.0),
                        SizedBox(
                          height: 46,
                          child: FilledButton.icon(
                            icon: _isImporting
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: c.ground,
                                    ),
                                  )
                                : const Icon(Symbols.download_rounded),
                            label: Text(
                              _isImporting
                                  ? 'Fetching from Lichess...'
                                  : 'Fetch & Import from Lichess',
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
                            ),
                            onPressed: _isImporting ? null : _handleLichessImport,
                          ),
                        ),
                        if (!isSignedIn && !_studyMayBePrivate) ...[
                          const SizedBox(height: 10.0),
                          _SignInHint(onSignIn: () => showSignInOptions(context, ref)),
                        ],
                      ] else ...[
                        TextField(
                          controller: _titleController,
                          decoration: const InputDecoration(
                            labelText: 'Study Title (optional)',
                            hintText: 'e.g. French Defense / 1.d4 Repertoire',
                          ),
                        ),
                        const SizedBox(height: 14.0),
                        Row(
                          children: [
                            Text(
                              'Train as:',
                              style: TextStyle(
                                fontFamily: SrsText.ui,
                                fontWeight: FontWeight.w500,
                                color: c.ink,
                              ),
                            ),
                            const Spacer(),
                            SrsSegmented<Side?>(
                              options: const {
                                null: 'Auto',
                                Side.white: 'White',
                                Side.black: 'Black',
                              },
                              value: _repertoireSide,
                              onChanged: (side) => setState(() => _repertoireSide = side),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14.0),
                        TextField(
                          controller: _pgnController,
                          maxLines: 6,
                          decoration: const InputDecoration(
                            labelText: 'PGN text',
                            hintText: 'Paste PGN moves here...',
                            alignLabelWithHint: true,
                          ),
                        ),
                        const SizedBox(height: 14.0),
                        OutlinedButton.icon(
                          icon: const Icon(Symbols.upload_file_rounded),
                          label: const Text('Pick .pgn file from disk'),
                          onPressed: _isImporting ? null : _pickPgnFile,
                        ),
                        const SizedBox(height: 16.0),
                        SizedBox(
                          height: 46,
                          child: FilledButton.icon(
                            icon: _isImporting
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: c.ground,
                                    ),
                                  )
                                : const Icon(Symbols.download_done_rounded),
                            label: Text(
                              _isImporting ? 'Importing...' : 'Import and Start Review',
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
                            ),
                            onPressed: _isImporting ? null : _handleFileImport,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
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
        SrsSheetDismissible(child: content),
      ],
    );
  }
}

/// Sign-in affordance for the Lichess tab, shown only while signed out.
///
/// Kept this quiet on purpose. A Lichess bearer token is needed for private and unlisted
/// studies and for nothing else the import flow does, so a filled call-to-action here would
/// press an account requirement onto every user fetching a public study, most of whom have no
/// reason to want one. One low-ink line, below the form, where it costs nothing to ignore.
///
/// A failed import does not use this — it uses [_PrivateStudyNotice].
class _SignInHint extends StatelessWidget {
  const _SignInHint({required this.onSignIn});

  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: SrsTextButton(label: 'Importing a private study? Sign in', onPressed: onSignIn),
    );
  }
}

/// Explains a signed-out 404 and offers to resolve it.
///
/// Deliberately separate from [_SignInHint], because it is a different kind of thing: that one
/// is an aside about a case the user has not hit yet, this one is the response to a failure
/// they just saw. It sits above the form rather than below it — the dialog's body is taller
/// than a landscape phone, so a notice placed after the fields starts below the fold in
/// exactly the state where the user needs it. It also does not claim to know why the study
/// was not returned, because an anonymous request genuinely cannot tell.
class _PrivateStudyNotice extends StatelessWidget {
  const _PrivateStudyNotice({required this.onSignIn});

  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final c = context.srs;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      decoration: BoxDecoration(color: c.hairlineSoft, borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Lichess answers the same for a private study as for one that does not exist. '
            'Sign in to tell the two apart.',
            style: SrsText.rowSub(c.ink2),
          ),
          const SizedBox(height: 2),
          SrsTextButton(label: 'Sign in and retry', onPressed: onSignIn),
        ],
      ),
    );
  }
}
