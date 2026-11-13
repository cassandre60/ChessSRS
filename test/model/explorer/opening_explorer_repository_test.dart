import 'package:chess_srs/src/model/analysis/opening_service.dart';
import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chess_srs/src/model/common/speed.dart';
import 'package:chess_srs/src/model/explorer/opening_explorer.dart';
import 'package:chess_srs/src/model/explorer/opening_explorer_repository.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';

import '../../test_container.dart';
import '../../test_helpers.dart';

void main() {
  group('OpeningExplorerRepository.getMasterDatabase', () {
    test('parse json', () async {
      const response = '''
{
  "white": 834333,
  "draws": 1085272,
  "black": 600303,
  "moves": [
    {
      "uci": "e2e4",
      "san": "e4",
      "averageRating": 2399,
      "white": 372266,
      "draws": 486092,
      "black": 280238,
      "game": null
    },
    {
      "uci": "d2d4",
      "san": "d4",
      "averageRating": 2414,
      "white": 302160,
      "draws": 397224,
      "black": 209077,
      "game": null
    }
  ],
  "topGames": [
    {
      "uci": "d2d4",
      "id": "QR5UbqUY",
      "winner": null,
      "black": {
        "name": "Caruana, F.",
        "rating": 2818
      },
      "white": {
        "name": "Carlsen, M.",
        "rating": 2882
      },
      "year": 2019,
      "month": "2019-08"
    },
    {
      "uci": "e2e4",
      "id": "Sxov6E94",
      "winner": "white",
      "black": {
        "name": "Carlsen, M.",
        "rating": 2882
      },
      "white": {
        "name": "Caruana, F.",
        "rating": 2818
      },
      "year": 2019,
      "month": "2019-08"
    }
  ],
  "opening": null
}
      ''';

      final mockClient = MockClient((request) {
        if (request.url.path == '/masters') {
          expect(request.url.queryParameters.containsKey('variant'), isFalse);
          return mockResponse(response, 200);
        }
        return mockResponse('', 404);
      });

      final container = await lichessClientContainer(mockClient);

      final repo = container.read(openingExplorerRepositoryProvider);

      final result = await repo.getMasterDatabase('fen');
      expect(result, isA<OpeningExplorerEntry>());
      expect(result.moves.length, 2);
      expect(result.topGames, isNotNull);
      expect(result.topGames!.length, 2);
    });

    test('includes since query parameter when provided', () async {
      const response = '{"white":0,"draws":0,"black":0,"moves":[],"topGames":[],"opening":null}';

      final mockClient = MockClient((request) {
        if (request.url.path == '/masters') {
          expect(request.url.queryParameters['since'], '2010');
          return mockResponse(response, 200);
        }
        return mockResponse('', 404);
      });

      final container = await lichessClientContainer(mockClient);
      final repo = container.read(openingExplorerRepositoryProvider);

      await repo.getMasterDatabase('fen', since: 2010);
    });
  });

  group('OpeningExplorerRepository.getLichessDatabase', () {
    test('parse json', () async {
      const response = '''
{
  "white": 2848672002,
  "draws": 225287646,
  "black": 2649860106,
  "moves": [
    {
      "uci": "e2e4",
      "san": "e4",
      "averageRating": 1604,
      "white": 1661457614,
      "draws": 129433754,
      "black": 1565161663,
      "game": null
    }
  ],
  "recentGames": [
    {
      "uci": "e2e4",
      "id": "RVb19S9O",
      "winner": "white",
      "speed": "rapid",
      "mode": "rated",
      "black": {
        "name": "Jcats1",
        "rating": 1548
      },
      "white": {
        "name": "carlosrivero32",
        "rating": 1690
      },
      "year": 2024,
      "month": "2024-06"
    }
  ],
  "topGames": [],
  "opening": null
}
      ''';

      final mockClient = MockClient((request) {
        if (request.url.path == '/lichess' &&
            request.url.queryParameters['ratings'] == '1000,1200') {
          expect(request.url.queryParameters['variant'], 'crazyhouse');
          expect(request.url.queryParameters['speeds'], 'rapid');
          return mockResponse(response, 200);
        }
        return mockResponse('', 404);
      });

      final container = await lichessClientContainer(mockClient);

      final repo = container.read(openingExplorerRepositoryProvider);

      final result = await repo.getLichessDatabase(
        'fen',
        variant: Variant.crazyhouse,
        speeds: const ISetConst({Speed.rapid}),
        ratings: const ISetConst({1000, 1200}),
      );
      expect(result, isA<OpeningExplorerEntry>());
      expect(result.moves.length, 1);
      expect(result.recentGames, isNotNull);
      expect(result.recentGames!.length, 1);
      expect(result.topGames, isNotNull);
      expect(result.topGames!.length, 0);
    });
  });

  group('OpeningExplorerRepository.getPlayerDatabase', () {
    test('parse json', () async {
      const response = '''
{
  "white": 1713,
  "draws": 119,
  "black": 1459,
  "moves": [
    {
      "uci": "e2e4",
      "san": "e4",
      "averageOpponentRating": 1767,
      "performance": 1796,
      "white": 1691,
      "draws": 116,
      "black": 1432,
      "game": null
    }
  ],
  "recentGames": [
    {
      "uci": "e2e4",
      "id": "RVb19S9O",
      "winner": "white",
      "speed": "bullet",
      "mode": "rated",
      "black": {
        "name": "foo",
        "rating": 1869
      },
      "white": {
        "name": "baz",
        "rating": 1912
      },
      "year": 2023,
      "month": "2023-08"
    }
  ],
  "opening": null,
  "queuePosition": 0
}
      ''';

      final mockClient = MockClient((request) {
        if (request.url.path == '/player' && request.url.queryParameters['speeds'] == 'bullet') {
          expect(request.url.queryParameters['variant'], 'crazyhouse');
          expect(request.url.queryParameters['modes'], 'rated');
          return mockResponse(response, 200);
        }
        return mockResponse('', 404);
      });

      final container = await lichessClientContainer(mockClient);

      final repo = container.read(openingExplorerRepositoryProvider);

      final results = await repo.getPlayerDatabase(
        'fen',
        variant: Variant.crazyhouse,
        usernameOrId: 'baz',
        color: Side.white,
        speeds: const ISetConst({Speed.bullet}),
        gameModes: const ISetConst({GameMode.rated}),
      );
      expect(results, isA<Stream<OpeningExplorerEntry>>());
      await for (final result in results) {
        expect(result, isA<OpeningExplorerEntry>());
        expect(result.moves.length, 1);
        expect(result.recentGames, isNotNull);
        expect(result.recentGames!.length, 1);
      }
    });
  });
  group('OpeningExplorerRepository.getOpenDatabase', () {
    test('parses chessdb response', () async {
      const response =
          '{"status":"ok","moves":[{"uci":"e2e4","san":"e4","winrate":"50.0","score":10}]}';
      final mockClient = MockClient((request) {
        if (request.url.host == 'www.chessdb.cn' && request.url.path == '/cdb.php') {
          return mockResponse(response, 200);
        }
        return mockResponse('', 404);
      });

      final container = await lichessClientContainer(mockClient);

      final repo = container.read(openingExplorerRepositoryProvider);

      final result = await repo.getOpenDatabase('fen');
      expect(result.moves.length, 1);
      expect(result.moves.first.san, 'e4');
      expect(result.moves.first.uci, 'e2e4');
      expect(result.moves.first.performance, 10);
      expect(result.white + result.draws + result.black, 1000);
      expect(result.opening, isNull);
    });

    test('returns empty entry for non-standard variants without calling chessdb', () async {
      final mockClient = MockClient((request) {
        if (request.url.host == 'www.chessdb.cn') {
          fail('chessdb should not be queried for non-standard variants');
        }
        return mockResponse('', 404);
      });

      final container = await lichessClientContainer(mockClient);
      final repo = container.read(openingExplorerRepositoryProvider);

      final result = await repo.getOpenDatabase('fen', variant: Variant.crazyhouse);

      expect(result.moves, isEmpty);
      expect(result.white, 0);
      expect(result.draws, 0);
      expect(result.black, 0);
    });

    test('falls back to empty entry when chessdb response is not usable', () async {
      final mockClient = MockClient((request) {
        if (request.url.host == 'www.chessdb.cn') {
          return mockResponse('{"status":"no_bestmove"}', 200);
        }
        return mockResponse('', 404);
      });

      final container = await lichessClientContainer(mockClient);
      final repo = container.read(openingExplorerRepositoryProvider);

      final result = await repo.getOpenDatabase('fen');

      expect(result.moves, isEmpty);
    });

    test('falls back to empty entry when chessdb request fails', () async {
      final mockClient = MockClient((request) {
        if (request.url.host == 'www.chessdb.cn') {
          return mockResponse('boom', 500);
        }
        return mockResponse('', 404);
      });

      final container = await lichessClientContainer(mockClient);
      final repo = container.read(openingExplorerRepositoryProvider);

      final result = await repo.getOpenDatabase('fen');

      expect(result.moves, isEmpty);
    });

    test('enriches entry with opening from openingService', () async {
      const response =
          '{"status":"ok","moves":[{"uci":"e2e4","san":"e4","winrate":"50.0","score":10}]}';
      final mockClient = MockClient((request) {
        if (request.url.host == 'www.chessdb.cn') {
          return mockResponse(response, 200);
        }
        return mockResponse('', 404);
      });

      final container = await lichessClientContainer(mockClient);
      final refProvider = Provider((ref) => ref);
      final repo = OpeningExplorerRepository(
        mockClient,
        openingService: _FakeOpeningService(
          container.read(refProvider),
          const FullOpening(
            eco: 'B00',
            name: "King's Pawn Game",
            fen: 'fen',
            pgnMoves: '1. e4',
            uciMoves: 'e2e4',
          ),
        ),
      );

      final result = await repo.getOpenDatabase('fen');

      expect(result.opening, isNotNull);
      expect(result.opening!.eco, 'B00');
      expect(result.opening!.name, "King's Pawn Game");
      expect(result.moves.length, 1);
    });

    test('ignores openingService failures', () async {
      final mockClient = MockClient((request) {
        if (request.url.host == 'www.chessdb.cn') {
          return mockResponse('', 500);
        }
        return mockResponse('', 404);
      });

      final container = await lichessClientContainer(mockClient);
      final refProvider = Provider((ref) => ref);
      final repo = OpeningExplorerRepository(
        mockClient,
        openingService: _ThrowingOpeningService(container.read(refProvider)),
      );

      final result = await repo.getOpenDatabase('fen');

      expect(result.moves, isEmpty);
      expect(result.opening, isNull);
    });
  });
}

class _FakeOpeningService extends OpeningService {
  _FakeOpeningService(super.ref, this.result);

  final FullOpening? result;

  @override
  Future<FullOpening?> fetchFromFen(String fen) async => result;
}

class _ThrowingOpeningService extends OpeningService {
  _ThrowingOpeningService(super.ref);

  @override
  Future<FullOpening?> fetchFromFen(String fen) async => throw Exception('boom');
}
