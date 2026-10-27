import 'package:chess_srs/src/model/board_editor/board_editor_controller.dart';
import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ProviderContainer makeContainer(BoardEditorControllerParams? params) {
    final container = ProviderContainer();
    final subscription = container.listen(boardEditorControllerProvider(params), (_, _) {});
    addTearDown(subscription.close);
    addTearDown(container.dispose);
    return container;
  }

  group('BoardEditorController', () {
    // Black is in check while it is White's turn: the FEN is valid, but the
    // position it describes is illegal, so `Position.setupPosition` rejects it.
    const illegalPositionFen = 'r3k2r/8/8/8/8/4Q3/8/R3K2R w KQkq - 0 1';

    test('loads a FEN whose position is illegal', () {
      final container = makeContainer(null);
      final provider = boardEditorControllerProvider(null);

      container.read(provider.notifier).loadFen(illegalPositionFen);

      final state = container.read(provider);
      expect(state.pieces, readFen(illegalPositionFen).lock);
      expect(state.sideToPlay, Side.white);
      expect(state.castlingRights.values, everyElement(isTrue));
      expect(state.fen, illegalPositionFen);
      // The position is still not playable, so it cannot be analyzed.
      expect(state.pgn, isNull);
    });

    test('opens with an initial FEN whose position is illegal', () {
      const params = (
        initialVariant: Variant.standard,
        initialFen: illegalPositionFen,
        initialOrientation: null,
      );
      final container = makeContainer(params);

      expect(container.read(boardEditorControllerProvider(params)).fen, illegalPositionFen);
    });

    test('drops the castling rights of a rook that is missing', () {
      final container = makeContainer(null);
      final provider = boardEditorControllerProvider(null);

      container.read(provider.notifier).loadFen('4k3/8/8/8/8/8/8/R3K3 w KQkq - 0 1');

      final state = container.read(provider);
      expect(state.castlingRights[CastlingRight.whiteQueen], isTrue);
      expect(state.castlingRights[CastlingRight.whiteKing], isFalse);
      expect(state.castlingRights[CastlingRight.blackQueen], isFalse);
      expect(state.castlingRights[CastlingRight.blackKing], isFalse);
    });

    test('antichess positions have no castling rights', () {
      final params = (
        initialVariant: Variant.antichess,
        initialFen: Variant.standard.initialPosition.fen,
        initialOrientation: null,
      );
      final container = makeContainer(params);

      final state = container.read(boardEditorControllerProvider(params));
      expect(state.castlingRights.values, everyElement(isFalse));
    });

    test('clearBoard clears all castling rights and pieces', () {
      final container = makeContainer(null);
      final provider = boardEditorControllerProvider(null);

      container.read(provider.notifier).loadFen('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1');
      container.read(provider.notifier).clearBoard();

      final state = container.read(provider);
      expect(state.pieces, isEmpty);
      expect(state.castlingRights.values, everyElement(isFalse));
    });

    test('editSquare places the piece on first click and removes it on a second', () {
      final container = makeContainer(null);
      final provider = boardEditorControllerProvider(null);

      container.read(provider.notifier).updateMode(EditorPointerMode.edit, Piece.whiteQueen);
      const square = Square.e4;
      container.read(provider.notifier).editSquare(square);

      expect(container.read(provider).pieces[square], Piece.whiteQueen);

      container.read(provider.notifier).editSquare(square);

      expect(container.read(provider).pieces[square], isNull);
    });

    test('toggleEnPassantSquare toggles between the square and null', () {
      final container = makeContainer(null);
      final provider = boardEditorControllerProvider(null);

      const square = Square.e3;
      container.read(provider.notifier).toggleEnPassantSquare(square);
      expect(container.read(provider).enPassantSquare, square);

      container.read(provider.notifier).toggleEnPassantSquare(square);
      expect(container.read(provider).enPassantSquare, isNull);
    });

    test('activePieceOnEdit returns the selected piece in edit mode', () {
      final container = makeContainer(null);
      final provider = boardEditorControllerProvider(null);

      container.read(provider.notifier).updateMode(EditorPointerMode.edit, Piece.whiteQueen);

      final state = container.read(provider);
      expect(state.activePieceOnEdit, Piece.whiteQueen);
    });

    test('deletePiecesActive is true in edit mode with no piece selected', () {
      final container = makeContainer(null);
      final provider = boardEditorControllerProvider(null);

      container.read(provider.notifier).updateMode(EditorPointerMode.edit, null);

      final state = container.read(provider);
      expect(state.deletePiecesActive, isTrue);
    });

    test('deletePiecesActive is false outside edit mode', () {
      final container = makeContainer(null);
      final provider = boardEditorControllerProvider(null);

      container.read(provider.notifier).updateMode(EditorPointerMode.drag, null);

      final state = container.read(provider);
      expect(state.deletePiecesActive, isFalse);
    });

    test('opens with the standard initial position for the standard variant', () {
      final container = makeContainer(null);
      final state = container.read(boardEditorControllerProvider(null));
      expect(state.fen, Variant.standard.initialPosition.fen);
    });

    test('movePiece moves a piece between squares', () {
      final container = makeContainer(null);
      final provider = boardEditorControllerProvider(null);

      container.read(provider.notifier).loadFen('8/8/8/8/8/8/4P3/8 w - - 0 1');
      container.read(provider.notifier).movePiece(Square.e2, Square.e4, Piece.whitePawn);

      final state = container.read(provider);
      expect(state.pieces[Square.e4], Piece.whitePawn);
      expect(state.pieces[Square.e2], isNull);
    });

    test('enPassantOptions contains the target square for a basic white en passant', () {
      final container = makeContainer(null);
      final provider = boardEditorControllerProvider(null);

      container.read(provider.notifier).loadFen('8/8/8/3pP3/8/8/8/8 w - - 0 1');

      final state = container.read(provider);
      expect(state.enPassantOptions.has(Square.d6), isTrue);
      expect(state.enPassantOptions.size, 1);
    });

    test('enPassantOptions contains the target square for a basic black en passant', () {
      final container = makeContainer(null);
      final provider = boardEditorControllerProvider(null);

      container.read(provider.notifier).loadFen('8/8/8/8/3Pp3/8/8/8 b - - 0 1');

      final state = container.read(provider);
      expect(state.enPassantOptions.has(Square.d3), isTrue);
      expect(state.enPassantOptions.size, 1);
    });

    test('enPassantOptions is empty when the adjacent square has no opponent pawn', () {
      final container = makeContainer(null);
      final provider = boardEditorControllerProvider(null);

      container.read(provider.notifier).loadFen('8/8/8/4P3/8/8/8/8 w - - 0 1');

      final state = container.read(provider);
      expect(state.enPassantOptions.size, 0);
    });

    test('enPassantOptions is empty when the target square is occupied', () {
      final container = makeContainer(null);
      final provider = boardEditorControllerProvider(null);

      container.read(provider.notifier).loadFen('8/3p4/8/3pP3/8/8/8/8 w - - 0 1');

      final state = container.read(provider);
      expect(state.enPassantOptions.size, 0);
    });

    test('enPassantOptions is empty when the origin square is occupied', () {
      final container = makeContainer(null);
      final provider = boardEditorControllerProvider(null);

      container.read(provider.notifier).loadFen('8/3P4/8/3pP3/8/8/8/8 w - - 0 1');

      final state = container.read(provider);
      expect(state.enPassantOptions.size, 0);
    });

    test('enPassantOptions handles an a-file neighbour (left boundary)', () {
      final container = makeContainer(null);
      final provider = boardEditorControllerProvider(null);

      container.read(provider.notifier).loadFen('8/8/8/pP6/8/8/8/8 w - - 0 1');

      final state = container.read(provider);
      expect(state.enPassantOptions.has(Square.a6), isTrue);
      expect(state.enPassantOptions.size, 1);
    });

    test('enPassantOptions handles an h-file neighbour (right boundary)', () {
      final container = makeContainer(null);
      final provider = boardEditorControllerProvider(null);

      container.read(provider.notifier).loadFen('8/8/8/6Pp/8/8/8/8 w - - 0 1');

      final state = container.read(provider);
      expect(state.enPassantOptions.has(Square.h6), isTrue);
      expect(state.enPassantOptions.size, 1);
    });

    test('castling letter absent when the king-side rook is missing', () {
      final container = makeContainer(null);
      final provider = boardEditorControllerProvider(null);

      container
          .read(provider.notifier)
          .loadFen('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1');
      container.read(provider.notifier).discardPiece(Square.h1);

      final state = container.read(provider);
      expect(state.fen.split(' ')[2].contains('K'), isFalse);
    });

    test('castling letter absent when the king-side right is disabled', () {
      final container = makeContainer(null);
      final provider = boardEditorControllerProvider(null);

      container
          .read(provider.notifier)
          .loadFen('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1');
      container.read(provider.notifier).setCastling(Side.white, CastlingSide.king, false);

      final state = container.read(provider);
      expect(state.fen.split(' ')[2].contains('K'), isFalse);
    });

    test('castling letter absent when the queen-side right is disabled', () {
      final container = makeContainer(null);
      final provider = boardEditorControllerProvider(null);

      container
          .read(provider.notifier)
          .loadFen('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1');
      container.read(provider.notifier).setCastling(Side.white, CastlingSide.queen, false);

      final state = container.read(provider);
      expect(state.fen.split(' ')[2].contains('Q'), isFalse);
    });

    test('castling letter absent when the black king-side right is disabled', () {
      final container = makeContainer(null);
      final provider = boardEditorControllerProvider(null);

      container
          .read(provider.notifier)
          .loadFen('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1');
      container.read(provider.notifier).setCastling(Side.black, CastlingSide.king, false);

      final state = container.read(provider);
      expect(state.fen.split(' ')[2].contains('k'), isFalse);
    });

    test('castling letter absent when the black queen-side right is disabled', () {
      final container = makeContainer(null);
      final provider = boardEditorControllerProvider(null);

      container
          .read(provider.notifier)
          .loadFen('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1');
      container.read(provider.notifier).setCastling(Side.black, CastlingSide.queen, false);

      final state = container.read(provider);
      expect(state.fen.split(' ')[2].contains('q'), isFalse);
    });

    test('castling letter absent when the king-side rook square holds a non-rook', () {
      final container = makeContainer(null);
      final provider = boardEditorControllerProvider(null);

      container
          .read(provider.notifier)
          .loadFen('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNQ w KQkq - 0 1');
      container.read(provider.notifier).setCastling(Side.white, CastlingSide.king, true);

      final state = container.read(provider);
      expect(state.fen.split(' ')[2].contains('K'), isFalse);
    });

    test('enPassantOptions ignores non-pawn pieces of the side to move', () {
      final container = makeContainer(null);
      final provider = boardEditorControllerProvider(null);

      container.read(provider.notifier).loadFen('8/8/8/3pQ3/8/8/8/8 w - - 0 1');

      final state = container.read(provider);
      expect(state.enPassantOptions.size, 0);
    });

    test('enPassantOptions ignores non-pawn pieces of the side to move (black)', () {
      final container = makeContainer(null);
      final provider = boardEditorControllerProvider(null);

      container.read(provider.notifier).loadFen('8/8/8/8/3PQ3/8/8/8 b - - 0 1');

      final state = container.read(provider);
      expect(state.enPassantOptions.size, 0);
    });

    test('chess960 castling letter absent when the king is missing', () {
      const params = (
        initialVariant: Variant.chess960,
        initialFen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
        initialOrientation: null,
      );
      final container = makeContainer(params);
      final provider = boardEditorControllerProvider(params);

      container.read(provider.notifier).discardPiece(Square.e1);
      container.read(provider.notifier).setCastling(Side.white, CastlingSide.king, true);

      final state = container.read(provider);
      expect(state.fen.split(' ')[2].contains('K'), isFalse);
    });
  });
}
