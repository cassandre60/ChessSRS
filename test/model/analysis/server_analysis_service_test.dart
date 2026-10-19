import 'dart:async';

import 'package:chess_srs/src/model/analysis/server_analysis_service.dart';
import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chess_srs/src/model/common/id.dart';
import 'package:chess_srs/src/model/common/node.dart';
import 'package:chess_srs/src/network/http.dart';
import 'package:chess_srs/src/network/socket.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../network/fake_http_client_factory.dart';
import '../../network/fake_websocket_channel.dart';
import '../../test_container.dart';

/// A channel factory whose connections never complete, so a socket's `firstConnection` future
/// stays pending and the service's own connect timeout is the thing under test.
class _NeverConnectingChannelFactory extends WebSocketChannelFactory {
  const _NeverConnectingChannelFactory();

  @override
  Future<WebSocketChannel> create(
    String url, {
    Map<String, dynamic>? headers,
    Duration timeout = const Duration(seconds: 10),
  }) => Completer<WebSocketChannel>().future;
}

void main() {
  group('ServerAnalysisService request lifecycle', () {
    const gameA = GameId('gameAAAA');
    const gameB = GameId('gameBBBB');

    /// A container whose `request-analysis` POSTs are held open until the matching entry of
    /// [releaseRequests] is invoked, so a test can start a second request while the first is still
    /// awaiting its HTTP call.
    final releaseRequests = <VoidCallback>[];

    Future<ProviderContainer> makeServiceContainer() {
      return makeContainer(
        overrides: {
          httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
            (ref) => FakeHttpClientFactory(
              () => MockClient((request) async {
                if (request.url.path.endsWith('/request-analysis')) {
                  final gate = Completer<void>();
                  releaseRequests.add(() {
                    if (!gate.isCompleted) gate.complete();
                  });
                  await gate.future;
                }
                return http.Response('{}', 200);
              }),
            ),
          ),
          // A channel per connection, as a real reconnect gets.
          webSocketChannelFactoryProvider: webSocketChannelFactoryProvider.overrideWithValue(
            FakeWebSocketChannelFactory((uri) => FakeWebSocketChannel(uri)),
          ),
        },
      );
    }

    tearDown(releaseRequests.clear);

    test('a slow request does not claim the service after a newer one started', () async {
      final container = await makeServiceContainer();
      addTearDown(container.dispose);
      final service = container.read(serverAnalysisServiceProvider);

      // Request A goes out and parks on its HTTP call.
      final first = service.requestAnalysis(const ServerAnalysisSource.game(gameId: gameA));
      await pumpEventQueue();
      expect(releaseRequests, hasLength(1));

      // Request B starts and completes while A is still waiting.
      final second = service.requestAnalysis(const ServerAnalysisSource.game(gameId: gameB));
      await pumpEventQueue();
      expect(releaseRequests, hasLength(2));
      releaseRequests[1]();
      await second;
      expect(service.currentAnalysis.value, const ServerAnalysisSource.game(gameId: gameB));

      // Now let A finish. It must not overwrite the newer request's claim.
      releaseRequests[0]();
      await first;
      expect(
        service.currentAnalysis.value,
        const ServerAnalysisSource.game(gameId: gameB),
        reason: 'a request that finished late must not displace the one that replaced it',
      );
    });

    test('a study request that times out does not send on a disposed socket', () async {
      // `firstConnection` only completes once `create` returns, so a create that never returns
      // is what actually exercises the timeout path.
      final container = await makeContainer(
        overrides: {
          webSocketChannelFactoryProvider: webSocketChannelFactoryProvider.overrideWith(
            (ref) => const _NeverConnectingChannelFactory(),
          ),
        },
      );
      addTearDown(container.dispose);
      final service = container.read(serverAnalysisServiceProvider);

      const source = ServerAnalysisSource.studyChapter(
        studyId: StudyId('study'),
        chapterId: StudyChapterId('chapter'),
      );

      // The socket connect times out after 3s, which cancels the analysis and nulls the field.
      // The continuation that follows used to reach back through that field and crash.
      //
      // The wait runs on the fake clock, the pattern #221 used for a service test: the connect
      // timeout is a Timer, so waiting for it is an elapse, not a wall-clock sleep. The old
      // `Future.delayed(4s)` bought that timeout with a one-second margin — a race under load,
      // since a run whose cancellation landed after 4s failed on a healthy build — and it spent
      // four seconds of real time on every run of the file. Here the timeout is advanced
      // exactly, and the test costs no wall-clock time at all.
      fakeAsync((async) {
        var requested = false;
        service.requestAnalysis(source).then((_) => requested = true);
        async.flushMicrotasks();

        expect(requested, isTrue, reason: 'the request must have been issued');
        expect(
          service.currentAnalysis.value,
          source,
          reason: 'the request claims the analysis before the socket connect settles',
        );

        // Exactly the timeout the service applies, and no more: the connect never lands.
        async.elapse(const Duration(seconds: 3));
        async.flushMicrotasks();

        expect(service.currentAnalysis.value, isNull);
        // Reaching here without an unhandled asynchronous error is the assertion that matters.
      });
    }, timeout: const Timeout(Duration(seconds: 30)));
  });

  group('ServerAnalysisService.mergeOngoingAnalysis', () {
    test('merges analysis using UCI instead of id field', () {
      // Create a simple game tree: e2e4
      final root = Root(position: Chess.initial);
      final e4Move = Move.parse('e2e4')!;
      final e4Position = root.position.playUnchecked(e4Move);
      final e4Branch = Branch(sanMove: SanMove('e4', e4Move), position: e4Position);
      root.addChild(e4Branch);

      // Server analysis data - note: no 'id' field, only 'uci'
      final serverNode = {
        'eval': {'cp': 20},
        'children': [
          {
            'uci': 'e2e4',
            'san': 'e4',
            'eval': {'cp': 25},
            'children': [
              {
                'uci': 'e7e5',
                'san': 'e5',
                'eval': {'cp': 30},
                'children': <Map<String, dynamic>>[],
              },
            ],
          },
        ],
      };

      // This should work without the 'id' field
      ServerAnalysisService.mergeOngoingAnalysis(root, serverNode);

      // Verify the tree was merged correctly
      expect(root.children.length, 1);
      expect(root.children.first.sanMove.san, 'e4');
      expect(root.children.first.children.length, 1);
      expect(root.children.first.children.first.sanMove.san, 'e5');
    });

    test('adds new variation from server analysis using UCI', () {
      // Create a game tree with just e2e4
      final root = Root(position: Chess.initial);
      final e4Move = Move.parse('e2e4')!;
      final e4Position = root.position.playUnchecked(e4Move);
      final e4Branch = Branch(sanMove: SanMove('e4', e4Move), position: e4Position);
      root.addChild(e4Branch);

      // Server sends a new variation (d2d4) - no 'id' field
      final serverNode = {
        'children': [
          {
            'uci': 'd2d4',
            'san': 'd4',
            'eval': {'cp': 15},
            'children': <Map<String, dynamic>>[],
          },
        ],
      };

      ServerAnalysisService.mergeOngoingAnalysis(root, serverNode);

      // Should have added d4 as a new variation
      expect(root.children.length, 2);
      final variations = root.children.map((c) => c.sanMove.san).toList();
      expect(variations, containsAll(['e4', 'd4']));
    });

    test('merges evaluation into existing node', () {
      final root = Root(position: Chess.initial);
      final e4Move = Move.parse('e2e4')!;
      final e4Position = root.position.playUnchecked(e4Move);
      final e4Branch = Branch(sanMove: SanMove('e4', e4Move), position: e4Position);
      root.addChild(e4Branch);

      // Server sends eval for e4 - no 'id' field
      final serverNode = {
        'children': [
          {
            'uci': 'e2e4',
            'san': 'e4',
            'eval': {'cp': 42},
            'comments': [
              {'text': 'Best move!'},
            ],
            'children': <Map<String, dynamic>>[],
          },
        ],
      };

      ServerAnalysisService.mergeOngoingAnalysis(root, serverNode);

      // Verify eval was merged
      expect(root.children.length, 1);
      expect(root.children.first.lichessAnalysisComments?.length, 1);
      expect(root.children.first.lichessAnalysisComments?.first.text, 'Best move!');
    });
  });
}
