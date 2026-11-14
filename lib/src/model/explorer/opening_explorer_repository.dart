import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:chess_srs/src/constants.dart';
import 'package:chess_srs/src/model/analysis/opening_service.dart';
import 'package:chess_srs/src/model/common/chess.dart' show LightOpening, Variant;
import 'package:chess_srs/src/model/common/speed.dart';
import 'package:chess_srs/src/model/explorer/opening_explorer.dart';
import 'package:chess_srs/src/model/explorer/opening_explorer_preferences.dart';
import 'package:chess_srs/src/network/http.dart';
import 'package:chess_srs/src/utils/riverpod.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart';

final openingExplorerProvider = AsyncNotifierProvider.autoDispose
    .family<
      OpeningExplorer,
      ({OpeningExplorerEntry entry, bool isIndexing})?,
      ({String fen, Variant variant})
    >((request) => OpeningExplorer(request.fen, request.variant), name: 'OpeningExplorerProvider');

class OpeningExplorer extends AsyncNotifier<({OpeningExplorerEntry entry, bool isIndexing})?> {
  OpeningExplorer(this.fen, this.variant);

  final String fen;
  final Variant variant;

  StreamSubscription<OpeningExplorerEntry>? _openingExplorerSubscription;

  @override
  Future<({OpeningExplorerEntry entry, bool isIndexing})?> build() async {
    ref.onDispose(() {
      _openingExplorerSubscription?.cancel();
    });

    await ref.debounce(const Duration(milliseconds: 300));

    final prefs = ref.watch(openingExplorerPreferencesProvider);
    final db = _openingExplorerDatabaseFor(prefs.db, variant);
    final repository = ref.read(openingExplorerRepositoryProvider);

    switch (db) {
      case OpeningDatabase.master:
        try {
          final openingExplorer = await repository.getMasterDatabase(
            fen,
            since: prefs.masterDb.sinceYear,
          );
          return (entry: openingExplorer, isIndexing: false);
        } catch (e) {
          debugPrint('OpeningExplorer: master DB fetch failed, falling back to open DB: $e');
          final entry = await repository.getOpenDatabase(fen, variant: variant);
          return (entry: entry, isIndexing: false);
        }
      case OpeningDatabase.lichess:
        try {
          final openingExplorer = await repository.getLichessDatabase(
            fen,
            variant: variant,
            speeds: prefs.lichessDb.speeds,
            ratings: prefs.lichessDb.ratings,
            since: prefs.lichessDb.since,
          );
          return (entry: openingExplorer, isIndexing: false);
        } catch (e) {
          debugPrint('OpeningExplorer: lichess DB fetch failed, falling back to open DB: $e');
          final entry = await repository.getOpenDatabase(fen, variant: variant);
          return (entry: entry, isIndexing: false);
        }
      case OpeningDatabase.chessdb:
        final entry = await repository.getOpenDatabase(fen, variant: variant);
        return (entry: entry, isIndexing: false);
      case OpeningDatabase.player:
        if (prefs.playerDb.username == null) {
          final entry = await repository.getOpenDatabase(fen, variant: variant);
          return (entry: entry, isIndexing: false);
        }
        try {
          final openingExplorerStream = await repository.getPlayerDatabase(
            fen,
            variant: variant,
            // null check handled by widget
            usernameOrId: prefs.playerDb.username!,
            color: prefs.playerDb.side,
            speeds: prefs.playerDb.speeds,
            gameModes: prefs.playerDb.gameModes,
            since: prefs.playerDb.since,
          );

          _openingExplorerSubscription = openingExplorerStream.listen(
            (openingExplorer) =>
                state = AsyncValue.data((entry: openingExplorer, isIndexing: true)),
            onDone: () => state.value != null
                ? state = AsyncValue.data((entry: state.value!.entry, isIndexing: false))
                : state = AsyncValue.error(
                    'No opening explorer data returned for player ${prefs.playerDb.username}',
                    StackTrace.current,
                  ),
          );
          return null;
        } catch (e) {
          debugPrint('OpeningExplorer: player DB fetch failed, falling back to open DB: $e');
          final entry = await repository.getOpenDatabase(fen, variant: variant);
          return (entry: entry, isIndexing: false);
        }
    }
  }
}

/// A provider for [OpeningExplorerRepository].
final openingExplorerRepositoryProvider = Provider<OpeningExplorerRepository>((Ref ref) {
  return OpeningExplorerRepository(
    ref.watch(defaultClientProvider),
    defaultClient: ref.watch(defaultClientProvider),
    openingService: ref.watch(openingServiceProvider),
  );
}, name: 'OpeningExplorerRepositoryProvider');

Uri _explorerUri(String path, [Map<String, dynamic>? queryParameters]) =>
    kLichessOpeningExplorerHost.startsWith('localhost') ||
        kLichessOpeningExplorerHost.startsWith('10.') ||
        kLichessOpeningExplorerHost.startsWith('192.168.')
    ? Uri.http(kLichessOpeningExplorerHost, path, queryParameters)
    : Uri.https(kLichessOpeningExplorerHost, path, queryParameters);

class OpeningExplorerRepository {
  const OpeningExplorerRepository(this.client, {this.defaultClient, this.openingService});

  final Client client;
  final Client? defaultClient;
  final OpeningService? openingService;

