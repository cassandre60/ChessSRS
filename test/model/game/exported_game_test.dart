import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chess_srs/src/model/common/id.dart';
import 'package:chess_srs/src/model/common/perf.dart';
import 'package:chess_srs/src/model/common/speed.dart';
import 'package:chess_srs/src/model/game/exported_game.dart';
import 'package:chess_srs/src/model/game/game.dart';
import 'package:chess_srs/src/model/game/game_status.dart';
import 'package:chess_srs/src/model/game/player.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LightExportedGame', () {
    final base = LightExportedGame(
      id: const GameId('abcdefgh'),
      rated: true,
      speed: Speed.blitz,
      perf: Perf.blitz,
      createdAt: DateTime.utc(2024, 1, 2),
      lastMoveAt: DateTime.utc(2024, 1, 2, 0, 5),
      status: GameStatus.resign,
      white: const Player(name: 'White'),
      black: const Player(name: 'Black'),
      variant: Variant.standard,
    );

    test('isBookmarked reflects bookmarked flag', () {
      expect(base.isBookmarked, isFalse);
      expect(base.copyWith(bookmarked: false).isBookmarked, isFalse);
      expect(base.copyWith(bookmarked: true).isBookmarked, isTrue);
    });

    test('isImported is true only for import source', () {
      expect(base.isImported, isFalse);
      expect(base.copyWith(source: GameSource.lobby).isImported, isFalse);
      expect(base.copyWith(source: GameSource.friend).isImported, isFalse);
      expect(base.copyWith(source: GameSource.import).isImported, isTrue);
    });

    test('stores core identity and result fields', () {
      final game = base.copyWith(
        fullId: const GameFullId('abcdefgh1234'),
        winner: Side.white,
        lastFen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
      );

      expect(game.id, const GameId('abcdefgh'));
      expect(game.fullId, const GameFullId('abcdefgh1234'));
      expect(game.rated, isTrue);
      expect(game.speed, Speed.blitz);
      expect(game.perf, Perf.blitz);
      expect(game.status, GameStatus.resign);
      expect(game.variant, Variant.standard);
      expect(game.winner, Side.white);
      expect(game.lastFen, isNotEmpty);
      expect(game.white.name, 'White');
      expect(game.black.name, 'Black');
    });
  });
}
