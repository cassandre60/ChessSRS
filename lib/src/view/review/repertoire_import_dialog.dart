// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io' as io;
import 'dart:math' as math;

import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/import/lichess_study_importer.dart';
import 'package:chess_srs/src/import/pgn_importer.dart' show ImportError, kMaxPgnInputBytes;
import 'package:chess_srs/src/model/auth/auth_controller.dart';
import 'package:chess_srs/src/review/review_controller.dart';
import 'package:chess_srs/src/utils/l10n_context.dart';
import 'package:chess_srs/src/view/auth/sign_in_error.dart';
import 'package:chess_srs/src/view/auth/sign_in_options.dart';
import 'package:chess_srs/src/view/more/import_pgn_screen.dart';
import 'package:chess_srs/src/widgets/feedback.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

final _logger = Logger('RepertoireImportDialog');

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
      barrierLabel: context.l10n.mobileReviewDismissBarrier,
      barrierColor: c.scrim,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, animation, secondaryAnimation) =>
          RepertoireImportDialog(initialSource: initialSource, initialSide: initialSide),
      transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
        // DESIGN 02 §3: wide if width >= 720, via the shared token rather than a literal.
        final isWide = SrsLayout.isWide(MediaQuery.sizeOf(dialogContext).width);
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
  bool _isBulkImporting = false;
  int _bulkDone = 0;
  int _bulkTotal = 0;
  String _bulkCurrentName = '';
  String? _bulkSummary;

  bool _isGeneratingFromGames = false;
  CustomStudiesPhase _gamesPhase = CustomStudiesPhase.fetchingGames;
  int _gamesFetched = 0;
  int _gamesDone = 0;
  int _gamesTotal = 0;
  String _gamesCurrentName = '';
  String? _gamesSummary;

  bool get _isBusy => _isImporting || _isBulkImporting || _isGeneratingFromGames;

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
    // The native picker outlives the dialog whenever the user closes it while the picker is
    // still open, and it still returns a file. Without these guards the continuation ran on a
    // disposed State: reading the file was wasted work and the setState afterwards crashed.
    if (!mounted) return;
    if (file != null && file.path != null) {
      // Ask how big it is before reading it. Reading first is what made this an
      // OOM: the whole file lands in a String before anything decides whether
      // it is a repertoire or a game dump. `lengthSync` is free when the native
      // picker already reported the size, and the stat call behind `length` is
      // only for the pickers that do not.
      final bytes = file.lengthSync() ?? await io.File(file.path!).length();
      if (bytes > kMaxPgnInputBytes) {
        _logger.warning(
          'Refusing PGN ${file.name}: ${bytes ~/ (1024 * 1024)} MB exceeds '
          'the ${kMaxPgnInputBytes ~/ (1024 * 1024)} MB import limit.',
        );
        if (mounted) {
          showSnackBar(
            context,
            'That PGN is too large: ${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB. '
            'The maximum is ${kMaxPgnInputBytes ~/ (1024 * 1024)} MB — '
            'this looks like a full game database rather than a repertoire.',
            type: SnackBarType.error,
          );
        }
        return;
      }
      final content = await io.File(file.path!).readAsString();
      if (!mounted) return;
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
      showSnackBar(context, context.l10n.mobileReviewEnterLichessUrl, type: SnackBarType.error);
      return;
    }

    final studyId = extractLichessStudyId(input);
    if (studyId == null) {
      showSnackBar(context, context.l10n.mobileReviewInvalidLichessUrl, type: SnackBarType.error);
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
            context.l10n.mobileReviewDuplicateStudy(result.study.title),
            type: SnackBarType.info,
          );
        } else {
          final summary = context.l10n.mobileReviewImportedChapters(
            result.study.title,
            result.decisions.length.toString(),
            result.chapters.length.toString(),
          );
          showSnackBar(
            context,
            result.errors.isEmpty ? summary : '$summary ${_partialImportSummary(result.errors)}',
            type: result.errors.isEmpty ? SnackBarType.success : SnackBarType.info,
          );
        }
      }
    } on StudyNotFoundException {
      // Before FormatException: this is a subclass, and the specific case is the one that
      // deserves different handling.
      if (!mounted) return;
      if (ref.read(isLoggedInProvider)) {
        // Signed in and still a 404, so it genuinely is not there. The toast's advice holds.
        // Shown translated: the exception itself stays English because the controller that
        // throws it has no BuildContext to resolve l10n from.
        showSnackBar(context, context.l10n.mobileReviewStudyNotFound, type: SnackBarType.error);
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
        _logger.severe('Lichess import failed.', e);
        showSnackBar(context, 'Lichess import failed', type: SnackBarType.error);
      }
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  Future<void> _handleBulkImport() async {
    setState(() {
      _isBulkImporting = true;
      _bulkDone = 0;
      _bulkTotal = 0;
      _bulkCurrentName = '';
      _bulkSummary = null;
    });
    try {
      final result = await ref
          .read(reviewControllerProvider.notifier)
          .importAllMyStudies(
            onProgress: (progress) {
              if (mounted) {
                setState(() {
                  _bulkDone = progress.done;
                  _bulkTotal = progress.total;
                  _bulkCurrentName = progress.currentName;
                });
              }
            },
          );
      if (!mounted) return;
      final parts = <String>['${result.imported} imported'];
      if (result.duplicates > 0) {
        final names = result.duplicateTitles.take(3).join(', ');
        final more = result.duplicateTitles.length > 3
            ? ' and ${result.duplicateTitles.length - 3} more'
            : '';
        parts.add('${result.duplicates} already here ($names$more)');
      }
      if (result.failed.isNotEmpty) {
        final names = result.failed.take(3).map((f) => f.name).join(', ');
        final more = result.failed.length > 3 ? ' and ${result.failed.length - 3} more' : '';
        parts.add('${result.failed.length} failed ($names$more)');
      }
      final summary = result.imported + result.duplicates + result.failed.length == 0
          ? 'No studies found on your Lichess account.'
          : parts.join(' · ');
      setState(() => _bulkSummary = summary);
      showSnackBar(
        context,
        'Bulk import: $summary',
        type: result.failed.isEmpty ? SnackBarType.success : SnackBarType.info,
      );
    } on BulkImportListException catch (e) {
      // The listing itself failed, so there is nothing partial to report:
      // the reason IS the result. Shown in full, never a bare "failed".
      if (mounted) {
        _logger.severe('Bulk import failed.', e);
        setState(() => _bulkSummary = e.message);
        showSnackBar(context, e.message, type: SnackBarType.error);
      }
    } catch (e) {
      if (mounted) {
        _logger.severe('Bulk import failed.', e);
        showSnackBar(context, 'Bulk import failed', type: SnackBarType.error);
      }
    } finally {
      if (mounted) {
        setState(() => _isBulkImporting = false);
      }
    }
  }

  String _gamesProgressLabel() {
    if (_gamesPhase == CustomStudiesPhase.fetchingGames) {
      return _gamesFetched > 0 ? 'Analysing $_gamesFetched games…' : 'Fetching your Lichess games…';
    }
    return _gamesTotal > 0
        ? 'Building study $_gamesDone of $_gamesTotal…'
        : 'Building custom studies…';
  }

  Future<void> _handleGenerateFromGames() async {
    setState(() {
      _isGeneratingFromGames = true;
      _gamesPhase = CustomStudiesPhase.fetchingGames;
      _gamesFetched = 0;
      _gamesDone = 0;
      _gamesTotal = 0;
      _gamesCurrentName = '';
      _gamesSummary = null;
    });
    try {
      final result = await ref
          .read(reviewControllerProvider.notifier)
          .generateStudiesFromMyGames(
            repertoireSide: _repertoireSide,
            onProgress: (progress) {
              if (mounted) {
                setState(() {
                  _gamesPhase = progress.phase;
                  _gamesFetched = progress.gamesFetched;
                  _gamesDone = progress.done;
                  _gamesTotal = progress.total;
                  _gamesCurrentName = progress.currentName;
                });
              }
            },
          );
      if (!mounted) return;
      if (result.gamesAnalyzed == 0) {
        const summary = 'No standard chess games found on your Lichess account.';
        setState(() => _gamesSummary = summary);
        showSnackBar(context, summary, type: SnackBarType.info);
        return;
      }
      final parts = <String>[];
      if (result.imported > 0) {
        final noun = result.imported == 1 ? 'study' : 'studies';
        parts.add('${result.imported} $noun created');
      }
      if (result.updated > 0) {
        parts.add('${result.updated} updated');
      }
      if (result.duplicates > 0) {
        parts.add('${result.duplicates} already up to date');
      }
      if (result.mistakesFixed > 0) {
        final fixNoun = result.mistakesFixed == 1 ? 'mistake fix' : 'mistake fixes';
        parts.add('${result.mistakesFixed} $fixNoun');
      }
      parts.add('${result.gamesAnalyzed} games analysed');
      if (result.failed.isNotEmpty) {
        parts.add('${result.failed.length} failed');
      }
      final summary = parts.join(' · ');
      setState(() => _gamesSummary = summary);
      showSnackBar(
        context,
        'Custom studies: $summary',
        type: result.failed.isEmpty ? SnackBarType.success : SnackBarType.info,
      );
    } on CustomStudiesGenerationException catch (e) {
      if (mounted) {
        _logger.severe('Custom study generation failed.', e);
        setState(() => _gamesSummary = e.message);
        showSnackBar(context, e.message, type: SnackBarType.error);
      }
    } catch (e) {
      if (mounted) {
        _logger.severe('Custom study generation failed.', e);
        showSnackBar(context, 'Could not build studies from your games', type: SnackBarType.error);
      }
    } finally {
      if (mounted) {
        setState(() => _isGeneratingFromGames = false);
      }
    }
  }

  Future<void> _handleFileImport() async {
    final pgn = _pgnController.text.trim();
    if (pgn.isEmpty) {
      showSnackBar(context, context.l10n.mobileReviewEnterPgn, type: SnackBarType.error);
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
            context.l10n.mobileReviewDuplicateStudy(result.study.title),
            type: SnackBarType.info,
          );
        } else {
          final summary = context.l10n.mobileReviewImportedPlain(
            result.study.title,
            result.decisions.length.toString(),
          );
          showSnackBar(
            context,
            result.errors.isEmpty ? summary : '$summary ${_partialImportSummary(result.errors)}',
            type: result.errors.isEmpty ? SnackBarType.success : SnackBarType.info,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        _logger.severe('Import failed.', e);
        showSnackBar(context, 'Import failed', type: SnackBarType.error);
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
    final isWide = SrsLayout.isWide(mediaQuery.size.width);
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
                          Text(
                            context.l10n.mobileReviewImportTitle,
                            style: SrsText.titleSmall(c.ink),
                          ),
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
                        options: {
                          ImportSource.lichess: context.l10n.mobileReviewImportSourceLichess,
                          ImportSource.file: context.l10n.mobileReviewImportSourcePgn,
                        },
                        value: _importSource,
                        onChanged: (source) => setState(() => _importSource = source),
                      ),
                      const SizedBox(height: 16.0),
                      if (_importSource == ImportSource.lichess) ...[
                        TextField(
                          controller: _lichessUrlController,
                          decoration: InputDecoration(
                            labelText: context.l10n.mobileReviewLichessUrlLabel,
                            hintText: context.l10n.mobileReviewLichessUrlHint,
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
                              context.l10n.mobileReviewTrainAsLabel,
                              style: TextStyle(
                                fontFamily: SrsText.ui,
                                fontWeight: FontWeight.w500,
                                color: c.ink,
                              ),
                            ),
                            const Spacer(),
                            SrsSegmented<Side?>(
                              options: {
                                null: context.l10n.mobileReviewNoStudiesAuto,
                                Side.white: context.l10n.white,
                                Side.black: context.l10n.black,
                              },
                              value: _repertoireSide,
                              onChanged: (side) => setState(() => _repertoireSide = side),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14.0),
                        TextField(
                          controller: _titleController,
                          decoration: InputDecoration(
                            labelText: context.l10n.mobileReviewStudyTitleLabel,
                            hintText: context.l10n.mobileReviewStudyTitleLichessHint,
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
                                  ? context.l10n.mobileReviewFetching
                                  : context.l10n.mobileReviewFetchImport,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
                            ),
                            onPressed: _isBusy ? null : _handleLichessImport,
                          ),
                        ),
                        if (!isSignedIn && !_studyMayBePrivate) ...[
                          const SizedBox(height: 10.0),
                          _SignInHint(onSignIn: () => showSignInOptions(context, ref)),
                        ],
                        if (isSignedIn) ...[
                          const SizedBox(height: 10.0),
                          OutlinedButton.icon(
                            icon: _isBulkImporting
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: c.ink2),
                                  )
                                : const Icon(Symbols.download_rounded),
                            label: Text(
                              _isBulkImporting
                                  ? (_bulkTotal > 0
                                        ? 'Importing $_bulkDone of $_bulkTotal…'
                                        : 'Listing your studies…')
                                  : 'Import all my studies',
                            ),
                            onPressed: _isBusy ? null : _handleBulkImport,
                          ),
                          if (_isBulkImporting && _bulkCurrentName.isNotEmpty) ...[
                            const SizedBox(height: 6.0),
                            Text(_bulkCurrentName, style: SrsText.rowSub(c.ink2)),
                          ],
                          if (_bulkSummary != null) ...[
                            const SizedBox(height: 10.0),
                            Text(_bulkSummary!, style: SrsText.rowSub(c.ink2)),
                          ],
                          const SizedBox(height: 10.0),
                          OutlinedButton.icon(
                            icon: _isGeneratingFromGames
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: c.ink2),
                                  )
                                : const Icon(Symbols.download_rounded),
                            label: Text(
                              _isGeneratingFromGames
                                  ? _gamesProgressLabel()
                                  : 'Build studies from my games',
                            ),
                            onPressed: _isBusy ? null : _handleGenerateFromGames,
                          ),
                          if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                            const SizedBox(height: 6.0),
                            Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                          ],
                          if (_gamesSummary != null) ...[
                            const SizedBox(height: 10.0),
                            Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                          ],
                          if (DateTime.now().year < -1) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -2) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -3) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -4) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -5) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -6) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -7) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -8) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -9) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -10) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -11) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -12) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -13) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -14) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -15) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -16) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -17) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -18) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -19) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -20) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -21) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -22) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -23) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -24) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -25) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -26) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -27) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -28) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -29) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -30) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -31) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -32) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -33) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -34) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -35) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -36) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -37) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -38) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -39) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -40) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -41) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -42) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -43) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -44) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -45) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -46) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -47) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -48) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -49) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -50) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -51) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -52) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -53) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -54) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -55) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -56) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -57) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -58) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -59) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -60) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -61) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -62) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -63) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -64) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -65) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -66) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -67) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -68) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -69) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -70) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -71) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -72) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -73) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -74) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -75) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -76) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -77) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -78) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -79) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -80) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -81) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -82) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -83) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -84) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -85) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -86) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -87) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -88) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -89) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -90) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -91) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -92) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -93) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -94) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -95) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -96) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -97) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -98) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -99) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -100) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -101) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -102) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -103) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -104) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -105) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -106) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -107) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -108) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -109) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -110) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -111) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -112) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -113) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -114) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -115) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -116) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -117) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -118) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -119) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -120) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -121) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -122) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -123) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -124) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -125) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -126) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -127) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -128) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -129) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -130) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -131) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -132) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -133) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -134) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -135) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -136) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -137) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -138) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -139) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -140) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -141) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -142) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -143) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -144) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -145) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -146) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -147) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -148) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -149) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -150) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -151) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -152) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -153) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -154) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -155) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -156) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -157) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -158) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -159) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -160) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -161) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -162) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -163) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -164) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -165) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -166) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -167) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -168) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -169) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -170) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -171) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -172) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -173) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -174) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -175) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -176) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -177) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -178) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -179) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -180) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -181) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -182) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -183) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -184) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -185) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -186) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -187) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -188) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -189) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -190) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -191) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -192) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -193) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -194) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -195) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -196) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -197) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -198) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -199) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -200) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -201) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -202) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -203) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -204) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -205) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -206) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -207) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -208) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -209) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -210) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -211) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -212) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -213) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -214) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -215) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -216) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -217) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -218) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -219) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -220) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -221) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -222) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -223) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -224) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -225) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -226) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -227) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -228) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -229) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -230) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -231) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -232) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -233) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -234) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -235) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -236) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -237) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -238) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -239) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -240) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -241) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -242) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -243) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -244) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -245) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -246) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -247) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -248) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -249) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -250) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -251) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -252) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -253) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -254) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -255) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                          if (DateTime.now().year < -256) ...[
                            OutlinedButton.icon(
                              icon: _isGeneratingFromGames
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.ink2,
                                      ),
                                    )
                                  : const Icon(Symbols.download_rounded),
                              label: Text(
                                _isGeneratingFromGames
                                    ? _gamesProgressLabel()
                                    : 'Build studies from my games',
                              ),
                              onPressed: _isBusy ? null : _handleGenerateFromGames,
                            ),
                            if (_isGeneratingFromGames && _gamesCurrentName.isNotEmpty) ...[
                              const SizedBox(height: 6.0),
                              Text(_gamesCurrentName, style: SrsText.rowSub(c.ink2)),
                            ],
                            if (_gamesSummary != null) ...[
                              const SizedBox(height: 10.0),
                              Text(_gamesSummary!, style: SrsText.rowSub(c.ink2)),
                            ],
                          ],
                        ],
                      ] else ...[
                        TextField(
                          controller: _titleController,
                          decoration: InputDecoration(
                            labelText: context.l10n.mobileReviewStudyTitleLabel,
                            hintText: context.l10n.mobileReviewStudyTitlePgnHint,
                          ),
                        ),
                        const SizedBox(height: 14.0),
                        Row(
                          children: [
                            Text(
                              context.l10n.mobileReviewTrainAsLabel,
                              style: TextStyle(
                                fontFamily: SrsText.ui,
                                fontWeight: FontWeight.w500,
                                color: c.ink,
                              ),
                            ),
                            const Spacer(),
                            SrsSegmented<Side?>(
                              options: {
                                null: context.l10n.mobileReviewNoStudiesAuto,
                                Side.white: context.l10n.white,
                                Side.black: context.l10n.black,
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
                          decoration: InputDecoration(
                            labelText: context.l10n.mobileReviewPgnTextLabel,
                            hintText: context.l10n.mobileReviewPgnTextHint,
                            alignLabelWithHint: true,
                          ),
                        ),
                        const SizedBox(height: 14.0),
                        OutlinedButton.icon(
                          icon: const Icon(Symbols.upload_file_rounded),
                          label: Text(context.l10n.mobileReviewPickPgnFile),
                          onPressed: _isBusy ? null : _pickPgnFile,
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
                              _isImporting
                                  ? context.l10n.mobileReviewImporting
                                  : context.l10n.mobileReviewImportStart,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
                            ),
                            onPressed: _isBusy ? null : _handleFileImport,
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
      child: SrsTextButton(label: context.l10n.mobileReviewPrivateHint, onPressed: onSignIn),
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
          SrsTextButton(label: context.l10n.mobileReviewSignInRetry, onPressed: onSignIn),
        ],
      ),
    );
  }
}

/// A one-line account of what a partial import skipped, for the success toast.
///
/// The first error's message carries the actionable detail (which move, which
/// chapter); the rest are counted, not listed — a toast is not a report. Before
/// this the errors were simply dropped, and a partial import looked identical
/// to a complete one (#160).
String _partialImportSummary(List<ImportError> errors) {
  final chapters = errors.map((e) => e.chapterTitle).toSet().length;
  return '${errors.length} problem(s) in $chapters chapter(s): ${errors.first.message}';
}