  Future<OpeningExplorerEntry> getOpenDatabase(
    String fen, {
    Variant variant = Variant.standard,
  }) async {
    LightOpening? opening;
    if (openingService != null) {
      try {
        final fullOpening = await openingService!.fetchFromFen(fen);
        if (fullOpening != null) {
          opening = LightOpening(eco: fullOpening.eco, name: fullOpening.name);
        }
      } catch (e) {
        debugPrint('OpeningExplorer: fetchFromFen failed, continuing without opening info: $e');
      }
    }

    final httpClient = defaultClient ?? client;
    if (variant == Variant.standard) {
      try {
        final uri = Uri.https('www.chessdb.cn', '/cdb.php', {
          'action': 'queryall',
          'board': fen,
          'json': '1',
        });
        final response = await httpClient.get(uri).timeout(const Duration(seconds: 4));
        if (response.statusCode == 200) {
          final data = jsonDecode(utf8.decode(response.bodyBytes));
          if (data is Map<String, dynamic> && data['status'] == 'ok') {
            final rawMoves = data['moves'] as List<dynamic>?;
            if (rawMoves != null && rawMoves.isNotEmpty) {
              final parsedMoves = <OpeningMove>[];
              int totalWhite = 0;
              int totalDraws = 0;
              int totalBlack = 0;

              for (final m in rawMoves) {
                if (m is Map<String, dynamic>) {
                  final uci = m['uci'] as String? ?? '';
                  final san = m['san'] as String? ?? uci;
                  final winrate = double.tryParse(m['winrate']?.toString() ?? '50.0') ?? 50.0;
                  final score = (m['score'] as num?)?.toInt();

                  // Represent win percentage proportionally for display
                  const baseGames = 1000;
                  final whiteWins = math.max(1, (winrate / 100.0 * 760).round());
                  const draws = 180;
                  final blackWins = math.max(1, baseGames - whiteWins - draws);

                  totalWhite += whiteWins;
                  totalDraws += draws;
                  totalBlack += blackWins;

                  parsedMoves.add(
                    OpeningMove(
                      uci: uci,
                      san: san,
                      white: whiteWins,
                      draws: draws,
                      black: blackWins,
                      performance: score,
                    ),
                  );
                }
              }

              if (parsedMoves.isNotEmpty) {
                return OpeningExplorerEntry(
                  white: totalWhite,
                  draws: totalDraws,
                  black: totalBlack,
                  moves: parsedMoves.toIList(),
                  opening: opening,
                );
              }
            }
          }
        }
      } catch (e) {
        debugPrint('OpeningExplorer: chessdb.cn query failed, falling back to empty entry: $e');
      }
    }

    return OpeningExplorerEntry(
      white: 0,
      draws: 0,
      black: 0,
      moves: const IListConst([]),
      opening: opening,
    );
  }

  Future<OpeningExplorerEntry> getMasterDatabase(String fen, {int? since}) {
    return client.readJson(
      _explorerUri('/masters', {
        'source': 'mobile',
        'fen': fen,
        if (since != null) 'since': since.toString(),
      }),
      mapper: OpeningExplorerEntry.fromJson,
    );
  }

  Future<OpeningExplorerEntry> getLichessDatabase(
    String fen, {
    required Variant variant,
    required ISet<Speed> speeds,
    required ISet<int> ratings,
    DateTime? since,
  }) {
    return client.readJson(
      _explorerUri('/lichess', {
        'source': 'mobile',
        'variant': _openingExplorerVariantKey(variant),
        'fen': fen,
        if (speeds.isNotEmpty) 'speeds': speeds.map((speed) => speed.name).join(','),
        if (ratings.isNotEmpty) 'ratings': ratings.join(','),
        if (since != null) 'since': '${since.year}-${since.month}',
      }),
      mapper: OpeningExplorerEntry.fromJson,
    );
  }

  Future<Stream<OpeningExplorerEntry>> getPlayerDatabase(
    String fen, {
    required Variant variant,
    required String usernameOrId,
    required Side color,
    required ISet<Speed> speeds,
    required ISet<GameMode> gameModes,
    DateTime? since,
  }) {
    return client.readNdJsonStream(
      _explorerUri('/player', {
        'source': 'mobile',
        'variant': _openingExplorerVariantKey(variant),
        'fen': fen,
        'player': usernameOrId,
        'color': color.name,
        if (speeds.isNotEmpty) 'speeds': speeds.map((speed) => speed.name).join(','),
        if (gameModes.isNotEmpty) 'modes': gameModes.map((gameMode) => gameMode.name).join(','),
        if (since != null) 'since': '${since.year}-${since.month}',
      }),
      mapper: OpeningExplorerEntry.fromJson,
    );
  }
}

// Opening explorer treats imported/custom positions as standard chess.
// Other variants must be explicit or the API falls back to standard data.
String _openingExplorerVariantKey(Variant variant) =>
    variant == Variant.fromPosition ? Variant.standard.name : variant.name;

OpeningDatabase _openingExplorerDatabaseFor(OpeningDatabase db, Variant variant) {
  // The masters endpoint has no variant parameter. For variants, fall back to
  // Lichess DB instead of asking users to change their persisted setting.
  if (db == OpeningDatabase.master &&
      variant != Variant.standard &&
      variant != Variant.fromPosition) {
    return OpeningDatabase.lichess;
  }
  return db;
}
