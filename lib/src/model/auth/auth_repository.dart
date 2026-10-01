import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:chess_srs/src/constants.dart';
import 'package:chess_srs/src/model/auth/auth_user.dart';
import 'package:chess_srs/src/model/auth/bearer.dart';
import 'package:chess_srs/src/model/auth/sign_in_failure_reporter.dart';
import 'package:chess_srs/src/model/user/user.dart';
import 'package:chess_srs/src/network/http.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:url_launcher/url_launcher.dart';

/// Host of the custom URI scheme callback. Must stay in sync with the
/// intent-filter for `net.openid.appauth.RedirectUriReceiverActivity` in
/// `android/app/src/main/AndroidManifest.xml` and the `CFBundleURLSchemes` entry in `ios/Runner/Info.plist`.
const _kOAuthCustomSchemeCallbackHost = 'login-callback';

/// The custom URI scheme redirect for OAuth.
///
/// Custom schemes are more universally supported across Android browsers/OEMs than
/// HTTPS App Link redirects, so they are used on every platform and host.
const kOAuthRedirectUri = '$kLichessCustomUriSchemeName://$_kOAuthCustomSchemeCallbackHost';
const oauthScopes = ['web:mobile'];

/// Thrown when the user dismisses the OAuth session before completing it.
///
/// This is distinct from a genuine sign-in failure: the UI should silently
/// ignore it rather than surfacing an error.
class SignInCancelledException implements Exception {
  const SignInCancelledException();

  @override
  String toString() => 'Sign-in was cancelled.';
}

/// Thrown when the server rate-limits one of the email login requests (429).
class EmailLoginRateLimitException implements Exception {
  const EmailLoginRateLimitException();

  @override
  String toString() => 'Too many email login requests.';
}

/// Thrown when the submitted login code is unknown, expired, or already used (404).
class InvalidEmailLoginCodeException implements Exception {
  const InvalidEmailLoginCodeException();

  @override
  String toString() => 'Invalid or expired email login code.';
}

/// A provider for [FlutterAppAuth].
final appAuthProvider = Provider<FlutterAppAuth>((Ref ref) {
  return const FlutterAppAuth();
}, name: 'AppAuthProvider');

final authRepositoryProvider = Provider<AuthRepository>((Ref ref) {
  final appAuth = ref.read(appAuthProvider);
  return AuthRepository(ref, appAuth);
}, name: 'AuthRepositoryProvider');

class AuthRepository {
  AuthRepository(Ref ref, FlutterAppAuth appAuth) : _ref = ref, _appAuth = appAuth;

  final Ref _ref;
  final Logger _log = Logger('AuthRepository');
  final FlutterAppAuth _appAuth;

  LichessClient get _client => _ref.read(lichessClientProvider);

