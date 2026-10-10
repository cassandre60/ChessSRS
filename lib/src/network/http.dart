import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:chess_srs/src/constants.dart';
import 'package:chess_srs/src/model/auth/auth_controller.dart';
import 'package:chess_srs/src/model/auth/bearer.dart';
import 'package:chess_srs/src/model/common/preloaded_data.dart';
import 'package:chess_srs/src/model/log/http_log_storage.dart';
import 'package:chess_srs/src/model/user/user.dart';
import 'package:chess_srs/src/network/aggregator.dart';
import 'package:chess_srs/src/network/server_status.dart';
import 'package:chess_srs/src/utils/riverpod.dart';
import 'package:cronet_http/cronet_http.dart';
import 'package:cupertino_http/cupertino_http.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart'
    show
        BaseClient,
        BaseRequest,
        BaseResponse,
        Client,
        ClientException,
        Request,
        Response,
        StreamedResponse;
import 'package:http/io_client.dart';
import 'package:http/retry.dart';
import 'package:logging/logging.dart';
import 'package:package_info_plus/package_info_plus.dart';

final _logger = Logger('HttpClient');

const _maxCacheSize = 2 * 1024 * 1024;

/// Request header marking a request whose failure is expected and must not pollute the logs.
///
/// The connectivity checks run precisely when the device may be offline, so their requests fail
/// as a matter of course; logging each failure as a warning only buries the records that matter.
/// A request carrying this header is logged at [Level.FINEST] instead. The header is stripped
/// before the request goes out, so it never reaches the server.
const kQuietRequestHeader = 'x-quiet-request';

bool guessIsUnsecureSchemeFromHost(String host) {
  return host.startsWith('localhost') || host.startsWith('10.') || host.startsWith('192.168.');
}

/// Creates a Uri pointing to lichess server with the given unencoded path and query parameters.
Uri lichessUri(String unencodedPath, [Map<String, dynamic>? queryParameters]) =>
    guessIsUnsecureSchemeFromHost(kLichessHost)
    ? Uri.http(kLichessHost, unencodedPath, queryParameters)
    : Uri.https(kLichessHost, unencodedPath, queryParameters);

/// Stands in for a value that must not appear in a log.
const kRedactedLogValue = '***';

/// Query parameters whose value is a credential or a personal identifier.
///
/// This is a denylist rather than an allowlist on purpose. Its opposite — allowlisting the
/// parameters known to be safe — fails quietly and in the direction nobody notices: a
/// parameter added later is blanked, the log gets less informative exactly when a new feature
/// is being debugged, and no test fails. A denylist keeps the log useful. What stops a new
/// secret-bearing parameter slipping past this list is review discipline, not automation: there
/// is no app-wide scan (an earlier classification-guard attempt produced only false positives
/// and was dropped). So when a credential is put in a query string, its name must be added
/// here in the same change — and the sweep is part of every network review (see Round 4).
///
/// Add a name when a credential is put in a query string, not when an ordinary parameter is.
const Set<String> kSensitiveQueryParameters = {
  'code', // one-time login code
  'email', // personal identifier
  'otp',
  'password',
  'secret',
  'sessionid',
  'token',
  'username', // personal identifier
};

/// Path prefixes whose following segment is a credential, with the reason.
///
/// Matched by prefix rather than by guessing "long opaque segment", which would mangle ordinary
/// paths and make the log useless for the case it exists to serve.
const Map<String, String> kSecretBearingPathPrefixes = {
  '/mobile/register/firebase': 'the FCM registration token, a long-lived device credential',
};

/// Returns [uri] with anything that must not be logged replaced by [kRedactedLogValue].
///
/// Applied on the way *into* storage and logging, never to the request that is sent: the client
/// has to deliver the real one-time code and the real token, so redacting at the source would
/// break sign-in. What is stored is what has to be safe.
///
/// Only the secret parts are replaced. The path, the remaining parameters and the host are left
/// alone, because "which request was made, and what came back" is the whole diagnostic value of
/// the log.
Uri redactUriForLogging(Uri uri) {
  var segments = uri.pathSegments;

  for (final entry in kSecretBearingPathPrefixes.entries) {
    final prefixSegments = entry.key.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.length > prefixSegments.length && _startsWith(segments, prefixSegments)) {
      segments = [
        ...segments.take(prefixSegments.length),
        kRedactedLogValue,
        ...segments.skip(prefixSegments.length + 1),
      ];
      break;
    }
  }

  var changed = !_sameSegments(segments, uri.pathSegments);

  final parameters = <String, dynamic>{...uri.queryParameters};
  parameters.forEach((name, value) {
    if (kSensitiveQueryParameters.contains(name.toLowerCase()) && value != kRedactedLogValue) {
      parameters[name] = kRedactedLogValue;
      changed = true;
    }
  });

  if (!changed) return uri;
  return uri.replace(
    pathSegments: segments,
    queryParameters: parameters.isEmpty ? null : parameters,
  );
}

