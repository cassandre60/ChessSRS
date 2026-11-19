import 'package:chess_srs/src/model/board_editor/position.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Position.fromJson', () {
    test('maps each field from its own key', () {
      const json = <String, dynamic>{
        'name': 'Ruy Lopez',
        'fen': 'r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 3 3',
        'eco': 'C60',
      };

      final position = Position.fromJson(json);

      expect(position.name, 'Ruy Lopez');
      expect(position.fen, 'r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 3 3');
      expect(position.eco, 'C60');
    });

    test('distinguishes a missing mapped field from the others', () {
      final position = Position.fromJson({
        'name': 'name-value',
        'fen': 'fen-value',
        'eco': 'eco-value',
      });

      expect(position.name, isNot(position.fen));
      expect(position.fen, isNot(position.eco));
    });
  });

  group('Position value semantics', () {
    const a = Position(name: 'Italian', fen: 'fen-a', eco: 'C50');

    test('positions with equal fields are equal', () {
      const b = Position(name: 'Italian', fen: 'fen-a', eco: 'C50');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('a differing field breaks equality', () {
      const b = Position(name: 'Italian', fen: 'fen-b', eco: 'C50');
      expect(a, isNot(b));
    });

    test('copyWith overrides only the requested field', () {
      final renamed = a.copyWith(name: 'Giuoco Piano');

      expect(renamed.name, 'Giuoco Piano');
      expect(renamed.fen, a.fen);
      expect(renamed.eco, a.eco);
      expect(renamed, isNot(a));
    });
  });
}
