import 'dart:async';

import 'package:chess_srs/src/model/auth/auth_controller.dart';
import 'package:chess_srs/src/model/auth/auth_repository.dart';
import 'package:chess_srs/src/model/auth/auth_storage.dart';
import 'package:chess_srs/src/model/common/id.dart';
import 'package:chess_srs/src/model/user/user.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_container.dart';

class _FakeAuthStorage extends AuthStorage {
  AuthUser? storedUser;
  int deleteCalls = 0;
  int writeCalls = 0;

  @override
  Future<AuthUser?> read() async => storedUser;

  @override
  Future<void> write(AuthUser authUser) async {
    storedUser = authUser;
    writeCalls++;
  }

  @override
  Future<void> delete() async {
    storedUser = null;
    deleteCalls++;
  }
}

class _FakeAuthRepository extends Fake implements AuthRepository {
  _FakeAuthRepository({this.onCheckToken, this.onSignIn});

  Future<bool> Function(AuthUser user)? onCheckToken;
  Future<AuthUser> Function()? onSignIn;

  int checkTokenCalls = 0;
  AuthUser? signedOutUser;

  @override
  Future<bool> checkToken(AuthUser authUser) {
    checkTokenCalls++;
    if (onCheckToken != null) {
      return onCheckToken!(authUser);
    }
    return Future.value(true);
  }

  @override
  Future<void> signOut([AuthUser? authUser]) async {
    signedOutUser = authUser;
  }

  @override
  Future<AuthUser> signIn() {
    if (onSignIn != null) {
      return onSignIn!();
    }
    throw UnimplementedError();
  }
}

const userA = AuthUser(
  token: 'token-a',
  user: LightUser(id: UserId('user-a'), name: 'User A'),
);

const userB = AuthUser(
  token: 'token-b',
  user: LightUser(id: UserId('user-b'), name: 'User B'),
);