bool _startsWith(List<String> segments, List<String> prefix) {
  for (var i = 0; i < prefix.length; i++) {
    if (segments[i] != prefix[i]) return false;
  }
  return true;
}

bool _sameSegments(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The host of the lichess main server, without the port part.
/// Other lichess services, such as the opening explorer, the tablebase or the
/// CDN, are served by different hosts.
final _lichessMainHost = lichessUri('/').host;

/// Creates the appropriate http client for the platform.
///
/// Do not use directly, use [defaultClientProvider] or [lichessClientProvider] instead.
class HttpClientFactory {
  const HttpClientFactory({this.wrapper});

  final Client Function(Client client)? wrapper;

  Client _createClient() {
    const userAgent = 'Lichess Mobile';
    try {
      if (Platform.isAndroid) {
        final engine = CronetEngine.build(
          cacheMode: CacheMode.memory,
          cacheMaxSize: _maxCacheSize,
          userAgent: userAgent,
          enableHttp2: true,
        );
        return CronetClient.fromCronetEngine(engine);
      } else if (Platform.isIOS || Platform.isMacOS) {
        final config = URLSessionConfiguration.ephemeralSessionConfiguration()
          ..cache = URLCache.withCapacity(memoryCapacity: _maxCacheSize)
          ..httpAdditionalHeaders = {'User-Agent': userAgent};
        return CupertinoClient.fromSessionConfiguration(config);
      }
    } catch (_) {
      return IOClient(HttpClient()..userAgent = userAgent);
    }
    return IOClient(HttpClient()..userAgent = userAgent);
  }

  Client call() {
    final client = _createClient();
    return wrapper?.call(client) ?? client;
  }
}

/// The global [HttpClientFactory] provider.
///
/// Http clients created by this factory log all requests and responses to the database.
final httpClientFactoryProvider = Provider<HttpClientFactory>((Ref ref) {
  return HttpClientFactory(
    wrapper: (client) => _RegisterCallbackClient(
      client,
      onRequest: (request) async {
        if (request.method == 'HEAD' || Platform.environment.containsKey('FLUTTER_TEST')) return;
        final httpLogStorage = await ref.read(httpLogStorageProvider.future);
        httpLogStorage.save(
          HttpLogEntry(
            httpLogId: request.hashCode.toString(),
            requestDateTime: DateTime.now(),
            requestMethod: request.method,
            requestUrl: redactUriForLogging(request.url),
          ),
        );
      },
      onResponse: (response) async {
        if (Platform.environment.containsKey('FLUTTER_TEST')) return;
        if (response.request != null) {
          final httpLogStorage = await ref.read(httpLogStorageProvider.future);
          httpLogStorage.updateWithResponse(
            response.request!.hashCode.toString(),
            responseCode: response.statusCode,
            responseDateTime: DateTime.now(),
          );
        }
      },
      onError: (request, error, [st]) async {
        if (request.method == 'HEAD' || Platform.environment.containsKey('FLUTTER_TEST')) return;
        final httpLogStorage = await ref.read(httpLogStorageProvider.future);
        if (error is ClientException) {
          httpLogStorage.updateWithError(request.hashCode.toString(), errorMessage: error.message);
        } else {
          httpLogStorage.updateWithError(
            request.hashCode.toString(),
            errorMessage: error.toString(),
          );
        }
      },
    ),
  );
});

/// The default http client.
///
/// This client is used for all requests that don't go to the main lichess server, for
/// example, requests to lichess CDN, or other APIs.
/// This client does not set any Authorization header.
///
/// Only one instance of this client is created and kept alive for the whole app.
final defaultClientProvider = Provider<DefaultClient>((Ref ref) {
  final userAgent = makeUserAgent(
    ref.read(preloadedDataProvider).requireValue.packageInfo,
    ref.read(preloadedDataProvider).requireValue.deviceInfo,
    ref.read(preloadedDataProvider).requireValue.sri,
    null,
  );
  final client = DefaultClient(ref.read(httpClientFactoryProvider)(), userAgent: userAgent);
  ref.onDispose(() => client.close());
  return client;
}, name: 'DefaultHttpClientProvider');

/// The http client configured to make requests to the lichess API.
///
/// Only one instance of this client is created and kept alive for the whole app.
final lichessClientProvider = Provider<LichessClient>((Ref ref) {
  final client = LichessClient(
    // Retry just once on 429 Too Many Requests.
    RetryClient(
      ref.read(httpClientFactoryProvider)(),
      retries: 1,
      delay: _defaultDelay,
      when: shouldRetryOn429,
    ),
    ref,
  );
  ref.onDispose(() => client.close());
  return client;
}, name: 'LichessHttpClientProvider');

/// Whether a response should be retried once by [lichessClientProvider].
///
/// Retries on 429 Too Many Requests, except for the puzzle batch endpoints (`/api/puzzle/batch/…`),
/// which are rate-limited deliberately:
/// - solve submissions (`POST`) are handled with a back-off by `PuzzleSolveLimiter`, so retrying
///   here only burns a request and delays arming the back-off;
/// - batch downloads (`GET`) are issued once per puzzle angle, so a retry doubles an already large
///   burst against an endpoint that has just said it is receiving too many requests.
@visibleForTesting
bool shouldRetryOn429(BaseResponse response) {
  if (response.statusCode != 429) return false;
  final request = response.request;
  final isPuzzleBatch = request != null && request.url.path.startsWith('/api/puzzle/batch/');
  return !isPuzzleBatch;
}

Duration _defaultDelay(int retryCount) =>
    const Duration(milliseconds: 900) * math.pow(1.5, retryCount);

final userAgentProvider = Provider<String>((Ref ref) {
  final user = ref.watch(authControllerProvider.select((value) => value?.user));

  return makeUserAgent(
    ref.read(preloadedDataProvider).requireValue.packageInfo,
    ref.read(preloadedDataProvider).requireValue.deviceInfo,
    ref.read(preloadedDataProvider).requireValue.sri,
    user,
  );
});

/// Creates a user-agent string with the app version, build number, and device info and possibly the user ID if a user is logged in.
String makeUserAgent(PackageInfo info, BaseDeviceInfo deviceInfo, String sri, LightUser? user) {
  final base = 'ChessSRS/${info.version} as:${user?.id ?? 'anon'} sri:$sri';

  if (deviceInfo is AndroidDeviceInfo) {
    return '$base os:Android/${deviceInfo.version.release} dev:${deviceInfo.model}';
  } else if (deviceInfo is IosDeviceInfo) {
    return '$base os:iOS/${deviceInfo.systemVersion} dev:${deviceInfo.model}';
  }

  return base;
}

/// Downloads a file from the given [url] and saves it to the [file].
///
/// Returns true if the download was successful, false otherwise. A download that fails halfway
/// through leaves nothing behind: the partial file is deleted, so that a later attempt starts from
/// a clean slate instead of finding a file that looks downloaded but is truncated.
Future<bool> downloadFile(
  Client client,
  Uri url,
  File file, {
  int? expectedLength,
  void Function(int received, int length)? onProgress,
}) async {
  _logger.fine('Downloading ${redactUriForLogging(url)} to ${file.path}');

  Future<bool> discard(String reason, [Object? error, StackTrace? stackTrace]) async {
    _logger.warning('Download of ${redactUriForLogging(url)} failed: $reason', error, stackTrace);
    try {
      if (await file.exists()) await file.delete();
    } catch (e, st) {
      _logger.warning('Could not delete the incomplete ${file.path}:', e, st);
    }
    return false;
  }

  final StreamedResponse response;
  try {
    response = await client.send(Request('GET', url));
  } catch (e, st) {
    return await discard('the request failed', e, st);
  }

  if (response.statusCode != 200) {
    // The body is an error page, not the file we asked for.
    await response.stream.drain<void>().catchError((Object _) {});
    return await discard('unexpected status ${response.statusCode}');
  }

  final sink = file.openWrite();

  int received = 0;
  final contentLength = response.contentLength;
  final totalLength = contentLength ?? expectedLength;

  Object? failure;
  StackTrace? failureStackTrace;

  try {
    await response.stream
        .map((s) {
          received += s.length;
          if (totalLength != null && totalLength > 0) {
            onProgress?.call(received, totalLength);
          }
          return s;
        })
        .pipe(sink);
  } catch (e, st) {
    failure = e;
    failureStackTrace = st;
  } finally {
    // Closing the sink is what actually flushes the bytes to disk, so its failure is a download
    // failure, not a detail to log and forget.
    try {
      await sink.flush();
      await sink.close();
    } catch (e, st) {
      failure ??= e;
      failureStackTrace ??= st;
    }
  }

  if (failure != null) {
    return await discard('the file could not be written', failure, failureStackTrace);
  }

  // Fewer bytes than announced means the body was cut short. More is not an error: a client that
  // transparently decompresses the body reports the compressed length here.
  //
  // The expected length counts, not only the one the server chose to send. A chunked response
  // carries no Content-Length at all, and in that case the caller's expectedLength is the only
  // completeness signal there is — so testing contentLength alone skipped the check entirely for
  // those responses and reported success for a file that was short.
  if (totalLength != null && received < totalLength) {
    return await discard('got $received bytes out of $totalLength');
  }

  final int length;
  try {
    length = await file.length();
  } catch (e, st) {
    return await discard('the file could not be read back', e, st);
  }

  if (length != received) {
    return await discard('only $length bytes of $received made it to disk');
  }

  return length > 0;
}

/// A [Client] that intercepts all requests, responses, and errors using the provided callbacks.
///
/// This client wraps around another [Client] and intercepts the requests, responses,
/// and errors, allowing custom handling through the provided callback functions.
///
/// The [onRequest] callback is called before the request is sent.
/// The [onResponse] callback is called after a response is received.
/// The [onError] callback is called when an error occurs during the request.
///
///
/// This class is intended for debugging and monitoring purposes.
///
/// See also:
/// - [BaseClient] for the base class.
/// - [Client] for the interface that this class implements.
class _RegisterCallbackClient extends BaseClient {
  _RegisterCallbackClient(this._inner, {this.onRequest, this.onResponse, this.onError});

  final Client _inner;

  final void Function(BaseRequest request)? onRequest;
  final void Function(BaseResponse response)? onResponse;
  final void Function(BaseRequest request, Object error, [StackTrace? stackTrace])? onError;

  @override
  Future<StreamedResponse> send(BaseRequest request) async {
    try {
      onRequest?.call(request);
      final response = await _inner.send(request);
      onResponse?.call(response);
      return response;
    } catch (error, st) {
      onError?.call(request, error, st);
      rethrow;
    }
  }
}

/// Lichess HTTP client.
///
/// * Requests made with [head], [get], [post], [put], [patch], [delete] that contain
/// only a path (no host or scheme) are automatically routed to the lichess server
/// defined in [kLichessHost]. If the URL already contains a host and scheme, it is
/// used as-is. It does not apply to the low-level [send] method.
/// * Sets the Authorization header when a token has been stored.
/// * Sets the user-agent header with the app version, build number, and device info. If the user is logged in, it also includes the user's id.
/// * Logs all requests and responses with status code >= 400.
/// * When a response has the 401 status, checks if the authUser token is still valid,
/// and deletes the authUser if it's not.
class LichessClient implements Client {
  LichessClient(this._inner, this._ref)
    : _cachedPackageInfo = _ref.read(preloadedDataProvider).requireValue.packageInfo,
      _cachedDeviceInfo = _ref.read(preloadedDataProvider).requireValue.deviceInfo,
      _cachedSri = _ref.read(preloadedDataProvider).requireValue.sri;

  static const defaultRequestTimeout = Duration(seconds: 15);

  final Ref _ref;
  final Client _inner;
  final PackageInfo _cachedPackageInfo;
  final BaseDeviceInfo _cachedDeviceInfo;
  final String _cachedSri;

  @override
  Future<StreamedResponse> send(BaseRequest request) async {
    final authUser = _ref.read(authControllerProvider);
    final isMainHost = request.url.host.isEmpty || request.url.host == _lichessMainHost;

    if (isMainHost && authUser != null && !request.headers.containsKey('Authorization')) {
      final bearer = signBearerToken(authUser.token);
      request.headers['Authorization'] = 'Bearer $bearer';
    }
    request.headers['User-Agent'] = makeUserAgent(
      _cachedPackageInfo,
      _cachedDeviceInfo,
      _cachedSri,
      isMainHost ? authUser?.user : null,
    );

    final quiet = request.headers.remove(kQuietRequestHeader) != null;

    _logger.log(
      quiet ? Level.FINEST : Level.INFO,
      '${request.method} ${redactUriForLogging(request.url)} ${request.headers['User-Agent']}',
    );

    try {
      final response = await _inner.send(request).timeout(defaultRequestTimeout);

      _logIfError(response, quiet: quiet);

      // Only the main server can tell us whether lichess is up: the opening
      // explorer and the tablebase run on their own servers and may well be
      // available while lichess itself is down (and vice versa).
      if (_ref.mounted && isMainHost) {
        _ref.read(serverStatusProvider.notifier).handleHttpResponse(response.statusCode);
      }

      if (response.statusCode == 401 && authUser != null && isMainHost) {
        _ref.read(authControllerProvider.notifier).checkToken(authUser);
      }

      return response;
    } catch (e, st) {
      _logger.log(
        quiet ? Level.FINEST : Level.WARNING,
        'Request to ${redactUriForLogging(request.url)} failed:',
        e,
        st,
      );
      rethrow;
    }
  }

  void _logIfError(BaseResponse response, {required bool quiet}) {
    if (response.request != null && response.statusCode >= 400) {
      final request = response.request!;
      final method = request.method;
      final url = redactUriForLogging(request.url);
      _logger.log(
        quiet ? Level.FINEST : Level.WARNING,
        '$method $url responded with status ${response.statusCode} ${response.reasonPhrase}',
      );
    }
  }

  @override
  void close() {
    _inner.close();
  }

  @override
  Future<Response> head(Uri url, {Map<String, String>? headers}) =>
      _sendUnstreamed('HEAD', url, headers);

  @override
  Future<Response> get(Uri url, {Map<String, String>? headers}) =>
      _sendUnstreamed('GET', url, headers);

  @override
  Future<Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) => _sendUnstreamed('POST', url, headers, body, encoding);

  @override
  Future<Response> put(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
      _sendUnstreamed('PUT', url, headers, body, encoding);

  @override
  Future<Response> patch(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) => _sendUnstreamed('PATCH', url, headers, body, encoding);

  @override
  Future<Response> delete(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) => _sendUnstreamed('DELETE', url, headers, body, encoding);

  @override
  Future<String> read(Uri url, {Map<String, String>? headers}) async {
    final response = await get(url, headers: headers);
    _checkResponseSuccess(url, response);
    return response.body;
  }

  @override
  Future<Uint8List> readBytes(Uri url, {Map<String, String>? headers}) async {
    final response = await get(url, headers: headers);
    _checkResponseSuccess(url, response);
    return response.bodyBytes;
  }

  /// Sends a non-streaming [Request] and returns a non-streaming [Response].
  Future<Response> _sendUnstreamed(
    String method,
    Uri url,
    Map<String, String>? headers, [
    Object? body,
    Encoding? encoding,
  ]) async {
    final request = Request(
      method,
      url.host.isNotEmpty ? url : lichessUri(url.path, url.hasQuery ? url.queryParameters : null),
    );

    if (headers != null) request.headers.addAll(headers);
    if (encoding != null) request.encoding = encoding;
    if (body != null) {
      if (body is String) {
        request.body = body;
      } else if (body is List) {
        request.bodyBytes = body.cast<int>();
      } else if (body is Map) {
        request.bodyFields = body.cast<String, String>();
      } else {
        throw ArgumentError('Invalid request body "$body".');
      }
    }

    return await Response.fromStream(await send(request));
  }
}

/// Default HTTP client.
///
/// * Sets the user-agent header with the app version, build number, and device info.
/// * Logs all requests and responses with status code >= 400.
class DefaultClient implements Client {
  DefaultClient(this._inner, {required this._userAgent, this.timeout = defaultRequestTimeout});

  /// How long a request through this client may take before it is abandoned.
  ///
  /// [LichessClient] has always had one; this client had none, so a server that accepted the
  /// connection and then went quiet left the request pending forever. Upstream's traffic through
  /// here is mostly short cloud calls, which is presumably why it was never noticed — but this
  /// fork is local-first, and the opening database, the NNUE weights and the Maia book all come
  /// through this client. A stall on a multi-megabyte download is an app that sits and waits with
  /// no way out and no error, so the same deadline its sibling already uses is applied here.
  ///
  /// Overridable per call for a caller that legitimately needs longer; the default is the ceiling
  /// for an ordinary request, not for every request.
  static const defaultRequestTimeout = LichessClient.defaultRequestTimeout;

  final Client _inner;
  final String _userAgent;
  final Duration timeout;

  @override
  Future<StreamedResponse> send(BaseRequest request) async {
    request.headers['User-Agent'] = _userAgent;

    final quiet = request.headers.remove(kQuietRequestHeader) != null;

    _logger.log(
      quiet ? Level.FINEST : Level.INFO,
      '${request.method} ${redactUriForLogging(request.url)} ${request.headers['User-Agent']}',
    );

    try {
      final response = await _inner.send(request).timeout(timeout);

      _logIfError(response, quiet: quiet);

      return response;
    } catch (e, st) {
      _logger.log(
        quiet ? Level.FINEST : Level.WARNING,
        'Request to ${redactUriForLogging(request.url)} failed:',
        e,
        st,
      );
      rethrow;
    }
  }

  void _logIfError(BaseResponse response, {required bool quiet}) {
    if (response.request != null && response.statusCode >= 400) {
      final request = response.request!;
      final method = request.method;
      final url = redactUriForLogging(request.url);
      _logger.log(
        quiet ? Level.FINEST : Level.WARNING,
        '$method $url responded with status ${response.statusCode} ${response.reasonPhrase}',
      );
    }
  }

  @override
  void close() {
    _inner.close();
  }

  @override
  Future<Response> head(Uri url, {Map<String, String>? headers}) =>
      _sendUnstreamed('HEAD', url, headers);

  @override
  Future<Response> get(Uri url, {Map<String, String>? headers}) =>
      _sendUnstreamed('GET', url, headers);

  @override
  Future<Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) => _sendUnstreamed('POST', url, headers, body, encoding);

  @override
  Future<Response> put(Uri url, {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
      _sendUnstreamed('PUT', url, headers, body, encoding);

  @override
  Future<Response> patch(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) => _sendUnstreamed('PATCH', url, headers, body, encoding);

  @override
  Future<Response> delete(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) => _sendUnstreamed('DELETE', url, headers, body, encoding);

  @override
  Future<String> read(Uri url, {Map<String, String>? headers}) async {
    final response = await get(url, headers: headers);
    _checkResponseSuccess(url, response);
    return response.body;
  }

  @override
  Future<Uint8List> readBytes(Uri url, {Map<String, String>? headers}) async {
    final response = await get(url, headers: headers);
    _checkResponseSuccess(url, response);
    return response.bodyBytes;
  }

  /// Sends a non-streaming [Request] and returns a non-streaming [Response].
  Future<Response> _sendUnstreamed(
    String method,
    Uri url,
    Map<String, String>? headers, [
    Object? body,
    Encoding? encoding,
  ]) async {
    final request = Request(method, url);

    if (headers != null) request.headers.addAll(headers);
    if (encoding != null) request.encoding = encoding;
    if (body != null) {
      if (body is String) {
        request.body = body;
      } else if (body is List) {
        request.bodyBytes = body.cast<int>();
      } else if (body is Map) {
        request.bodyFields = body.cast<String, String>();
      } else {
        throw ArgumentError('Invalid request body "$body".');
      }
    }

    return await Response.fromStream(await send(request));
  }
}

/// An exception thrown when the server responds with a status code >= 400.
class ServerException extends ClientException {
  final int statusCode;
  final Map<String, dynamic>? jsonError;

  ServerException(this.statusCode, super.message, Uri super.url, this.jsonError);
}

/// Throws an error if [response] is not successful.
void _checkResponseSuccess(Uri url, Response response) {
  if (response.statusCode < 400) return;
  // The URL goes into the exception message, which surfaces in the UI and in crash reports, so
  // it is redacted like every other logged URL (a secret-bearing query string must never ride
  // along in an error).
  var message = 'Request to ${redactUriForLogging(url)} failed with status ${response.statusCode}';
  Map<String, dynamic>? jsonError;
  if (response.body.isNotEmpty) {
    try {
      final json = jsonDecode(response.body);
      if (json is Map<String, dynamic>) {
        jsonError = json;
        if (json.containsKey('error')) {
          message = '$message: ${json['error']}';
        }
      }
    } catch (_) {
      message = '$message: ${response.body}';
    }
  }
  throw ServerException(response.statusCode, message, redactUriForLogging(url), jsonError);
}

/// A JSON decoder that decodes UTF-8 bytes.
///
/// This is a fusion of [Utf8Decoder] and [JsonDecoder] which is more efficient
/// than decoding the bytes to a string and then parsing the JSON.
final jsonUtf8Decoder = const Utf8Decoder().fuse(const JsonDecoder());

extension ClientExtension on Client {
  /// Sends an HTTP POST request with the given headers and body to the given URL and read response body.
  ///
  /// Returns a Future that completes to the body of the response as a string.
  /// Throws a [ServerException] if the response doesn't have a success status code.
  Future<String> postRead(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) async {
    final response = await post(url, headers: headers, body: body, encoding: encoding);
    _checkResponseSuccess(url, response);
    return response.body;
  }

  /// Sends an HTTP GET request with the given headers to the given URL and returns a [Future<Response>] that completes to the response.
  ///
  /// Throws a [ServerException] if the response doesn't have a success status code.
  Future<Response> readResponse(Uri url, {Map<String, String>? headers}) async {
    final response = await get(url, headers: headers);
    _checkResponseSuccess(url, response);
    return response;
  }

  /// Sends an HTTP DELETE request with the given headers and body to the given URL and read response body.
  ///
  /// Returns a Future that completes to the body of the response as a string.
  /// Throws a [ServerException] if the response doesn't have a success status code.
  Future<String> deleteRead(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) async {
    final response = await delete(url, headers: headers, body: body, encoding: encoding);
    _checkResponseSuccess(url, response);
    return response.body;
  }

  /// Sends an HTTP GET request with the given headers to the given URL and
  /// returns a Future that completes to the body of the response as a JSON object
  /// mapped to [T].
  ///
  /// Throws a [ServerException] if the response doesn't have a success status code.
  /// Throws a [ClientException] if the response JSON body can't be decoded.
  Future<T> readJson<T>(
    Uri url, {
    Map<String, String>? headers,
    required T Function(Map<String, dynamic>) mapper,
  }) async {
    final response = await get(url, headers: headers);
    _checkResponseSuccess(url, response);
    final json = jsonUtf8Decoder.convert(response.bodyBytes);
    if (json is! Map<String, dynamic>) {
      _logger.severe('Could not read JSON object as $T: expected an object.');
      throw ClientException(
        'Could not read JSON object as $T: expected an object.',
        redactUriForLogging(url),
      );
    }
    try {
      return mapper(json);
    } catch (e, st) {
      _logger.severe('Could not read JSON object as $T:', e, st);
      throw ClientException('Could not read JSON object as $T: $e\n$st', redactUriForLogging(url));
    }
  }

  /// Sends an HTTP GET request with the given headers to the given URL and
  /// returns a Future that completes to the body of the response as a JSON list
  /// of objects mapped to [T].
  ///
  /// Throws a [ServerException] if the response doesn't have a success status code.
  /// Throws a [ClientException] if the response JSON body can't be decoded.
  Future<IList<T>> readJsonList<T>(
    Uri url, {
    Map<String, String>? headers,
    required T? Function(Map<String, dynamic>) mapper,
  }) async {
    final response = await get(url, headers: headers);
    _checkResponseSuccess(url, response);
    final json = jsonUtf8Decoder.convert(response.bodyBytes);
    if (json is! List<dynamic>) {
      _logger.severe('Could not read JSON object as List: expected a list.');
      throw ClientException(
        'Could not read JSON object as List: expected a list.',
        redactUriForLogging(url),
      );
    }

    final List<T> list = [];
    for (final e in json) {
      if (e is! Map<String, dynamic>) {
        _logger.severe('Could not read JSON object as $T: expected an object.');
        throw ClientException(
          'Could not read JSON object as $T: expected an object.',
          redactUriForLogging(url),
        );
      }
      try {
        final mapped = mapper(e);
        if (mapped != null) {
          list.add(mapped);
        }
      } catch (e, st) {
        _logger.severe('Could not read JSON object as $T:', e, st);
        throw ClientException('Could not read JSON object as $T: $e', redactUriForLogging(url));
      }
    }
    return IList(list);
  }

  /// Sends an HTTP GET request with the given headers to the given URL and
  /// returns a Future that completes to the body of the response as a ND-JSON
  /// list of objects mapped to [T].
  ///
  /// Throws a [ServerException] if the response doesn't have a success status code.
  /// Throws a [ClientException] if the response JSON body can't be decoded.
  Future<IList<T>> readNdJsonList<T>(
    Uri url, {
    Map<String, String>? headers,
    required T Function(Map<String, dynamic>) mapper,
  }) async {
    final response = await get(url, headers: headers);
    _checkResponseSuccess(url, response);
    return _readNdJsonList(response, mapper);
  }

  /// Sends an HTTP GET request with the given headers to the given URL and
  /// returns a Future that completes to the stream of the response as a ND-JSON
  /// object mapped to T.
  ///
  /// Throws a [ServerException] if the response doesn't have a success status code.
  /// Throws a [ClientException] if the response JSON body can't be decoded.
  Future<Stream<T>> readNdJsonStream<T>(
    Uri url, {
    Map<String, String>? headers,
    required T Function(Map<String, dynamic>) mapper,
  }) async {
    final request = Request('GET', url);
    if (headers != null) request.headers.addAll(headers);
    final response = await send(request);
    if (response.statusCode >= 400) {
      var message =
          'Request to ${redactUriForLogging(url)} failed with status ${response.statusCode}';
      if (response.reasonPhrase != null) {
        message = '$message: ${response.reasonPhrase}';
      }
      throw ServerException(response.statusCode, '$message.', redactUriForLogging(url), null);
    }
    try {
      return response.stream.map(utf8.decode).where((e) => e.isNotEmpty && e != '\n').map((e) {
        final json = jsonDecode(e) as Map<String, dynamic>;
        return mapper(json);
      });
    } catch (e, st) {
      _logger.severe('Could not read nd-json object as $T.', e, st);
      throw ClientException('Could not read nd-json object as $T: $e', redactUriForLogging(url));
    }
  }

  /// Sends an HTTP POST request with the given headers and body to the given URL and
  /// returns a Future that completes to the body of the response as a JSON object
  /// mapped to [T].
  ///
  /// Throws a [ServerException] if the response doesn't have a success status code.
  /// Throws a [ClientException] if the response JSON body can't be decoded.
  Future<T> postReadJson<T>(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
    required T Function(Map<String, dynamic>) mapper,
  }) async {
    final response = await post(url, headers: headers, body: body, encoding: encoding);
    _checkResponseSuccess(url, response);
    final json = jsonUtf8Decoder.convert(response.bodyBytes);
    if (json is! Map<String, dynamic>) {
      _logger.severe('Could not read json object as $T: expected an object.');
      throw ClientException(
        'Could not read json object as $T: expected an object.',
        redactUriForLogging(url),
      );
    }
    try {
      return mapper(json);
    } catch (e, st) {
      _logger.severe('Could not read json as $T:', e, st);
      throw ClientException('Could not read json as $T: $e', redactUriForLogging(url));
    }
  }

  /// Sends an HTTP POST request with the given headers and body to the given URL and
  /// returns a Future that completes to the body of the response as a JSON list
  /// of objects mapped to [T].
  ///
  /// Throws a [ServerException] if the response doesn't have a success status code.
  /// Throws a [ClientException] if the response JSON body can't be decoded.
  Future<IList<T>> postReadNdJsonList<T>(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
    required T Function(Map<String, dynamic>) mapper,
  }) async {
    final response = await post(url, headers: headers, body: body, encoding: encoding);
    _checkResponseSuccess(url, response);
    return _readNdJsonList(response, mapper);
  }

  IList<T> _readNdJsonList<T>(Response response, T Function(Map<String, dynamic>) mapper) {
    try {
      return IList(
        LineSplitter.split(
          utf8.decode(response.bodyBytes),
        ).where((e) => e.isNotEmpty && e != '\n').map((e) {
          final json = jsonDecode(e) as Map<String, dynamic>;
          return mapper(json);
        }),
      );
    } catch (e, st) {
      _logger.severe('Could not read nd-json objects as List<$T>.', e, st);
      throw ClientException(
        'Could not read nd-json objects as List<$T>: $e',
        response.request == null ? null : redactUriForLogging(response.request!.url),
      );
    }
  }
}

