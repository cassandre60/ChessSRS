// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:chess_srs/src/model/auth/auth_controller.dart';
import 'package:chess_srs/src/model/auth/auth_repository.dart';
import 'package:chess_srs/src/model/auth/auth_storage.dart';
import 'package:chess_srs/src/model/common/id.dart';
import 'package:chess_srs/src/model/user/user.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderContainer;
import 'package:flutter_test/flutter_test.dart';

import '../../test_container.dart';

/// Records what the app asked it to do, and answers with whatever the test decides.
class _FakeAuthStorage extends AuthStorage {
  AuthUser? storedUser;
  int deleteCalls = 0;

  @override
  Future<AuthUser?> read() async => storedUser;

  @override
  Future<void> write(AuthUser authUser) async => storedUser = authUser;

  @override
  Future<void> delete() async {
    storedUser = null;
    deleteCalls++;
  }
}

class _FakeAuthRepository extends Fake implements AuthRepository {
  _FakeAuthRepository({this.onCheckToken, this.onSignIn});

  /// Answer to `/api/token/test`. Defaults to "still valid".
  Future<bool> Function(AuthUser user)? onCheckToken;

  /// Account returned by the sign-in flow.
  Future<AuthUser> Function()? onSignIn;

  int checkTokenCalls = 0;
  AuthUser? checkedUser;

  @override
  Future<bool> checkToken(AuthUser authUser) {
    checkTokenCalls++;
    checkedUser = authUser;
    if (onCheckToken != null) return onCheckToken!(authUser);
    return Future.value(true);
  }

  @override
  Future<AuthUser> signIn() {
    if (onSignIn != null) return onSignIn!();
    throw UnimplementedError();
  }
}

const alice = AuthUser(
  token: 'aliceToken',
  user: LightUser(id: UserId('alice'), name: 'alice'),
);
const bob = AuthUser(
  token: 'bobToken',
  user: LightUser(id: UserId('bob'), name: 'bob'),
);

void main() {
  /// A container starting as [current], with [storage] and [repo] wired in.
  ///
  /// [storage] is seeded with [current] because that is the session a launch would find: the
  /// controller's state comes from `preloadedDataProvider`, but the token check clears *storage*,
  /// and the two are only the same session if storage was seeded to match.
  Future<ProviderContainerHandle> startingAs(
    AuthUser? current, {
    required _FakeAuthStorage storage,
    required _FakeAuthRepository repo,
  }) async {
    final container = await makeContainer(
      authUser: current,
      overrides: {
        authStorageProvider: authStorageProvider.overrideWithValue(storage),
        authRepositoryProvider: authRepositoryProvider.overrideWithValue(repo),
      },
    );

    // `authControllerProvider` is `autoDispose`, and a bare read of an autoDispose provider with no
    // listener is collected immediately -- at which point `ref.mounted` is false inside
    // `checkToken` and it returns without doing anything. The tests would then pass for the wrong
    // reason: the check would simply never run.
    final subscription = container.listen<AuthUser?>(authControllerProvider, (_, _) {});
    addTearDown(subscription.close);

    return ProviderContainerHandle(container);
  }

  group('startup token check', () {
    test('clears a session the server no longer recognises', () async {
      final storage = _FakeAuthStorage()..storedUser = alice;
      final repo = _FakeAuthRepository(onCheckToken: (_) async => false);
      final handle = await startingAs(alice, storage: storage, repo: repo);

      await handle.runStartupCheck();

      expect(repo.checkedUser?.token, alice.token, reason: 'the stored session is the one tested');
      expect(handle.authUser, isNull, reason: 'the user is signed out');
      expect(storage.deleteCalls, 1);
      expect(storage.storedUser, isNull);
    });

    test('keeps a session the server still recognises', () async {
      final storage = _FakeAuthStorage()..storedUser = alice;
      final repo = _FakeAuthRepository();
      final handle = await startingAs(alice, storage: storage, repo: repo);

      await handle.runStartupCheck();

      expect(handle.authUser, alice);
      expect(storage.deleteCalls, 0);
      expect(storage.storedUser, alice);
    });

    // The regression this change exists for.
    test('a sign-in during the check is not signed out by its result', () async {
      final inFlight = Completer<bool>();
      final storage = _FakeAuthStorage()..storedUser = alice;
      final repo = _FakeAuthRepository(
        // Alice's token really is no longer valid. The question is what happens to Bob, who signed
        // in while this was still pending.
        onCheckToken: (_) => inFlight.future,
        onSignIn: () async => bob,
      );
      final handle = await startingAs(alice, storage: storage, repo: repo);

      final check = handle.runStartupCheck();

      // Bob signs in before Alice's validation comes back.
      await handle.signIn();
      expect(handle.authUser, bob);
      expect(storage.storedUser, bob);

      inFlight.complete(false);
      await check;

      expect(handle.authUser, bob, reason: "alice's stale validation must not clear bob's session");
      expect(
        storage.deleteCalls,
        0,
        reason: 'storage holds one session, and deleting it would sign bob out',
      );
      expect(storage.storedUser, bob);
    });

    // The safety rule from the `catchError` of the code this replaced, and the one most worth
    // pinning: being unable to reach lichess is not evidence that the token is bad.
    test('a network error keeps the token', () async {
      final storage = _FakeAuthStorage()..storedUser = alice;
      final repo = _FakeAuthRepository(onCheckToken: (_) async => throw Exception('offline'));
      final handle = await startingAs(alice, storage: storage, repo: repo);

      // Completes rather than rethrowing. `http.dart` depends on `checkToken` rethrowing so its
      // 401 path is unchanged, which puts the swallow here instead -- and a launch that cannot
      // reach lichess must not look like an invalid session.
      await handle.runStartupCheck();

      expect(handle.authUser, alice);
      expect(storage.deleteCalls, 0);
      expect(storage.storedUser, alice);
    });

    test('does nothing when no session is stored', () async {
      final storage = _FakeAuthStorage();
      final repo = _FakeAuthRepository();
      final handle = await startingAs(null, storage: storage, repo: repo);

      await handle.runStartupCheck();

      expect(repo.checkTokenCalls, 0, reason: 'a signed-out app has no token to validate');
      expect(storage.deleteCalls, 0);
    });
  });
}

/// Keeps the `container`/`authUser` pair readable without repeating `read` at every assertion.
class ProviderContainerHandle {
  ProviderContainerHandle(this.container);

  final ProviderContainer container;

  AuthUser? get authUser => container.read(authControllerProvider);

  /// Awaits the startup check the way the app's own lifecycle eventually does.
  ///
  /// The check is fire-and-forget by design -- the app is usable while it runs -- so awaiting the
  /// provider's future here is the seam, not a behaviour the app promises.
  Future<void> runStartupCheck() => container.read(startupTokenCheckProvider.future);

  Future<void> signIn() => container.read(authControllerProvider.notifier).signIn();
}
