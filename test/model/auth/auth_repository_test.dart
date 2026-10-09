// SPEC coverage: INV-006.

import 'package:chess_srs/src/model/auth/auth_repository.dart';
import 'package:chess_srs/src/model/auth/bearer.dart';
import 'package:chess_srs/src/network/http.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';

import '../../network/fake_http_client_factory.dart';
import '../../test_container.dart';
import '../../test_helpers.dart';

const _accountResponse =
    '{"id":"test","username":"test","createdAt":1290415680000,"seenAt":1290415680000,"perfs":{}}';

/// Scopes Lichess owns for its own signed clients, which no other `client_id` may request.
///
/// Kept in the test as well as the source so the two cannot drift apart silently.
const _clientOwnedScopes = {'web:mobile', 'web:polygon'};

/// Fake [FlutterAppAuth] that returns a canned token response (or throws) instead of opening a real
/// browser session and performing the OAuth code exchange.
class FakeFlutterAppAuth implements FlutterAppAuth {
  FakeFlutterAppAuth(this.onAuthorize);

  final Future<AuthorizationTokenResponse> Function(AuthorizationTokenRequest request) onAuthorize;

  @override
  Future<AuthorizationTokenResponse> authorizeAndExchangeCode(AuthorizationTokenRequest request) =>
      onAuthorize(request);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AuthorizationTokenResponse tokenResponse({String? accessToken = 'test-token'}) =>
    AuthorizationTokenResponse(accessToken, null, null, null, 'Bearer', null, null, null);

FlutterAppAuthUserCancelledException userCancelled() => FlutterAppAuthUserCancelledException(
  code: 'user_cancelled',
  platformErrorDetails: FlutterAppAuthPlatformErrorDetails(),
);

MockClient accountClient() => MockClient((request) {
  switch (request.url.path) {
    case '/api/account':
      return mockResponse(_accountResponse, 200);
    default:
      return mockResponse('', 404);
  }
});

/// Container for the email login flow, which needs no [FlutterAppAuth].
Future<ProviderContainer> emailLoginContainer(MockClientHandler handler) {
  return makeContainer(
    overrides: {
      httpClientFactoryProvider: httpClientFactoryProvider.overrideWith((ref) {
        return FakeHttpClientFactory(() => MockClient(handler));
      }),
    },
  );
}

Future<ProviderContainer> appAuthContainer(MockClient mockClient, FlutterAppAuth appAuth) {
  return makeContainer(
    overrides: {
      httpClientFactoryProvider: httpClientFactoryProvider.overrideWith((ref) {
        return FakeHttpClientFactory(() => mockClient);
      }),
      appAuthProvider: appAuthProvider.overrideWith((ref) => appAuth),
    },
  );
}

void main() {
  // A real failure, owner-reported 2026-10-08: signing in on a device returned Lichess's
  // "Bad authorization request / Invalid scopes". The mobile path went through
  // flutter_appauth, which put `scope=web:mobile` on the authorize URL; that scope belongs to the
  // official `lichess_mobile` client, so any other `client_id` is refused with HTTP 400.
  //
  // The desktop flow, meanwhile, sent no `scope` at all -- which is why only the device failed,
  // and why "remove the scope" looked like a fix last time: it cured the desktop symptom without
  // noticing that the mobile path was asking for a scope it can never be granted. The scopes this
  // app *can* ask for are the ones its own endpoints need (see [oauthScopes]).
  //
  // The regression tests are on the URI the app builds, not on a network call: opening a real
  // browser is not something a test can do, but the query is exactly what the server reads.
  test('the desktop OAuth URI asks only for a scope Lichess accepts', () {
    final uri = buildDesktopOAuthUri(
      clientId: 'chesssrs.test',
      redirectUri: 'http://127.0.0.1:1234/callback',
      codeChallenge: 'challenge',
    );

    final scope = uri.queryParameters['scope'];
    if (scope != null) {
      for (final requested in scope.split(RegExp(r'[\s+]+'))) {
        expect(
          oauthScopes,
          contains(requested),
          reason:
              'Lichess answers "bad scope" for anything outside $oauthScopes, and web:mobile / '
              'web:polygon are answered with "Invalid scopes" because they belong to Lichess\'s '
              'own signed clients',
        );
      }
    }
  });

  test('the mobile flow never asks for a scope Lichess reserves for its own clients', () {
    // The exact defect: `scope=web:mobile` from `client_id=chess_srs` is a 400, so the account
    // never reaches the authorize screen and sign-in cannot complete on any device.
    expect(oauthScopes, isNotEmpty);
    expect(
      oauthScopes,
      isNot(anyElement(isIn(_clientOwnedScopes))),
      reason:
          'Lichess reserves these scopes for its own signed clients and refuses any other '
          'client_id that asks for one with "Invalid scopes"',
    );
  });

  test('the mobile flow asks for the study and preference scopes its endpoints need', () {
    // Lichess checks the `scope` parameter against its own scope set. These three are valid
    // scopes, and each one is an endpoint this app calls while signed in:
    // study:read -> GET /api/study/:id.pgn, study:write -> POST /api/study/:id/import-pgn,
    // preference:read -> GET /api/account/preferences.
    expect(oauthScopes, containsAll(['study:read', 'study:write', 'preference:read']));
  });

  test('the desktop OAuth URI carries PKCE and the redirect', () {
    final uri = buildDesktopOAuthUri(
      clientId: 'chesssrs.test',
      redirectUri: 'http://127.0.0.1:1234/callback',
      codeChallenge: 'challenge',
    );

    expect(uri.path, '/oauth');
    expect(uri.queryParameters['response_type'], 'code');
    expect(uri.queryParameters['client_id'], 'chesssrs.test');
    expect(uri.queryParameters['redirect_uri'], 'http://127.0.0.1:1234/callback');
    expect(uri.queryParameters['code_challenge'], 'challenge');
    expect(uri.queryParameters['code_challenge_method'], 'S256');
  });

  group('AuthRepository.signIn', () {
    test('returns the authenticated user on success', () async {
      final container = await appAuthContainer(
        accountClient(),
        FakeFlutterAppAuth((request) async => tokenResponse()),
      );
      final authUser = await container.read(authRepositoryProvider).signIn();

      expect(authUser.token, 'test-token');
      expect(authUser.user.name, 'test');
    });

    test('requests the custom-scheme redirect URI', () async {
      String? redirectUrl;
      final container = await appAuthContainer(
        accountClient(),
        FakeFlutterAppAuth((request) async {
          redirectUrl = request.redirectUrl;
          return tokenResponse();
        }),
      );
      await container.read(authRepositoryProvider).signIn();

      expect(redirectUrl, kOAuthRedirectUri);
      expect(redirectUrl, startsWith('org.chesssrs.app://'));
    });

    test('requests scopes Lichess will grant this client', () async {
      // flutter_appauth serialises this list into the authorize URL's `scope` parameter, so
      // whatever is here is what decides whether the authorize screen renders at all. A single
      // reserved `web:*` entry turns the whole request into a 400 "Invalid scopes".
      List<String>? requestedScopes;
      final container = await appAuthContainer(
        accountClient(),
        FakeFlutterAppAuth((request) async {
          requestedScopes = request.scopes;
          return tokenResponse();
        }),
      );
      await container.read(authRepositoryProvider).signIn();

      expect(requestedScopes, oauthScopes);
      expect(requestedScopes, isNot(anyElement(isIn(_clientOwnedScopes))));
      expect(requestedScopes, containsAll(['study:read', 'study:write', 'preference:read']));
    });

    test('throws SignInCancelledException when the user cancels the auth session', () async {
      final container = await appAuthContainer(
        accountClient(),
        FakeFlutterAppAuth((request) async => throw userCancelled()),
      );

      await expectLater(
        container.read(authRepositoryProvider).signIn(),
        throwsA(isA<SignInCancelledException>()),
      );
    });

    test('rethrows non-cancellation errors', () async {
      final container = await appAuthContainer(
        accountClient(),
        FakeFlutterAppAuth((request) async => throw Exception('authorization failed')),
      );

      await expectLater(
        container.read(authRepositoryProvider).signIn(),
        throwsA(
          isA<Exception>().having(
            (e) => e,
            'is not a cancellation',
            isNot(isA<SignInCancelledException>()),
          ),
        ),
      );
    });

    test('throws when no access token is returned', () async {
      final container = await appAuthContainer(
        accountClient(),
        FakeFlutterAppAuth((request) async => tokenResponse(accessToken: null)),
      );

      await expectLater(container.read(authRepositoryProvider).signIn(), throwsA(isA<Exception>()));
    });
  });

  group('AuthRepository.requestEmailLoginCode', () {
    test('posts the email and username in the body', () async {
      Uri? requestedUrl;
      Map<String, String>? requestedBody;
      final container = await emailLoginContainer((request) {
        requestedUrl = request.url;
        requestedBody = request.bodyFields;
        return mockResponse('', 204);
      });

      await container
          .read(authRepositoryProvider)
          .requestEmailLoginCode(username: 'johndoe', email: 'johndoe@lichess.org');

      expect(requestedUrl?.path, '/auth/mobile-code/email');
      expect(requestedUrl?.hasQuery, isFalse);
      expect(requestedBody, {'email': 'johndoe@lichess.org', 'username': 'johndoe'});
    });

    test('throws EmailLoginRateLimitException on 429', () async {
      final container = await emailLoginContainer((request) => mockResponse('', 429));

      await expectLater(
        container
            .read(authRepositoryProvider)
            .requestEmailLoginCode(username: 'johndoe', email: 'johndoe@lichess.org'),
        throwsA(isA<EmailLoginRateLimitException>()),
      );
    });

    test('throws a ServerException on other errors', () async {
      final container = await emailLoginContainer((request) => mockResponse('', 500));

      await expectLater(
        container
            .read(authRepositoryProvider)
            .requestEmailLoginCode(username: 'johndoe', email: 'johndoe@lichess.org'),
        throwsA(isA<ServerException>()),
      );
    });

    test('falls back to query parameters if the server returns 404 to body-only request', () async {
      final requests = <Uri>[];
      final container = await emailLoginContainer((request) {
        requests.add(request.url);
        if (!request.url.hasQuery) {
          return mockResponse('', 404);
        }
        return mockResponse('', 204);
      });

      await container
          .read(authRepositoryProvider)
          .requestEmailLoginCode(username: 'johndoe', email: 'johndoe@lichess.org');

      expect(requests, hasLength(2));
      expect(requests.first.hasQuery, isFalse);
      expect(requests.last.queryParameters, {
        'email': 'johndoe@lichess.org',
        'username': 'johndoe',
      });
    });
  });

  group('AuthRepository.signInWithEmailCode', () {
    test('exchanges the code for a token and returns the authenticated user', () async {
      Uri? requestedUrl;
      Map<String, String>? requestedBody;
      final container = await emailLoginContainer((request) {
        switch (request.url.path) {
          case '/auth/mobile-code/bearer':
            requestedUrl = request.url;
            requestedBody = request.bodyFields;
            return mockResponse('lio_token', 200);
          case '/api/account':
            return mockResponse(_accountResponse, 200);
          default:
            return mockResponse('', 404);
        }
      });

      final authUser = await container
          .read(authRepositoryProvider)
          .signInWithEmailCode(username: 'johndoe', email: 'johndoe@lichess.org', code: 'xxxxxx');

      expect(requestedUrl?.hasQuery, isFalse);
      expect(requestedBody, {
        'email': 'johndoe@lichess.org',
        'username': 'johndoe',
        'code': 'xxxxxx',
      });
      expect(authUser.token, 'lio_token');
      expect(authUser.user.name, 'test');
    });

    test('sends the signed token when fetching the account', () async {
      String? authorization;
      final container = await emailLoginContainer((request) {
        switch (request.url.path) {
          case '/auth/mobile-code/bearer':
            return mockResponse('lio_token', 200);
          case '/api/account':
            authorization = request.headers['Authorization'];
            return mockResponse(_accountResponse, 200);
          default:
            return mockResponse('', 404);
        }
      });

      await container
          .read(authRepositoryProvider)
          .signInWithEmailCode(username: 'johndoe', email: 'johndoe@lichess.org', code: 'xxxxxx');

      expect(authorization, 'Bearer ${signBearerToken('lio_token')}');
    });

    test('throws InvalidEmailLoginCodeException on 404', () async {
      final container = await emailLoginContainer((request) => mockResponse('', 404));

      await expectLater(
        container
            .read(authRepositoryProvider)
            .signInWithEmailCode(username: 'johndoe', email: 'johndoe@lichess.org', code: 'expire'),
        throwsA(isA<InvalidEmailLoginCodeException>()),
      );
    });

    test('throws EmailLoginRateLimitException on 429', () async {
      final container = await emailLoginContainer((request) => mockResponse('', 429));

      await expectLater(
        container
            .read(authRepositoryProvider)
            .signInWithEmailCode(username: 'johndoe', email: 'johndoe@lichess.org', code: 'xxxxxx'),
        throwsA(isA<EmailLoginRateLimitException>()),
      );
    });

    test('throws when the response body holds no token', () async {
      final container = await emailLoginContainer((request) => mockResponse('  ', 200));

      await expectLater(
        container
            .read(authRepositoryProvider)
            .signInWithEmailCode(username: 'johndoe', email: 'johndoe@lichess.org', code: 'xxxxxx'),
        throwsA(isA<Exception>()),
      );
    });

    test('falls back to query parameters if the server returns 404 to body-only request', () async {
      final requests = <Uri>[];
      final container = await emailLoginContainer((request) {
        switch (request.url.path) {
          case '/auth/mobile-code/bearer':
            requests.add(request.url);
            if (!request.url.hasQuery) {
              return mockResponse('', 404);
            }
            return mockResponse('lio_token', 200);
          case '/api/account':
            return mockResponse(_accountResponse, 200);
          default:
            return mockResponse('', 404);
        }
      });

      final authUser = await container
          .read(authRepositoryProvider)
          .signInWithEmailCode(username: 'johndoe', email: 'johndoe@lichess.org', code: 'xxxxxx');

      expect(requests, hasLength(2));
      expect(requests.first.hasQuery, isFalse);
      expect(requests.last.queryParameters, {
        'email': 'johndoe@lichess.org',
        'username': 'johndoe',
        'code': 'xxxxxx',
      });
      expect(authUser.token, 'lio_token');
    });
  });
}