extension ClientRefExtension on Ref {
  /// Runs [fn] with a [LichessClient].
  Future<T> withClient<T>(Future<T> Function(LichessClient) fn) async {
    final client = read(lichessClientProvider);
    return await fn(client);
  }

  /// Runs [fn] with a [LichessClient] and keeps the provider alive for [duration].
  ///
  /// This is primarily used for caching network requests in a [FutureProvider].
  ///
  /// If [fn] throws with a [ServerException], the provider is kept alive as we don't want to retry
  /// server errors immediately.
  Future<U> withClientCacheFor<U>(Future<U> Function(LichessClient) fn, Duration duration) async {
    final link = cacheFor(duration);
    final client = read(lichessClientProvider);
    try {
      return await fn(client);
    } on ServerException {
      rethrow;
    } on Exception {
      link.close();
      rethrow;
    }
  }

  /// Runs [fn] with the [Aggregator] and keeps the provider alive for [duration].
  ///
  /// This is primarily used for caching network requests in a [FutureProvider].
  ///
  /// If [fn] throws with a [ServerException], the provider is kept alive as we don't want to retry
  /// server errors immediately.
  Future<U> withAggregatorCacheFor<U>(
    Future<U> Function(LichessClient, Aggregator) fn,
    Duration duration,
  ) async {
    final link = cacheFor(duration);
    final client = read(lichessClientProvider);
    final aggregator = read(aggregatorProvider);
    try {
      return await fn(client, aggregator);
    } on ServerException {
      rethrow;
    } on Exception {
      link.close();
      rethrow;
    }
  }
}
