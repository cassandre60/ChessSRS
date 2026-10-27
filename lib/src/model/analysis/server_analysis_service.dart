import 'dart:async';

import 'package:chess_srs/src/model/auth/auth_controller.dart';
import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chess_srs/src/model/common/eval.dart';
import 'package:chess_srs/src/model/common/id.dart';
import 'package:chess_srs/src/model/common/node.dart';
import 'package:chess_srs/src/model/common/preloaded_data.dart';
import 'package:chess_srs/src/model/common/socket.dart';
import 'package:chess_srs/src/model/common/uci.dart';
import 'package:chess_srs/src/model/game/game_repository.dart';
import 'package:chess_srs/src/model/game/game_socket_events.dart';
import 'package:chess_srs/src/network/http.dart';
import 'package:chess_srs/src/network/socket.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:logging/logging.dart';

part 'server_analysis_service.freezed.dart';

final _logger = Logger('ServerAnalysisService');

@freezed
sealed class ServerAnalysisSource with _$ServerAnalysisSource {
  const ServerAnalysisSource._();

  const factory ServerAnalysisSource.game({required GameId gameId}) = _GameServerAnalysisSource;

  const factory ServerAnalysisSource.studyChapter({
    required StudyId studyId,
    required StudyChapterId chapterId,
  }) = _StudyChapterServerAnalysisSource;
}

const Duration kMaxWaitForServerAnalysis = Duration(minutes: 1);

/// A provider for [ServerAnalysisService].
final serverAnalysisServiceProvider = Provider<ServerAnalysisService>((Ref ref) {
  return ServerAnalysisService(ref);
}, name: 'ServerAnalysisServiceProvider');

class ServerAnalysisService {
  ServerAnalysisService(this.ref);

  StreamSubscription<SocketEvent>? _socketSubscription;

  final Ref ref;

  final _currentAnalysis = ValueNotifier<ServerAnalysisSource?>(null);

  Completer<void>? _analysisCompleter;

  final _analysisProgress = ValueNotifier<(ServerAnalysisSource, ServerEvalEvent)?>(null);

  /// The current game being analyzed.
  ValueListenable<ServerAnalysisSource?> get currentAnalysis => _currentAnalysis;

  /// The last analysis progress event received from the server.
  ValueListenable<(ServerAnalysisSource, ServerEvalEvent)?> get lastAnalysisEvent =>
      _analysisProgress;

  SocketClient? _socketClient;

  /// Monotonic request counter.
  ///
  /// Every request claims the current value, and every asynchronous continuation belonging to that
  /// request re-checks it before touching shared state. Starting a new request — or cancelling the
  /// current one — moves it on, so a continuation that was already in flight when the world moved
  /// on can tell that it is stale and drop out instead of overwriting the newer request.
  int _requestGeneration = 0;

  /// Request server analysis for a game.
  ///
  /// This will return a future that completes when the server analysis is
  /// launched (but not when it is finished).
  Future<void> requestAnalysis(ServerAnalysisSource source, [Side? side]) async {
    // If we are already listening for analysis updates of this exact game/study,
    // don't tear everything down and reconnect.
    if (_currentAnalysis.value == source &&
        _socketSubscription != null &&
        _analysisCompleter != null) {
      return;
    }

    _cancelAnalysis();
    final generation = _requestGeneration;
    bool isCurrent() => generation == _requestGeneration;

    final uri = Uri(
      path: switch (source) {
        _GameServerAnalysisSource(:final gameId) =>
          '/watch/$gameId/${side?.name ?? Side.white.name}/v6',
        _StudyChapterServerAnalysisSource(:final studyId) => '/study/$studyId/socket/v6',
      },
    );

    // Held locally as well as on the field: a cancellation disposes the field and nulls it, and
    // these continuations can run after that.
    final socketClient = SocketClient(
      uri,
      channelFactory: ref.read(webSocketChannelFactoryProvider),
      getSession: () => ref.read(authControllerProvider),
      packageInfo: ref.read(preloadedDataProvider).requireValue.packageInfo,
      deviceInfo: ref.read(preloadedDataProvider).requireValue.deviceInfo,
      sri: ref.read(preloadedDataProvider).requireValue.sri,
    );
    _socketClient = socketClient;
    socketClient.connect();
    final completer = Completer<void>();
    _analysisCompleter = completer;
    _socketSubscription = socketClient.stream.listen(
      (event) {
        if (!isCurrent()) return;
        if (event.topic == 'analysisProgress') {
          final data = ServerEvalEvent.fromJson(event.data as Map<String, dynamic>);

          _analysisProgress.value = (source, data);

          if (data.isAnalysisComplete && !completer.isCompleted) {
            completer.complete();
          }
        }
      },
      onDone: () {
        if (isCurrent()) _cancelAnalysis();
      },
      cancelOnError: true,
    );

    switch (source) {
      case _GameServerAnalysisSource(:final gameId):
        try {
          await ref.read(gameRepositoryProvider).requestServerAnalysis(gameId);
          // The request took time. A newer request may own the service by now, in which case
          // claiming the current analysis here would resurrect the one just replaced.
          if (!isCurrent()) return;
          _currentAnalysis.value = source;
        } on ServerException catch (e, st) {
          // 400 means analysis already requested (most likely) so we'll still try to listen to the socket
          // for updates.
          // TODO: should disambiguate this better. Server will also return an error when max number
          // of analyses is reached.
          if (e.statusCode == 400) {
            if (!isCurrent()) return;
            _logger.info('Analysis already requested for game $gameId');
            _currentAnalysis.value = source;
          } else {
            _logger.severe('ServerException requesting server analysis', e, st);
            if (isCurrent()) _cancelAnalysis();
            rethrow;
          }
        } catch (e, st) {
          _logger.severe('Error requesting server analysis', e, st);
          if (isCurrent()) _cancelAnalysis();
          rethrow;
        }

      case _StudyChapterServerAnalysisSource(:final chapterId):
        _currentAnalysis.value = source;
        // `firstConnection` settling after a timeout or a cancellation used to reach back through
        // the field, which by then was null. The captured client is disposed in that case, and
        // `isCurrent` is false, so there is nothing left to send on.
        socketClient.firstConnection
            .timeout(const Duration(seconds: 3))
            .then((_) {
              if (!isCurrent()) return;
              socketClient.send('requestAnalysis', chapterId);
            })
            .catchError((Object e, StackTrace st) {
              if (!isCurrent()) return;
              _logger.severe('Error connecting to analysis socket', e, st);
              _cancelAnalysis();
            });
    }

    // A deadline, not an error: running out of time is the ordinary end of this wait, so the
    // rejection is absorbed here rather than surfacing as an unhandled asynchronous error.
    unawaited(
      completer.future
          .timeout(kMaxWaitForServerAnalysis)
          .then((_) {}, onError: (Object _, StackTrace _) {})
          .whenComplete(() {
            if (isCurrent()) _cancelAnalysis();
          }),
    );
  }