void main() {
  test('checkToken clears state and storage when token is invalid', () async {
    final fakeStorage = _FakeAuthStorage()..storedUser = userA;
    final fakeRepo = _FakeAuthRepository(onCheckToken: (_) async => false);

    final container = await makeContainer(
      authUser: userA,
      overrides: {
        authStorageProvider: authStorageProvider.overrideWithValue(fakeStorage),
        authRepositoryProvider: authRepositoryProvider.overrideWithValue(fakeRepo),
      },
    );
    final sub = container.listen(authControllerProvider, (_, _) {});
    addTearDown(sub.close);

    final controller = container.read(authControllerProvider.notifier);
    expect(container.read(authControllerProvider), userA);

    await controller.checkToken();

    expect(container.read(authControllerProvider), isNull);
    expect(fakeStorage.deleteCalls, 1);
  });

  test('checkToken does not clear state if account changed while check was in-flight', () async {
    final completer = Completer<bool>();
    final fakeStorage = _FakeAuthStorage()..storedUser = userA;
    final fakeRepo = _FakeAuthRepository(
      onCheckToken: (_) => completer.future,
      onSignIn: () async => userB,
    );

    final container = await makeContainer(
      authUser: userA,
      overrides: {
        authStorageProvider: authStorageProvider.overrideWithValue(fakeStorage),
        authRepositoryProvider: authRepositoryProvider.overrideWithValue(fakeRepo),
      },
    );
    final sub = container.listen(authControllerProvider, (_, _) {});
    addTearDown(sub.close);

    final controller = container.read(authControllerProvider.notifier);

    // Start checking token for userA
    final checkFuture = controller.checkToken(userA);

    // While in-flight, user signs into userB
    await controller.signIn();
    expect(container.read(authControllerProvider), userB);
    expect(fakeStorage.storedUser, userB);

    // userA's checkToken returns false (invalid)
    completer.complete(false);
    await checkFuture;

    // Verify userB is still active and storage was NOT deleted
    expect(container.read(authControllerProvider), userB);
    expect(fakeStorage.storedUser, userB);
    expect(fakeStorage.deleteCalls, 0);
  });

  test('checkToken deduplicates concurrent checks for the same token', () async {
    final completer = Completer<bool>();
    final fakeRepo = _FakeAuthRepository(onCheckToken: (_) => completer.future);

    final container = await makeContainer(
      authUser: userA,
      overrides: {authRepositoryProvider: authRepositoryProvider.overrideWithValue(fakeRepo)},
    );
    final sub = container.listen(authControllerProvider, (_, _) {});
    addTearDown(sub.close);

    final controller = container.read(authControllerProvider.notifier);

    final check1 = controller.checkToken(userA);
    final check2 = controller.checkToken(userA);

    expect(fakeRepo.checkTokenCalls, 1);

    completer.complete(true);
    await Future.wait([check1, check2]);

    expect(fakeRepo.checkTokenCalls, 1);
  });

  test('signOut revokes token and clears state and storage', () async {
    final fakeStorage = _FakeAuthStorage()..storedUser = userA;
    final fakeRepo = _FakeAuthRepository();

    final container = await makeContainer(
      authUser: userA,
      overrides: {
        authStorageProvider: authStorageProvider.overrideWithValue(fakeStorage),
        authRepositoryProvider: authRepositoryProvider.overrideWithValue(fakeRepo),
      },
    );
    final sub = container.listen(authControllerProvider, (_, _) {});
    addTearDown(sub.close);

    final controller = container.read(authControllerProvider.notifier);
    await controller.signOut();

    expect(container.read(authControllerProvider), isNull);
    expect(fakeStorage.deleteCalls, 1);
    expect(fakeRepo.signedOutUser, userA);
  });

  test('signOut does not clear state if new sign-in completed during sign-out delay', () async {
    final fakeStorage = _FakeAuthStorage()..storedUser = userA;
    final fakeRepo = _FakeAuthRepository(onSignIn: () async => userB);

    final container = await makeContainer(
      authUser: userA,
      overrides: {
        authStorageProvider: authStorageProvider.overrideWithValue(fakeStorage),
        authRepositoryProvider: authRepositoryProvider.overrideWithValue(fakeRepo),
      },
    );
    final sub = container.listen(authControllerProvider, (_, _) {});
    addTearDown(sub.close);

    final controller = container.read(authControllerProvider.notifier);

    // The sign-out's 500ms delay is a timer, so the wait runs on the fake clock: the sign-in
    // lands inside the delay window and the stale sign-out must not undo it.
    fakeAsync((async) {
      var signedIn = false;
      var signedOut = false;

      // Trigger signOut: it records the user and bumps the generation synchronously, then parks
      // on its 500ms delay — so by the time this call returns the timer is already running.
      unawaited(controller.signOut().then((_) => signedOut = true));

      // Immediately sign in as userB before the 500ms expires
      unawaited(controller.signIn().then((_) => signedIn = true));
      async.flushMicrotasks();
      expect(signedIn, isTrue, reason: 'the sign-in lands while the sign-out is still parked');
      expect(container.read(authControllerProvider), userB);

      // Let the sign-out's delay expire on the fake clock: its generation is stale by now.
      async.elapse(const Duration(milliseconds: 500));
      async.flushMicrotasks();
      expect(signedOut, isTrue, reason: 'the stale sign-out has run to its end');

      // Verify userB was not wiped out by userA's stale signOut
      expect(container.read(authControllerProvider), userB);
      expect(fakeStorage.storedUser, userB);
      expect(fakeStorage.deleteCalls, 0);
      expect(
        fakeRepo.signedOutUser,
        isNull,
        reason: "a superseded signOut must not revoke anyone's token",
      );
    });
  });

  test('retains authUser state when all listeners are closed', () async {
    final fakeStorage = _FakeAuthStorage();
    final fakeRepo = _FakeAuthRepository(onSignIn: () async => userA);
    final container = await makeContainer(
      overrides: {
        authStorageProvider: authStorageProvider.overrideWithValue(fakeStorage),
        authRepositoryProvider: authRepositoryProvider.overrideWithValue(fakeRepo),
      },
    );
    final sub = container.listen(authControllerProvider, (_, _) {});

    // Initially null
    expect(container.read(authControllerProvider), isNull);

    // Sign in as userA
    await container.read(authControllerProvider.notifier).signIn();
    expect(container.read(authControllerProvider), userA);

    // Close listener (simulates user leaving screen)
    sub.close();
    // A deterministic settle, not a timed wait: one turn for any disposal close() could have
    // scheduled, before asserting the state survived it — an absence a poll cannot express.
    await pumpEventQueue();

    // Must still be userA!
    expect(container.read(authControllerProvider), userA);
  });
}
