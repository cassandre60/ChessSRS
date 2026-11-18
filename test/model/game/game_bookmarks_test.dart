// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/model/auth/auth_controller.dart';
import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chess_srs/src/model/common/id.dart';
import 'package:chess_srs/src/model/common/perf.dart';
import 'package:chess_srs/src/model/common/speed.dart';
import 'package:chess_srs/src/model/game/exported_game.dart';
import 'package:chess_srs/src/model/game/game.dart';
import 'package:chess_srs/src/model/game/game_bookmarks.dart';
import 'package:chess_srs/src/model/game/game_repository.dart';
import 'package:chess_srs/src/model/game/game_status.dart';
import 'package:chess_srs/src/model/game/player.dart';
import 'package:chess_srs/src/model/user/user.dart';
import 'package:dartchess/dartchess.dart' show Side;
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../test_container.dart';

class MockGameRepository extends Mock implements GameRepository {}

/// Lets a test change the signed-in account the same way sign-in/sign-out does, so a rebuild
/// can be observed without going through the real auth flow.
class _SwitchableAuth extends AuthController {
  _SwitchableAuth(this._user);

  final AuthUser? _user;

  @override
  AuthUser? build() => _user;

  AuthUser? get user => state;

  set user(AuthUser? user) => state = user;
}

const _alice = AuthUser(
  token: 'a',
  user: LightUser(id: UserId('alice'), name: 'alice'),
);
const _bob = AuthUser(
  token: 'b',
  user: LightUser(id: UserId('bob'), name: 'bob'),
);

LightExportedGameWithPov _game(String id, {DateTime? createdAt}) => (
  game: LightExportedGame(
    id: GameId(id),
    source: GameSource.lobby,
    rated: false,
    speed: Speed.classical,
    perf: Perf.classical,
    createdAt: createdAt ?? DateTime.utc(2021),
    lastMoveAt: DateTime.utc(2021),
    status: GameStatus.mate,
    white: const Player(name: 'Alice'),
    black: const Player(name: 'Bob'),
    variant: Variant.standard,
    winner: Side.white,
  ),
  pov: Side.white,
);

IList<LightExportedGameWithPov> _page(List<String> ids, {DateTime? createdAt}) =>
    [for (final id in ids) _game(id, createdAt: createdAt)].toIList();

