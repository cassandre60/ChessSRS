// SPEC coverage: INV-064.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chess_srs/src/model/common/socket.dart';
import 'package:chess_srs/src/network/connectivity.dart';
import 'package:chess_srs/src/network/http.dart';
import 'package:chess_srs/src/network/socket.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/misc.dart' show Override, ProviderOrFamily;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../binding.dart';
import '../test_container.dart';
import '../test_helpers.dart';
import '../utils/fake_connectivity.dart';
import 'fake_http_client_factory.dart';
import 'fake_websocket_channel.dart';

final defaultSocketUri = Uri(path: kDefaultSocketRoute);

SocketClient makeTestSocketClient({
  Uri? route,
  WebSocketChannelFactory fakeChannelFactory = defaultFakeWebSocketChannelFactory,
  int? version,
  VoidCallback? onEventGapFailure,
  Duration? pingDelay,
  Duration? pingMaxLag,
  Duration? autoReconnectDelay,
  Duration? reconnectGracePeriod,
  Duration? resendAckDelay,
}) {
  final client = SocketClient(
    route ?? defaultSocketUri,
    version: version,
    channelFactory: fakeChannelFactory,
    onEventGapFailure: onEventGapFailure,
    getSession: () => null,
    sri: 'testSri',
    packageInfo: PackageInfo(
      appName: 'chess_srs_test',
      version: 'test',
      buildNumber: '0.0.0',
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
    pingDelay: pingDelay ?? const Duration(milliseconds: 50),
    pingMaxLag: pingMaxLag ?? const Duration(milliseconds: 200),
    autoReconnectDelay: autoReconnectDelay ?? const Duration(milliseconds: 100),
    reconnectGracePeriod: reconnectGracePeriod ?? const Duration(seconds: 1),
    resendAckDelay: resendAckDelay ?? const Duration(milliseconds: 100),
  );

  return client;
}

/// Collects every log record the socket writes, the fine-grained ones included.
///
/// The root logger is raised for the duration of the test and put back afterwards: the socket
/// says plenty of things that are only interesting at the level it says them at.
List<LogRecord> collectLogRecords() {
  final records = <LogRecord>[];
  final previousLevel = Logger.root.level;
  Logger.root.level = Level.FINE;
  addTearDown(() => Logger.root.level = previousLevel);
  final subscription = Logger.root.onRecord.listen(records.add);
  addTearDown(subscription.cancel);
  return records;
}

/// A [WebSocketChannelFactory] that hands out one prepared channel, for the fakes that are built
/// around a single scripted connection rather than a route.
class _SingleChannelFactory implements WebSocketChannelFactory {
  const _SingleChannelFactory(this.channel);

  final WebSocketChannel channel;

  @override
  Future<WebSocketChannel> create(
    String url, {
    Map<String, dynamic>? headers,
    Duration timeout = const Duration(seconds: 1),
  }) async => channel;
}

/// A [WebSocketChannelFactory] that records the URL of every connection it is asked for.
///
/// The fakes above key their channels by path alone, so a connection missing its query string is
/// indistinguishable from one carrying it — which is how a handshake lila answers with a 400 went
/// unnoticed: every test saw a channel open.
class _RecordingUrlChannelFactory implements WebSocketChannelFactory {
  final urls = <String>[];

  @override
  Future<WebSocketChannel> create(
    String url, {
    Map<String, dynamic>? headers,
    Duration timeout = const Duration(seconds: 1),
  }) async {
    urls.add(url);
    return createDefaultFakeWebSocketChannel(Uri.parse(url));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestLichessBinding.ensureInitialized();

  group('SocketClient', () {
    test('the client refuses a timing it cannot work with', () {
      // A zero delay is not a slower ping: it is a ping storm, a reconnect loop with no breathing
      // room between the attempts, or an acknowledgement replayed on every turn of the event
      // loop. The constructor is where that is caught.
      expect(() => makeTestSocketClient(pingDelay: Duration.zero), throwsAssertionError);
      expect(() => makeTestSocketClient(pingMaxLag: Duration.zero), throwsAssertionError);
      expect(() => makeTestSocketClient(autoReconnectDelay: Duration.zero), throwsAssertionError);
      expect(() => makeTestSocketClient(reconnectGracePeriod: Duration.zero), throwsAssertionError);
      expect(() => makeTestSocketClient(resendAckDelay: Duration.zero), throwsAssertionError);
    });

    test('connects with the sri in the query string', () async {
      final factory = _RecordingUrlChannelFactory();

      final socketClient = makeTestSocketClient(fakeChannelFactory: factory);
      await socketClient.connect();
      await socketClient.close();

      expect(Uri.parse(factory.urls.single).queryParameters['sri'], 'testSri');
    });

    test('connects with the sri in the query string on the analysis route', () async {
      // The F-CLOUDEVAL path: cloud eval goes out over /analysis/socket, and
      // INV-064 holds per route, not just for the default one.
      final factory = _RecordingUrlChannelFactory();

      final socketClient = makeTestSocketClient(
        route: Uri(path: '/analysis/socket/v5'),
        fakeChannelFactory: factory,
      );
      await socketClient.connect();
      await socketClient.close();

      final url = Uri.parse(factory.urls.single);
      expect(url.path, '/analysis/socket/v5');
      expect(url.queryParameters['sri'], 'testSri');
    });

    test('handles ping/pong', () async {
      final fakeChannel = FakeWebSocketChannel(defaultSocketUri);

      final socketClient = makeTestSocketClient(
        fakeChannelFactory: FakeWebSocketChannelFactory((_) => fakeChannel),
      );
      socketClient.connect();

      int sentPingCount = 0;
      fakeChannel.sentMessages.forEach((message) {
        if (FakeWebSocketChannel.isPing(message)) {
          sentPingCount++;
          // close after 3 pings
          if (sentPingCount == 3) {
            socketClient.close();
          }
        }
      });

      // 1 ready event is expected
      expectLater(socketClient.connectedStream, emitsInOrder([null]));

      // 2 pong messages are expected since we're closing just after 3 pings
      await expectLater(fakeChannel.stream, emitsInOrder(['0', '0']));
    });

    test('the ping that carries the lag goes out every tenth time', () {
      fakeAsync((async) {
        final fakeChannel = FakeWebSocketChannel(defaultSocketUri);

        // The listener goes in first: the first ping goes out with the handshake.
        final sent = <dynamic>[];
        fakeChannel.sentMessages.listen(sent.add);

        final socketClient = makeTestSocketClient(
          fakeChannelFactory: FakeWebSocketChannelFactory((_) => fakeChannel),
        );
        socketClient.connect();
        async.flushMicrotasks();

        // Long enough for a dozen pings and a dozen pongs.
        async.elapse(const Duration(milliseconds: 700));
        async.flushMicrotasks();

        final pings = sent.where(FakeWebSocketChannel.isPing).toList();
        final lagPings = <int>[];
        for (var i = 0; i < pings.length; i++) {
          if (pings[i] != 'p') lagPings.add(i);
        }

        expect(lagPings, isNotEmpty, reason: 'the sweep was long enough to see the pattern');
        expect(
          lagPings.every((index) => index % 10 == 2),
          isTrue,
          reason: 'the lag rides on every tenth ping, and on no other',
        );
        for (final index in lagPings) {
          final decoded = jsonDecode(pings[index] as String) as Map<String, dynamic>;
          expect(decoded['t'], 'p');
          expect(decoded['l'], isA<int>(), reason: 'the ping carries the lag it measured');
        }
      });
    });

    test('reconnects when connection attempt fails', () async {
      int numConnectionAttempts = 0;

      final fakeChannelFactory = FakeWebSocketChannelFactory((_) {
        numConnectionAttempts++;
        if (numConnectionAttempts == 1) {
          throw const SocketException('Connection failed');
        }
        return FakeWebSocketChannel(defaultSocketUri);
      });

      final socketClient = makeTestSocketClient(fakeChannelFactory: fakeChannelFactory);
      socketClient.connect();

      // The first connection attempt will fail, but the second one will succeed
      await socketClient.firstConnection;

      expect(numConnectionAttempts, 2);
      expect(socketClient.nbConnectionAttempts, 2);
      expect(socketClient.nbConnectionSuccess, 1);

      socketClient.close();
    });

    test('logs a connection failure at the level its cause deserves', () async {
      var attempts = 0;
      final fakeChannelFactory = FakeWebSocketChannelFactory((_) {
        attempts++;
        return switch (attempts) {
          // What a device with no network looks like: routine, and not worth a log the user's
          // crash reports would have to carry.
          1 => throw const SocketException('Connection failed'),
          // The server answered, but not with a websocket: a regression on its side, or a TLS
          // chain the device will not trust.
          2 => throw const WebSocketException('Connection was not upgraded to websocket'),
          // A bug in the connection setup, which no amount of retrying will fix.
          3 => throw StateError('boom'),
          _ => FakeWebSocketChannel(defaultSocketUri),
        };
      });

      final records = <LogRecord>[];
      final subscription = Logger.root.onRecord
          .where((record) => record.level >= Level.WARNING)
          .listen(records.add);
      addTearDown(subscription.cancel);

      final socketClient = makeTestSocketClient(fakeChannelFactory: fakeChannelFactory);
      socketClient.connect();

      await socketClient.firstConnection;
      expect(attempts, 4);

      expect(records, hasLength(2), reason: 'the missing network alone is not reported');
      expect(records.first.level, Level.WARNING);
      expect(records.first.error, isA<WebSocketException>());
      expect(records.last.level, Level.SEVERE);
      expect(records.last.error, isStateError);
      expect(
        records.every((record) => record.stackTrace != null),
        isTrue,
        reason: 'the stack trace is what points at the line that threw',
      );

      socketClient.close();
    });

    test('the first pong timeout reconnects at once, the ones after it wait', () {
      var channelsCreated = 0;
      final fakeChannelFactory = FakeWebSocketChannelFactory((route) {
        channelsCreated++;
        return FakeWebSocketChannel(route)..shouldSendPong = false;
      });

      fakeAsync((async) {
        // The ping goes out as the socket opens, so the first pong times out at [pingMaxLag].
        final socketClient = makeTestSocketClient(fakeChannelFactory: fakeChannelFactory);
        socketClient.connect();

        async.elapse(const Duration(milliseconds: 199));
        expect(channelsCreated, 1);

        // 1ms past the timeout, and well short of the 100ms [autoReconnectDelay] this client is
        // built with: the socket has already spent [pingMaxLag] waiting, so it retries at once.
        async.elapse(const Duration(milliseconds: 2));
        expect(channelsCreated, 2);

        // That attempt goes the same way, and this one does wait: a peer that keeps accepting
        // handshakes and answering nothing must not be retried every [pingMaxLag] forever.
        async.elapse(const Duration(milliseconds: 249));
        expect(channelsCreated, 2, reason: 'the second timeout waits out the backoff');

        async.elapse(const Duration(milliseconds: 100));
        expect(channelsCreated, 3);

        socketClient.close();
        async.flushTimers();
      });
    });

    test('a message sent after a connection that broke while opening is queued, not lost', () {
      // Every message this client sends, ping excepted, whichever channel it goes out on: one
      // written to the channel of the attempt that failed would show up here just the same.
      final sent = <dynamic>[];
      var nextChannelFailsItsPing = true;
      final fakeChannelFactory = FakeWebSocketChannelFactory((route) {
        final channel = FakeWebSocketChannel(route);
        if (nextChannelFailsItsPing) {
          nextChannelFailsItsPing = false;
          channel.failWriteWhen = FakeWebSocketChannel.isPing;
        }
        channel.sentMessagesExceptPing.listen(sent.add);
        return channel;
      });

      fakeAsync((async) {
        // The handshake succeeds and the peer is gone by the first ping: the attempt fails with a
        // channel of its own already in hand.
        final socketClient = makeTestSocketClient(fakeChannelFactory: fakeChannelFactory);
        socketClient.connect();
        async.elapse(const Duration(milliseconds: 20));
        expect(socketClient.isFailing.value, isTrue);
        expect(socketClient.isConnected, isFalse);

        socketClient.send('test', {'foo': 'bar'});
        async.elapse(const Duration(milliseconds: 10));
        expect(sent, isEmpty, reason: 'the channel of the failed attempt is gone');

        // It goes out on the connection that the retry makes instead.
        async.elapse(const Duration(seconds: 1));
        expect(socketClient.isConnected, isTrue);
        expect(sent, [
          jsonEncode({
            't': 'test',
            'd': {'foo': 'bar'},
          }),
        ]);

        socketClient.close();
        async.flushTimers();
      });
    });

    test('a message sent with noRetry is dropped rather than queued', () {
      var canConnect = false;
      final sent = <dynamic>[];
      final fakeChannelFactory = FakeWebSocketChannelFactory((route) {
        if (!canConnect) throw const SocketException('No internet');
        final channel = FakeWebSocketChannel(route);
        channel.sentMessagesExceptPing.listen(sent.add);
        return channel;
      });

      fakeAsync((async) {
        final socketClient = makeTestSocketClient(fakeChannelFactory: fakeChannelFactory);
        socketClient.connect();
        async.elapse(const Duration(milliseconds: 20));
        expect(socketClient.isConnected, isFalse);

        // The keep-alive is only true of the moment it is sent; the other message is not.
        socketClient.send('keepAlive', null, noRetry: true);
        socketClient.send('talk', null);

        canConnect = true;
        async.elapse(const Duration(seconds: 1));

        expect(socketClient.isConnected, isTrue);
        expect(sent, [
          jsonEncode({'t': 'talk'}),
        ]);

        socketClient.close();
        async.flushTimers();
      });
    });

    test('a flush that breaks partway keeps the messages it did not send', () {
      var canConnect = false;
      var nextChannelBreaks = true;
      final sent = <dynamic>[];
      final fakeChannelFactory = FakeWebSocketChannelFactory((route) {
        if (!canConnect) throw const SocketException('No internet');
        final channel = FakeWebSocketChannel(route);
        if (nextChannelBreaks) {
          nextChannelBreaks = false;
          // This peer takes the first message and hangs up on the second.
          channel.failWriteWhen = (data) => data is String && data.contains('"t":"second"');
        }
        channel.sentMessagesExceptPing.listen(sent.add);
        return channel;
      });

      fakeAsync((async) {
        final socketClient = makeTestSocketClient(fakeChannelFactory: fakeChannelFactory);
        socketClient.connect();
        async.elapse(const Duration(milliseconds: 20));
        expect(socketClient.isFailing.value, isTrue);

        socketClient.send('first', null);
        socketClient.send('second', null);

        // The socket gets a channel again, and the flush breaks halfway through it.
        canConnect = true;
        async.elapse(const Duration(milliseconds: 150));
        expect(sent, [
          jsonEncode({'t': 'first'}),
        ]);
        expect(socketClient.isFailing.value, isTrue);

        // The message that sink never took is still queued, and goes out on the next connection.
        async.elapse(const Duration(seconds: 1));
        expect(socketClient.isConnected, isTrue);
        expect(sent, [
          jsonEncode({'t': 'first'}),
          jsonEncode({'t': 'second'}),
        ]);

        socketClient.close();
        async.flushTimers();
      });
    });

    test('a message sent while the socket waits out its backoff is queued, not lost', () {
      var offline = false;
      // Every message this client sends, ping excepted, whichever channel it goes out on: one
      // written to a channel that is already gone would show up here just the same.
      final sent = <dynamic>[];
      FakeWebSocketChannel? currentChannel;
      final fakeChannelFactory = FakeWebSocketChannelFactory((route) {
        if (offline) throw const SocketException('No internet');
        final channel = FakeWebSocketChannel(route);
        channel.sentMessagesExceptPing.listen(sent.add);
        return currentChannel = channel;
      });

      fakeAsync((async) {
        final socketClient = makeTestSocketClient(fakeChannelFactory: fakeChannelFactory);
        socketClient.connect();

        async.elapse(const Duration(milliseconds: 20));
        expect(socketClient.isConnected, isTrue);

        // The network goes away under the socket: the ping goes unanswered, and the attempts that
        // follow cannot get a channel either, so the client is left waiting out its backoff.
        offline = true;
        currentChannel!.shouldSendPong = false;
        async.elapse(const Duration(seconds: 1));
        expect(socketClient.isFailing.value, isTrue);
        expect(socketClient.isConnected, isFalse);

        socketClient.send('test', {'foo': 'bar'});
        async.elapse(const Duration(milliseconds: 500));
        expect(sent, isEmpty, reason: 'there is no channel to write it to');

        // It goes out on the connection that the network coming back makes possible.
        offline = false;
        async.elapse(const Duration(seconds: 2));

        expect(socketClient.isConnected, isTrue);
        expect(sent, [
          jsonEncode({
            't': 'test',
            'd': {'foo': 'bar'},
          }),
        ]);

        socketClient.close();
        async.flushTimers();
      });
    });

    test('a channel that takes its time closing does not disconnect the one after it', () {
      final channels = <FakeWebSocketChannel>[];
      final fakeChannelFactory = FakeWebSocketChannelFactory((route) {
        final channel = FakeWebSocketChannel(route)..closeDelay = const Duration(seconds: 5);
        channels.add(channel);
        return channel;
      });

      fakeAsync((async) {
        final socketClient = makeTestSocketClient(fakeChannelFactory: fakeChannelFactory);
        socketClient.connect();
        async.elapse(const Duration(milliseconds: 20));
        expect(socketClient.isConnected, isTrue);

        // Reconnecting closes the first channel, which takes seconds to finish doing so — long
        // after the socket that replaced it has answered a ping of its own.
        socketClient.connect();
        async.elapse(const Duration(milliseconds: 20));
        expect(channels.length, 2);
        expect(socketClient.isConnected, isTrue);

        var disconnections = 0;
        socketClient.averageLag.addListener(() {
          if (socketClient.averageLag.value == Duration.zero) disconnections++;
        });

        async.elapse(const Duration(seconds: 6));

        expect(socketClient.isConnected, isTrue);
        expect(disconnections, 0, reason: 'the old channel closing says nothing about this one');

        socketClient.close();
        async.flushTimers();
      });
    });

    test('a connection the peer drops is failing at once', () {
      FakeWebSocketChannel? channel;
      final fakeChannelFactory = FakeWebSocketChannelFactory(
        (route) => channel = FakeWebSocketChannel(route),
      );

      fakeAsync((async) {
        final socketClient = makeTestSocketClient(fakeChannelFactory: fakeChannelFactory);
        socketClient.connect();

        async.elapse(const Duration(milliseconds: 20));
        expect(socketClient.isConnected, isTrue);

        // What a device losing its network under an open socket looks like: the channel is torn
        // down, and there is nothing to wait for — least of all the pong timeout.
        channel!.closeFromServer(const SocketException('Network is unreachable'));
        async.elapse(const Duration(milliseconds: 1));

        expect(socketClient.isFailing.value, isTrue);
        expect(socketClient.isConnected, isFalse);

        socketClient.close();
        async.flushTimers();
      });
    });

    test('a connection the peer closes cleanly is failing at once', () {
      FakeWebSocketChannel? channel;
      final fakeChannelFactory = FakeWebSocketChannelFactory(
        (route) => channel = FakeWebSocketChannel(route),
      );

      fakeAsync((async) {
        final socketClient = makeTestSocketClient(fakeChannelFactory: fakeChannelFactory);
        socketClient.connect();

        async.elapse(const Duration(milliseconds: 20));
        expect(socketClient.isConnected, isTrue);

        channel!.closeFromServer();
        async.elapse(const Duration(milliseconds: 1));

        expect(socketClient.isFailing.value, isTrue);
        expect(socketClient.isConnected, isFalse);

        socketClient.close();
        async.flushTimers();
      });
    });

    test('a socket that opens but never answers a ping is failing', () {
      var serverAnswers = false;
      var channelsCreated = 0;
      final fakeChannelFactory = FakeWebSocketChannelFactory((route) {
        channelsCreated++;
        return FakeWebSocketChannel(route)..shouldSendPong = serverAnswers;
      });

      fakeAsync((async) {
        final socketClient = makeTestSocketClient(fakeChannelFactory: fakeChannelFactory);
        var failingChanges = 0;
        socketClient.isFailing.addListener(() => failingChanges++);
        socketClient.connect();

        async.elapse(const Duration(milliseconds: 10));
        expect(socketClient.isFailing.value, isFalse, reason: 'the first ping has yet to time out');

        // The handshake keeps succeeding, so nothing here fails to connect: it is the ping going
        // unanswered that says this socket is no use.
        async.elapse(const Duration(seconds: 1));
        expect(socketClient.isFailing.value, isTrue);
        expect(failingChanges, 1);

        final attemptsSoFar = channelsCreated;

        // Every one of those handshakes used to end the run, which kept the backoff at its
        // shortest and told nobody the socket was failing.
        async.elapse(const Duration(seconds: 5));
        expect(channelsCreated, greaterThan(attemptsSoFar), reason: 'it does keep reconnecting');
        expect(socketClient.isFailing.value, isTrue);
        expect(failingChanges, 1, reason: 'one run, not one per try');

        // The server answers again: a pong, not a handshake, is what ends the run.
        serverAnswers = true;
        async.elapse(const Duration(seconds: 30));
        expect(socketClient.isFailing.value, isFalse);
        expect(socketClient.isConnected, isTrue);

        socketClient.close();
        async.flushTimers();
      });
    });

    test('a socket that never answers a ping is retried on the backoff, not on every timeout', () {
      var channelsCreated = 0;
      final fakeChannelFactory = FakeWebSocketChannelFactory((route) {
        channelsCreated++;
        return FakeWebSocketChannel(route)..shouldSendPong = false;
      });

      fakeAsync((async) {
        final socketClient = makeTestSocketClient(fakeChannelFactory: fakeChannelFactory);
        socketClient.connect();

        // Within the grace period the socket retries at full speed: a peer that has just stopped
        // answering is worth a few quick attempts.
        async.elapse(const Duration(seconds: 1));
        final earlyAttempts = channelsCreated;
        expect(earlyAttempts, greaterThan(2));

        // Minutes of a peer that accepts every handshake and answers nothing: the delay between
        // attempts has grown to its ceiling instead of staying at the pong timeout.
        async.elapse(const Duration(minutes: 5));
        final attemptsSoFar = channelsCreated;
        async.elapse(const Duration(minutes: 1));

        expect(
          channelsCreated - attemptsSoFar,
          lessThanOrEqualTo(2),
          reason: 'a minute of a socket that never answers is worth about one attempt',
        );

        socketClient.close();
        async.flushTimers();
      });
    });

    test('does not reconnect when closed while a connection attempt is in flight', () {
      int numConnectionAttempts = 0;

      // Simulates a server that never accepts the connection: each attempt fails after a delay,
      // like a connection timeout would.
      final fakeChannelFactory = DelayedFakeWebSocketChannelFactory(
        const Duration(milliseconds: 100),
        (_) {
          numConnectionAttempts++;
          throw const SocketException('Connection failed');
        },
      );

      final socketClient = makeTestSocketClient(fakeChannelFactory: fakeChannelFactory);

      fakeAsync((async) {
        socketClient.connect();

        // Close while the first attempt is still awaiting the channel creation.
        async.elapse(const Duration(milliseconds: 49));
        expect(numConnectionAttempts, 0, reason: 'the attempt is still awaiting channel creation');
        socketClient.close();
        async.elapse(Duration.zero);

        // Long enough for the in-flight attempt to fail at the factory delay's exact edge and for
        // a reconnect to have been scheduled (autoReconnectDelay is 100ms) — and not fired.
        async.elapse(const Duration(milliseconds: 51));
        expect(numConnectionAttempts, 1, reason: 'the in-flight attempt still fails and counts');

        async.elapse(const Duration(milliseconds: 99));
        expect(socketClient.isActive, isFalse, reason: 'nothing pends for a closed client');
        async.elapse(const Duration(milliseconds: 1));
        expect(
          numConnectionAttempts,
          1,
          reason: 'close during the in-flight attempt cancels reconnection',
        );
        expect(socketClient.isActive, isFalse);
      });
    });

    test('discards a connection that succeeds after the client was closed', () {
      final Map<int, FakeWebSocketChannel> channels = {};
      int numConnectionAttempts = 0;

      final fakeChannelFactory = DelayedFakeWebSocketChannelFactory(
        const Duration(milliseconds: 100),
        (_) {
          numConnectionAttempts++;
          final channel = FakeWebSocketChannel(defaultSocketUri);
          channels[numConnectionAttempts] = channel;
          return channel;
        },
      );

      final socketClient = makeTestSocketClient(fakeChannelFactory: fakeChannelFactory);

      fakeAsync((async) {
        socketClient.connect();

        // Close while the connection attempt is still awaiting the channel creation.
        async.elapse(const Duration(milliseconds: 49));
        socketClient.close();
        async.elapse(Duration.zero);

        // The channel created by the stale attempt must not be adopted, and must be closed.
        async.elapse(const Duration(milliseconds: 50));
        async.elapse(Duration.zero);
        expect(channels[1], isNull, reason: 'creation happens exactly at the factory delay edge');
        async.elapse(const Duration(milliseconds: 1));
        async.elapse(Duration.zero);
        expect(channels[1], isNotNull);
        expect(
          channels[1]!.closeCode,
          isNotNull,
          reason: 'the stale channel is closed, not adopted',
        );
        expect(socketClient.isConnected, false);
        expect(socketClient.nbConnectionSuccess, 0, reason: 'a stale success is not a success');

        // A client closed mid-attempt stays closed: no late reconnect may surface.
        async.elapse(const Duration(milliseconds: 100));
        expect(numConnectionAttempts, 1, reason: 'close during the attempt cancels reconnection');
        expect(socketClient.isActive, isFalse);
      });
    });

    test('retries at full speed during the grace period, then backs off', () {
      final attempts = <Duration>[];

      fakeAsync((async) {
        final start = async.elapsed;
        final socketClient = makeTestSocketClient(
          fakeChannelFactory: FakeWebSocketChannelFactory((_) {
            attempts.add(async.elapsed - start);
            throw const SocketException('Network is unreachable');
          }),
        );
        socketClient.connect();

        // The grace period is 1s in tests, the reconnect delay 100ms.
        async.elapse(const Duration(seconds: 5));

        final gaps = [for (var i = 1; i < attempts.length; i++) attempts[i] - attempts[i - 1]];

        expect(
          gaps.take(11),
          everyElement(const Duration(milliseconds: 100)),
          reason: 'a blip must not be made to wait',
        );
        expect(gaps[11], const Duration(milliseconds: 200), reason: 'then the delay doubles');
        expect(gaps.last, greaterThan(const Duration(milliseconds: 200)));

        socketClient.close();
        async.flushTimers();
      });
    });

    test('a successful connection resets the backoff', () {
      fakeAsync((async) {
        final attempts = <Duration>[];
        final start = async.elapsed;
        var failing = true;
        final socketClient = makeTestSocketClient(
          fakeChannelFactory: FakeWebSocketChannelFactory((route) {
            attempts.add(async.elapsed - start);
            if (failing) throw const SocketException('Network is unreachable');
            return FakeWebSocketChannel(route);
          }),
        );
        socketClient.connect();

        // Fail well past the grace period, so the delay has grown.
        async.elapse(const Duration(seconds: 5));
        final grownGap = attempts.last - attempts[attempts.length - 2];
        expect(grownGap, greaterThan(const Duration(milliseconds: 100)));

        // The network comes back, then drops again: the next retry is at full speed, since this is
        // a new failure and not the continuation of the old one.
        failing = false;
        async.elapse(const Duration(seconds: 5));
        expect(socketClient.nbConnectionSuccess, greaterThan(0));

        failing = true;
        attempts.clear();
        socketClient.connect();
        async.elapse(const Duration(milliseconds: 250));

        expect(attempts[1] - attempts[0], const Duration(milliseconds: 100));

        socketClient.close();
        async.flushTimers();
      });
    });

    test('reconnects automatically if pong is not received', () async {
      int numConnectionAttempts = 0;
      // channels per connection attempt
      final Map<int, FakeWebSocketChannel> channels = {};

      final fakeChannelFactory = FakeWebSocketChannelFactory((_) {
        numConnectionAttempts++;
        final channel = FakeWebSocketChannel(defaultSocketUri);
        int sentPingCount = 0;
        channel.sentMessages.forEach((message) {
          if (FakeWebSocketChannel.isPing(message)) {
            sentPingCount++;
            // on first connection, stop responding to pings after 3 pings
            if (numConnectionAttempts == 1 && sentPingCount == 3) {
              channel.shouldSendPong = false;
            }
          }
        });
        channels[numConnectionAttempts] = channel;

        return channel;
      });

      final socketClient = makeTestSocketClient(fakeChannelFactory: fakeChannelFactory);
      socketClient.connect();

      await socketClient.firstConnection;

      // will only receive 3 pings since the server stops responding to pings
      expectLater(channels[1]!.stream, emitsInOrder(['0', '0', '0']));

      // we expect another connection because it reconnects if not receiving pong
      await expectLater(socketClient.connectedStream, emits(null));

      // check the first connection was closed
      // no need to check the close code since it will alway be 1000 in our fake channel
      expect(channels[1]!.closeCode, isNotNull);
      expect(channels[2]!.closeCode, isNull);

      socketClient.close();
    });

    test('computes average lag', () async {
      final fakeChannel = FakeWebSocketChannel(
        defaultSocketUri,
        connectionLag: const Duration(milliseconds: 10),
      );

      final socketClient = makeTestSocketClient(
        fakeChannelFactory: FakeWebSocketChannelFactory((_) => fakeChannel),
      );
      socketClient.connect();

      // before the connection is ready the average lag is zero
      expect(socketClient.averageLag.value, Duration.zero);

      await socketClient.firstConnection;

      // after the connection is ready the average lag is still zero since
      // there was no ping/pong exchange yet
      expect(socketClient.averageLag.value, Duration.zero);

      // at this time the first ping is sent, wait for the pong
      await expectLater(fakeChannel.stream, emits('0'));

      // after the ping/pong exchange the average lag is computed
      expect(socketClient.averageLag.value.inMilliseconds, greaterThanOrEqualTo(10));

      // wait for more ping/pong exchanges
      await expectLater(fakeChannel.stream, emitsInOrder(['0', '0', '0', '0']));

      // average lag is still the same
      expect(socketClient.averageLag.value.inMilliseconds, greaterThanOrEqualTo(10));

      // increase the lag of the connection
      fakeChannel.connectionLag = const Duration(milliseconds: 100);

      // wait for more ping/pong exchanges
      await expectLater(fakeChannel.stream, emitsInOrder(['0', '0', '0', '0']));

      // average lag should be higher
      expect(socketClient.averageLag.value.inMilliseconds, greaterThanOrEqualTo(40));

      await socketClient.close();

      // after disconnecting the average lag is zero again
      expect(socketClient.averageLag.value, Duration.zero);
    });

    test('the average lag is the mean of the first four pongs, then a decaying one', () {
      fakeAsync((async) {
        final fakeChannel = FakeWebSocketChannel(
          defaultSocketUri,
          connectionLag: const Duration(milliseconds: 10),
        );

        // Every ping is answered more slowly than the last one, so the pongs differ and the
        // weight the client gives them becomes visible.
        var pings = 0;
        fakeChannel.sentMessages.listen((message) {
          if (!FakeWebSocketChannel.isPing(message)) return;
          pings++;
          fakeChannel.connectionLag = Duration(milliseconds: 10 * (pings + 1));
        });

        final socketClient = makeTestSocketClient(
          fakeChannelFactory: FakeWebSocketChannelFactory((_) => fakeChannel),
        );
        socketClient.connect();
        async.flushMicrotasks();

        // Four pongs: 10ms, 20ms, 30ms and 40ms.
        async.elapse(const Duration(milliseconds: 260));
        async.flushMicrotasks();

        final lags = [10, 20, 30, 40];
        final mean = lags.reduce((a, b) => a + b) ~/ lags.length;
        expect(
          socketClient.averageLag.value.inMilliseconds,
          mean,
          reason: 'the first four pongs are averaged evenly, not weighted',
        );

        // The fifth pong (50ms) moves the average by a tenth of the difference.
        async.elapse(const Duration(milliseconds: 100));
        async.flushMicrotasks();
        expect(
          socketClient.averageLag.value,
          Duration(milliseconds: mean) +
              (const Duration(milliseconds: 50) - Duration(milliseconds: mean)) * 0.1,
          reason: 'after the fourth pong the average decays instead of averaging',
        );
      });
    });

    test('handles ackable messages', () {
      fakeAsync((async) {
        final fakeChannel = FakeWebSocketChannel(defaultSocketUri);

        final socketClient = makeTestSocketClient(
          fakeChannelFactory: FakeWebSocketChannelFactory((_) => fakeChannel),
        );
        socketClient.connect();
        async.elapse(kFakeWebSocketConnectionLag);
        async.flushMicrotasks();

        // Collect every outgoing (non-ping) message. emitsInOrder stops after its
        // last matcher, so it would pass if an extra resend leaked through; the
        // collector + the checks below are what make the negative case fail.
        final emitted = <dynamic>[];
        final collector = fakeChannel.sentMessagesExceptPing.listen(emitted.add);

        // send a message that requires an ack
        socketClient.send('test', {'data': 'ackable'}, ackable: true);
        async.flushMicrotasks();

        // several messages are expected, since the server didn't ack the message
        expectLater(
          fakeChannel.sentMessagesExceptPing,
          emitsInOrder([
            '{"t":"test","d":{"data":"ackable","a":1}}',
            '{"t":"test","d":{"data":"ackable","a":1}}',
            '{"t":"test","d":{"data":"ackable","a":1}}',
          ]),
        );

        // Let the resend timers fire deterministically instead of sleeping.
        async.elapse(const Duration(seconds: 3));
        async.flushMicrotasks();

        // Every message sent so far is the ackable message, byte for byte.
        expect(emitted, isNotEmpty);
        expect(emitted.every((m) => m == '{"t":"test","d":{"data":"ackable","a":1}}'), isTrue);

        final countBeforeAck = emitted.length;

        // server acks the message
        sendServerSocketMessages(defaultSocketUri, ['{"t":"ack","d":1}']);
        async.flushMicrotasks();

        // The ack stops further resends: nothing more is sent afterwards.
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();

        expect(emitted.length, countBeforeAck);

        collector.cancel();
        socketClient.close();
        async.flushTimers();
      });
    });

    test('a message sent with withLag carries the measured lag', () {
      fakeAsync((async) {
        final fakeChannel = FakeWebSocketChannel(defaultSocketUri);

        final socketClient = makeTestSocketClient(
          fakeChannelFactory: FakeWebSocketChannelFactory((_) => fakeChannel),
        );
        socketClient.connect();
        async.elapse(kFakeWebSocketConnectionLag);
        async.flushMicrotasks();

        final sent = <dynamic>[];
        fakeChannel.sentMessagesExceptPing.listen(sent.add);

        socketClient.send('chat', {'room': 'study'}, withLag: true);
        socketClient.send('move', {'u': 'e2e4'}, ackable: true, withLag: true);
        async.flushMicrotasks();

        final lag = socketClient.averageLag.value.inMilliseconds;
        expect(sent, hasLength(2));

        final plain = jsonDecode(sent.first as String) as Map<String, dynamic>;
        expect(plain['d'], containsPair('l', lag), reason: 'a plain message carries the lag');

        final ackable = jsonDecode(sent.last as String) as Map<String, dynamic>;
        expect(ackable['d'], containsPair('l', lag), reason: 'an ackable message carries the lag');
        expect(
          ackable['d'],
          containsPair('u', 'e2e4'),
          reason: 'and keeps the fields it was given',
        );
      });
    });

    test(
      'queues non-ackable messages sent while not connected and flushes them on connect',
      () async {
        final fakeChannel = FakeWebSocketChannel(defaultSocketUri);

        final socketClient = makeTestSocketClient(
          fakeChannelFactory: FakeWebSocketChannelFactory((_) => fakeChannel),
        );

        // Messages sent before the connection is open must be queued, not dropped.
        socketClient.send('test1', null);
        socketClient.send('test2', {'foo': 'bar'});

        // They are flushed, in order, once the connection opens. Subscribe before
        // connecting, since the flush happens as soon as the connection is ready
        // and [sentMessages] is a broadcast stream.
        final expectation = expectLater(
          fakeChannel.sentMessagesExceptPing,
          emitsInOrder(['{"t":"test1"}', '{"t":"test2","d":{"foo":"bar"}}']),
        );

        await socketClient.connect();
        await expectation;

        socketClient.close();
      },
    );

    test('queues a message sent while the socket is connecting and sends it once open', () async {
      final fakeChannel = FakeWebSocketChannel(defaultSocketUri);

      final socketClient = makeTestSocketClient(
        fakeChannelFactory: FakeWebSocketChannelFactory((_) => fakeChannel),
      );

      // Start connecting but don't await: the connection is in progress (the
      // attempt is counted but not yet successful).
      final connectFuture = socketClient.connect();
      expect(socketClient.nbConnectionAttempts, 1);
      expect(socketClient.nbConnectionSuccess, 0);

      // Sent while connecting: must be queued, not dropped.
      socketClient.send('test', null);

      // Subscribe before the connection opens, since the flush is immediate and
      // [sentMessages] is a broadcast stream.
      final expectation = expectLater(
        fakeChannel.sentMessagesExceptPing,
        emitsThrough('{"t":"test"}'),
      );

      await connectFuture;
      expect(socketClient.nbConnectionSuccess, 1);
      await expectation;

      socketClient.close();
    });

    test('queues an ackable message sent while not connected and sends it on connect', () async {
      final fakeChannel = FakeWebSocketChannel(defaultSocketUri);

      final socketClient = makeTestSocketClient(
        fakeChannelFactory: FakeWebSocketChannelFactory((_) => fakeChannel),
      );

      // An ackable message (e.g. a move) sent before the connection is open must
      // be sent as soon as it opens, not only after the ack-resend delay.
      socketClient.send('move', {'u': 'e2e4'}, ackable: true);

      final expectation = expectLater(
        fakeChannel.sentMessagesExceptPing,
        emitsThrough('{"t":"move","d":{"u":"e2e4","a":1}}'),
      );

      await socketClient.connect();
      await expectation;

      socketClient.close();
    });

    test('does not double-send a queued ackable message whose ack is past the resend cutoff', () {
      fakeAsync((async) {
        final fakeChannel = FakeWebSocketChannel(defaultSocketUri);

        final socketClient = makeTestSocketClient(
          fakeChannelFactory: FakeWebSocketChannelFactory((_) => fakeChannel),
        );

        final sent = <dynamic>[];
        fakeChannel.sentMessagesExceptPing.listen(sent.add);

        // Sent while disconnected: queued and also tracked in _acks.
        socketClient.send('move', {'u': 'e2e4'}, ackable: true);

        // Let enough time pass that the ack is older than the resend cutoff
        // (2500ms), so _resendAcks() would otherwise resend it on connect.
        async.elapse(const Duration(seconds: 3));

        socketClient.connect();
        async.elapse(kFakeWebSocketConnectionLag);
        async.flushMicrotasks();

        // It is sent exactly once on reconnect (by the flush), not twice (flush
        // + _resendAcks).
        expect(sent.where((m) => m == '{"t":"move","d":{"u":"e2e4","a":1}}').length, 1);

        socketClient.close();
      });
    });

    test('drops queued and unacknowledged messages when the account changes', () {
      fakeAsync((async) {
        // A fresh channel per connection, as a real reconnect gets: a closed channel's outgoing
        // stream is finished, so reusing one would hide whatever the new connection sends.
        final sent = <String>[];
        final socketClient = makeTestSocketClient(
          fakeChannelFactory: FakeWebSocketChannelFactory((_) {
            final channel = FakeWebSocketChannel(defaultSocketUri);
            channel.sentMessagesExceptPing.listen((m) {
              if (m is String) sent.add(m);
            });
            return channel;
          }),
        );

        socketClient.connect();
        async.elapse(kFakeWebSocketConnectionLag);
        async.flushMicrotasks();

        // An ackable message the server never acknowledges: it stays in _acks and is replayed by
        // _resendAcks on every reconnect.
        socketClient.send('move', {'u': 'e2e4'}, ackable: true);
        // And one composed while the connection is down, queued in _resendWhenOpen.
        socketClient.close();
        socketClient.send('chat', {'room': 'study'});

        // Past the resend cutoff, so a surviving acknowledgement is certain to be replayed.
        async.elapse(const Duration(seconds: 5));

        final sentBeforeAuthChange = sent.length;

        socketClient.onAuthChanged();
        socketClient.connect();
        async.elapse(kFakeWebSocketConnectionLag);
        async.flushMicrotasks();

        // Long enough for another periodic resend sweep.
        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();

        // Only what was delivered *after* the identity change; the original send is legitimate.
        final afterAuthChange = sent.skip(sentBeforeAuthChange);

        expect(
          afterAuthChange.where((m) => m.contains('"move"')),
          isEmpty,
          reason: 'an unacknowledged move from the old account must not reach the new one',
        );
        expect(
          afterAuthChange.where((m) => m.contains('"chat"')),
          isEmpty,
          reason: 'a queued message from the old account must not reach the new one',
        );

        socketClient.close();
        async.flushTimers();
      });
    });

    test('an unacknowledged message is still replayed without an account change', () {
      fakeAsync((async) {
        final sent = <String>[];
        final socketClient = makeTestSocketClient(
          fakeChannelFactory: FakeWebSocketChannelFactory((_) {
            final channel = FakeWebSocketChannel(defaultSocketUri);
            channel.sentMessagesExceptPing.listen((m) {
              if (m is String) sent.add(m);
            });
            return channel;
          }),
        );

        socketClient.connect();
        async.elapse(kFakeWebSocketConnectionLag);
        async.flushMicrotasks();

        socketClient.send('move', {'u': 'e2e4'}, ackable: true);
        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();

        socketClient.close();
        async.elapse(kFakeWebSocketConnectionLag);
        socketClient.connect();
        async.elapse(kFakeWebSocketConnectionLag);
        async.flushMicrotasks();

        // Retry-until-acked is the whole point of the ack queue, so it must survive a plain
        // reconnect. Only an identity change may discard it.
        expect(
          sent.where((m) => m == '{"t":"move","d":{"u":"e2e4","a":1}}'),
          hasLength(greaterThan(1)),
          reason: 'the message is delivered on the first connection and retried on the next',
        );

        socketClient.close();
        async.flushTimers();
      });
    });

    test('handles batch message', () async {
      final fakeChannel = FakeWebSocketChannel(defaultSocketUri);

      final socketClient = makeTestSocketClient(
        fakeChannelFactory: FakeWebSocketChannelFactory((_) => fakeChannel),
      );
      await socketClient.connect();

      const serverMessage = '''
      {
         "t":"batch",
         "d":[
            {"t":"test1","d":"data"},
            {"t":"test2","d":"data"},
            {"t":"test3","d":"data"}
         ]
      }
      ''';

      const eventsToMatch = [
        SocketEvent(topic: 'test1', data: 'data', json: {'t': 'test1', 'd': 'data'}),
        SocketEvent(topic: 'test2', data: 'data', json: {'t': 'test2', 'd': 'data'}),
        SocketEvent(topic: 'test3', data: 'data', json: {'t': 'test3', 'd': 'data'}),
      ];

      // Collect every event the socket emits: emitsInOrder stops consuming after
      // its last matcher, so it would pass on a batch processed twice or on a
      // batch envelope emitted after the sub-events.
      final emitted = <SocketEvent>[];
      final collector = socketClient.stream.listen(emitted.add);
      addTearDown(collector.cancel);

      // check that the messages in the batch were distributed
      await testEventEmitted(socketClient, fakeChannel, serverMessage, eventsToMatch);

      // Each batched message is distributed exactly once, in order, and the
      // batch envelope itself never reaches the stream.
      expect(emitted, eventsToMatch);

      await socketClient.close();
    });

    test('a disposed client cannot be reconnected', () async {
      final socketClient = makeTestSocketClient();
      socketClient.dispose();

      await expectLater(socketClient.connect(), throwsStateError);
    });

    test('a peer that hangs up is routine, not a warning', () {
      final records = collectLogRecords();

      fakeAsync((async) {
        FakeWebSocketChannel? channel;
        final socketClient = makeTestSocketClient(
          fakeChannelFactory: FakeWebSocketChannelFactory(
            (route) => channel = FakeWebSocketChannel(route),
          ),
        );
        socketClient.connect();
        async.elapse(const Duration(milliseconds: 20));
        expect(socketClient.isConnected, isTrue);

        // The peer hangs up without an error: the ordinary end of a connection.
        channel!.closeFromServer();
        async.elapse(const Duration(milliseconds: 1));

        final hangups = records
            .where((record) => record.message.contains('was closed (failing'))
            .toList();
        expect(hangups, hasLength(1), reason: 'the hangup is reported once');
        expect(
          hangups.single.level,
          Level.FINE,
          reason: 'a peer that hangs up is ordinary, and the reconnect answers it',
        );

        socketClient.close();
        async.flushTimers();
      });
    });

    test('the ping/pong protocol is announced once, not on every pong', () {
      final records = collectLogRecords();

      fakeAsync((async) {
        final socketClient = makeTestSocketClient();
        socketClient.connect();
        async.elapse(const Duration(milliseconds: 200));
        async.flushMicrotasks();

        final announcements = records
            .where((record) => record.message.contains('Ping/pong protocol'))
            .toList();
        expect(announcements, hasLength(1), reason: 'the protocol is established, not repeated');

        socketClient.close();
        async.flushTimers();
      });
    });
  });

  test('the global stream carries only the topics that are broadcast to everyone', () async {
    final events = <SocketEvent>[];
    final subscription = socketGlobalStream.listen(events.add);
    addTearDown(subscription.cancel);

    final fakeChannel = FakeWebSocketChannel(defaultSocketUri);
    final socketClient = makeTestSocketClient(
      fakeChannelFactory: FakeWebSocketChannelFactory((_) => fakeChannel),
    );
    await socketClient.connect();

    sendServerSocketMessages(defaultSocketUri, [
      '{"t":"n","d":10,"r":3}',
      '{"t":"message","d":"hello"}',
      '{"t":"challenges","d":[]}',
      '{"t":"announce","d":"x"}',
      '{"t":"test","d":"data"}',
    ]);
    await pumpEventQueue();

    expect(events.map((event) => event.topic), [
      'n',
      'message',
      'challenges',
      'announce',
    ], reason: 'a topic that is not broadcast to everyone stays on the socket that received it');

    await socketClient.close();
  });

  test('a connection timeout is routine, like a missing network', () async {
    var attempts = 0;
    final fakeChannelFactory = FakeWebSocketChannelFactory((_) {
      attempts++;
      if (attempts == 1) throw TimeoutException('Connection timed out');
      return FakeWebSocketChannel(defaultSocketUri);
    });

    final records = <LogRecord>[];
    final subscription = Logger.root.onRecord
        .where((record) => record.level >= Level.WARNING)
        .listen(records.add);
    addTearDown(subscription.cancel);

    final socketClient = makeTestSocketClient(fakeChannelFactory: fakeChannelFactory);
    socketClient.connect();
    await socketClient.firstConnection;

    expect(records, isEmpty, reason: 'a timeout says nothing beyond the network being slow');

    socketClient.close();
  });

  test('emits events', () async {
    final fakeChannel = FakeWebSocketChannel(defaultSocketUri);

    final socketClient = makeTestSocketClient(
      fakeChannelFactory: FakeWebSocketChannelFactory((_) => fakeChannel),
    );
    await socketClient.connect();

    // Collect every event the socket emits across the whole test. An empty
    // emitsInOrder matcher consumes zero events and therefore passes no matter
    // what the stream does; this exact-sequence assertion is what makes the
    // "should not emit" steps below able to fail.
    final emitted = <SocketEvent>[];
    final collector = socketClient.stream.listen(emitted.add);
    addTearDown(collector.cancel);

    // should not emit if _pong
    sendServerSocketMessages(defaultSocketUri, ['0']);

    // should emit if n
    const pongMessage = '{"t":"n","d":10,"r":3}';
    const pongEvent = SocketEvent(topic: 'n', data: {'nbPlayers': 10, 'nbGames': 3});
    sendServerSocketMessages(defaultSocketUri, [pongMessage]);

    // should not emit if ack
    sendServerSocketMessages(defaultSocketUri, ['{"t":"ack","d":1}']);

    // should not emit if batch
    sendServerSocketMessages(defaultSocketUri, ['{"t":"batch","d":[]}']);

    // should emit if random topic
    const randomMessage = '{"t":"test","d":"data"}';
    const randomEvent = SocketEvent(topic: 'test', data: 'data', json: {'t': 'test', 'd': 'data'});
    sendServerSocketMessages(defaultSocketUri, [randomMessage]);

    // Barrier: once a fresh listener has seen both expected events in order,
    // all five messages above have been processed, so [emitted] is complete.
    await expectLater(socketClient.stream, emitsInOrder([pongEvent, randomEvent]));

    // Only the "n" pong and the arbitrary topic reach the stream; the protocol
    // pong, the ack and the empty batch are consumed internally.
    expect(emitted, [pongEvent, randomEvent]);

    await socketClient.close();
  });

  test('handle event gap', () {
    fakeAsync((async) {
      final fakeChannel = FakeWebSocketChannel(defaultSocketUri);

      int onEventGapFailureCalled = 0;

      final socketClient = makeTestSocketClient(
        fakeChannelFactory: FakeWebSocketChannelFactory((_) => fakeChannel),
        version: 0,
        onEventGapFailure: () {
          onEventGapFailureCalled++;
        },
      );
      socketClient.connect();

      socketClient.stream.listen((event) {
        // ignore the events
      });
      expectLater(
        socketClient.stream,
        emitsInOrder([
          const SocketEvent(
            topic: 'test',
            version: 1,
            data: 'data',
            json: {'t': 'test', 'v': 1, 'd': 'data'},
          ),
          const SocketEvent(
            topic: 'test',
            version: 2,
            data: 'data',
            json: {'t': 'test', 'v': 2, 'd': 'data'},
          ),
          const SocketEvent(
            topic: 'test',
            version: 3,
            data: 'data',
            json: {'t': 'test', 'v': 3, 'd': 'data'},
          ),
          const SocketEvent(
            topic: 'test',
            version: 4,
            data: 'data',
            json: {'t': 'test', 'v': 4, 'd': 'data'},
          ),
        ]),
      );

      async.elapse(kFakeWebSocketConnectionLag);

      // server sends the message
      sendServerSocketMessages(defaultSocketUri, [
        '{"t":"test","v":1, "d":"data"}',
        '{"t":"test","v":2, "d":"data"}',
        '{"t":"test","v":4, "d":"data"}',
      ]);

      async.flushMicrotasks();

      async.elapse(const Duration(milliseconds: 200));

      sendServerSocketMessages(defaultSocketUri, ['{"t":"test","v":3, "d":"data"}']);

      async.elapse(const Duration(milliseconds: 2000));

      expect(onEventGapFailureCalled, 0);

      socketClient.close();
    });
  });

  test('handle event gap failure', () {
    fakeAsync((async) {
      final fakeChannel = FakeWebSocketChannel(defaultSocketUri);

      int onEventGapFailureCalled = 0;

      final socketClient = makeTestSocketClient(
        fakeChannelFactory: FakeWebSocketChannelFactory((_) => fakeChannel),
        version: 0,
        onEventGapFailure: () {
          onEventGapFailureCalled++;
        },
      );
      socketClient.connect();

      socketClient.stream.listen((event) {
        // ignore the events
      });
      expectLater(
        socketClient.stream,
        emitsInOrder([
          const SocketEvent(
            topic: 'test',
            version: 1,
            data: 'data',
            json: {'t': 'test', 'v': 1, 'd': 'data'},
          ),
          const SocketEvent(
            topic: 'test',
            version: 2,
            data: 'data',
            json: {'t': 'test', 'v': 2, 'd': 'data'},
          ),
        ]),
      );

      async.elapse(kFakeWebSocketConnectionLag);

      // server sends the message
      sendServerSocketMessages(defaultSocketUri, [
        '{"t":"test","v":1, "d":"data"}',
        '{"t":"test","v":2, "d":"data"}',
        '{"t":"test","v":4, "d":"data"}',
      ]);

      async.flushMicrotasks();

      expect(onEventGapFailureCalled, 0);

      // wait for possibly missing events to be received

      async.elapse(const Duration(milliseconds: 2000));

      // check that the event gap failure was called after 2 seconds
      expect(onEventGapFailureCalled, 1);

      socketClient.close();
    });
  });

  test('a version gap is given ten retries before the client gives up on it', () {
    fakeAsync((async) {
      final fakeChannel = FakeWebSocketChannel(defaultSocketUri);

      var gapFailures = 0;
      final socketClient = makeTestSocketClient(
        fakeChannelFactory: FakeWebSocketChannelFactory((_) => fakeChannel),
        version: 0,
        onEventGapFailure: () {
          gapFailures++;
        },
      );
      socketClient.connect();
      socketClient.stream.listen((_) {});

      async.elapse(kFakeWebSocketConnectionLag);
      sendServerSocketMessages(defaultSocketUri, [
        '{"t":"test","v":1, "d":"data"}',
        '{"t":"test","v":2, "d":"data"}',
        '{"t":"test","v":4, "d":"data"}',
      ]);
      async.flushMicrotasks();

      // Nine retries have gone by, 200ms apart, and the client is still waiting for the event
      // that fills the hole.
      async.elapse(const Duration(milliseconds: 1800));
      expect(gapFailures, 0, reason: 'the gap is given the whole window before it is given up');

      async.elapse(const Duration(milliseconds: 300));
      expect(gapFailures, 1, reason: 'the tenth retry settles it');

      socketClient.close();
      async.flushTimers();
    });
  });

  test('an unfilled version gap reconnects from the last committed version', () {
    fakeAsync((async) {
      // A fresh channel per connection, so a reconnect is observable.
      final channels = <FakeWebSocketChannel>[];
      final socketClient = makeTestSocketClient(
        fakeChannelFactory: FakeWebSocketChannelFactory((uri) {
          final channel = FakeWebSocketChannel(uri);
          channels.add(channel);
          return channel;
        }),
        version: 0,
      );
      socketClient.connect();
      socketClient.stream.listen((_) {});

      async.elapse(kFakeWebSocketConnectionLag);
      expect(channels, hasLength(1));

      // Events 1 and 2 land; 4 arrives with 3 missing, and 3 never does.
      sendServerSocketMessages(defaultSocketUri, [
        '{"t":"test","v":1, "d":"data"}',
        '{"t":"test","v":2, "d":"data"}',
        '{"t":"test","v":4, "d":"data"}',
      ]);
      async.flushMicrotasks();
      expect(socketClient.version, 2, reason: 'the last committed version is where the hole is');

      // Outlast the grace window.
      async.elapse(const Duration(seconds: 3));
      async.flushMicrotasks();

      expect(
        channels.length,
        greaterThan(1),
        reason: 'a gap that never fills must be recovered by reconnecting, not just reported',
      );

      socketClient.close();
      async.flushTimers();
    });
  });

  test('a reconnect after a gap asks the server to resume from the last committed version', () {
    fakeAsync((async) {
      final requestedUrls = <String>[];
      final socketClient = makeTestSocketClient(
        fakeChannelFactory: FakeWebSocketChannelFactory((uri) {
          requestedUrls.add(uri.toString());
          return FakeWebSocketChannel(uri);
        }),
        version: 0,
      );
      socketClient.connect();
      socketClient.stream.listen((_) {});

      async.elapse(kFakeWebSocketConnectionLag);

      sendServerSocketMessages(defaultSocketUri, [
        '{"t":"test","v":1, "d":"data"}',
        '{"t":"test","v":4, "d":"data"}',
      ]);
      async.flushMicrotasks();
      expect(socketClient.version, 1);

      async.elapse(const Duration(seconds: 3));
      async.flushMicrotasks();

      expect(requestedUrls.length, greaterThan(1), reason: 'a reconnect happened');
      // The replay has to start at the hole; a resume from the tip would skip it forever.
      expect(
        requestedUrls.last,
        contains('v=1'),
        reason: 'the server is asked to replay from the last committed version, not from the gap',
      );

      socketClient.close();
      async.flushTimers();
    });
  });

  test('a version-gap retry scheduled before a disconnect does not resurrect the client', () {
    fakeAsync((async) {
      final channels = <FakeWebSocketChannel>[];
      final socketClient = makeTestSocketClient(
        fakeChannelFactory: FakeWebSocketChannelFactory((uri) {
          final channel = FakeWebSocketChannel(uri);
          channels.add(channel);
          return channel;
        }),
        version: 0,
      );
      socketClient.connect();
      socketClient.stream.listen((_) {});
      async.elapse(kFakeWebSocketConnectionLag);
      expect(channels, hasLength(1));

      // v4 arrives with v3 missing: a retry is scheduled 200ms out.
      sendServerSocketMessages(defaultSocketUri, ['{"t":"test","v":4, "d":"data"}']);
      async.flushMicrotasks();

      // The subscription goes away before the retry fires. The orphaned timer used to keep
      // reprocessing the stale event, run its retries out, and schedule a reconnect — waking
      // a client that was deliberately closed.
      socketClient.close();
      async.elapse(const Duration(seconds: 3));
      async.flushMicrotasks();

      expect(
        channels,
        hasLength(1),
        reason: 'the orphaned gap retry must not reconnect a client that was closed',
      );
      async.flushTimers();
    });
  });

  test('a reply that arrives before anyone is listening is dropped, not buffered', () async {
    // This is what makes request ordering load-bearing. A request that subscribes after it has
    // sent loses the reply outright — the event is never queued for a listener that turns up
    // afterwards — so it waits out its whole deadline for an answer the server already sent.
    // Anything that sends a request and waits for its reply has to subscribe first; the cloud
    // eval request in OfflineComputerGameController is the case this exists for.
    final evalHit = {
      't': 'evalHit',
      'd': {
        'knodes': 1,
        'depth': 20,
        'pvs': [
          {'moves': 'e2e4', 'cp': 30},
        ],
      },
    };

    Future<List<SocketEvent>> requestAndCollect({required bool subscribeFirst}) async {
      final channel = ImmediateResponseWebSocketChannel(
        (topic) => topic == 'evalGet' ? evalHit : null,
      );
      final socketClient = makeTestSocketClient(fakeChannelFactory: _SingleChannelFactory(channel));
      socketClient.connect();
      await socketClient.firstConnection;

      final seen = <SocketEvent>[];
      if (subscribeFirst) {
        socketClient.stream.listen(seen.add);
        socketClient.send('evalGet', {'fen': 'x', 'path': '', 'mpv': 1});
      } else {
        socketClient.send('evalGet', {'fen': 'x', 'path': '', 'mpv': 1});
        socketClient.stream.listen(seen.add);
      }
      await pumpEventQueue();
      socketClient.close();
      return seen.where((e) => e.topic == 'evalHit').toList();
    }

    expect(
      await requestAndCollect(subscribeFirst: true),
      hasLength(1),
      reason: 'subscribing before the send must catch the reply',
    );
    expect(
      await requestAndCollect(subscribeFirst: false),
      isEmpty,
      reason:
          'the reply is lost when the subscription comes after the send, which is why the '
          'order matters and is not merely tidy',
    );
  });

  group('SocketPool', () {
    test('closes the socket once the app has been in the background for a while', () async {
      final container = await makeContainer();
      final pool = container.read(socketPoolProvider);

      // The pool made by the test container does not connect on its own.
      pool.currentClient.connect();
      await pool.currentClient.firstConnection;
      expect(pool.currentClient.isActive, isTrue);

      fakeAsync((async) {
        pool.onAppHidden();

        async.elapse(const Duration(seconds: 59));
        expect(
          pool.currentClient.isActive,
          isTrue,
          reason: 'the socket is kept for a while, as the user may well come right back',
        );

        async.elapse(const Duration(seconds: 2));
        expect(pool.currentClient.isActive, isFalse);

        // Coming back to the app brings it up again.
        pool.onAppShown();
        expect(pool.currentClient.isActive, isTrue);

        pool.currentClient.close();
        async.flushTimers();
      });
    });

    test('reconnects the socket as soon as the device is back online', () async {
      var offline = true;
      final container = await makeContainer(overrides: offlineNetworkOverrides(() => offline));

      await container.read(connectivityChangesProvider.future);
      expect(container.read(isDeviceOnlineProvider), isFalse);

      final pool = container.read(socketPoolProvider);
      pool.currentClient.connect();
      await pumpEventQueue();
      expect(pool.currentClient.isConnected, isFalse);

      offline = false;
      FakeConnectivity.controller.add([ConnectivityResult.wifi]);

      // The socket, left to its own backoff, would not try again for seconds: connectivity knows
      // the network is back first and brings it up at once.
      await pool.currentClient.firstConnection.timeout(
        const Duration(seconds: 1),
        onTimeout: () => fail('the socket did not reconnect when the device came back online'),
      );
      await waitUntil(() => pool.currentClient.isConnected);
      expect(pool.currentClient.isConnected, isTrue);

      pool.currentClient.close();
    });

    test(
      'reconnects a failing socket even if the route before it answered while offline',
      () async {
        const otherRoute = '/other/socket/v5';
        var networkDown = false;
        final attempts = <Uri>[];
        FakeWebSocketChannel? defaultChannel;
        final container = await makeContainer(
          overrides: {
            httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
              (ref) => FakeHttpClientFactory(
                () => MockClient((request) async {
                  if (networkDown) throw const SocketException('No internet');
                  return http.Response('', 200);
                }),
              ),
            ),
            webSocketChannelFactoryProvider: webSocketChannelFactoryProvider.overrideWithValue(
              FakeWebSocketChannelFactory((route) {
                attempts.add(route);
                if (networkDown) throw const SocketException('No internet');
                final channel = createDefaultFakeWebSocketChannel(route);
                if (route.path == kDefaultSocketRoute) defaultChannel = channel;
                return channel;
              }),
            ),
          },
        );

        fakeAsync((async) {
          container.read(connectivityChangesProvider);
          final pool = container.read(socketPoolProvider);
          pool.open(defaultSocketUri);
          async.elapse(const Duration(seconds: 1));
          expect(pool.currentClient.isConnected, isTrue);

          // The device is found offline, and the socket on the default route answers a ping all the
          // same — the channel it holds is fine, whatever the probed hosts say.
          networkDown = true;
          FakeConnectivity.controller.add([ConnectivityResult.none]);
          // A lag of its own, so that the pong to come is a change the pool hears about.
          defaultChannel!.connectionLag = const Duration(milliseconds: 40);
          async.elapse(const Duration(seconds: 30));
          expect(container.read(isDeviceOnlineProvider), isFalse);
          expect(pool.currentClient.isConnected, isTrue);

          // A screen then opens another route, whose socket cannot connect and settles into its
          // backoff. What the route before it answered says nothing about this one.
          pool.open(Uri(path: otherRoute));
          async.elapse(const Duration(milliseconds: 500));
          expect(pool.currentClient.isConnected, isFalse);
          final attemptsSoFar = attempts.length;

          // The network comes back. This socket has everything to gain from an attempt now, rather
          // than at the end of a backoff seconds away.
          networkDown = false;
          FakeConnectivity.controller.add([ConnectivityResult.wifi]);
          async.elapse(const Duration(milliseconds: 200));

          expect(container.read(isDeviceOnlineProvider), isTrue);
          expect(attempts.length, attemptsSoFar + 1);
          expect(pool.currentClient.isConnected, isTrue);

          pool.currentClient.close();
          async.flushTimers();
        });
      },
    );

    test('does not reconnect a socket that came back up before the check noticed', () async {
      var offline = false;
      var channelsCreated = 0;
      FakeWebSocketChannel? currentChannel;
      final container = await makeContainer(
        overrides: {
          httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
            (ref) => FakeHttpClientFactory(
              () => MockClient((request) async {
                if (offline) throw const SocketException('No internet');
                return http.Response('', 200);
              }),
            ),
          ),
          webSocketChannelFactoryProvider: webSocketChannelFactoryProvider.overrideWithValue(
            FakeWebSocketChannelFactory((route) {
              if (offline) throw const SocketException('No internet');
              channelsCreated++;
              return currentChannel = createDefaultFakeWebSocketChannel(route);
            }),
          ),
        },
      );

      fakeAsync((async) {
        container.read(connectivityChangesProvider);
        final pool = container.read(socketPoolProvider);
        pool.currentClient.connect();
        async.elapse(const Duration(seconds: 1));
        expect(channelsCreated, 1);
        expect(container.read(isDeviceOnlineProvider), isTrue);

        // The network goes away, the plugin says so, and the socket loses its channel with it.
        offline = true;
        FakeConnectivity.controller.add([ConnectivityResult.none]);
        currentChannel!.closeFromServer(const SocketException('No internet'));
        async.elapse(const Duration(seconds: 5));
        expect(container.read(isDeviceOnlineProvider), isFalse);
        expect(pool.currentClient.isConnected, isFalse);

        // The network comes back, and the socket's own retry gets there first.
        offline = false;
        async.elapse(const Duration(seconds: 10));
        expect(pool.currentClient.isConnected, isTrue);
        final channelsWhenBack = channelsCreated;

        // Only then does the check catch up. The socket it would reconnect has been up and
        // answering since before this edge, so tearing it down would cost an event gap for nothing.
        FakeConnectivity.controller.add([ConnectivityResult.wifi]);
        async.elapse(const Duration(seconds: 1));
        expect(container.read(isDeviceOnlineProvider), isTrue);
        expect(channelsCreated, channelsWhenBack);

        pool.currentClient.close();
        async.flushTimers();
      });
    });

    test(
      'reconnects a socket that has yet to notice the network went away and came back',
      () async {
        var offline = false;
        var channelsCreated = 0;
        final container = await makeContainer(
          overrides: {
            httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
              (ref) => FakeHttpClientFactory(
                () => MockClient((request) async {
                  if (offline) throw const SocketException('No internet');
                  return http.Response('', 200);
                }),
              ),
            ),
            // The fake network has no idea it is gone: the channel stays open and goes on
            // answering, which is just what a socket bound to a lost network looks like until its
            // next ping — up to 25s away on the default route.
            webSocketChannelFactoryProvider: webSocketChannelFactoryProvider.overrideWithValue(
              FakeWebSocketChannelFactory((route) {
                channelsCreated++;
                return createDefaultFakeWebSocketChannel(route);
              }),
            ),
          },
        );

        fakeAsync((async) {
          // The notifier is built inside [fakeAsync] so that the timers it starts — the throttler's
          // among them — belong to this zone and answer to [elapse].
          container.read(connectivityChangesProvider);
          final pool = container.read(socketPoolProvider);
          pool.currentClient.connect();
          async.elapse(const Duration(seconds: 1));

          expect(channelsCreated, 1);
          expect(pool.currentClient.isConnected, isTrue);
          expect(container.read(isDeviceOnlineProvider), isTrue);

          offline = true;
          FakeConnectivity.controller.add([ConnectivityResult.none]);
          async.elapse(const Duration(milliseconds: 100));
          expect(container.read(isDeviceOnlineProvider), isFalse);
          expect(pool.currentClient.isConnected, isTrue, reason: 'the socket has yet to find out');
          expect(pool.currentClient.isFailing.value, isFalse);

          // The network comes back before the socket has noticed anything at all. Its connection
          // belongs to the network that went away, so it must be made again whatever it looks like.
          offline = false;
          async.elapse(kConnectivityThrottleDelay);
          FakeConnectivity.controller.add([ConnectivityResult.wifi]);
          async.elapse(const Duration(milliseconds: 100));

          expect(container.read(isDeviceOnlineProvider), isTrue);
          expect(channelsCreated, 2);

          pool.currentClient.close();
          async.flushTimers();
        });
      },
    );

    test('reconnects the socket when the plugin recovers on a retried build', () async {
      // The real plugin fails with a [PlatformException], which riverpod retries: the status the
      // socket listens to is settled by a later build than the one that first failed, and the edge
      // it produces has to reach the pool like any other.
      var socketDown = true;
      final connectivity = PluginFailingConnectivity();
      final container = await makeContainer(
        overrides: {
          connectivityPluginProvider: connectivityPluginProvider.overrideWith((_) => connectivity),
          webSocketChannelFactoryProvider: webSocketChannelFactoryProvider.overrideWithValue(
            FakeWebSocketChannelFactory((route) {
              if (socketDown) throw const SocketException('No internet');
              return createDefaultFakeWebSocketChannel(route);
            }),
          ),
        },
      );

      fakeAsync((async) {
        // Listened to, not merely read: a provider nobody listens to is not retried.
        container.listen(connectivityChangesProvider, (_, _) {});
        final pool = container.read(socketPoolProvider);
        pool.currentClient.connect();
        async.elapse(const Duration(milliseconds: 100));

        expect(container.read(isDeviceOnlineProvider), isFalse);
        expect(pool.currentClient.isFailing.value, isTrue);

        // Everything comes back at once, and the retried build is what says so. The socket's own
        // next attempt is [_kAutoReconnectDelay] away — seconds later than this.
        socketDown = false;
        connectivity.shouldFail = false;
        async.elapse(const Duration(milliseconds: 600));

        expect(container.read(isDeviceOnlineProvider), isTrue);
        expect(pool.currentClient.isConnected, isTrue);

        pool.currentClient.close();
        async.flushTimers();
      });
    });

    test(
      'reconnects the socket when a failed connectivity check is followed by an online one',
      () async {
        var offline = true;
        final container = await makeContainer(
          overrides: {
            ...offlineNetworkOverrides(() => offline),
            // The check itself cannot even run: what it leaves behind is an error, which the app
            // reads as offline like any other check that reached nothing.
            connectivityPluginProvider: connectivityPluginProvider.overrideWith(
              (_) => FailingConnectivity(),
            ),
          },
        );

        await expectLater(container.read(connectivityChangesProvider.future), throwsStateError);
        expect(container.read(isDeviceOnlineProvider), isFalse);

        final pool = container.read(socketPoolProvider);
        pool.currentClient.connect();
        await pumpEventQueue();
        expect(pool.currentClient.isConnected, isFalse);

        // The socket is waiting out its backoff, and the only thing that can cut it short is the
        // device coming back online — from an error just as much as from a settled offline status.
        offline = false;
        FakeConnectivity.controller.add([ConnectivityResult.wifi]);

        await pool.currentClient.firstConnection.timeout(
          const Duration(seconds: 1),
          onTimeout: () => fail('the socket did not reconnect when the device came back online'),
        );
        await waitUntil(() => pool.currentClient.isConnected);
        expect(pool.currentClient.isConnected, isTrue);

        pool.currentClient.close();
      },
    );

    test('does not reconnect the socket while the app is in the background', () async {
      var offline = true;
      var socketAttempts = 0;
      final container = await makeContainer(
        overrides: offlineNetworkOverrides(() => offline, onSocketAttempt: (_) => socketAttempts++),
      );

      await container.read(connectivityChangesProvider.future);

      final pool = container.read(socketPoolProvider);
      pool.currentClient.connect();
      await pumpEventQueue();
      expect(socketAttempts, 1);

      pool.onAppHidden();

      offline = false;
      FakeConnectivity.controller.add([ConnectivityResult.wifi]);
      await pumpEventQueue();
      await waitUntil(() => container.read(isDeviceOnlineProvider));

      expect(container.read(isDeviceOnlineProvider), isTrue);
      expect(
        socketAttempts,
        1,
        reason: 'nothing needs the socket while the app is in the background',
      );
      expect(pool.currentClient.isConnected, isFalse);

      // Coming back to the app is what brings it up.
      pool.onAppShown();
      await pool.currentClient.firstConnection.timeout(
        const Duration(seconds: 1),
        onTimeout: () => fail('the socket did not reconnect when the app came back'),
      );

      pool.currentClient.close();
    });

    test('nothing reopens the socket once it has been closed in the background', () async {
      final attempts = <Uri>[];
      final container = await makeContainer(
        overrides: offlineNetworkOverrides(() => false, onSocketAttempt: attempts.add),
      );
      final pool = container.read(socketPoolProvider);

      fakeAsync((async) {
        pool.currentClient.connect();
        async.elapse(const Duration(seconds: 1));
        expect(pool.currentClient.isConnected, isTrue);
        expect(attempts.length, 1);

        pool.onAppHidden();
        async.elapse(const Duration(minutes: 2));
        expect(pool.currentClient.isActive, isFalse, reason: 'the socket is closed in background');

        // Everything that would bring the socket back in the foreground must leave it closed
        // here, and no timer left over from the connected socket may bring it back either.
        pool.onDeviceBackOnline();
        pool.onAuthChanged();
        async.elapse(const Duration(minutes: 10));

        expect(attempts.length, 1, reason: 'the socket must stay closed while in the background');
        expect(pool.currentClient.isActive, isFalse);

        // The user coming back is the one thing that reopens it.
        pool.onAppShown();
        async.elapse(const Duration(seconds: 1));
        expect(attempts.length, 2);
        expect(pool.currentClient.isConnected, isTrue);

        pool.currentClient.close();
        async.flushTimers();
      });
    });

    test('does not reopen the default socket in the background when a route goes idle', () async {
      const route = '/lobby/socket/v5';
      final attempts = <Uri>[];
      final container = await makeContainer(
        overrides: offlineNetworkOverrides(() => false, onSocketAttempt: attempts.add),
      );
      final pool = container.read(socketPoolProvider);

      fakeAsync((async) {
        final client = pool.open(Uri(path: route));
        final subscription = client.stream.listen((_) {});
        async.elapse(const Duration(seconds: 1));
        expect(attempts.map((uri) => uri.path), [route]);

        pool.onAppHidden();
        async.elapse(const Duration(minutes: 2));

        // The screen that was using this route is gone: the pool disposes its idle client, which
        // in the foreground would have it fall back to the default socket.
        subscription.cancel();
        async.elapse(const Duration(minutes: 1));

        expect(attempts.map((uri) => uri.path), [route]);
        expect(pool.currentClient.isActive, isFalse);

        async.flushTimers();
      });
    });

    test('forceReconnect reopens a route that is already connected, and only then', () async {
      final attempts = <Uri>[];
      final container = await makeContainer(
        overrides: offlineNetworkOverrides(() => false, onSocketAttempt: attempts.add),
      );
      final pool = container.read(socketPoolProvider);

      fakeAsync((async) {
        const route = '/lobby/socket/v5';
        pool.open(Uri(path: route));
        async.elapse(const Duration(seconds: 1));
        expect(attempts.map((uri) => uri.path), [route]);

        // Asking for the route again, without asking for a reconnect, leaves it alone.
        pool.open(Uri(path: route));
        async.elapse(const Duration(seconds: 1));
        expect(attempts.map((uri) => uri.path), [route], reason: 'a live route is not reopened');

        // Asking for a reconnect is what reopens it.
        pool.open(Uri(path: route), forceReconnect: true);
        async.elapse(const Duration(seconds: 1));
        expect(attempts.map((uri) => uri.path), [
          route,
          route,
        ], reason: 'forceReconnect reopens it');

        pool.currentClient.close();
        async.flushTimers();
      });
    });

    test(
      'a route that goes idle while another one is current leaves the pool where it is',
      () async {
        final attempts = <Uri>[];
        final container = await makeContainer(
          overrides: offlineNetworkOverrides(() => false, onSocketAttempt: attempts.add),
        );
        final pool = container.read(socketPoolProvider);

        fakeAsync((async) {
          const first = '/first/socket/v5';
          const second = '/second/socket/v5';

          final firstClient = pool.open(Uri(path: first));
          final firstSubscription = firstClient.stream.listen((_) {});
          pool.open(Uri(path: second));
          async.elapse(const Duration(seconds: 1));
          expect(attempts.map((uri) => uri.path), [first, second]);
          expect(pool.currentClient.route.path, second);

          // The first route goes idle: the screen that was using it is gone.
          firstSubscription.cancel();
          async.elapse(const Duration(seconds: 3));

          expect(
            pool.currentClient.route.path,
            second,
            reason:
                'the route that went idle is not the current one, so the pool stays where it is',
          );
          expect(
            attempts.map((uri) => uri.path),
            [first, second],
            reason:
                'the default socket is not brought back for a route that was not the current one',
          );

          pool.currentClient.close();
          async.flushTimers();
        });
      },
    );

    test(
      'after the app comes back, a route that goes idle brings the default socket back',
      () async {
        final attempts = <Uri>[];
        final container = await makeContainer(
          overrides: offlineNetworkOverrides(() => false, onSocketAttempt: attempts.add),
        );
        final pool = container.read(socketPoolProvider);

        fakeAsync((async) {
          // The app goes to the background and comes straight back: the pool is in the foreground
          // again, and everything the background kept closed is open again.
          pool.onAppHidden();
          pool.onAppShown();

          const route = '/lobby/socket/v5';
          final client = pool.open(Uri(path: route));
          final subscription = client.stream.listen((_) {});
          async.elapse(const Duration(seconds: 1));
          expect(attempts.map((uri) => uri.path), [kDefaultSocketRoute, route]);

          // The screen that was using the route is gone.
          subscription.cancel();
          async.elapse(const Duration(seconds: 3));

          expect(attempts.map((uri) => uri.path), [
            kDefaultSocketRoute,
            route,
            kDefaultSocketRoute,
          ], reason: 'the default socket comes back when the app is in the foreground');

          pool.currentClient.close();
          async.flushTimers();
        });
      },
    );

    test('a disposed pool refuses to open a route', () async {
      final container = await makeContainer();
      final pool = container.read(socketPoolProvider);
      pool.dispose();

      expect(() => pool.open(Uri(path: '/lobby/socket/v5')), throwsStateError);
    });
  });

  group('socketPingProvider', () {
    test('reports no lag as soon as the device is known to be offline', () async {
      var offline = false;
      final container = await makeContainer(overrides: offlineNetworkOverrides(() => offline));

      await container.read(connectivityChangesProvider.future);

      final client = container.read(socketPoolProvider).currentClient;
      client.connect();
      await client.firstConnection;
      await waitUntil(() {
        return container.read(socketPingProvider(null)).averageLag != Duration.zero;
      });
      await pumpEventQueue();

      expect(container.read(socketPingProvider(null)).averageLag, isNot(Duration.zero));

      // The network goes away. The socket has yet to notice — its next ping has not even been
      // sent — but the check does, and the indicator must not go on showing a lag measured over a
      // network that is no longer there.
      offline = true;
      FakeConnectivity.controller.add([ConnectivityResult.none]);
      await pumpEventQueue();

      expect(container.read(isDeviceOnlineProvider), isFalse);
      expect(container.read(socketPingProvider(null)).averageLag, Duration.zero);

      client.close();
    });

    test('a ping reading is about the route it was asked for', () async {
      final container = await makeContainer();
      final pool = container.read(socketPoolProvider);
      final client = pool.currentClient;
      client.connect();
      await client.firstConnection;
      await waitUntil(() => client.isConnected);

      // A reading of the whole app is about the route that is current.
      expect(container.read(socketPingProvider(null)).averageLag, isNot(Duration.zero));
      expect(container.read(socketPingProvider(null)).isActive, isTrue);

      // A reading of a route that is not the current one says nothing at all.
      const otherRoute = '/other/socket/v5';
      expect(container.read(socketPingProvider(Uri(path: otherRoute))).averageLag, Duration.zero);
      expect(container.read(socketPingProvider(Uri(path: otherRoute))).isActive, isFalse);

      client.close();
    });

    test('a ping reading that stays open follows the socket down', () async {
      final container = await makeContainer();
      final client = container.read(socketPoolProvider).currentClient;
      client.connect();
      await client.firstConnection;
      await waitUntil(() => client.isConnected);

      // A reading that stays open is what the ping icon in the app is: it has to follow the
      // socket, not keep the lag it saw when it was built.
      final subscription = container.listen(socketPingProvider(null), (_, _) {});
      addTearDown(subscription.close);
      expect(container.read(socketPingProvider(null)).averageLag, isNot(Duration.zero));

      client.close();
      await pumpEventQueue();

      expect(
        container.read(socketPingProvider(null)).averageLag,
        Duration.zero,
        reason: 'a reading that stays open follows the socket down',
      );
    });

    test('the ping rating follows the lag ladder', () async {
      const lags = <String, int>{'/fast': 100, '/ok': 150, '/slow': 300, '/bad': 500};
      const ratings = <String, int>{'/fast': 4, '/ok': 3, '/slow': 2, '/bad': 1};

      final container = await makeContainer(
        overrides: {
          webSocketChannelFactoryProvider: webSocketChannelFactoryProvider.overrideWithValue(
            FakeWebSocketChannelFactory(
              (route) => FakeWebSocketChannel(
                route,
                connectionLag: Duration(milliseconds: lags[route.path]!),
              ),
            ),
          ),
        },
      );
      await container.read(connectivityChangesProvider.future);
      final pool = container.read(socketPoolProvider);

      // A socket that is down has no lag, and no rating either.
      expect(container.read(socketPingProvider(null)).rating, 0);

      fakeAsync((async) {
        for (final entry in lags.entries) {
          final route = Uri(path: entry.key);
          pool.open(route);
          // Long enough for the handshake and for the pong that measures the lag.
          async.elapse(const Duration(milliseconds: 700));
          async.flushMicrotasks();

          expect(
            container.read(socketPingProvider(route)).averageLag,
            Duration(milliseconds: entry.value),
            reason: entry.key,
          );
          expect(
            container.read(socketPingProvider(route)).rating,
            ratings[entry.key],
            reason: entry.key,
          );
        }
      });

      pool.currentClient.close();
    });
  });
}

