// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/model/board_editor/board_editor_controller.dart';
import 'package:chess_srs/src/utils/l10n_context.dart';
import 'package:dartchess/dartchess.dart' hide Position;
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Position-legality controls for the board editor: side to move, castling rights and
/// en-passant square. Content for an [SrsSheetSurface]; the caller owns the surface.
class BoardEditorFilters extends ConsumerWidget {
  const BoardEditorFilters({required this.params, super.key});

  final BoardEditorControllerParams? params;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editorController = boardEditorControllerProvider(params);
    final editorState = ref.watch(editorController);

    final castlingSides = Side.values
        .where((side) => editorState.variant.sideCanCastle(side))
        .toIList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SrsSheetGrabber(),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SrsGroupHeader('Side to move'),
                SrsSegmented<Side>(
                  options: {
                    Side.white: context.l10n.whitePlays,
                    Side.black: context.l10n.blackPlays,
                  },
                  value: editorState.sideToPlay,
                  onChanged: (side) => ref.read(editorController.notifier).setSideToPlay(side),
                ),
                if (castlingSides.isNotEmpty) ...[
                  SrsGroupHeader(context.l10n.castling),
                  for (final side in castlingSides)
                    // King wing first: CastlingSide.values declares queen first, which would
                    // stack O-O-O above O-O against every convention.
                    for (final cSide in const [CastlingSide.king, CastlingSide.queen])
                      _CastlingRow(
                        params: params,
                        side: side,
                        castlingSide: cSide,
                        possible: editorState.isCastlingPossible(side, cSide),
                        allowed: editorState.isCastlingAllowed(side, cSide),
                      ),
                ],
                if (editorState.variant.hasEnPassant &&
                    editorState.enPassantOptions.isNotEmpty) ...[
                  const SrsGroupHeader('En passant'),
                  SrsSegmented<Square>(
                    options: {
                      for (final square in editorState.enPassantOptions.squares)
                        square: square.name,
                    },
                    value: editorState.enPassantSquare,
                    onChanged: (square) =>
                        ref.read(editorController.notifier).toggleEnPassantSquare(square),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One castling wing as a switch row. An impossible wing (missing king or rook on the
/// board) stays visible but disabled, so the board explains itself instead of hiding
/// the right.
class _CastlingRow extends ConsumerWidget {
  const _CastlingRow({
    required this.params,
    required this.side,
    required this.castlingSide,
    required this.possible,
    required this.allowed,
  });

  final BoardEditorControllerParams? params;
  final Side side;
  final CastlingSide castlingSide;
  final bool possible;
  final bool allowed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sideName = side == Side.white ? context.l10n.white : context.l10n.black;
    final wing = castlingSide == CastlingSide.king ? 'O-O' : 'O-O-O';
    void onToggled(bool on) {
      ref.read(boardEditorControllerProvider(params).notifier).setCastling(side, castlingSide, on);
    }

    return SrsSettingsRow(
      label: '$sideName $wing',
      control: SrsSwitch(
        value: possible && allowed,
        semanticLabel: '$sideName $wing',
        onChanged: possible ? onToggled : null,
      ),
    );
  }
}
