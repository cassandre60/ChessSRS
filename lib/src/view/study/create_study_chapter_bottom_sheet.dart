import 'dart:convert';

import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chess_srs/src/model/common/id.dart';
import 'package:chess_srs/src/model/study/study.dart';
import 'package:chess_srs/src/model/study/study_repository.dart';
import 'package:chess_srs/src/utils/l10n_context.dart';
import 'package:chess_srs/src/view/more/import_pgn_screen.dart';
import 'package:chess_srs/src/widgets/adaptive_choice_picker.dart';
import 'package:chess_srs/src/widgets/board_preview.dart';
import 'package:chess_srs/src/widgets/feedback.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

sealed class CreateStudyChapterParams {}

class CreateChapterOfExistingStudy extends CreateStudyChapterParams {
  CreateChapterOfExistingStudy(this.studyId);
  final StudyId studyId;
}

enum _ChapterSource { empty, fen, pgn }

class CreateStudyChapterBottomSheet extends ConsumerStatefulWidget {
  const CreateStudyChapterBottomSheet({
    required this.params,
    required this.chapterNumber,
    this.onChaptersCreated,
  });

  final CreateStudyChapterParams params;
  final int chapterNumber;
  final void Function(StudyId, IList<StudyChapterId>)? onChaptersCreated;

  @override
  ConsumerState<CreateStudyChapterBottomSheet> createState() =>
      _CreateStudyChapterBottomSheetState();
}

class _CreateStudyChapterBottomSheetState extends ConsumerState<CreateStudyChapterBottomSheet> {
  String chapterName = '';

  final _nameController = TextEditingController();
  final _textController = TextEditingController();

  _ChapterSource _source = _ChapterSource.empty;
  Side orientation = Side.white;
  Variant variant = Variant.standard;
  String? errorText;

  /// Whether a chapter creation request is in flight.
  bool _isSubmitting = false;

