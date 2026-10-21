// SPEC coverage: INV-006 (what may reach a log) and INV-008 (only the main host is
// first-party). The other behaviours pinned below -- the download path, the ND-JSON
// readers, the request-log levels, the client's deadline -- have no SPEC invariant
// yet: they are pinned so that a change which breaks them fails a test.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chess_srs/src/constants.dart';
import 'package:chess_srs/src/model/auth/auth_controller.dart';
import 'package:chess_srs/src/model/auth/bearer.dart';
import 'package:chess_srs/src/model/common/id.dart';
import 'package:chess_srs/src/model/user/user.dart';
import 'package:chess_srs/src/network/http.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';

import '../test_container.dart';
import 'fake_http_client_factory.dart';

void main() {
  setUp(() {
    FakeClient.reset();
  });

  group('shouldRetryOn429', () {
    http.Response response(int status, {String method = 'GET', String path = '/api/test'}) {
      return http.Response(
        '',
        status,
        request: http.Request(method, Uri.parse('https://lichess.org$path')),
      );
    }

    test('retries a generic 429', () {
      expect(shouldRetryOn429(response(429)), isTrue);
      expect(shouldRetryOn429(response(429, method: 'POST')), isTrue);
    });

    test('does not retry non-429 responses', () {
      expect(shouldRetryOn429(response(200)), isFalse);
      expect(shouldRetryOn429(response(503)), isFalse);
    });

    test('does not retry a puzzle solve submission (POST /api/puzzle/batch)', () {
      // solveBatch handles 429 with a back-off, so the retry only wastes a call
      expect(
        shouldRetryOn429(response(429, method: 'POST', path: '/api/puzzle/batch/mix')),
        isFalse,
      );
    });

    test('does not retry a puzzle batch download (GET /api/puzzle/batch)', () {
      // Batch downloads are issued once per angle, so retrying doubles a burst the server has just
      // refused.
      expect(
        shouldRetryOn429(response(429, method: 'GET', path: '/api/puzzle/batch/mix')),
        isFalse,
      );
      expect(
        shouldRetryOn429(response(429, method: 'GET', path: '/api/puzzle/batch/advancedPawn')),
        isFalse,
      );
    });
  });

  group('LichessClient', () {
    test('sends requests to lichess host when only path is provided', () async {
      final container = await makeContainer(
        overrides: {
          httpClientFactoryProvider: httpClientFactoryProvider.overrideWith((ref) {
            return FakeHttpClientFactory(() => FakeClient());
          }),
        },
      );
      final client = container.read(lichessClientProvider);
      final response = await client.get(Uri(path: '/test'));
      expect(response.statusCode, 200);
      final requests = FakeClient.verifyRequests();
      expect(
        requests.first,
        isA<http.BaseRequest>()
            .having((r) => r.url.path, 'path', '/test')
            .having((r) => r.url.host, 'host', kLichessHost)
            .having((r) => r.url.scheme, 'scheme', 'https'),
      );
    });

    test('uses full URL as-is when host is provided', () async {
      final container = await makeContainer(
        overrides: {
          httpClientFactoryProvider: httpClientFactoryProvider.overrideWith((ref) {
            return FakeHttpClientFactory(() => FakeClient());
          }),
        },
      );
      final client = container.read(lichessClientProvider);
      final response = await client.get(Uri.https('explorer.lichess.org', '/test'));
      expect(response.statusCode, 200);
      final requests = FakeClient.verifyRequests();
      expect(
        requests.first,
        isA<http.BaseRequest>()
            .having((r) => r.url.path, 'path', '/test')
            .having((r) => r.url.host, 'host', 'explorer.lichess.org')
            .having((r) => r.url.scheme, 'scheme', 'https'),
      );
    });

    test('uses full URL as-is with query parameters when host is provided', () async {
      final container = await makeContainer(
        overrides: {
          httpClientFactoryProvider: httpClientFactoryProvider.overrideWith((ref) {
            return FakeHttpClientFactory(() => FakeClient());
          }),
        },
      );
      final client = container.read(lichessClientProvider);
      final response = await client.get(Uri.https('explorer.lichess.org', '/test', {'foo': 'bar'}));
      expect(response.statusCode, 200);
      final requests = FakeClient.verifyRequests();
      expect(
        requests.first,
        isA<http.BaseRequest>()
            .having((r) => r.url.host, 'host', 'explorer.lichess.org')
            .having((r) => r.url.queryParameters['foo'], 'query param', 'bar'),
      );
    });

    test('sets user agent (no authUser)', () async {
      final container = await makeContainer(
        overrides: {
          httpClientFactoryProvider: httpClientFactoryProvider.overrideWith((ref) {
            return FakeHttpClientFactory(() => FakeClient());
          }),
        },
      );
      final client = container.read(lichessClientProvider);
      await client.get(Uri(path: '/test'));
      final requests = FakeClient.verifyRequests();
      expect(
        requests.first,
        isA<http.BaseRequest>().having(
          (r) => r.headers['User-Agent'],
          'User-Agent',
          'ChessSRS/0.0.0 as:anon sri:test-sri',
        ),
      );
    });

    test('sets user agent (with authUser)', () async {
      final container = await makeContainer(
        overrides: {
          httpClientFactoryProvider: httpClientFactoryProvider.overrideWith((ref) {
            return FakeHttpClientFactory(() => FakeClient());
          }),
        },
        authUser: const AuthUser(
          token: 'test-token',
          user: LightUser(id: UserId('test-user-id'), name: 'test-username'),
        ),
      );
      final client = container.read(lichessClientProvider);
      await client.get(Uri(path: '/test'));
      final requests = FakeClient.verifyRequests();
      expect(
        requests.first,
        isA<http.BaseRequest>().having(
          (r) => r.headers['User-Agent'],
          'User-Agent',
          'ChessSRS/0.0.0 as:test-user-id sri:test-sri',
        ),
      );
    });

    test('read methods throw ServerException on status code >= 400', () async {
      final container = await makeContainer(
        overrides: {
          httpClientFactoryProvider: httpClientFactoryProvider.overrideWith((ref) {
            return FakeHttpClientFactory(() => FakeClient());
          }),
        },
      );
      final client = container.read(lichessClientProvider);
      for (final method in [
        client.read,
        client.readBytes,
        (Uri url) => client.readJson(url, mapper: (json) => json),
        (Uri url) => client.readJsonList(url, mapper: (json) => json),
        (Uri url) => client.readNdJsonList(url, mapper: (json) => json),
        (Uri url) => client.readNdJsonStream(url, mapper: (json) => json),
      ]) {
        expect(
          () => method(Uri(path: '/will/return/500')),
          throwsA(isA<ServerException>().having((e) => e.statusCode, 'statusCode', 500)),
        );
        expect(
          () => method(Uri(path: '/will/return/503')),
          throwsA(isA<ServerException>().having((e) => e.statusCode, 'statusCode', 503)),
        );
        expect(
          () => method(Uri(path: '/will/return/400')),
          throwsA(isA<ServerException>().having((e) => e.statusCode, 'statusCode', 400)),
        );
        expect(
          () => method(Uri(path: '/will/return/404')),
          throwsA(isA<ServerException>().having((e) => e.statusCode, 'statusCode', 404)),
        );
        expect(
          () => method(Uri(path: '/will/return/401')),
          throwsA(isA<ServerException>().having((e) => e.statusCode, 'statusCode', 401)),
        );
        expect(
          () => method(Uri(path: '/will/return/403')),
          throwsA(isA<ServerException>().having((e) => e.statusCode, 'statusCode', 403)),
        );
      }
    });

    test('other methods do not throw on status code >= 400', () async {
      final container = await makeContainer(
        overrides: {
          httpClientFactoryProvider: httpClientFactoryProvider.overrideWith((ref) {
            return FakeHttpClientFactory(() => FakeClient());
          }),
        },
      );
      final client = container.read(lichessClientProvider);
      for (final method in [client.get, client.post, client.put, client.patch, client.delete]) {
        expect(() => method(Uri(path: '/will/return/500')), returnsNormally);
        expect(() => method(Uri(path: '/will/return/503')), returnsNormally);
        expect(() => method(Uri(path: '/will/return/400')), returnsNormally);
        expect(() => method(Uri(path: '/will/return/404')), returnsNormally);
        expect(() => method(Uri(path: '/will/return/401')), returnsNormally);
        expect(() => method(Uri(path: '/will/return/403')), returnsNormally);
      }
    });

    test('socket and tls errors do not throw ClientException', () async {
      final container = await makeContainer(
        overrides: {
          httpClientFactoryProvider: httpClientFactoryProvider.overrideWith((ref) {
            return FakeHttpClientFactory(() => FakeClient());
          }),
        },
      );
      final client = container.read(lichessClientProvider);
      expect(
        () => client.get(Uri(path: '/will/throw/socket/exception')),
        throwsA(isA<SocketException>().having((e) => e.message, 'message', 'no internet')),
      );
      expect(
        () => client.get(Uri(path: '/will/throw/tls/exception')),
        throwsA(isA<TlsException>().having((e) => e.message, 'message', 'tls error')),
      );
    });

    test('failed JSON parsing will throw ClientException', () async {
      final container = await makeContainer(
        overrides: {
          httpClientFactoryProvider: httpClientFactoryProvider.overrideWith((ref) {
            return FakeHttpClientFactory(() => FakeClient());
          }),
        },
      );
      final client = container.read(lichessClientProvider);
      expect(
        () => client.readJson(
          Uri(path: '/will/return/204'),
          mapper: (json) {
            return json;
          },
        ),
        throwsA(
          isA<http.ClientException>().having(
            (e) => e.message,
            'message',
            'Could not read JSON object as Map<String, dynamic>: expected an object.',
          ),
        ),
      );
    });

    test('adds a signed bearer token when a authUser is available the request', () async {
      final container = await makeContainer(
        overrides: {
          httpClientFactoryProvider: httpClientFactoryProvider.overrideWith((ref) {
            return FakeHttpClientFactory(() => FakeClient());
          }),
        },
        authUser: const AuthUser(
          token: 'test-token',
          user: LightUser(id: UserId('test-user-id'), name: 'test-username'),
        ),
      );

      final authUser = container.read(authControllerProvider);
      expect(authUser, isNotNull);

      final client = container.read(lichessClientProvider);
      await client.get(Uri(path: '/test'));

      final requests = FakeClient.verifyRequests();
      expect(requests.length, 1);
      expect(
        requests.first,
        isA<http.BaseRequest>().having(
          (r) => r.headers['Authorization'],
          'Authorization',
          'Bearer ${signBearerToken('test-token')}',
        ),
      );
    });

    test('LichessClient does not attach Authorization to non-main-host requests', () async {
      final container = await makeContainer(
        overrides: {
          httpClientFactoryProvider: httpClientFactoryProvider.overrideWith((ref) {
            return FakeHttpClientFactory(() => FakeClient());
          }),
        },
        authUser: const AuthUser(
          token: 'test-token',
          user: LightUser(id: UserId('test-user-id'), name: 'test-username'),
        ),
      );

      final client = container.read(lichessClientProvider);
      await client.get(Uri.parse('https://explorer.lichess.org/masters'));

      final requests = FakeClient.verifyRequests();
      expect(requests.length, 1);
      expect(requests.first.headers.containsKey('Authorization'), isFalse);
      expect(requests.first.headers['User-Agent'], isNot(contains('as:test-user-id')));
    });

    test(
      'when receiving a 401, will test authUser token and delete authUser if not valid anymore',
      () async {
        int nbTokenTestRequests = 0;
        final container = await makeContainer(
          overrides: {
            httpClientFactoryProvider: httpClientFactoryProvider.overrideWith((ref) {
              return FakeHttpClientFactory(() => FakeClient());
            }),
            defaultClientProvider: defaultClientProvider.overrideWith((ref) {
              return DefaultClient(
                MockClient((request) async {
                  if (request.url.path == '/api/token/test') {
                    nbTokenTestRequests++;
                    final token = request.body.split(',')[0];
                    final response = '{"$token": null}';
                    return http.Response(response, 200);
                  }
                  return http.Response('', 404);
                }),
                userAgent: 'ChessSRS/0.0.0 as:test-user-id sri:test-sri',
              );
            }),
          },
          authUser: const AuthUser(
            token: 'test-token',
            user: LightUser(id: UserId('test-user-id'), name: 'test-username'),
          ),
        );

        fakeAsync((async) {
          final authUser = container.read(authControllerProvider);
          expect(authUser, isNotNull);

          final client = container.read(lichessClientProvider);
          try {
            client.get(Uri(path: '/will/return/401'));
          } on ServerException catch (_) {}

          async.flushMicrotasks();

          final requests = FakeClient.verifyRequests();
          expect(requests.length, 1);
          expect(
            requests.first,
            isA<http.BaseRequest>().having(
              (r) => r.headers['Authorization'],
              'Authorization',
              'Bearer ${signBearerToken('test-token')}',
            ),
          );

          expect(nbTokenTestRequests, 1);

          expect(container.read(authControllerProvider), isNull);
        });
      },
    );

    test('when receiving a 401, will test authUser token and keep authUser if still valid', () async {
      int nbTokenTestRequests = 0;
      final container = await makeContainer(
        overrides: {
          httpClientFactoryProvider: httpClientFactoryProvider.overrideWith((ref) {
            return FakeHttpClientFactory(() => FakeClient());
          }),
          defaultClientProvider: defaultClientProvider.overrideWith((ref) {
            return DefaultClient(
              MockClient((request) async {
                if (request.url.path == '/api/token/test') {
                  nbTokenTestRequests++;
                  final token = request.body.split(',')[0];
                  final response =
                      '{"$token": {"userId": "test-user-id","scope": "web:mobile", "expires":1760704968038}}';
                  return http.Response(response, 200);
                }
                return http.Response('', 404);
              }),
              userAgent: 'ChessSRS/0.0.0 as:test-user-id sri:test-sri',
            );
          }),
        },
        authUser: const AuthUser(
          token: 'test-token',
          user: LightUser(id: UserId('test-user-id'), name: 'test-username'),
        ),
      );

      fakeAsync((async) {
        final authUser = container.read(authControllerProvider);
        expect(authUser, isNotNull);

        final client = container.read(lichessClientProvider);
        try {
          client.get(Uri(path: '/will/return/401'));
        } on ServerException catch (_) {}

        async.flushMicrotasks();

        final requests = FakeClient.verifyRequests();
        expect(requests.length, 1);
        expect(
          requests.first,
          isA<http.BaseRequest>().having(
            (r) => r.headers['Authorization'],
            'Authorization',
            'Bearer ${signBearerToken('test-token')}',
          ),
        );

        expect(nbTokenTestRequests, 1);

        expect(container.read(authControllerProvider), equals(authUser));
      });
    });
  });

  group('kQuietRequestHeader', () {
    test('is stripped before the request is sent', () async {
      final container = await makeContainer(
        overrides: {
          httpClientFactoryProvider: httpClientFactoryProvider.overrideWith((ref) {
            return FakeHttpClientFactory(() => FakeClient());
          }),
        },
      );
      final client = container.read(defaultClientProvider);
      await client.head(
        Uri.https('www.gstatic.com', '/generate_204'),
        headers: const {kQuietRequestHeader: '1'},
      );
      final requests = FakeClient.verifyRequests();
      expect(requests.first.headers.containsKey(kQuietRequestHeader), isFalse);
    });
  });

  group('downloadFile', () {
    Future<File> targetFile() async {
      final tempDir = await Directory.systemTemp.createTemp('download_test_');
      addTearDown(() => tempDir.delete(recursive: true));
      return File('${tempDir.path}/file.bin');
    }

    test('saves the file when the whole body arrives', () async {
      final file = await targetFile();
      final client = MockClient((request) async => http.Response('hello', 200));

      final result = await downloadFile(client, Uri.parse('https://example.org/file'), file);

      expect(result, isTrue);
      expect(await file.readAsString(), 'hello');
    });

    test('deletes the partial file when the body is truncated', () async {
      final file = await targetFile();
      final client = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
          Stream<List<int>>.fromIterable([utf8.encode('hel')]),
          200,
          contentLength: 5,
        );
      });

      final result = await downloadFile(client, Uri.parse('https://example.org/file'), file);

      expect(result, isFalse);
      expect(await file.exists(), isFalse);
    });

    test('deletes the partial file when the stream fails', () async {
      final file = await targetFile();
      final client = MockClient.streaming((request, bodyStream) async {
        final controller = StreamController<List<int>>();
        controller.add(utf8.encode('hel'));
        controller.addError(const SocketException('connection reset'));
        unawaited(controller.close());
        return http.StreamedResponse(controller.stream, 200);
      });

      final result = await downloadFile(client, Uri.parse('https://example.org/file'), file);

      expect(result, isFalse);
      expect(await file.exists(), isFalse);
    });

    test('writes nothing when the server answers with an error', () async {
      final file = await targetFile();
      final client = MockClient((request) async => http.Response('nope', 404));

      final result = await downloadFile(client, Uri.parse('https://example.org/file'), file);

      expect(result, isFalse);
      expect(await file.exists(), isFalse);
    });

    test('deletes the file when the body is short of the expected length', () async {
      final file = await targetFile();
      // No Content-Length at all: a chunked response, which is what a CDN or proxy sends when
      // it cannot determine the size up front. The caller has said how many bytes to expect,
      // and that promise is the only completeness signal there is here.
      final client = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(Stream<List<int>>.fromIterable([utf8.encode('hel')]), 200);
      });

      final result = await downloadFile(
        client,
        Uri.parse('https://example.org/file'),
        file,
        expectedLength: 5,
      );

      expect(result, isFalse, reason: 'three bytes were asked for and five were promised');
      expect(await file.exists(), isFalse);
    });

    test('accepts a body of exactly the expected length with no Content-Length', () async {
      final file = await targetFile();
      final client = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(Stream<List<int>>.fromIterable([utf8.encode('hello')]), 200);
      });

      final result = await downloadFile(
        client,
        Uri.parse('https://example.org/file'),
        file,
        expectedLength: 5,
      );

      expect(result, isTrue);
      expect(await file.readAsString(), 'hello');
    });

    test('returns false when the request throws', () async {
      final file = await targetFile();
      final client = MockClient((request) async => throw const SocketException('no route'));

      final result = await downloadFile(client, Uri.parse('https://example.org/file'), file);

      expect(result, isFalse);
      expect(await file.exists(), isFalse);
    });

    test('an empty body is not a successful download and reports no progress', () async {
      // Nothing was downloaded, so nothing was saved: an empty file is not a download,
      // and there is no progress to report about a body that never came.
      final file = await targetFile();
      final client = MockClient((request) async => http.Response('', 200));
      final progress = <int>[];

      final result = await downloadFile(
        client,
        Uri.parse('https://example.org/file'),
        file,
        onProgress: (received, length) => progress.add(received),
      );

      expect(result, isFalse);
      expect(progress, isEmpty, reason: 'there was nothing to report progress about');
    });
  });

  group('guessIsUnsecureSchemeFromHost', () {
    test('treats a local or LAN host as unsecure', () {
      // A server on this machine or on the local network has no certificate to speak
      // of, so it is reached over http rather than https. The three shapes are separate
      // conditions: a host is one of them, not all of them at once.
      expect(guessIsUnsecureSchemeFromHost('localhost'), isTrue);
      expect(guessIsUnsecureSchemeFromHost('10.0.0.5'), isTrue);
      expect(guessIsUnsecureSchemeFromHost('192.168.1.7'), isTrue);
      expect(guessIsUnsecureSchemeFromHost('lichess.org'), isFalse);
    });
  });

  group('redactUriForLogging', () {
    // SPEC INV-006. The redaction is the guard that keeps a credential out of the
    // 7-day log tables, so it has to replace the secret and nothing else: the stored
    // URL is still the URL that was requested.

    test('leaves a path that is the secret-bearing prefix itself alone', () {
      // The secret is the segment *after* the prefix, so the prefix on its own carries
      // nothing to hide.
      final uri = Uri.parse('https://lichess.dev/mobile/register/firebase');

      expect(redactUriForLogging(uri), equals(uri));
    });

    test('keeps the path segments that follow the secret one', () {
      final redacted = redactUriForLogging(
        Uri.parse('https://lichess.dev/mobile/register/firebase/tok3n/extra'),
      );

      expect(redacted.path, '/mobile/register/firebase/$kRedactedLogValue/extra');
    });

    test('returns a URL with nothing to redact exactly as it was', () {
      // Only the secret parts are replaced: the path, the remaining parameters and the
      // host are left alone. A parameter that comes back re-encoded is a parameter that
      // was not left alone, and the log is there to say which request was made.
      final uri = Uri.parse('https://lichess.dev/api/games/user/alice?since=a%20b');

      expect(redactUriForLogging(uri), equals(uri));
    });
  });

  group('the request log', () {
    test('an error response is logged as a warning and an ordinary one is not', () async {
      // The log is the only trace a failed request leaves, so an error status is
      // written at the level the operator reads -- and a successful response is not
      // dressed up as an error.
      final records = collectLogRecords();
      final container = await makeContainer(
        overrides: {
          httpClientFactoryProvider: httpClientFactoryProvider.overrideWith((ref) {
            return FakeHttpClientFactory(
              () => MockClient((request) async {
                final status = request.url.path == '/bad' ? 400 : 200;
                return http.Response('body', status, request: request);
              }),
            );
          }),
        },
      );
      final lichess = container.read(lichessClientProvider);
      final standard = container.read(defaultClientProvider);

      await lichess.get(Uri.https('lichess.dev', '/bad'));
      await standard.get(Uri.https('lichess.dev', '/bad'));
      await lichess.get(Uri.https('lichess.dev', '/good'));
      await standard.get(Uri.https('lichess.dev', '/good'));

      final warnings = records
          .where((r) => r.level == Level.WARNING)
          .map((r) => r.message)
          .toList();
      expect(warnings, hasLength(2), reason: 'the two failed requests are the only warnings');
      expect(
        warnings.every((m) => m.contains('responded with status 400')),
        isTrue,
        reason: 'a successful response is not an error and is not logged as one',
      );
    });

    test('a quiet request is logged below the ordinary level', () async {
      // The connectivity checks run when the device may well be offline, so their
      // requests fail as a matter of course. A quiet request is still logged, but not
      // at the level that buries the records that matter.
      final records = collectLogRecords();
      final container = await makeContainer(
        overrides: {
          httpClientFactoryProvider: httpClientFactoryProvider.overrideWith((ref) {
            return FakeHttpClientFactory(() => FakeClient());
          }),
        },
      );
      final lichess = container.read(lichessClientProvider);
      final standard = container.read(defaultClientProvider);

      await lichess.get(Uri(path: '/quiet'), headers: {kQuietRequestHeader: '1'});
      await standard.get(Uri(path: '/quiet'), headers: {kQuietRequestHeader: '1'});
      await lichess.get(Uri(path: '/ordinary'));
      await standard.get(Uri(path: '/ordinary'));

      final quiet = records
          .where((r) => r.message.contains('/quiet '))
          .map((r) => r.level)
          .toList();
      final ordinary = records
          .where((r) => r.message.contains('/ordinary '))
          .map((r) => r.level)
          .toList();
      expect(quiet, hasLength(2));
      expect(ordinary, hasLength(2));
      expect(quiet, everyElement(Level.FINEST));
      expect(ordinary, everyElement(Level.INFO));
    });
  });

  group('the read helpers', () {
    test('the POST and DELETE readers throw on an error status', () async {
      // Every one of these hands the caller a remote answer, so the caller has to be
      // told the request failed -- not handed the error page as if it were the answer.
      // The app leans on that: the account preferences, the sign-out and the token
      // check all go through these.
      final container = await makeContainer(
        overrides: {
          httpClientFactoryProvider: httpClientFactoryProvider.overrideWith((ref) {
            return FakeHttpClientFactory(() => FakeClient());
          }),
        },
      );
      final client = container.read(lichessClientProvider);

      for (final method in [
        (Uri url) => client.postRead(url),
        (Uri url) => client.readResponse(url),
        (Uri url) => client.deleteRead(url),
        (Uri url) => client.postReadJson(url, mapper: (json) => json),
        (Uri url) => client.postReadNdJsonList(url, mapper: (json) => json),
      ]) {
        expect(
          () => method(Uri(path: '/will/return/400')),
          throwsA(isA<ServerException>().having((e) => e.statusCode, 'statusCode', 400)),
        );
        expect(
          () => method(Uri(path: '/will/return/500')),
          throwsA(isA<ServerException>().having((e) => e.statusCode, 'statusCode', 500)),
        );
      }
    });

    test('a POST body is sent the way the caller meant it', () async {
      // The app writes through this layer: the account preferences and the one-time
      // login code are posted as form fields, and the body has to arrive as it was
      // meant, not as an empty request.
      final captured = _CapturingClient();
      final container = await makeContainer(
        overrides: {
          httpClientFactoryProvider: httpClientFactoryProvider.overrideWith((ref) {
            return FakeHttpClientFactory(() => captured);
          }),
        },
      );
      final clients = <http.Client>[
        container.read(lichessClientProvider),
        container.read(defaultClientProvider),
      ];

      for (final client in clients) {
        await client.post(Uri.https('lichess.dev', '/api/thing'), body: 'raw text');
        expect(utf8.decode(await captured.lastBody()), 'raw text');
        expect(captured.lastContentType, startsWith('text/plain'));

        await client.post(Uri.https('lichess.dev', '/api/thing'), body: {'a': 'b'});
        expect(utf8.decode(await captured.lastBody()), 'a=b');
        expect(captured.lastContentType, startsWith('application/x-www-form-urlencoded'));

        await client.post(Uri.https('lichess.dev', '/api/thing'), body: [1, 2, 3]);
        expect(await captured.lastBody(), [1, 2, 3]);
        expect(captured.lastContentType, isNull);
      }
    });
  });

  group('the error a failed request reports', () {
    test('reports the error the server sent', () async {
      // The message surfaces in the UI and in crash reports, so the server's own error
      // has to be in it -- and the parsed body has to reach the caller with it.
      final client = MockClient((request) async => http.Response('{"error":"nope"}', 400));

      try {
        await client.readResponse(Uri.https('lichess.dev', '/api/account'));
        fail('readResponse must throw on a 400');
      } on ServerException catch (e) {
        expect(e.message, contains('nope'));
        expect(e.jsonError, isNotNull);
      }
    });

    test('an ND-JSON stream reports the reason the server gave', () async {
      final client = MockClient(
        (request) async => http.Response('nope', 404, reasonPhrase: 'Not Found'),
      );

      await expectLater(
        client
            .readNdJsonStream(Uri.https('lichess.dev', '/api/x'), mapper: (json) => json)
            .then((stream) => stream.toList()),
        throwsA(isA<ServerException>().having((e) => e.message, 'message', contains('Not Found'))),
      );
    });
  });

  group('the ND-JSON readers', () {
    test('a body with a blank line yields every record', () async {
      // A blank line between two records is not a record: it is skipped, not parsed.
      final client = MockClient((request) async => http.Response('{"a":1}\n\n{"b":2}\n', 200));

      final records = await client.readNdJsonList(
        Uri.https('lichess.dev', '/api/x'),
        mapper: (json) => json,
      );

      expect(records, [
        {'a': 1},
        {'b': 2},
      ]);
    });

    test('a stream with a blank line yields every record', () async {
      final client = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
          Stream<List<int>>.fromIterable([
            utf8.encode('{"a":1}\n'),
            utf8.encode('\n'),
            utf8.encode('{"b":2}\n'),
          ]),
          200,
        );
      });

      final records = await (await client.readNdJsonStream(
        Uri.https('lichess.dev', '/api/x'),
        mapper: (json) => json,
      )).toList();

      expect(records, [
        {'a': 1},
        {'b': 2},
      ]);
    });

    test('a parse failure carries the request URL on the exception', () async {
      // SPEC INV-006. The URL is what makes the failure diagnosable, and it has to be
      // the redacted one.
      final client = MockClient(
        (request) async => http.Response('not json', 200, request: request),
      );

      try {
        await client.readNdJsonList(Uri.https('lichess.dev', '/api/x'), mapper: (json) => json);
        fail('readNdJsonList must throw when the body is not ND-JSON');
      } on http.ClientException catch (e) {
        expect(e.toString(), contains('/api/x'));
      }
    });
  });

  group('the client', () {
    test('gives up on a request the server never answers', () async {
      // A server that took the connection and then went quiet used to leave the
      // request pending forever: no error, no timeout, and an app that simply waits.
      // The deadline runs on the fake clock here, so the test costs nothing.
      final container = await makeContainer(
        overrides: {
          httpClientFactoryProvider: httpClientFactoryProvider.overrideWith((ref) {
            return FakeHttpClientFactory(
              () => MockClient((_) => Completer<http.Response>().future),
            );
          }),
        },
      );

      fakeAsync((async) {
        final client = container.read(lichessClientProvider);
        final errors = <Object>[];
        unawaited(client.get(Uri(path: '/never')).then<void>((_) {}, onError: errors.add));

        async.elapse(const Duration(seconds: 16));

        expect(errors, hasLength(1), reason: 'a request with no reply must not stay pending');
        expect(errors.single, isA<TimeoutException>());
      });
    });

    test('applies the wrapper it was given', () {
      // The wrapper is what installs the request logging, so a client that comes out of
      // the factory unwrapped is a client that logs nothing at all.
      var wrapped = 0;
      final factory = HttpClientFactory(
        wrapper: (client) {
          wrapped++;
          return client;
        },
      );

      final client = factory.call();
      addTearDown(client.close);

      expect(wrapped, 1);
    });
  });

  group('an error response that carries no request', () {
    test('does not break the client', () async {
      // A response the client cannot name in the log is still a response: the error has
      // to reach the caller all the same.
      final container = await makeContainer(
        overrides: {
          httpClientFactoryProvider: httpClientFactoryProvider.overrideWith((ref) {
            return FakeHttpClientFactory(() => _RequestlessClient());
          }),
        },
      );

      final lichess = container.read(lichessClientProvider);
      final standard = DefaultClient(_RequestlessClient(), userAgent: 'test');

      expect((await lichess.get(Uri(path: '/thing'))).statusCode, 404);
      expect((await standard.get(Uri.parse('https://lichess.dev/thing'))).statusCode, 404);
    });
  });
}

