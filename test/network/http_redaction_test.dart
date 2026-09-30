// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:chess_srs/src/network/http.dart';
import 'package:flutter_test/flutter_test.dart';

/// The redaction helper, over the shapes it actually has to handle.
///
/// Asserted on what the value does *not* contain rather than on the exact output, so the
/// placeholder can change without rewriting these. The one thing pinned exactly is that an
/// ordinary URL is returned untouched: a helper that blanks harmless parameters would quietly
/// make every log in the app less useful, and nobody would notice.
void main() {
  group('redactUriForLogging', () {
    test('leaves an ordinary request exactly as it was', () {
      final uri = Uri.parse(
        'https://lichess.dev/api/games/user/alice?max=20&moves=true&lastFen=true',
      );

      expect(redactUriForLogging(uri), equals(uri));
    });

    test('leaves a path with no credentials untouched', () {
      final uri = Uri.parse('https://lichess.dev/api/puzzle/batch/AbCdEf');

      expect(redactUriForLogging(uri), equals(uri));
    });

    test('redacts the one-time login code', () {
      final redacted = redactUriForLogging(
        Uri.parse('https://lichess.dev/auth/mobile-code/bearer?code=123456&username=alice'),
      );

      expect(redacted.toString(), isNot(contains('123456')));
      expect(redacted.queryParameters['code'], kRedactedLogValue);
    });

    test('redacts the email address and username', () {
      final redacted = redactUriForLogging(
        Uri.parse('https://lichess.dev/auth/mobile-code/email?email=a%40b.com&username=alice'),
      );

      expect(redacted.toString(), isNot(contains('a%40b.com')));
      expect(redacted.toString(), isNot(contains('alice')));
    });

    test('redacts the FCM token carried in the path', () {
      final redacted = redactUriForLogging(
        Uri.parse('https://lichess.dev/mobile/register/firebase/cMsT0kEnVaLuE123'),
      );

      expect(redacted.toString(), isNot(contains('cMsT0kEnVaLuE123')));
      // The route is what makes the log worth having, so it survives.
      expect(redacted.path, '/mobile/register/firebase/$kRedactedLogValue');
    });

    test('keeps diagnostic parameters while redacting the secret beside them', () {
      final redacted = redactUriForLogging(
        Uri.parse('https://lichess.dev/auth/mobile-code/email?username=alice&email=a%40b.com'),
      );

      // Nothing to keep in this one, so check the shape on a request that has both kinds.
      expect(redacted.path, '/auth/mobile-code/email');

      final mixed = redactUriForLogging(
        Uri.parse('https://lichess.dev/api/games/user/alice?max=20&token=sekrit&moves=true'),
      );
      expect(mixed.queryParameters['max'], '20');
      expect(mixed.queryParameters['moves'], 'true');
      expect(mixed.queryParameters['token'], kRedactedLogValue);
      expect(mixed.toString(), isNot(contains('sekrit')));
    });

    test('matches the parameter name case-insensitively', () {
      final redacted = redactUriForLogging(
        Uri.parse('https://lichess.dev/x?Code=123456&EMAIL=a%40b.com'),
      );

      expect(redacted.toString(), isNot(contains('123456')));
      expect(redacted.toString(), isNot(contains('a%40b.com')));
    });

    test('is idempotent, so redacting twice cannot double-encode', () {
      final once = redactUriForLogging(
        Uri.parse('https://lichess.dev/auth/mobile-code/bearer?code=123456'),
      );

      expect(redactUriForLogging(once), equals(once));
    });

    test('does not redact a path that merely starts with the same words', () {
      // The prefix rule is a route, not a substring: a token-shaped segment elsewhere on the API
      // is not a credential this app puts in a URL.
      final uri = Uri.parse('https://lichess.dev/api/mobile/register/firebase');

      expect(redactUriForLogging(uri), equals(uri));
    });

    test('handles a relative URI, which is how the FCM registration is built', () {
      final redacted = redactUriForLogging(Uri.parse('/mobile/register/firebase/tok3n'));

      expect(redacted.toString(), isNot(contains('tok3n')));
    });
  });

  group('every logged URL goes through the helper', () {
    // The end-to-end version of this — drive a real request and read `http_log` back to assert
    // the secret is absent — is not reachable here: http.dart returns from its onRequest hook
    // when FLUTTER_TEST is set, precisely so the suite does not fill the log tables, so no row is
    // ever written under test. Removing that guard to enable the test would make every test in
    // the suite write log rows.
    //
    // What is left is the thing that actually rots: a new logging site added to http.dart later
    // that interpolates the URL directly. That is a one-line scan with no false positives, unlike
    // trying to classify every query parameter in the app.
    test('no unredacted request URL is logged or stored in http.dart', () {
      final source = File('lib/src/network/http.dart').readAsStringSync();

      for (final pattern in {
        r'\$\{request\.url\}': r'${request.url}',
        r'requestUrl: request\.url': 'requestUrl: request.url',
      }.entries) {
        expect(
          source,
          isNot(matches(RegExp(pattern.key))),
          reason:
              'a request URL reaches a log or the http_log row without redactUriForLogging. '
              'Wrap it: ${pattern.value.replaceAll(r'$', '')} would store the credential',
        );
      }
    });
  });
}