  @override
  void initState() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        chapterName = context.l10n.studyChapterX(widget.chapterNumber.toString());
        _nameController.text = chapterName;
      });
    });
    super.initState();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _textController.dispose();
    super.dispose();
  }

  void _onTextChanged(String value) {
    setState(() {
      _textController.text = value;
      _validateInput();
    });
  }

  /// Recomputes [errorText] from the current input, source and variant.
  void _validateInput() {
    errorText = null;

    final value = _textController.text.trim();
    if (value.isEmpty) {
      return;
    }

    switch (_source) {
      case _ChapterSource.empty:
        break;
      case _ChapterSource.fen:
        try {
          Position.setupPosition(variant.rule, Setup.parseFen(value));
        } catch (_) {
          errorText = context.l10n.invalidFen;
        }
      case _ChapterSource.pgn:
        try {
          errorText = _hasAnyPlayableGame(PgnGame.parseMultiGameLazy(value))
              ? null
              : context.l10n.invalidPgn;
        } catch (_) {
          errorText = context.l10n.invalidPgn;
        }
    }
  }

  /// Whether at least one of the [games] holds something we can make a chapter out of.
  ///
  /// [PgnGame.parseMultiGameLazy] never rejects input: arbitrary text parses into a single game
  /// with default headers and an empty move tree, so its emptiness cannot be used to tell a PGN
  /// from prose. A game is only meaningful here if it has at least one move, or a FEN header
  /// setting up a starting position.
  ///
  /// Games are parsed lazily and [Iterable.any] short-circuits, so a well-formed PGN — however
  /// many games it holds — costs a single full parse.
  bool _hasAnyPlayableGame(Iterable<PgnLazyGame> games) => games.any(
    (game) => game.headers.containsKey('FEN') || game.toPgnGame().moves.children.isNotEmpty,
  );

  @override
  Widget build(BuildContext context) {
    final c = context.srs;
    return SingleChildScrollView(
      // The sheet grows upwards and does no keyboard avoidance of its own, so without this
      // the on-screen keyboard covers the orientation row and the submit button while the
      // chapter name is being edited.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SrsSheetGrabber(),
            Text(context.l10n.name, style: SrsText.settingLabel(c.ink)),
            const SizedBox(height: 4),
            SrsTextInput(
              controller: _nameController,
              semanticLabel: context.l10n.name,
              onChanged: (value) => setState(() => chapterName = value),
            ),
            const SizedBox(height: 16),
            SrsSegmented<_ChapterSource>(
              options: {
                _ChapterSource.empty: context.l10n.studyEmpty,
                _ChapterSource.fen: 'FEN',
                _ChapterSource.pgn: 'PGN',
              },
              value: _source,
              onChanged: (source) {
                setState(() {
                  _source = source;
                  errorText = null;
                  if (_source != _ChapterSource.empty) _onTextChanged('');
                });
              },
            ),
            if (_source == _ChapterSource.fen) ...[
              const SizedBox(height: 16),
              SmallBoardPreview(
                orientation: orientation,
                fen: errorText == null ? _textController.text : kEmptyFEN,
                description: SrsTextInput(
                  controller: _textController,
                  hintText: context.l10n.pasteTheFenStringHere,
                  semanticLabel: context.l10n.pasteTheFenStringHere,
                  readOnly: true,
                  onTap: () => _getClipboardData(),
                ),
              ),
              SrsTextButton(label: 'Paste from clipboard', onPressed: _getClipboardData),
              if (errorText != null) ...[
                const SizedBox(height: 4),
                Text(errorText!, style: SrsText.settingHelp(c.ink2)),
              ],
            ],
            if (_source == _ChapterSource.pgn) ...[
              const SizedBox(height: 16),
              SizedBox(
                height: 150,
                child: SrsTextInput(
                  controller: _textController,
                  hintText: context.l10n.pasteThePgnStringHere,
                  semanticLabel: context.l10n.pasteThePgnStringHere,
                  readOnly: true,
                  maxLines: 6,
                  onTap: () => _getClipboardData(),
                ),
              ),
              SrsTextButton(label: 'Paste from clipboard', onPressed: _getClipboardData),
              SrsTextButton(label: context.l10n.mobileOrImportPgnFile, onPressed: _pickPgnFile),
              if (errorText != null) ...[
                const SizedBox(height: 4),
                Text(errorText!, style: SrsText.settingHelp(c.ink2)),
              ],
            ],
            if (_source != _ChapterSource.pgn) ...[
              const SizedBox(height: 8),
              SrsSettingsRow(
                label: context.l10n.variant,
                value: variant.label(context.l10n),
                onTap: () {
                  showChoicePicker(
                    context,
                    choices: Variant.values,
                    selectedItem: variant,
                    labelBuilder: (Variant variant) => Text(variant.label(context.l10n)),
                    onSelectedItemChanged: (Variant variant) => setState(() {
                      this.variant = variant;
                      _validateInput();
                    }),
                  );
                },
              ),
            ],
            SrsSettingsRow(
              label: context.l10n.studyOrientation,
              value: _sideL10n(context, orientation),
              onTap: () {
                showChoicePicker(
                  context,
                  choices: Side.values,
                  selectedItem: orientation,
                  labelBuilder: (Side side) => Text(_sideL10n(context, side)),
                  onSelectedItemChanged: (Side side) => setState(() => orientation = side),
                );
              },
            ),
            const SizedBox(height: 16),
            SrsPillButton(
              expand: true,
              label: context.l10n.studyCreateChapter,
              onPressed: _canSubmit() ? () => _createChapter(_submitPgn()) : null,
            ),
          ],
        ),
      ),
    );
  }

  /// The PGN payload for the submit button. Pulled out of the build so the button reads
  /// as a button rather than a match statement.
  String _submitPgn() {
    return switch (_source) {
      _ChapterSource.empty => PgnGame.parsePgn(
        '',
        initHeaders: () => {'Variant': variant.pgnName},
      ).makePgn(),
      _ChapterSource.fen => PgnGame.parsePgn(
        '',
        initHeaders: () => {'FEN': _textController.text.trim(), 'Variant': variant.pgnName},
      ).makePgn(),
      _ChapterSource.pgn => _textController.text.trim(),
    };
  }

  Future<void> _createChapter(String pgn) async {
    final chapterPayload = CreateStudyChapterPayload(
      pgn: pgn,
      name: chapterName,
      orientation: orientation,
      variant: _source == _ChapterSource.pgn ? null : variant,
    );

    setState(() => _isSubmitting = true);

    try {
      final (studyId, chapterIds) = switch (widget.params) {
        CreateChapterOfExistingStudy(:final studyId) => (
          studyId,
          await ref.read(studyRepositoryProvider).createChapter(studyId, chapterPayload),
        ),
      };

      if (!mounted) return;
      Navigator.of(context).pop();

      widget.onChaptersCreated?.call(studyId, chapterIds);
    } catch (e) {
      if (!mounted) return;
      // Keep the sheet open so the user can amend the input and retry.
      setState(() => _isSubmitting = false);
      debugPrint('SEVERE: [CreateStudyChapterBottomSheet] could not create chapter: $e');
      showSnackBar(context, 'Could not create chapter', type: SnackBarType.error);
    }
  }

  bool _canSubmit() {
    if (_isSubmitting) return false;
    if (chapterName.trim().isEmpty) return false;

    switch (_source) {
      case _ChapterSource.empty:
        return true;
      case _ChapterSource.fen || _ChapterSource.pgn:
        return errorText == null && _textController.text.trim().isNotEmpty;
    }
  }

  Future<void> _getClipboardData() async {
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;

    final text = data?.text?.trim() ?? '';
    // The input fields are read-only and pasting is their only affordance, so failing silently
    // here would be indistinguishable from a broken button.
    if (text.isEmpty) {
      showSnackBar(context, 'Nothing to paste: the clipboard is empty', type: SnackBarType.error);
      return;
    }

    _onTextChanged(text);
  }

  Future<void> _pickPgnFile() async {
    try {
      final file = await ref.read(pickPgnFileProvider)();

      if (file != null) {
        final content = await const Utf8Decoder(
          allowMalformed: true,
        ).bind(file.readAsByteStream()).join();
        if (mounted) {
          _onTextChanged(content);
        }
      }
    } catch (e) {
      if (mounted) {
        debugPrint('SEVERE: [CreateStudyChapterBottomSheet] error loading file: $e');
        showSnackBar(context, 'Error loading file', type: SnackBarType.error);
      }
    }
  }
}

String _sideL10n(BuildContext context, Side side) => switch (side) {
  Side.white => context.l10n.white,
  Side.black => context.l10n.black,
};