class FakeClient extends http.BaseClient {
  static List<http.BaseRequest> _requests = [];

  static List<http.BaseRequest> verifyRequests() {
    final result = _requests;
    _requests = [];
    return result;
  }

  static void reset() {
    _requests = [];
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    _requests.add(request);

    return _responseBasedOnPath(request, request.finalize());
  }

  Future<http.StreamedResponse> _responseBasedOnPath(
    http.BaseRequest request,
    http.ByteStream bodyStream,
  ) async {
    switch (request.url.path) {
      case '/will/throw/socket/exception':
        throw const SocketException('no internet');
      case '/will/throw/tls/exception':
        throw const TlsException('tls error');
      case '/will/return/500':
        return http.StreamedResponse(_streamBody('500'), 500);
      case '/will/return/503':
        return http.StreamedResponse(_streamBody('503'), 503);
      case '/will/return/400':
        return http.StreamedResponse(_streamBody('400'), 400);
      case '/will/return/404':
        return http.StreamedResponse(_streamBody('404'), 404);
      case '/will/return/401':
        return http.StreamedResponse(_streamBody('401'), 401);
      case '/will/return/403':
        return http.StreamedResponse(_streamBody('403'), 403);
      case '/will/return/204':
        return http.StreamedResponse(_streamBody('204'), 204);
      case '/will/return/301':
        return http.StreamedResponse(_streamBody('301'), 301);
      default:
        return http.StreamedResponse(_streamBody('''{"result": "ok"}'''), 200);
    }
  }
}

