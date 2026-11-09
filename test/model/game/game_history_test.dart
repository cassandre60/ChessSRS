// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/model/account/account_repository.dart';
import 'package:chess_srs/src/model/auth/auth_controller.dart';
import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chess_srs/src/model/common/id.dart';
import 'package:chess_srs/src/model/common/perf.dart';
import 'package:chess_srs/src/model/common/speed.dart';
import 'package:chess_srs/src/model/game/exported_game.dart';
import 'package:chess_srs/src/model/game/game.dart';
import 'package:chess_srs/src/model/game/game_filter.dart';
import 'package:chess_srs/src/model/game/game_history.dart';
import 'package:chess_srs/src/model/game/game_repository.dart';
import 'package:chess_srs/src/model/game/game_status.dart';
import 'package:chess_srs/src/model/game/game_storage.dart';
import 'package:chess_srs/src/model/game/player.dart';
import 'package:chess_srs/src/model/user/user.dart';
import 'package:dartchess/dartchess.dart' show Side;
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override, ProviderOrFamily;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../test_container.dart';

class MockGameRepository extends Mock implements GameRepository {}

class MockGameStorage extends Mock implements GameStorage {}

/// An auth controller a test can sign in and out of, so a rebuild can be provoked the way
/// signing out of one account and into another does in the app.
class _SwitchableAuth extends AuthController {
  @override
  AuthUser? build() => null;

  // ignore: avoid_setters_without_getters
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

const _myHistory = (userId: null, filter: GameFilterState());

LightExportedGameWithPov _game(String id) => (
  game: LightExportedGame(
    id: GameId(id),
    source: GameSource.lobby,
    rated: false,
    speed: Speed.classical,
    perf: Perf.classical,
    createdAt: DateTime.utc(2021),
    lastMoveAt: DateTime.utc(2021),
    status: GameStatus.mate,
    white: const Player(name: 'Alice'),
    black: const Player(name: 'Bob'),
    variant: Variant.standard,
    winner: Side.white,
  ),
  pov: Side.white,
);

void main() {
  late MockGameRepository repository;

  /// The games each account's history is served from, so a leak between them is visible.
  final histories = <String, IList<LightExportedGameWithPov>>{
    'alice': [_game('aaaaaa11'), _game('bbbbbb22')].toIList(),
    'bob': [_game('cccccc33')].toIList(),
  };

  setUpAll(() {
    // `any(named: 'filter')` needs something of the type to hand back when a call does not
    // match the stub.
    registerFallbackValue(const GameFilterState());
  });

  setUp(() {
    repository = MockGameRepository();
    when(
      () => repository.getUserGames(
        any(),
        max: any(named: 'max'),
        until: any(named: 'until'),
        filter: any(named: 'filter'),
        withBookmarked: any(named: 'withBookmarked'),
        withMoves: any(named: 'withMoves'),
      ),
    ).thenAnswer((invocation) async {
      final userId = invocation.positionalArguments.first as UserId;
      return histories[userId.toString()] ?? const <Never>[].toIList();
    });
  });

  Future<(ProviderContainer, _SwitchableAuth)> containerFor(
    Map<ProviderOrFamily, Override> overrides,
  ) async {
    final container = await makeContainer(
      overrides: {
        gameRepositoryProvider: gameRepositoryProvider.overrideWithValue(repository),
        authControllerProvider: authControllerProvider.overrideWith(_SwitchableAuth.new),
        ...overrides,
      },
    );
    final auth = container.read(authControllerProvider.notifier) as _SwitchableAuth;
    return (container, auth);
  }

  group('UserGameHistoryNotifier', () {
    test("switching account does not leave the previous account's games on screen", () async {
      // A guard, not a regression test for a fixed bug: the audit reported that the accumulated
      // list survived a rebuild, so signing in as somebody else appended to the games already
      // there. It does not, because `ref.onDispose` — which clears the list — also fires when a
      // provider rebuilds, not only when it is destroyed. Verified by instrumenting a notifier
      // that watches a dependency: the instance is reused across the rebuild, yet the list it
      // accumulates into holds only the newest build's entry.
      //
      // Kept because the reason it is correct is not visible from the code. The list is a field
      // on the notifier, so it looks like the kind of thing that leaks between accounts, and the
      // next reader should not have to re-derive this to find out.
      final (container, auth) = await containerFor({});
      addTearDown(container.dispose);

      final provider = userGameHistoryProvider(_myHistory);
      // autoDispose: something has to be listening or the notifier is collected unread.
      final sub = container.listen(provider, (_, _) {});
      addTearDown(sub.close);

      auth.user = _alice;
      await container.read(provider.future);
      expect(container.read(provider).requireValue.gameList.map((e) => e.game.id), [
        const GameId('aaaaaa11'),
        const GameId('bbbbbb22'),
      ]);

      // The same notifier instance serves both accounts; only its build re-runs.
      final notifier = container.read(provider.notifier);

      auth.user = _bob;
      await pumpEventQueue();

      expect(container.read(provider.notifier), same(notifier));
      expect(container.read(provider).requireValue.gameList.map((e) => e.game.id), [
        const GameId('cccccc33'),
      ], reason: "bob's history must be his games alone, not alice's followed by his");
    });
  });

  group('UserNumberOfGamesProvider', () {
    test('uses the account count for a logged-in user when online and the server is up', () async {
      const accountUser = User(
        id: UserId('alice'),
        username: 'alice',
        perfs: IMap.empty(),
        count: UserGameCount(all: 42, bookmark: 0),
      );

      final storage = MockGameStorage();
      when(() => storage.count(userId: any(named: 'userId'))).thenAnswer((_) async => 7);

      final container = await makeContainer(
        authUser: _alice,
        overrides: {
          accountProvider: accountProvider.overrideWith((ref) => accountUser),
          gameStorageProvider: gameStorageProvider.overrideWith((ref) => storage),
        },
      );
      addTearDown(container.dispose);

      final sub = container.listen(userNumberOfGamesProvider(null), (_, _) {});
      addTearDown(sub.close);

      final count = await container.read(userNumberOfGamesProvider(null).future);
      expect(count, 42);

      verifyNever(() => storage.count(userId: any(named: 'userId')));
    });
  });
}