  /// Cancel the ongoing server analysis, if any.
  void _cancelAnalysis() {
    // Retire the current request first, so any continuation still in flight for it becomes stale
    // and bails rather than writing into the state this is about to clear.
    _requestGeneration++;
    _socketSubscription?.cancel();
    _socketSubscription = null;
    _currentAnalysis.value = null;
    _analysisCompleter = null;
    if (_socketClient?.isDisposed != true) {
      _socketClient?.dispose();
      _socketClient = null;
    }
  }

  /// Merge the ongoing analysis from the server into the given node tree.
  static void mergeOngoingAnalysis(Node n1, Map<String, dynamic> n2) {
    final eval = n2['eval'] as Map<String, dynamic>?;
    final cp = eval?['cp'] as int?;
    final mate = eval?['mate'] as int?;
    final pgnEval = cp != null
        ? PgnEvaluation.pawns(pawns: cpToPawns(cp))
        : mate != null
        ? PgnEvaluation.mate(mate: mate)
        : null;
    final glyphs = n2['glyphs'] as List<dynamic>?;
    final glyph = glyphs?.first as Map<String, dynamic>?;
    final comments = n2['comments'] as List<dynamic>?;
    final comment = (comments?.first as Map<String, dynamic>?)?['text'] as String?;
    final children = n2['children'] as List<dynamic>? ?? [];
    final pgnComment = pgnEval != null ? PgnComment(eval: pgnEval, text: comment) : null;
    if (n1 is Branch) {
      if (pgnComment != null) {
        if (n1.lichessAnalysisComments == null) {
          n1.lichessAnalysisComments = [pgnComment];
        } else {
          n1.lichessAnalysisComments!.removeWhere((c) => c.eval != null);
          n1.lichessAnalysisComments!.add(pgnComment);
        }
      }
      if (glyph != null) {
        n1.nags ??= [glyph['id'] as int];
      }
    }
    for (final c in children) {
      final n2child = c as Map<String, dynamic>;
      final uci = n2child['uci'] as String;
      final n1child = n1.childById(UciCharPair.fromUci(uci));
      if (n1child != null) {
        mergeOngoingAnalysis(n1child, n2child);
      } else {
        final san = n2child['san'] as String;
        final move = Move.parse(uci)!;
        n1.addChild(
          Branch(
            position: n1.position.playUnchecked(move),
            sanMove: SanMove(san, move),
            isCollapsed: children.length > 1,
          ),
        );
      }
    }
  }
}

/// A provider that exposes the current game being analyzed by the server.
final currentAnalysisProvider =
    NotifierProvider.autoDispose<CurrentAnalysis, ServerAnalysisSource?>(
      CurrentAnalysis.new,
      name: 'CurrentAnalysisProvider',
    );

class CurrentAnalysis extends Notifier<ServerAnalysisSource?> {
  @override
  ServerAnalysisSource? build() {
    final listenable = ref.watch(serverAnalysisServiceProvider).currentAnalysis;

    listenable.addListener(_listener);

    ref.onDispose(() {
      listenable.removeListener(_listener);
    });

    return listenable.value;
  }

  void _listener() {
    final source = ref.read(serverAnalysisServiceProvider).currentAnalysis.value;
    if (state != source) {
      state = source;
    }
  }
}
