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

  /// When set, [write] parks until it is completed — the seam that lets a test
  /// bump the controller's generation *during* a storage write, which is the
  /// only window in which `_onSignedIn`'s second fence can be observed.
  ///
  /// FIFO: successive writes park on successive gates, so a test can stage
  /// two in-flight sign-ins and bump the generation between their writes.
  final List<Completer<void>> writeGates = <Completer<void>>[];

  /// When set, [delete] parks until it is completed — the seam that lets a
  /// test bump the controller's generation *during* a storage delete, the only
  /// window in which signOut's and checkToken's second fences can be observed
  /// after their first guards have already passed.
  Completer<void>? deleteGate;

  @override
  Future<AuthUser?> read() async => storedUser;

  @override
  Future<void> write(AuthUser authUser) async {
    if (writeGates.isNotEmpty) {
      await writeGates.removeAt(0).future;
    }
    storedUser = authUser;
    writeCalls++;
  }

  @override
  Future<void> delete() async {
    final gate = deleteGate;
    if (gate != null) {
      await gate.future;
    }
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

  test('isLoggedInProvider tracks the signed-in state', () async {
    // MUTATION-14 survivor: the select inverted (`!= null` -> `== null`)
    // survived the mapped suite because no test ever read the boolean.
    final fakeStorage = _FakeAuthStorage()..storedUser = userA;
    final fakeRepo = _FakeAuthRepository();
    final container = await makeContainer(
      authUser: userA,
      overrides: {
        authStorageProvider: authStorageProvider.overrideWithValue(fakeStorage),
        authRepositoryProvider: authRepositoryProvider.overrideWithValue(fakeRepo),
      },
    );
    final sub = container.listen(isLoggedInProvider, (_, _) {});
    addTearDown(sub.close);

    expect(container.read(isLoggedInProvider), isTrue, reason: 'the container starts signed in');

    await container.read(authControllerProvider.notifier).signOut();

    expect(container.read(isLoggedInProvider), isFalse, reason: 'signing out flips the flag');
  });

  test('a stale sign-in parked mid-write does not clobber the newer session', () async {
    // MUTATION-14 survivor (the `_onSignedIn` fence): weakened to `&&` it lets
    // a superseded sign-in proceed while the notifier is still mounted. The
    // bump is staged *during* the stale sign-in's storage write — the only
    // window in which the second fence runs after the first one passed.
    const userC = AuthUser(
      token: 'token-c',
      user: LightUser(id: UserId('user-c'), name: 'User C'),
    );
    final fakeStorage = _FakeAuthStorage()..storedUser = userA;
    var signInCalls = 0;
    // Created inside fakeAsync below (zone-native completers): a future
    // completes in its creation zone, so a completer made outside the fake
    // zone would resume the controller outside `flushMicrotasks`' reach.
    Completer<AuthUser>? staleAnswer;
    final fakeRepo = _FakeAuthRepository(
      onSignIn: () => signInCalls++ == 0 ? staleAnswer!.future : Future.value(userB),
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

    fakeAsync((async) {
      // Zone-native completers: both writes park on these gates, the stale
      // sign-in on its repo answer. Local references — the fake consumes the
      // writeGates queue as writes start.
      final gate1 = Completer<void>();
      final gate2 = Completer<void>();
      fakeStorage.writeGates.addAll([gate1, gate2]);
      staleAnswer = Completer<AuthUser>();

      // Stale sign-in: parks on its repo answer.
      final staleSignIn = controller.signIn();
      async.flushMicrotasks();
      // Its answer arrives: it passes the first fence (generation still
      // current) and parks inside its storage write, on gate 1.
      staleAnswer!.complete(userC);
      async.flushMicrotasks();
      expect(fakeStorage.writeCalls, 0, reason: 'the stale write is parked on gate 1');

      // The newer sign-in bumps the generation and parks its own write on gate 2.
      final newerSignIn = controller.signIn();
      async.flushMicrotasks();
      expect(fakeStorage.writeCalls, 0, reason: 'the newer write is parked on gate 2');

      // Release gate 1: the stale write lands, and the stale `_onSignedIn`
      // reaches its second fence against the bumped generation.
      gate1.complete();
      async.flushMicrotasks();
      expect(fakeStorage.storedUser, userC, reason: 'gate 1 released: the stale write landed');

      // Original: the fence returns — userC never reaches the state while the
      // newer sign-in is still parked. Under the `&&` mutant the stale sign-in
      // proceeds and clobbers the state with the superseded session.
      expect(
        container.read(authControllerProvider),
        userA,
        reason: 'the stale sign-in must not clobber the state',
      );

      // Release gate 2: the newer sign-in applies normally.
      gate2.complete();
      async.flushMicrotasks();
      expect(container.read(authControllerProvider), userB);
      expect(fakeStorage.storedUser, userB);
      staleSignIn.ignore();
      newerSignIn.ignore();
    });
  });

  test('a stale sign-out parked mid-delete does not clear the newer session', () async {
    // MUTATION-14 survivor (the signOut fence): weakened to `&&` it clears the
    // state even though a newer generation owns it. The bump is staged
    // *during* the stale sign-out's storage delete — past the delay fence and
    // the post-revocation fence, in the only window before the final one.
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

    fakeAsync((async) {
      // The stale sign-out's storage delete parks on the gate.
      final deleteGate = Completer<void>();
      fakeStorage.deleteGate = deleteGate;

      // signOut bumps the generation and parks on its 500ms delay.
      final staleSignOut = controller.signOut();
      async.elapse(const Duration(milliseconds: 500));
      async.flushMicrotasks();
      expect(fakeStorage.deleteCalls, 0, reason: 'the delete is parked on the gate');

      // A newer sign-in lands while the stale sign-out is parked mid-delete.
      unawaited(controller.signIn());
      async.flushMicrotasks();
      expect(container.read(authControllerProvider), userB, reason: 'the newer session landed');

      // Release the delete: it clears storage, then the stale sign-out reaches
      // its final fence against the bumped generation.
      deleteGate.complete();
      async.flushMicrotasks();
      expect(fakeStorage.deleteCalls, 1, reason: 'the stale sign-out completed its delete');

      // Original: the fence returns — userB survives the stale sign-out. Under
      // the `&&` mutant the sign-out proceeds and nulls the newer session.
      expect(
        container.read(authControllerProvider),
        userB,
        reason: 'the stale sign-out must not clear the newer session',
      );
      staleSignOut.ignore();
    });
  });

  test('a stale token check for the unchanged session does not clear it', () async {
    // MUTATION-14 survivor (the checkToken fence's `&&` variant): with the
    // generation stale but the session unchanged, the fence must still return
    // — only a genuinely mismatched token may reach the clearing path.
    final inFlight = Completer<bool>();
    final signInGate = Completer<AuthUser>();
    final fakeStorage = _FakeAuthStorage()..storedUser = userA;
    var signInCalls = 0;
    final fakeRepo = _FakeAuthRepository(
      onCheckToken: (_) => inFlight.future,
      onSignIn: () => signInCalls++ == 0 ? signInGate.future : Future.value(userB),
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

    final check = controller.checkToken(userA);
    // The sign-in bumps the generation but never lands: state keeps userA's
    // token, so the token-mismatch clause stays false.
    final staleSignIn = controller.signIn();
    inFlight.complete(false);
    await check;

    expect(fakeStorage.deleteCalls, 0, reason: 'a stale fence must not delete the stored session');
    expect(container.read(authControllerProvider), userA);
    expect(fakeStorage.storedUser, userA);

    signInGate.complete(userB);
    await staleSignIn;
  });

  test('checkToken does not clear state when the generation bumps during its delete', () async {
    // MUTATION-14 survivor (the checkToken fence's second `&&` variant): the
    // fence runs again after the storage delete; a generation bump staged
    // *during* that delete must stop the state clearing, even though the
    // token still matches.
    final inFlight = Completer<bool>();
    final fakeStorage = _FakeAuthStorage()..storedUser = userA;
    final deleteGate = Completer<void>();
    fakeStorage.deleteGate = deleteGate;
    final fakeRepo = _FakeAuthRepository(
      onCheckToken: (_) => inFlight.future,
      onSignIn: () async => userA, // the same session re-signs in: same token, newer generation
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

    final check = controller.checkToken(userA);
    inFlight.complete(false);
    // The verdict is invalid; the first fence passes (mounted, generation
    // current, token matching) and the storage delete parks on the gate.
    await pumpEventQueue();
    expect(fakeStorage.deleteCalls, 0, reason: 'the delete is parked on the gate');

    // While the delete is parked, the same session re-signs in: a newer
    // generation over the same token.
    await controller.signIn();
    expect(container.read(authControllerProvider), userA);

    // The delete lands; the second fence must see the bumped generation.
    deleteGate.complete();
    await check;

    expect(fakeStorage.deleteCalls, 1, reason: 'the delete itself ran');
    expect(
      container.read(authControllerProvider),
      userA,
      reason: 'the invalid verdict predates the newer generation',
    );
  });
}
