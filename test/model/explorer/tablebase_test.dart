import 'package:chess_srs/src/model/explorer/tablebase.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isTablebaseRelevant', () {
    test('standard position with few pieces is relevant (<= 8)', () {
      final pos = Chess.fromSetup(Setup.parseFen('8/8/8/8/8/8/K1Q5/7k w - - 0 1'));
      expect(isTablebaseRelevant(pos), isTrue);
    });

    test('standard starting position is not relevant (> 8)', () {
      expect(isTablebaseRelevant(Chess.initial), isFalse);
    });

    test('atomic endgame is relevant at small piece counts (threshold 6)', () {
      final pos = Position.setupPosition(
        Rule.atomic,
        Setup.parseFen('8/8/8/8/8/8/K7/6k1 w - - 0 1'),
      );
      expect(pos.board.pieces.length <= 6, isTrue);
      expect(isTablebaseRelevant(pos), isTrue);
    });

    test('antichess endgame is relevant at small piece counts (threshold 6)', () {
      final pos = Position.setupPosition(
        Rule.antichess,
        Setup.parseFen('8/8/8/8/8/8/K7/6k1 w - - 0 1'),
      );
      expect(pos.board.pieces.length <= 6, isTrue);
      expect(isTablebaseRelevant(pos), isTrue);
    });

    test('crazyhouse has no tablebase support (threshold 0)', () {
      final pos = Position.setupPosition(
        Rule.crazyhouse,
        Setup.parseFen('8/8/8/8/8/8/K7/6k1 w - - 0 1'),
      );
      expect(pos.board.pieces.isNotEmpty, isTrue);
      expect(isTablebaseRelevant(pos), isFalse);
    });
  });

  group('invertTablebaseCategory', () {
    test('inverts win/loss pairs', () {
      expect(invertTablebaseCategory(TablebaseCategory.win), TablebaseCategory.loss);
      expect(invertTablebaseCategory(TablebaseCategory.loss), TablebaseCategory.win);
      expect(invertTablebaseCategory(TablebaseCategory.syzygyWin), TablebaseCategory.syzygyLoss);
      expect(invertTablebaseCategory(TablebaseCategory.syzygyLoss), TablebaseCategory.syzygyWin);
      expect(invertTablebaseCategory(TablebaseCategory.maybeWin), TablebaseCategory.maybeLoss);
      expect(invertTablebaseCategory(TablebaseCategory.maybeLoss), TablebaseCategory.maybeWin);
      expect(invertTablebaseCategory(TablebaseCategory.cursedWin), TablebaseCategory.blessedLoss);
      expect(invertTablebaseCategory(TablebaseCategory.blessedLoss), TablebaseCategory.cursedWin);
    });

    test('draw and unknown are invariant', () {
      expect(invertTablebaseCategory(TablebaseCategory.draw), TablebaseCategory.draw);
      expect(invertTablebaseCategory(TablebaseCategory.unknown), TablebaseCategory.unknown);
    });
  });

  group('TablebaseEntry/TablebaseMove parsing', () {
    test('TablebaseEntry.fromJson parses all category values', () {
      expect(
        TablebaseEntry.fromJson({'category': 'win', 'moves': []}).category,
        TablebaseCategory.win,
      );
      expect(
        TablebaseEntry.fromJson({'category': 'unknown', 'moves': []}).category,
        TablebaseCategory.unknown,
      );
      expect(
        TablebaseEntry.fromJson({'category': 'syzygy-win', 'moves': []}).category,
        TablebaseCategory.syzygyWin,
      );
      expect(
        TablebaseEntry.fromJson({'category': 'maybe-win', 'moves': []}).category,
        TablebaseCategory.maybeWin,
      );
      expect(
        TablebaseEntry.fromJson({'category': 'cursed-win', 'moves': []}).category,
        TablebaseCategory.cursedWin,
      );
      expect(
        TablebaseEntry.fromJson({'category': 'draw', 'moves': []}).category,
        TablebaseCategory.draw,
      );
      expect(
        TablebaseEntry.fromJson({'category': 'blessed-loss', 'moves': []}).category,
        TablebaseCategory.blessedLoss,
      );
      expect(
        TablebaseEntry.fromJson({'category': 'maybe-loss', 'moves': []}).category,
        TablebaseCategory.maybeLoss,
      );
      expect(
        TablebaseEntry.fromJson({'category': 'syzygy-loss', 'moves': []}).category,
        TablebaseCategory.syzygyLoss,
      );
      expect(
        TablebaseEntry.fromJson({'category': 'loss', 'moves': []}).category,
        TablebaseCategory.loss,
      );
    });

    test('unknown category string falls back to unknown', () {
      expect(
        TablebaseEntry.fromJson({'category': 'not-a-category', 'moves': []}).category,
        TablebaseCategory.unknown,
      );
    });

    test('TablebaseEntry.fromJson parses fields and nested moves', () {
      final entry = TablebaseEntry.fromJson({
        'dtz': 5,
        'dtc': 3,
        'dtm': 7,
        'checkmate': true,
        'stalemate': false,
        'insufficient_material': true,
        'category': 'win',
        'moves': [
          {
            'uci': 'e2e4',
            'san': 'e4',
            'dtz': 4,
            'dtc': 2,
            'dtm': 6,
            'zeroing': false,
            'conversion': true,
            'checkmate': false,
            'stalemate': false,
            'insufficient_material': false,
            'category': 'loss',
          },
        ],
      });
      expect(entry.dtz, 5);
      expect(entry.dtc, 3);
      expect(entry.dtm, 7);
      expect(entry.checkmate, isTrue);
      expect(entry.stalemate, isFalse);
      expect(entry.insufficientMaterial, isTrue);
      expect(entry.category, TablebaseCategory.win);
      expect(entry.moves.length, 1);
      final move = entry.moves[0];
      expect(move.uci, 'e2e4');
      expect(move.san, 'e4');
      expect(move.dtz, 4);
      expect(move.dtc, 2);
      expect(move.dtm, 6);
      expect(move.zeroing, isFalse);
      expect(move.conversion, isTrue);
      expect(move.category, TablebaseCategory.loss);
    });

    test('TablebaseEntry.fromJson defaults missing bools/nullables/moves', () {
      final entry = TablebaseEntry.fromJson({'category': 'draw', 'moves': []});
      expect(entry.dtz, isNull);
      expect(entry.dtc, isNull);
      expect(entry.dtm, isNull);
      expect(entry.checkmate, isFalse);
      expect(entry.stalemate, isFalse);
      expect(entry.insufficientMaterial, isFalse);
      expect(entry.moves, isEmpty);
    });

    test('TablebaseMove.fromJson parses fields and defaults', () {
      final move = TablebaseMove.fromJson({
        'uci': 'a2a3',
        'san': 'a3',
        'zeroing': true,
        'conversion': false,
        'checkmate': false,
        'stalemate': false,
        'insufficient_material': false,
        'category': 'cursed-win',
      });
      expect(move.uci, 'a2a3');
      expect(move.san, 'a3');
      expect(move.zeroing, isTrue);
      expect(move.conversion, isFalse);
      expect(move.checkmate, isFalse);
      expect(move.stalemate, isFalse);
      expect(move.insufficientMaterial, isFalse);
      expect(move.dtz, isNull);
      expect(move.dtc, isNull);
      expect(move.dtm, isNull);
      expect(move.category, TablebaseCategory.cursedWin);
    });
  });
}
