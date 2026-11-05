import 'package:chess_srs/src/model/engine/engine_spec.dart';
import 'package:chess_srs/src/model/common/eval.dart';
import 'package:chess_srs/src/model/engine/engine_utils.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';

Position position(String fen) => Chess.fromSetup(Setup.parseFen(fen));

void main() {
  group('hasNonStandardMaterial', () {
    test('the initial position is standard material', () {
      expect(hasNonStandardMaterial(Chess.initial), isFalse);
    });

    test('more than 32 pieces is not standard material', () {
      expect(
        hasNonStandardMaterial(
          position('rnbqkbnr/pppppppp/8/8/8/4N3/PPPPPPPP/RNBQKBNR w KQkq - 0 1'),
        ),
        isTrue,
      );
    });

    test('more than eight pawns on either side is not standard material', () {
      expect(hasNonStandardMaterial(position('4k3/8/8/8/8/P7/PPPPPPPP/4K3 w - - 0 1')), isTrue);
      expect(hasNonStandardMaterial(position('4k3/pppppppp/p7/8/8/8/8/4K3 w - - 0 1')), isTrue);
    });

    test('a promoted piece paid for with a pawn is standard material', () {
      // Eight white pieces beyond the king, one of them a second queen that came from a promotion.
      expect(hasNonStandardMaterial(position('4k3/8/8/8/8/8/PPPPPPP1/QQ2K3 w - - 0 1')), isFalse);
    });

    test('a third knight with no pawn spent on it is standard material', () {
      // A knight can be promoted to, and with no pawns left there is a promotion to account for it.
      expect(hasNonStandardMaterial(position('nnnk4/8/8/8/8/8/8/4KNNN w - - 0 1')), isFalse);
    });

    test('a third knight beside a full set of pawns is not standard material', () {
      expect(
        hasNonStandardMaterial(position('nnnk4/pppppppp/8/8/8/8/PPPPPPPP/4KNNN w - - 0 1')),
        isTrue,
      );
    });

    test('a promotion too many for the pawns left is not standard material', () {
      // Eight pawns and a second queen: the queen had nothing to be promoted from.
      expect(hasNonStandardMaterial(position('4k3/8/8/8/8/8/PPPPPPPP/QQ2K3 w - - 0 1')), isTrue);
    });

    test('two bishops on the same colour count as a promotion', () {
      // Light-squared bishops on f1 and h3, so one of them is promoted, and eight pawns to pay
      // for it are one too many.
      expect(hasNonStandardMaterial(position('4k3/8/8/8/8/7B/PPPPPPPP/4KB2 w - - 0 1')), isTrue);
    });

    test('a bishop pair on opposite colours is standard material', () {
      expect(hasNonStandardMaterial(position('4k3/8/8/8/8/8/PPPPPPPP/2B1KB2 w - - 0 1')), isFalse);
    });

    test('a second dark-squared bishop with a full pawn set counts as a promotion', () {
      // Eight pawns and two dark-squared bishops: one of the bishops must have been promoted,
      // so material is non-standard.
      expect(hasNonStandardMaterial(position('4k3/8/8/8/8/4B3/PPPPPPPP/2B4K w - - 0 1')), isTrue);
    });

    test('material is judged for both sides', () {
      expect(hasNonStandardMaterial(position('qqqqk3/pppppppp/8/8/8/8/8/4K3 w - - 0 1')), isTrue);
    });
  });

  group('engineShortLabel', () {
    test('reads the version from the engine name', () {
      expect(engineShortLabel('Stockfish 19'), 'SF 19');
      expect(engineShortLabel('Stockfish 19.1'), 'SF 19');
    });

    test('names Fairy-Stockfish without its version', () {
      expect(engineShortLabel('Fairy-Stockfish 14.0.1'), 'Fairy SF');
    });

    test('returns null for a name it cannot read', () {
      expect(engineShortLabel(null), isNull);
      expect(engineShortLabel('Lc0 v0.32.1'), isNull);
    });
  });

  group('isLightStockfish', () {
    test('recognises only the light Stockfish flavour', () {
      expect(isLightStockfish(const StockfishSpec.light()), isTrue);
      expect(isLightStockfish(const StockfishSpec.latest(nnuePath: 'x')), isFalse);
      expect(isLightStockfish(null), isFalse);
    });
  });

  group('threatModePosition', () {
    test('advances both move counters for a black-to-move position', () {
      final p = position('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR b KQkq - 0 12');
      final t = threatModePosition(p);
      expect(t.turn, Side.white);
      expect(t.halfmoves, p.halfmoves + 1);
      expect(t.fullmoves, p.fullmoves + 1);
    });
  });

  group('pickBestEval', () {
    test('prefers a threat-mode local eval even when a saved eval exists', () {
      final local = LocalEval(
        position: Chess.initial,
        depth: 1,
        nodes: 1,
        pvs: IList(),
        millis: 1,
        searchTime: Duration.zero,
        threatMode: true,
      );
      final saved = CloudEval(position: Chess.initial, depth: 100, nodes: 100, pvs: IList());
      expect(pickBestEval(localEval: local, savedEval: saved, serverEval: null), same(local));
    });
  });
}