/// Overrides for a container whose network is entirely down — the connectivity check and the
/// socket alike — for as long as [isOffline] returns true.
Map<ProviderOrFamily, Override> offlineNetworkOverrides(
  bool Function() isOffline, {
  void Function(Uri route)? onSocketAttempt,
}) => {
  httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
    (ref) => FakeHttpClientFactory(
      () => MockClient((request) async {
        if (isOffline()) throw const SocketException('No internet');
        return http.Response('', 200);
      }),
    ),
  ),
  webSocketChannelFactoryProvider: webSocketChannelFactoryProvider.overrideWithValue(
    FakeWebSocketChannelFactory((route) {
      onSocketAttempt?.call(route);
      if (isOffline()) throw const SocketException('No internet');
      return createDefaultFakeWebSocketChannel(route);
    }),
  ),
};

Future<void> testEventEmitted(
  SocketClient socketClient,
  FakeWebSocketChannel fakeChannel,
  String serverMessage,
  Iterable<SocketEvent> eventsToMatch,
) async {
  // Guard against the empty-matcher footgun: an empty [eventsToMatch] makes
  // emitsInOrder consume zero events, so the assertion below could never fail.
  // Negative ("should not emit") cases must use a collector + exact assertion
  // instead of this helper.
  expect(eventsToMatch, isNotEmpty, reason: 'testEventEmitted needs at least one expected event');

  // start listening to the stream
  final futureExpect = expectLater(socketClient.stream, emitsInOrder(eventsToMatch));

  // server sends the message
  sendServerSocketMessages(defaultSocketUri, [serverMessage]);

  // check that the socket events were emitted in order
  await futureExpect;
}