Stream<List<int>> _streamBody(String body) => Stream.value(utf8.encode(body));

/// Collects every log record the app writes, the fine-grained ones included.
///
/// The root logger is raised for the duration of the test and put back afterwards: the
/// HTTP layer says plenty of things that are only interesting at the level it says them
/// at, and a quiet request is only quiet while the logger is at its ordinary level.
List<LogRecord> collectLogRecords() {
  final records = <LogRecord>[];
  final previousLevel = Logger.root.level;
  Logger.root.level = Level.ALL;
  addTearDown(() => Logger.root.level = previousLevel);
  final subscription = Logger.root.onRecord.listen(records.add);
  addTearDown(subscription.cancel);
  return records;
}

/// A client that keeps the requests it was given, so a test can look at them.
class _CapturingClient extends http.BaseClient {
  final List<http.BaseRequest> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests.add(request);
    return Future.value(http.StreamedResponse(Stream<List<int>>.value(utf8.encode('ok')), 200));
  }

  /// The body of the last request, as it went out.
  Future<List<int>> lastBody() {
    final stream = requests.last.finalize();
    return stream.toBytes();
  }

  String? get lastContentType => requests.last.headers['content-type'];
}

/// A client whose responses carry no request, the way a rewritten response would.
class _RequestlessClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(Stream<List<int>>.value(utf8.encode('nope')), 404);
  }
}
