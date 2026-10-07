// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC coverage: INV-007.

import 'package:chess_srs/src/model/auth/auth_controller.dart';
import 'package:chess_srs/src/model/common/id.dart';
import 'package:chess_srs/src/model/common/preloaded_data.dart';
import 'package:chess_srs/src/model/user/user.dart';
import 'package:chess_srs/src/network/http.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../network/fake_http_client_factory.dart';
import '../../test_container.dart';

/// A stale token validation must not sign out the account that is actually signed in.
///
/// The app has one active session, so a 401 arriving for a request made under a *previous*
/// account will eventually be validated — and when that validation comes back invalid, the
/// naive behaviour is to clear whatever is signed in now. That signs out the wrong person: the
/// user is mid-way through using the app as themselves and a leftover request from before
/// their last sign-in silently logs them out.
///
/// [AuthController.checkToken] fences on both the controller's generation and the identity of the
/// token it was asked about, so the clear is dropped unless the very session that was validated
/// is still current. Nothing tested that, and it is the kind of guard a refactor removes
/// without noticing — so it is pinned here.
void main() {
  const alice = AuthUser(
    token: 'aliceToken',
    user: LightUser(id: UserId('alice'), name: 'alice'),
  );
  const bob = AuthUser(
    token: 'bobToken',
    user: LightUser(id: UserId('bob'), name: 'bob'),
  );

  /// A container already signed in as [current], with a server that considers [invalid]'s token
  /// no longer valid.
  /// The session the app starts as. [AuthController.build] reads the starting user from here, so
  /// this is how a test starts as one account without driving the OAuth browser flow.
  Override startingAs(AuthUser user) => preloadedDataProvider.overrideWith((ref) {
    return (
      sri: 'test-sri',
      packageInfo: PackageInfo(
        appName: 'chess_srs_test',
        version: '0.0.0',
        buildNumber: '0',
        packageName: 'chess_srs_test',
      ),
      deviceInfo: BaseDeviceInfo({
        'name': 'test',
        'model': 'test',
        'manufacturer': 'test',
        'systemName': 'test',
        'systemVersion': 'test',
        'identifierForVendor': 'test',
        'isPhysicalDevice': true,
      }),
      authUser: user,
      engineMaxMemoryInMb: 256,
      appDocumentsDirectory: null,
      appSupportDirectory: null,
    );
  });

  Future<ProviderContainer> containerWhere({required AuthUser current, required AuthUser invalid}) {
    final client = MockClient((request) async {
      if (request.url.path == '/api/token/test') {
        // An empty value for the token under test is what "no longer valid" looks like: the
        // endpoint answers with the tokens it still recognises.
        return http.Response('{"${invalid.token}": null}', 200);
      }
      return http.Response('', 404);
    });

    return makeContainer(
      overrides: {
        httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
          (ref) => FakeHttpClientFactory(() => client),
        ),
        preloadedDataProvider: startingAs(current),
      },
    );
  }

  /// Keeps [authControllerProvider] alive for the duration of a test.
  ///
  /// It is `autoDispose`, and a bare `read` of an autoDispose provider with no listener collects
  /// it immediately — at which point `ref.mounted` is false inside [AuthController.checkToken]
  /// and it returns before doing anything. Without this the fencing tests pass for the wrong
  /// reason: checkToken simply never runs.
  void keepAuthAlive(ProviderContainer container) {
    final subscription = container.listen<AuthUser?>(authControllerProvider, (_, _) {});
    addTearDown(subscription.close);
  }

  group('checkToken identity fencing', () {
    test('a stale validation does not sign out the account now signed in', () async {
      final container = await containerWhere(current: bob, invalid: alice);
      addTearDown(container.dispose);
      keepAuthAlive(container);

      final auth = container.read(authControllerProvider.notifier);
      expect(container.read(authControllerProvider)?.user.id, const UserId('bob'));

      // Bob is signed in. A request made while Alice was signed in comes back 401, and the
      // handler validates Alice's token — which really is no longer valid.
      await auth.checkToken(alice);
      await pumpEventQueue();

      expect(
        container.read(authControllerProvider)?.user.id,
        const UserId('bob'),
        reason: "alice's expired token must not clear bob's session",
      );
    });

    test('a validation for the account now signed in does clear it', () async {
      final container = await containerWhere(current: bob, invalid: bob);
      addTearDown(container.dispose);
      keepAuthAlive(container);

      final auth = container.read(authControllerProvider.notifier);
      expect(container.read(authControllerProvider)?.user.id, const UserId('bob'));

      await auth.checkToken(bob);
      await pumpEventQueue();

      // The counterpart, so the test above cannot pass by checkToken simply never clearing
      // anything. This is the behaviour the fence has to preserve, not suppress.
      expect(
        container.read(authControllerProvider),
        isNull,
        reason: 'the signed-in account is told its own token is invalid, so it is signed out',
      );
    });

    test('concurrent validations for one token are not run twice', () async {
      var calls = 0;
      final client = MockClient((request) async {
        if (request.url.path == '/api/token/test') {
          calls++;
          return http.Response('{"${alice.token}": "alice"}', 200);
        }
        return http.Response('', 404);
      });

      final container = await makeContainer(
        overrides: {
          httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
            (ref) => FakeHttpClientFactory(() => client),
          ),
          preloadedDataProvider: startingAs(alice),
        },
      );
      addTearDown(container.dispose);
      keepAuthAlive(container);

      final auth = container.read(authControllerProvider.notifier);
      await Future.wait([auth.checkToken(alice), auth.checkToken(alice)]);
      await pumpEventQueue();

      expect(
        calls,
        1,
        reason: 'a burst of 401s for one token is one validation, not one per response',
      );
    });
  });
}
