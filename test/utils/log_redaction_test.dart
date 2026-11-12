import 'package:chess_srs/src/utils/log_redaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('redactUriForLogging', () {
    test('returns the same Uri instance when nothing is sensitive', () {
      final uri = Uri.parse('https://lichess.org/api/account?variant=standard');

      expect(identical(redactUriForLogging(uri), uri), isTrue);
    });

    test('redacts sensitive query parameters case-insensitively', () {
      final uri = Uri.parse('https://lichess.org/auth?Token=abc&EMAIL=user%40example.com&keep=1');

      final redacted = redactUriForLogging(uri);

      expect(redacted.queryParameters['Token'], kRedactedLogValue);
      expect(redacted.queryParameters['EMAIL'], kRedactedLogValue);
      expect(redacted.queryParameters['keep'], '1');
      expect(redacted.host, 'lichess.org');
      expect(redacted.path, '/auth');
    });

    test('preserves repeated sensitive parameter cardinality', () {
      final uri = Uri.parse('https://lichess.org/auth?token=a&token=b&tag=x&tag=y');

      final redacted = redactUriForLogging(uri);

      expect(redacted.queryParametersAll['token'], [kRedactedLogValue, kRedactedLogValue]);
      expect(redacted.queryParametersAll['tag'], ['x', 'y']);
    });

    test('keeps already-redacted sensitive values unchanged', () {
      final uri = Uri.parse('https://lichess.org/auth?token=$kRedactedLogValue');

      final redacted = redactUriForLogging(uri);

      expect(identical(redacted, uri), isTrue);
      expect(redacted.queryParameters['token'], kRedactedLogValue);
    });

    test('redacts the credential segment for secret-bearing path prefixes', () {
      final uri = Uri.parse('https://lichess.org/mobile/register/firebase/fcm-secret-token/device');

      final redacted = redactUriForLogging(uri);

      expect(redacted.pathSegments, [
        'mobile',
        'register',
        'firebase',
        kRedactedLogValue,
        'device',
      ]);
      expect(redacted.host, 'lichess.org');
    });

    test('redacts both secret-bearing path segments and sensitive query params', () {
      final uri = Uri.parse(
        'https://lichess.org/mobile/register/firebase/fcm-secret-token?token=abc&safe=ok',
      );

      final redacted = redactUriForLogging(uri);

      expect(redacted.pathSegments, ['mobile', 'register', 'firebase', kRedactedLogValue]);
      expect(redacted.queryParameters['token'], kRedactedLogValue);
      expect(redacted.queryParameters['safe'], 'ok');
    });

    test('does not redact when path only matches the prefix without a credential segment', () {
      final uri = Uri.parse('https://lichess.org/mobile/register/firebase');

      expect(identical(redactUriForLogging(uri), uri), isTrue);
    });
  });

  group('redactLogText', () {
    test('returns text unchanged when embedded URL has no credentials', () {
      const text = 'GET https://lichess.org/api/account?variant=standard -> 200';

      expect(redactLogText(text), text);
    });

    test('redacts credentials inside embedded absolute URLs', () {
      const text = 'POST https://lichess.org/login?token=secret&x=1 failed';

      expect(redactLogText(text), 'POST https://lichess.org/login?token=%2A%2A%2A&x=1 failed');
    });

    test('preserves surrounding brackets and trailing punctuation', () {
      const text = 'error=[https://lichess.org/auth?code=abc], next';

      expect(redactLogText(text), 'error=[https://lichess.org/auth?code=%2A%2A%2A], next');
    });

    test('redacts embedded relative path URLs', () {
      const text = 'request /mobile/register/firebase/fcm-token/device timed out';

      expect(redactLogText(text), 'request mobile/register/firebase/***/device timed out');
    });

    test('withholds unparseable URL-like candidates instead of leaking them', () {
      const text = 'bad url https://[::1?token=secret in log';

      expect(redactLogText(text), 'bad url $kRedactedLogValue in log');
    });
  });
}