void main() {
  late MockGameRepository repository;
  late List<({AuthUser user, int max, DateTime? until})> calls;
  late Future<IList<LightExportedGameWithPov>> Function(AuthUser, int, DateTime?) responder;

  setUpAll(() {
    registerFallbackValue(_alice);
  });

  setUp(() {
    repository = MockGameRepository();
    calls = [];
    responder = (_, _, _) => Future.value(_page(const []));
    when(
      () => repository.getBookmarkedGames(
        any(),
        max: any(named: 'max'),
        until: any(named: 'until'),
      ),
    ).thenAnswer((invocation) {
      final user = invocation.positionalArguments.first as AuthUser;
      final max = invocation.namedArguments[#max] as int;
      final until = invocation.namedArguments[#until] as DateTime?;
      calls.add((user: user, max: max, until: until));
      return responder(user, max, until);
    });
  });

  /// A listener keeps the autoDispose paginator alive while the test awaits a read.
  Future<(ProviderContainer, _SwitchableAuth)> containerFor(AuthUser? user) async {
    final container = await makeContainer(
      overrides: {
        gameRepositoryProvider: gameRepositoryProvider.overrideWithValue(repository),
        authControllerProvider: authControllerProvider.overrideWith(() => _SwitchableAuth(user)),
      },
    );
    final sub = container.listen(gameBookmarksPaginatorProvider, (_, _) {});
    addTearDown(sub.close);
    addTearDown(container.dispose);
    final auth = container.read(authControllerProvider.notifier) as _SwitchableAuth;
    return (container, auth);
  }

  group('GameBookmarksPaginator.build', () {
    test('anonymous user gets an empty, non-paginated state without a repository read', () async {
      final (container, _) = await containerFor(null);

      final state = await container.read(gameBookmarksPaginatorProvider.future);

      expect(state.gameList, isEmpty);
      expect(state.isLoading, isFalse);
      expect(state.hasMore, isFalse);
      expect(state.hasError, isFalse);
      expect(calls, isEmpty);
    });

    test('signed-in user gets their bookmarks with hasMore set', () async {
      responder = (_, _, _) async => _page(['aaaaaa11', 'bbbbbb22']);
      final (container, _) = await containerFor(_alice);

      final state = await container.read(gameBookmarksPaginatorProvider.future);

      expect(
        state.gameList.map((e) => e.game.id),
        equals([const GameId('aaaaaa11'), const GameId('bbbbbb22')]),
      );
      expect(state.hasMore, isTrue);
      expect(state.isLoading, isFalse);
      expect(state.hasError, isFalse);
      expect(calls.length, 1);
      expect(calls.single.user, _alice);
      expect(calls.single.max, 20);
      expect(calls.single.until, isNull);
    });
  });

  group('GameBookmarksPaginator.getNext', () {
    test('appends a page, forwarding the last game timestamp as the cursor', () async {
      final firstCreatedAt = DateTime.utc(2021, 1, 1);
      var page = 0;
      responder = (_, _, _) async {
        page++;
        return page == 1
            ? _page(['aaaaaa11', 'bbbbbb22'], createdAt: firstCreatedAt)
            : _page(['cccccc33']);
      };
      final (container, _) = await containerFor(_alice);
      await container.read(gameBookmarksPaginatorProvider.future);
      final notifier = container.read(gameBookmarksPaginatorProvider.notifier);

      await notifier.getNext();

      final state = container.read(gameBookmarksPaginatorProvider).requireValue;
      expect(
        state.gameList.map((e) => e.game.id),
        equals([const GameId('aaaaaa11'), const GameId('bbbbbb22'), const GameId('cccccc33')]),
      );
      expect(state.isLoading, isFalse);
      expect(state.hasError, isFalse);
      // A short page means the end of the list.
      expect(state.hasMore, isFalse);
      expect(calls.length, 2);
      expect(calls[1].max, 20);
      expect(calls[1].until, firstCreatedAt);
    });

    test('a full page keeps hasMore true', () async {
      var page = 0;
      responder = (_, _, _) async {
        page++;
        return page == 1
            ? _page(['aaaaaa11'])
            : _page(List.generate(20, (i) => 'page2${i.toString().padLeft(3, '0')}'));
      };
      final (container, _) = await containerFor(_alice);
      await container.read(gameBookmarksPaginatorProvider.future);
      final notifier = container.read(gameBookmarksPaginatorProvider.notifier);

      await notifier.getNext();

      final state = container.read(gameBookmarksPaginatorProvider).requireValue;
      expect(state.gameList.length, 21);
      expect(state.hasMore, isTrue);
    });

    test('an empty page stops paging without duplicating the current list', () async {
      var page = 0;
      responder = (_, _, _) async {
        page++;
        return page == 1 ? _page(['aaaaaa11']) : _page(const []);
      };
      final (container, _) = await containerFor(_alice);
      await container.read(gameBookmarksPaginatorProvider.future);
      final notifier = container.read(gameBookmarksPaginatorProvider.notifier);

      await notifier.getNext();

      final state = container.read(gameBookmarksPaginatorProvider).requireValue;
      expect(state.gameList.map((e) => e.game.id), equals([const GameId('aaaaaa11')]));
      expect(state.hasMore, isFalse);
      expect(state.isLoading, isFalse);
    });

    test('a failed page sets hasError and clears isLoading but keeps the old list', () async {
      var page = 0;
      responder = (_, _, _) async {
        page++;
        if (page == 2) throw StateError('network down');
        return _page(['aaaaaa11']);
      };
      final (container, _) = await containerFor(_alice);
      await container.read(gameBookmarksPaginatorProvider.future);
      final notifier = container.read(gameBookmarksPaginatorProvider.notifier);

      await notifier.getNext();

      final state = container.read(gameBookmarksPaginatorProvider).requireValue;
      expect(state.gameList.map((e) => e.game.id), equals([const GameId('aaaaaa11')]));
      expect(state.hasError, isTrue);
      expect(state.isLoading, isFalse);
    });

    test('a signed-out paginator does not fetch a next page', () async {
      final (container, _) = await containerFor(null);
      await container.read(gameBookmarksPaginatorProvider.future);
      final notifier = container.read(gameBookmarksPaginatorProvider.notifier);

      await notifier.getNext();

      expect(calls, isEmpty);
    });
  });

  group('GameBookmarksPaginator.removeBookmark', () {
    test('removes the matching game and ignores an unknown id', () async {
      responder = (_, _, _) async => _page(['aaaaaa11', 'bbbbbb22']);
      final (container, _) = await containerFor(_alice);
      await container.read(gameBookmarksPaginatorProvider.future);
      final notifier = container.read(gameBookmarksPaginatorProvider.notifier);

      notifier.removeBookmark(const GameId('aaaaaa11'));

      final afterRemove = container.read(gameBookmarksPaginatorProvider).requireValue;
      expect(afterRemove.gameList.map((e) => e.game.id), equals([const GameId('bbbbbb22')]));

      notifier.removeBookmark(const GameId('unknown0'));

      expect(
        container.read(gameBookmarksPaginatorProvider).requireValue.gameList,
        same(afterRemove.gameList),
        reason: 'an unknown id must not replace the state',
      );
    });
  });

  test('switching account rebuilds with only the new account bookmarks', () async {
    responder = (user, _, _) async => user == _alice ? _page(['aaaaaa11']) : _page(['cccccc33']);
    final (container, auth) = await containerFor(_alice);
    await container.read(gameBookmarksPaginatorProvider.future);
    expect(
      container.read(gameBookmarksPaginatorProvider).requireValue.gameList.map((e) => e.game.id),
      equals([const GameId('aaaaaa11')]),
    );

    auth.user = _bob;
    await pumpEventQueue();

    expect(
      container.read(gameBookmarksPaginatorProvider).requireValue.gameList.map((e) => e.game.id),
      equals([const GameId('cccccc33')]),
      reason: 'the accumulated list is cleared when the provider rebuilds',
    );
  });
}