  /// Sign in with Lichess using OAuth 2.0 PKCE using the system browser.
  Future<AuthUser> signIn() async {
    if (defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return await _desktopSignIn();
    }

    final AuthorizationTokenResponse authResp;
    try {
      authResp = await _appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          kLichessClientId,
          kOAuthRedirectUri,
          allowInsecureConnections: kDebugMode,
          serviceConfiguration: AuthorizationServiceConfiguration(
            authorizationEndpoint: lichessUri('/oauth').toString(),
            tokenEndpoint: lichessUri('/api/token').toString(),
          ),
          scopes: oauthScopes,
        ),
      );
    } on FlutterAppAuthUserCancelledException {
      throw const SignInCancelledException();
    } catch (e, st) {
      await reportSignInFailure(_ref, e, st);
      rethrow;
    }

    _log.fine('Got OAuth token response');

    final token = authResp.accessToken;
    if (token == null) {
      throw Exception('Access token not found.');
    }

    return await _fetchAuthUser(token);
  }

  /// Desktop loopback OAuth PKCE flow using the system browser.
  Future<AuthUser> _desktopSignIn() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    try {
      final redirectUri = 'http://127.0.0.1:${server.port}/callback';

      final random = Random.secure();
      final verifierBytes = List<int>.generate(32, (_) => random.nextInt(256));
      final codeVerifier = base64UrlEncode(verifierBytes).replaceAll('=', '');
      final challengeBytes = sha256.convert(ascii.encode(codeVerifier)).bytes;
      final codeChallenge = base64UrlEncode(challengeBytes).replaceAll('=', '');

      final authUri = lichessUri('/oauth', {
        'response_type': 'code',
        'client_id': kLichessClientId,
        'redirect_uri': redirectUri,
        'code_challenge': codeChallenge,
        'code_challenge_method': 'S256',
        'scope': 'study:read study:write preference:read',
      });

      if (!await launchUrl(authUri, mode: LaunchMode.externalApplication)) {
        throw Exception('Could not launch system browser for authentication.');
      }

      final request = await server.first.timeout(
        const Duration(minutes: 5),
        onTimeout: () => throw const SignInCancelledException(),
      );

      final code = request.uri.queryParameters['code'];
      final error = request.uri.queryParameters['error'];

      final response = request.response;
      response.headers.contentType = ContentType.html;
      if (code != null) {
        response.write('''
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>ChessSRS Sign In</title></head>
<body style="font-family: system-ui, sans-serif; text-align: center; padding: 48px; background: #141416; color: #f4f4f5;">
  <h2 style="margin-bottom: 8px;">Authorization successful!</h2>
  <p style="color: #a1a1aa;">You can close this window and return to ChessSRS.</p>
</body>
</html>
''');
      } else {
        response.write('''
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>ChessSRS Sign In</title></head>
<body style="font-family: system-ui, sans-serif; text-align: center; padding: 48px; background: #141416; color: #f4f4f5;">
  <h2 style="margin-bottom: 8px;">Authorization was cancelled.</h2>
  <p style="color: #a1a1aa;">You can close this window and return to ChessSRS.</p>
</body>
</html>
''');
      }
      await response.close();

      if (error == 'access_denied') {
        throw const SignInCancelledException();
      }
      if (code == null) {
        throw Exception('Authorization code missing from callback: $error');
      }

      final tokenUri = lichessUri('/api/token');
      final tokenResponse = await _ref
          .read(defaultClientProvider)
          .post(
            tokenUri,
            body: {
              'grant_type': 'authorization_code',
              'code': code,
              'code_verifier': codeVerifier,
              'redirect_uri': redirectUri,
              'client_id': kLichessClientId,
            },
          );

      if (tokenResponse.statusCode >= 400) {
        throw ServerException(
          tokenResponse.statusCode,
          'Could not exchange authorization code: ${tokenResponse.statusCode}',
          tokenUri,
          null,
        );
      }

      final json = jsonDecode(tokenResponse.body) as Map<String, dynamic>;
      final token = json['access_token'] as String?;
      if (token == null) {
        throw Exception('Access token not found in response.');
      }

      _log.fine('Got desktop OAuth token response');

      return await _fetchAuthUser(token);
    } catch (e, st) {
      if (e is! SignInCancelledException) {
        await reportSignInFailure(_ref, e, st);
      }
      rethrow;
    } finally {
      await server.close(force: true);
    }
  }

  /// Asks lichess to email a 6 character login code for the [username] account to [email].
  ///
  /// Throws an [EmailLoginRateLimitException] if the request is rate-limited.
  Future<void> requestEmailLoginCode({required String username, required String email}) async {
    final url = lichessUri('/auth/mobile-code/email');
    // First try sending credentials in the form body (avoids proxy log leakage).
    var response = await _ref
        .read(defaultClientProvider)
        .post(url, body: {'email': email, 'username': username});

    // If server rejects with 404/400 because it only reads the query string (Lila's
    // queryStringGet("email")), fall back to query parameters.
    if (response.statusCode == 404 || response.statusCode == 400) {
      response = await _ref
          .read(defaultClientProvider)
          .post(
            lichessUri('/auth/mobile-code/email', {'email': email, 'username': username}),
            body: {'email': email, 'username': username},
          );
    }

    if (response.statusCode == 429) {
      throw const EmailLoginRateLimitException();
    }
    if (response.statusCode >= 400) {
      throw ServerException(
        response.statusCode,
        'Could not request an email login code: ${response.statusCode}',
        url,
        null,
      );
    }
  }

  /// Exchanges the login [code] received by [email] for an OAuth token on the [username] account,
  /// and fetches the account it belongs to.
  ///
  /// Throws an [InvalidEmailLoginCodeException] if the code is unknown, expired, or already used,
  /// and an [EmailLoginRateLimitException] if the request is rate-limited.
  Future<AuthUser> signInWithEmailCode({
    required String username,
    required String email,
    required String code,
  }) async {
    final url = lichessUri('/auth/mobile-code/bearer');
    // First try sending credentials in the body.
    var response = await _ref
        .read(defaultClientProvider)
        .post(url, body: {'email': email, 'username': username, 'code': code});

    // If server returns 404 because it only reads the query string (Lila's
    // queryStringGet("code")), fall back to query parameters.
    if (response.statusCode == 404) {
      response = await _ref
          .read(defaultClientProvider)
          .post(
            lichessUri('/auth/mobile-code/bearer', {
              'email': email,
              'username': username,
              'code': code,
            }),
            body: {'email': email, 'username': username, 'code': code},
          );
    }

    switch (response.statusCode) {
      case 429:
        throw const EmailLoginRateLimitException();
      case 404:
        throw const InvalidEmailLoginCodeException();
    }
    if (response.statusCode >= 400) {
      throw ServerException(
        response.statusCode,
        'Could not exchange the email login code: ${response.statusCode}',
        url,
        null,
      );
    }

    final token = response.body.trim();
    if (token.isEmpty) {
      throw Exception('Access token not found.');
    }

    _log.fine('Got a token from the email login code');

    return await _fetchAuthUser(token);
  }

  /// Fetches the account owning [token] and pairs it with the token.
  Future<AuthUser> _fetchAuthUser(String token) async {
    final user = await _client.readJson(
      Uri(path: '/api/account'),
      headers: {'Authorization': 'Bearer ${signBearerToken(token)}'},
      mapper: User.fromServerJson,
    );
    return AuthUser(token: token, user: user.lightUser);
  }

  /// Sign out the given or current user by revoking the auth token.
  Future<void> signOut([AuthUser? authUser]) async {
    final headers = authUser != null
        ? {'Authorization': 'Bearer ${signBearerToken(authUser.token)}'}
        : null;
    await _client.deleteRead(Uri(path: '/api/token'), headers: headers);
  }

  /// Check if the given authUser token is valid.
  Future<bool> checkToken(AuthUser authUser) async {
    final defaultClient = _ref.read(defaultClientProvider);
    final data = await defaultClient
        .postReadJson(lichessUri('/api/token/test'), mapper: (json) => json, body: authUser.token)
        .timeout(const Duration(seconds: 5));
    return data[authUser.token] != null;
  }
}
