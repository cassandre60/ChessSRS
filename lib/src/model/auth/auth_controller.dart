import 'dart:async';

import 'package:chess_srs/src/model/auth/auth_repository.dart';
import 'package:chess_srs/src/model/auth/auth_storage.dart';
import 'package:chess_srs/src/model/auth/auth_user.dart';
import 'package:chess_srs/src/model/common/preloaded_data.dart';
import 'package:flutter_riverpod/experimental/mutation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

export 'auth_user.dart';

enum AuthEvent { signIn, signOut }

final _authEventsController = StreamController<AuthEvent>.broadcast();

Stream<AuthEvent> get authEventsStream => _authEventsController.stream;

/// A provider for [AuthController].
final authControllerProvider = NotifierProvider.autoDispose<AuthController, AuthUser?>(
  AuthController.new,
  name: 'AuthControllerProvider',
);

/// A provider that indicates whether the user is logged in.
final isLoggedInProvider = Provider.autoDispose<bool>((Ref ref) {
  return ref.watch(authControllerProvider.select((authUser) => authUser != null));
}, name: 'IsLoggedInProvider');

final signInMutation = Mutation<void>();
final signOutMutation = Mutation<void>();

/// Mutation for requesting the login code email.
final emailLoginCodeRequestMutation = Mutation<void>();

/// Mutation for exchanging the login code for a session.
final emailLoginCodeSignInMutation = Mutation<void>();

class AuthController extends Notifier<AuthUser?> {
  int _generation = 0;
  final Map<String, Future<bool>> _inFlightTokenChecks = {};

  @override
  AuthUser? build() {
    return ref.read(preloadedDataProvider).requireValue.authUser;
  }

  /// Signs in the user with the OAuth browser flow.
  Future<void> signIn() async {
    final generation = ++_generation;
    final authRepo = ref.read(authRepositoryProvider);
    final authUser = await authRepo.signIn();
    await _onSignedIn(authUser, generation);
  }

  /// Asks lichess to email a login code for the [username] account to [email].
  Future<void> requestEmailLoginCode({required String username, required String email}) {
    return ref.read(authRepositoryProvider).requestEmailLoginCode(username: username, email: email);
  }

  /// Signs in the user on the [username] account with the login code they received by [email].
  Future<void> signInWithEmailCode({
    required String username,
    required String email,
    required String code,
  }) async {
    final generation = ++_generation;
    final authRepo = ref.read(authRepositoryProvider);
    final authUser = await authRepo.signInWithEmailCode(
      username: username,
      email: email,
      code: code,
    );
    await _onSignedIn(authUser, generation);
  }

  Future<void> _onSignedIn(AuthUser authUser, int generation) async {
    if (generation != _generation) return;
    final authStorage = ref.read(authStorageProvider);
    await authStorage.write(authUser);

    if (!ref.mounted || generation != _generation) return;
    state = authUser;

    _authEventsController.add(AuthEvent.signIn);
  }

  /// Signs out the user.
  Future<void> signOut() async {
    final userToSignOut = state;
    if (userToSignOut == null) return;
    final generation = ++_generation;
    final authRepo = ref.read(authRepositoryProvider);
    final authStorage = ref.read(authStorageProvider);

    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (generation != _generation) return;

    _authEventsController.add(AuthEvent.signOut);
    try {
      await authRepo.signOut(userToSignOut);
    } catch (_) {
      // Best-effort remote revocation
    }
    if (generation != _generation) return;

    await authStorage.delete();
    if (!ref.mounted || generation != _generation) return;
    state = null;
  }

  /// Checks if the given or current authUser token is still valid.
  ///
  /// If the token is invalid, it deletes the authUser from storage if it is still active.
  Future<void> checkToken([AuthUser? targetUser]) async {
    final userToCheck = targetUser ?? state;
    if (userToCheck == null) {
      return;
    }

    final token = userToCheck.token;
    final generation = _generation;
    final authRepo = ref.read(authRepositoryProvider);
    final authStorage = ref.read(authStorageProvider);

    final checkFuture = _inFlightTokenChecks.putIfAbsent(
      token,
      () => authRepo.checkToken(userToCheck),
    );

    bool isValid;
    try {
      isValid = await checkFuture;
    } finally {
      _inFlightTokenChecks.remove(token);
    }

    if (!isValid) {
      if (!ref.mounted || generation != _generation || state?.token != token) {
        return;
      }
      await authStorage.delete();
      if (!ref.mounted || generation != _generation || state?.token != token) {
        return;
      }
      state = null;
    }
  }
}

/// Validates the stored session token once, at startup.
///
/// This is the only startup token check. It delegates to [AuthController.checkToken] rather than
/// reimplementing it, because that method already refuses to act on a stale result: it fences on
/// both the controller's generation and the identity of the token it was asked about. The copy this
/// replaces had no such fence and called `authStorage.delete()` directly, so it deleted whichever
/// session was stored when the response arrived — including one established by a sign-in that
/// happened while the request was in flight.
///
/// Not `autoDispose`, because it is a one-shot that must survive having no listener: it is read
/// once from `Application.initState` and then nothing holds it.
///
/// A network error keeps the token. [AuthController.checkToken] rethrows, because `http.dart`
/// relies on that when a request 401s, so the swallow has to live here — a launch that cannot reach
/// lichess must not look like an invalid session.
final startupTokenCheckProvider = FutureProvider<void>((Ref ref) async {
  final authUser = ref.watch(preloadedDataProvider).value?.authUser;
  if (authUser == null) return;

  try {
    await ref.read(authControllerProvider.notifier).checkToken(authUser);
  } catch (_) {
    // Network error: assume the session is still valid, as the check this replaced did.
  }
}, name: 'StartupTokenCheckProvider');
