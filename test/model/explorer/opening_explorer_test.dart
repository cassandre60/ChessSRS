import 'package:chess_srs/src/model/common/perf.dart';
import 'package:chess_srs/src/model/explorer/opening_explorer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OpeningExplorerEntry', () {
    test('empty has zero counts and no moves', () {
      final entry = OpeningExplorerEntry.empty();

      expect(entry.white, 0);
      expect(entry.draws, 0);
      expect(entry.black, 0);
      expect(entry.moves, isEmpty);
      expect(entry.topGames, isNull);
      expect(entry.recentGames, isNull);
      expect(entry.opening, isNull);
      expect(entry.queuePosition, isNull);
    });

    test('fromJson parses moves and games', () {
      final entry = OpeningExplorerEntry.fromJson(const {
        'white': 10,
        'draws': 5,
        'black': 3,
        'moves': [
          {'uci': 'e2e4', 'san': 'e4', 'white': 6, 'draws': 3, 'black': 1, 'averageRating': 2000},
        ],
        'topGames': [
          {
            'id': 'abcd1234',
            'white': {'name': 'Alice', 'rating': 2100},
            'black': {'name': 'Bob', 'rating': 2050},
            'winner': 'white',
            'speed': 'rapid',
            'mode': 'rated',
            'year': 2024,
            'month': '2024-06',
          },
        ],
        'recentGames': <Object?>[],
        'queuePosition': 2,
      });

      expect(entry.white, 10);
      expect(entry.draws, 5);
      expect(entry.black, 3);
      expect(entry.moves, hasLength(1));
      expect(entry.moves.first.uci, 'e2e4');
      expect(entry.moves.first.san, 'e4');
      expect(entry.moves.first.games, 10);
      expect(entry.topGames, hasLength(1));
      expect(entry.topGames!.first.id.value, 'abcd1234');
      expect(entry.topGames!.first.white.name, 'Alice');
      expect(entry.topGames!.first.black.rating, 2050);
      expect(entry.topGames!.first.winner, 'white');
      expect(entry.topGames!.first.speed, Perf.rapid);
      expect(entry.topGames!.first.mode, GameMode.rated);
      expect(entry.topGames!.first.year, 2024);
      expect(entry.topGames!.first.month, '2024-06');
      expect(entry.recentGames, isEmpty);
      expect(entry.queuePosition, 2);
    });
  });

  group('OpeningMove', () {
    test('games sums white, draws and black', () {
      const move = OpeningMove(uci: 'd2d4', san: 'd4', white: 7, draws: 2, black: 4);

      expect(move.games, 13);
      expect(move.averageRating, isNull);
      expect(move.averageOpponentRating, isNull);
      expect(move.performance, isNull);
      expect(move.game, isNull);
    });

    test('fromJson parses optional fields', () {
      final move = OpeningMove.fromJson(const {
        'uci': 'g1f3',
        'san': 'Nf3',
        'white': 1,
        'draws': 2,
        'black': 3,
        'averageRating': 1800,
        'averageOpponentRating': 1750,
        'performance': 1820,
      });

      expect(move.uci, 'g1f3');
      expect(move.san, 'Nf3');
      expect(move.games, 6);
      expect(move.averageRating, 1800);
      expect(move.averageOpponentRating, 1750);
      expect(move.performance, 1820);
    });
  });

  group('OpeningExplorerGame', () {
    test('fromJson parses minimal and unknown mode as null', () {
      final game = OpeningExplorerGame.fromJson(const {
        'id': 'game1234',
        'white': {'name': 'W', 'rating': 1500},
        'black': {'name': 'B', 'rating': 1490},
        'mode': 'unknown',
      });

      expect(game.id.value, 'game1234');
      expect(game.white, (name: 'W', rating: 1500));
      expect(game.black, (name: 'B', rating: 1490));
      expect(game.mode, isNull);
      expect(game.speed, isNull);
      expect(game.winner, isNull);
      expect(game.uci, isNull);
      expect(game.year, isNull);
      expect(game.month, isNull);
    });
  });

  group('Opening enums', () {
    test('databases and game modes have expected values', () {
      expect(OpeningDatabase.values, hasLength(4));
      expect(OpeningDatabase.master.name, 'master');
      expect(OpeningDatabase.lichess.name, 'lichess');
      expect(OpeningDatabase.player.name, 'player');
      expect(OpeningDatabase.chessdb.name, 'chessdb');

      expect(GameMode.values, const [GameMode.casual, GameMode.rated]);
    });
  });
}
