// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:math' as math;

import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/import/opening_name.dart';
import 'package:chess_srs/src/import/pgn_exporter.dart';
import 'package:chess_srs/src/import/pgn_importer.dart';
import 'package:chess_srs/src/model/engine/opening_book.dart';
import 'package:dartchess/dartchess.dart';

/// Severity of a move mistake identified in a player's game.
enum MistakeSeverity {
  inaccuracy,
  mistake,
  blunder;

  String get label => switch (this) {
    MistakeSeverity.inaccuracy => 'inaccuracy',
    MistakeSeverity.mistake => 'mistake',
    MistakeSeverity.blunder => 'blunder',
  };
}

/// Evaluation and judgment data for a single ply in an exported Lichess game.
class LichessPlyAnalysis {
  const LichessPlyAnalysis({
    this.cp,
    this.mate,
    this.bestUci,
    this.variation,
    this.judgmentName,
    this.judgmentComment,
  });

  final int? cp;
  final int? mate;
  final String? bestUci;
  final String? variation;
  final String? judgmentName;
  final String? judgmentComment;
}

/// Lightweight representation of a user's played Lichess game for repertoire generation.
class LichessPlayedGame {
  const LichessPlayedGame({
    required this.id,
    required this.userSide,
    required this.moves,
    this.winner,
    this.openingEco,
    this.openingName,
    this.analysis,
    this.createdAt,
    this.variant = 'standard',
    this.initialFen,
  });

  final String id;
  final Side userSide;
  final List<String> moves;
  final Side? winner;
  final String? openingEco;
  final String? openingName;
  final List<LichessPlyAnalysis?>? analysis;
  final DateTime? createdAt;
  final String variant;
  final String? initialFen;
}

/// A single mistake correction incorporated into a generated opening study.
class OpeningMistakeFix {
  const OpeningMistakeFix({
    required this.fenKey,
    required this.ply,
    required this.mistakeSan,
    required this.correctSan,
    required this.mistakePlayCount,
    required this.severity,
    this.comment,
  });

  final String fenKey;
  final int ply;
  final String mistakeSan;
  final String correctSan;
  final int mistakePlayCount;
  final MistakeSeverity severity;
  final String? comment;
}

/// A custom study generated for one opening and side from the user's Lichess games.
class GeneratedOpeningStudy {
  const GeneratedOpeningStudy({
    required this.title,
    required this.openingFamily,
    required this.side,
    required this.pgnText,
    required this.gameCount,
    required this.mistakeFixes,
    required this.chapterCount,
    this.latestGameAt,
  });

  final String title;
  final String openingFamily;
  final Side side;
  final String pgnText;
  final int gameCount;
  final List<OpeningMistakeFix> mistakeFixes;
  final int chapterCount;
  final DateTime? latestGameAt;
}

/// Parses a single Lichess `/api/games/user/:username` JSON object into a [LichessPlayedGame]
/// from [username]'s perspective, or returns `null` if the game is not a standard game played by
/// [username] with at least one move.
LichessPlayedGame? parseLichessGameJson(Map<String, dynamic> json, {required String username}) {
  final normalizedUser = username.trim().toLowerCase();
  if (normalizedUser.isEmpty) return null;

  final variantRaw = json['variant'];
  final variantKey = switch (variantRaw) {
    final String s => s,
    final Map<String, dynamic> m => (m['key'] as String?) ?? 'standard',
    _ => 'standard',
  };
  final initialFen = json['initialFen'] as String?;
  final isStandardStart =
      initialFen == null ||
      initialFen.isEmpty ||
      initialFen == 'startpos' ||
      initialFen == kInitialFEN ||
      initialFen.startsWith(kInitialBoardFEN);
  if (variantKey != 'standard' && variantKey != 'chess' && variantKey != 'fromPosition') {
    return null;
  }
  if (!isStandardStart) return null;

  final players = json['players'];
  if (players is! Map<String, dynamic>) return null;

  final whiteMatch = _matchesPlayer(players['white'], normalizedUser);
  final blackMatch = _matchesPlayer(players['black'], normalizedUser);
  final Side userSide;
  if (whiteMatch) {
    userSide = Side.white;
  } else if (blackMatch) {
    userSide = Side.black;
  } else {
    return null;
  }

  final movesStr = (json['moves'] as String?)?.trim() ?? '';
  if (movesStr.isEmpty) return null;
  final moves = movesStr.split(RegExp(r'\s+')).where((m) => m.isNotEmpty).toList();
  if (moves.isEmpty) return null;

  final winnerRaw = json['winner'] as String?;
  final Side? winner = switch (winnerRaw) {
    'white' => Side.white,
    'black' => Side.black,
    _ => null,
  };

  String? openingEco;
  String? openingName;
  final openingRaw = json['opening'];
  if (openingRaw is Map<String, dynamic>) {
    openingEco = openingRaw['eco'] as String?;
    openingName = openingRaw['name'] as String?;
  }

  List<LichessPlyAnalysis?>? analysis;
  final analysisRaw = json['analysis'];
  if (analysisRaw is List<dynamic>) {
    analysis = analysisRaw.map((entry) {
      if (entry is! Map<String, dynamic>) return null;
      final judgmentRaw = entry['judgment'];
      String? judgmentName;
      String? judgmentComment;
      if (judgmentRaw is Map<String, dynamic>) {
        judgmentName = judgmentRaw['name'] as String?;
        judgmentComment = judgmentRaw['comment'] as String?;
      }
      return LichessPlyAnalysis(
        cp: (entry['eval'] as num?)?.toInt(),
        mate: (entry['mate'] as num?)?.toInt(),
        bestUci: entry['best'] as String?,
        variation: entry['variation'] as String?,
        judgmentName: judgmentName,
        judgmentComment: judgmentComment,
      );
    }).toList();
  }

  final createdMillis =
      (json['createdAt'] as num?)?.toInt() ?? (json['lastMoveAt'] as num?)?.toInt();
  final createdAt = createdMillis != null
      ? DateTime.fromMillisecondsSinceEpoch(createdMillis, isUtc: true)
      : null;

  final id = (json['id'] as String?)?.trim() ?? '';

  return LichessPlayedGame(
    id: id.isEmpty ? '${createdMillis ?? moves.hashCode}' : id,
    userSide: userSide,
    moves: moves,
    winner: winner,
    openingEco: openingEco,
    openingName: openingName,
    analysis: analysis,
    createdAt: createdAt,
    variant: variantKey,
    initialFen: initialFen,
  );
}

/// Parses an NDJSON body from Lichess `/api/games/user/:username` into [LichessPlayedGame]s.
List<LichessPlayedGame> parseLichessGamesNdJson(String ndjson, {required String username}) {
  final games = <LichessPlayedGame>[];
  for (final rawLine in const LineSplitter().convert(ndjson)) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    try {
      final decoded = jsonDecode(line);
      if (decoded is Map<String, dynamic>) {
        final parsed = parseLichessGameJson(decoded, username: username);
        if (parsed != null) {
          games.add(parsed);
        }
      }
    } catch (_) {
      // Skip malformed NDJSON lines without aborting the batch.
    }
  }
  return games;
}

bool _matchesPlayer(Object? playerObj, String normalizedUsername) {
  if (playerObj is! Map<String, dynamic>) return false;
  final userObj = playerObj['user'];
  if (userObj is Map<String, dynamic>) {
    final id = (userObj['id'] as String?)?.trim().toLowerCase();
    if (id == normalizedUsername) return true;
    final name = (userObj['name'] as String?)?.trim().toLowerCase();
    if (name == normalizedUsername) return true;
  }
  final directId = (playerObj['id'] as String?)?.trim().toLowerCase();
  if (directId == normalizedUsername) return true;
  final directName = (playerObj['name'] as String?)?.trim().toLowerCase();
  return directName == normalizedUsername;
}

/// Generates custom opening studies from a player's Lichess games.
///
/// Groups games by opening family and side, builds the player's habitual move
/// tree for each opening, and replaces recurring or analyzed mistakes with the
/// correct answer move while preserving the player's own lines leading up to
/// each position.
List<GeneratedOpeningStudy> generateOpeningStudiesFromGames(
  List<LichessPlayedGame> games, {
  Side? sideFilter,
  PolyglotBook? book,
  int maxPly = 24,
  int maxOpponentBranches = 4,
}) {
  final grouped = <String, _OpeningGameGroup>{};

  for (final game in games) {
    if (sideFilter != null && game.userSide != sideFilter) continue;
    final replayed = _replayGameSteps(game, maxPly: maxPly);
    if (replayed.isEmpty) continue;

    final hasUserMove = replayed.any((s) => s.posBefore.turn == game.userSide);
    if (!hasUserMove) continue;

    final openingFamily = _classifyOpeningFamily(game, replayed);
    final variationTitle = _extractVariationTitle(game.openingName, openingFamily);
    final key = '${game.userSide.name}::$openingFamily';

    final group = grouped.putIfAbsent(
      key,
      () => _OpeningGameGroup(openingFamily: openingFamily, side: game.userSide),
    );
    group.games.add(_ReplayedGame(source: game, variationTitle: variationTitle, steps: replayed));
  }

  final studies = <GeneratedOpeningStudy>[];
  for (final group in grouped.values) {
    final generated = _buildStudyForOpeningGroup(
      group,
      book: book,
      maxPly: maxPly,
      maxOpponentBranches: maxOpponentBranches,
    );
    if (generated != null) {
      studies.add(generated);
    }
  }

  studies.sort((a, b) {
    final fixCompare = b.mistakeFixes.length.compareTo(a.mistakeFixes.length);
    if (fixCompare != 0) return fixCompare;
    final countCompare = b.gameCount.compareTo(a.gameCount);
    if (countCompare != 0) return countCompare;
    return a.title.compareTo(b.title);
  });

  return studies;
}

class _ReplayedStep {
  const _ReplayedStep({
    required this.plyIndex,
    required this.posBefore,
    required this.move,
    required this.repertoireMove,
    required this.posAfter,
    this.evalBefore,
    this.evalAfter,
  });

  final int plyIndex;
  final Position posBefore;
  final NormalMove move;
  final RepertoireMove repertoireMove;
  final Position posAfter;
  final LichessPlyAnalysis? evalBefore;
  final LichessPlyAnalysis? evalAfter;
}

class _ReplayedGame {
  const _ReplayedGame({required this.source, required this.variationTitle, required this.steps});

  final LichessPlayedGame source;
  final String variationTitle;
  final List<_ReplayedStep> steps;
}

class _OpeningGameGroup {
  _OpeningGameGroup({required this.openingFamily, required this.side});

  final String openingFamily;
  final Side side;
  final List<_ReplayedGame> games = [];
}

List<_ReplayedStep> _replayGameSteps(LichessPlayedGame game, {required int maxPly}) {
  final steps = <_ReplayedStep>[];
  Position pos = Chess.initial;
  final limit = math.min(game.moves.length, maxPly);

  for (var i = 0; i < limit; i++) {
    final san = game.moves[i];
    final parsed = pos.parseSan(san);
    if (parsed is! NormalMove) break;

    final repMove = normalmoveToRepertoireMove(parsed, pos);
    final nextPos = pos.playUnchecked(parsed);
    final evalBefore = i > 0 ? game.analysis?.elementAtOrNull(i - 1) : null;
    final evalAfter = game.analysis?.elementAtOrNull(i);

    steps.add(
      _ReplayedStep(
        plyIndex: i,
        posBefore: pos,
        move: parsed,
        repertoireMove: repMove,
        posAfter: nextPos,
        evalBefore: evalBefore,
        evalAfter: evalAfter,
      ),
    );
    pos = nextPos;
  }

  return steps;
}

String _classifyOpeningFamily(LichessPlayedGame game, List<_ReplayedStep> steps) {
  final rawName = game.openingName?.trim();
  if (rawName != null && rawName.isNotEmpty) {
    final simplified = simplifyOpeningName(rawName);
    if (simplified.isNotEmpty && !mentionsOpeningButIsNotFamily(simplified)) {
      return simplified;
    }
  }

  final rawEco = game.openingEco?.trim().toUpperCase();
  if (rawEco != null && rawEco.isNotEmpty) {
    final fromEco = ecoToOpeningFamily(rawEco);
    if (fromEco != null && !mentionsOpeningButIsNotFamily(fromEco)) {
      return fromEco;
    }
  }

  var root = RepertoireNode(id: 'root', fen: kInitialFEN, fenKey: fenKey(kInitialFEN));
  final nodes = <RepertoireNode>[];
  final depth = math.min(steps.length, 8);
  for (var i = 0; i < depth; i++) {
    nodes.add(
      RepertoireNode(
        id: 'n$i',
        fen: steps[i].posAfter.fen,
        fenKey: fenKey(steps[i].posAfter.fen),
        incomingMove: steps[i].repertoireMove,
      ),
    );
  }
  for (var i = nodes.length - 2; i >= 0; i--) {
    nodes[i] = nodes[i].copyWith(children: [nodes[i + 1]]);
  }
  if (nodes.isNotEmpty) {
    root = root.copyWith(children: [nodes.first]);
  }
  final fromMoves = detectOpeningFamilyFromMoves(root);
  if (fromMoves != null && !mentionsOpeningButIsNotFamily(fromMoves)) {
    return fromMoves;
  }

  final firstSan = steps.first.repertoireMove.san ?? '';
  final secondSan = steps.length > 1 ? (steps[1].repertoireMove.san ?? '') : '';
  if (firstSan == 'e4' && secondSan == 'e5') return 'Open Game';
  if (firstSan == 'e4') return "King's Pawn Game";
  if (firstSan == 'd4') return "Queen's Pawn Game";
  if (firstSan == 'c4') return 'English Opening';
  if (firstSan == 'Nf3') return 'Réti Opening';
  return 'Flank Opening';
}

String _extractVariationTitle(String? rawOpeningName, String openingFamily) {
  if (rawOpeningName == null || rawOpeningName.trim().isEmpty) {
    return 'Main Lines';
  }
  final colonIdx = rawOpeningName.indexOf(':');
  if (colonIdx >= 0 && colonIdx + 1 < rawOpeningName.length) {
    final sub = rawOpeningName.substring(colonIdx + 1).trim();
    final commaIdx = sub.indexOf(',');
    final cleaned = (commaIdx > 0 ? sub.substring(0, commaIdx) : sub).trim();
    if (cleaned.isNotEmpty) return cleaned;
  }
  final trimmed = rawOpeningName.trim();
  if (trimmed.toLowerCase() != openingFamily.toLowerCase()) {
    return trimmed;
  }
  return 'Main Lines';
}

class _PlayedMoveStats {
  _PlayedMoveStats({required this.move});

  final RepertoireMove move;
  int playCount = 0;
  int wins = 0;
  int draws = 0;
  int losses = 0;
  int inaccuracyCount = 0;
  int mistakeCount = 0;
  int blunderCount = 0;

  int get totalMistakes => inaccuracyCount + mistakeCount + blunderCount;

  MistakeSeverity get worstSeverity {
    if (blunderCount > 0) return MistakeSeverity.blunder;
    if (mistakeCount > 0) return MistakeSeverity.mistake;
    return MistakeSeverity.inaccuracy;
  }
}

class _RecommendedFixStats {
  _RecommendedFixStats({required this.move, required this.severity});

  final RepertoireMove move;
  int count = 0;
  MistakeSeverity severity;
}

class _UserNodeStats {
  _UserNodeStats({required this.fenKeyStr, required this.position, required this.ply});

  final String fenKeyStr;
  final Position position;
  final int ply;
  final Map<String, _PlayedMoveStats> playedMoves = {};
  final Map<String, _RecommendedFixStats> recommendedFixes = {};

  _PlayedMoveStats get mostPlayed {
    final list = playedMoves.values.toList();
    list.sort((a, b) {
      final countCmp = b.playCount.compareTo(a.playCount);
      if (countCmp != 0) return countCmp;
      final mistakeCmp = a.totalMistakes.compareTo(b.totalMistakes);
      if (mistakeCmp != 0) return mistakeCmp;
      return (b.wins - b.losses).compareTo(a.wins - a.losses);
    });
    return list.first;
  }
}

class _ResolvedUserDecision {
  const _ResolvedUserDecision({required this.chosenMove, this.fix, this.comment});

  final RepertoireMove chosenMove;
  final OpeningMistakeFix? fix;
  final String? comment;
}

GeneratedOpeningStudy? _buildStudyForOpeningGroup(
  _OpeningGameGroup group, {
  required PolyglotBook? book,
  required int maxPly,
  required int maxOpponentBranches,
}) {
  final userNodes = <String, _UserNodeStats>{};
  final allOppMovesByKey = <String, Map<String, ({RepertoireMove move, int count})>>{};
  DateTime? latestGameAt;

  for (final game in group.games) {
    final createdAt = game.source.createdAt;
    if (createdAt != null && (latestGameAt == null || createdAt.isAfter(latestGameAt))) {
      latestGameAt = createdAt;
    }

    for (final step in game.steps) {
      final key = fenKey(step.posBefore.fen);
      if (step.posBefore.turn == group.side) {
        final nodeStats = userNodes.putIfAbsent(
          key,
          () => _UserNodeStats(fenKeyStr: key, position: step.posBefore, ply: step.plyIndex + 1),
        );
        final moveStats = nodeStats.playedMoves.putIfAbsent(
          step.repertoireMove.uci,
          () => _PlayedMoveStats(move: step.repertoireMove),
        );
        moveStats.playCount++;
        if (game.source.winner == group.side) {
          moveStats.wins++;
        } else if (game.source.winner == null) {
          moveStats.draws++;
        } else {
          moveStats.losses++;
        }

        final detected = _detectStepMistake(step, group.side);
        if (detected != null) {
          switch (detected.severity) {
            case MistakeSeverity.inaccuracy:
              moveStats.inaccuracyCount++;
            case MistakeSeverity.mistake:
              moveStats.mistakeCount++;
            case MistakeSeverity.blunder:
              moveStats.blunderCount++;
          }
          if (detected.bestMove != null && detected.bestMove!.uci != step.repertoireMove.uci) {
            final fixStats = nodeStats.recommendedFixes.putIfAbsent(
              detected.bestMove!.uci,
              () => _RecommendedFixStats(move: detected.bestMove!, severity: detected.severity),
            );
            fixStats.count++;
            if (detected.severity.index > fixStats.severity.index) {
              fixStats.severity = detected.severity;
            }
          }
        }
      } else {
        final oppMap = allOppMovesByKey.putIfAbsent(key, () => {});
        final prev = oppMap[step.repertoireMove.uci];
        oppMap[step.repertoireMove.uci] = (
          move: step.repertoireMove,
          count: (prev?.count ?? 0) + 1,
        );
      }
    }
  }

  if (userNodes.isEmpty) return null;

  final candidateDecisions = <String, _ResolvedUserDecision>{};
  for (final entry in userNodes.entries) {
    candidateDecisions[entry.key] = _resolveCandidateDecision(entry.value, book: book);
  }

  // Protect trunk moves when an early move was only a mild inaccuracy (or isolated
  // mistake) and continuing down the player's actual move reaches a deeper serious
  // mistake in the same line.
  final resolvedDecisions = <String, _ResolvedUserDecision>{};
  for (final entry in userNodes.entries) {
    final nodeStats = entry.value;
    final candidate = candidateDecisions[entry.key]!;
    final mostPlayed = nodeStats.mostPlayed;
    if (candidate.fix != null && candidate.chosenMove.uci != mostPlayed.move.uci) {
      final parsedMost = Move.parse(mostPlayed.move.uci);
      if (parsedMost is NormalMove && nodeStats.position.isLegal(parsedMost)) {
        final afterMost = nodeStats.position.playUnchecked(parsedMost);
        final hasDeeperSeriousFix = _subtreeHasSeriousMistake(
          afterMost,
          side: group.side,
          userNodes: userNodes,
          allOppMovesByKey: allOppMovesByKey,
          candidateDecisions: candidateDecisions,
          visited: {entry.key},
        );
        final isEarlyTrunk = nodeStats.ply <= 2;
        final isMildMistake = candidate.fix!.severity == MistakeSeverity.inaccuracy;
        if (hasDeeperSeriousFix && (isEarlyTrunk || isMildMistake)) {
          resolvedDecisions[entry.key] = _ResolvedUserDecision(chosenMove: mostPlayed.move);
          continue;
        }
      }
    }
    resolvedDecisions[entry.key] = candidate;
  }

  // Partition games into chapters by sub-variation, keeping variations with mistakes
  // or multiple games as dedicated chapters and merging singletons into Main Lines.
  final byVariation = <String, List<_ReplayedGame>>{};
  for (final game in group.games) {
    byVariation.putIfAbsent(game.variationTitle, () => []).add(game);
  }

  final chapterBuckets = <String, List<_ReplayedGame>>{};
  if (byVariation.length == 1) {
    final singleEntry = byVariation.entries.first;
    final chapterName = singleEntry.key == 'Main Lines' ? group.openingFamily : singleEntry.key;
    chapterBuckets[chapterName] = singleEntry.value;
  } else {
    for (final entry in byVariation.entries) {
      final hasFix = _gamesInBucketTouchFix(
        entry.value,
        side: group.side,
        resolvedDecisions: resolvedDecisions,
      );
      if (hasFix || entry.value.length >= 2 || entry.key == 'Main Lines') {
        chapterBuckets[entry.key] = [...?chapterBuckets[entry.key], ...entry.value];
      } else {
        chapterBuckets['Main Lines'] = [...?chapterBuckets['Main Lines'], ...entry.value];
      }
    }
  }

  final sortedChapterEntries = chapterBuckets.entries.toList()
    ..sort((a, b) {
      final aFixes = _countFixesInBucket(a.value, group.side, resolvedDecisions);
      final bFixes = _countFixesInBucket(b.value, group.side, resolvedDecisions);
      final fixCmp = bFixes.compareTo(aFixes);
      if (fixCmp != 0) return fixCmp;
      return b.value.length.compareTo(a.value.length);
    });

  final studyId = 'generated-${group.side.name}-${group.openingFamily.hashCode}';
  final sideLabel = group.side == Side.white ? 'White' : 'Black';
  final studyTitle = '${group.openingFamily} ($sideLabel)';

  final chapters = <Chapter>[];
  final collectedFixesByKey = <String, OpeningMistakeFix>{};
  var nodeCounter = 0;

  for (var idx = 0; idx < sortedChapterEntries.length && idx < 10; idx++) {
    final entry = sortedChapterEntries[idx];
    final chapterOppMoves = <String, Map<String, ({RepertoireMove move, int count})>>{};
    final chapterUserKeys = <String>{};

    for (final game in entry.value) {
      for (final step in game.steps) {
        final key = fenKey(step.posBefore.fen);
        if (step.posBefore.turn == group.side) {
          chapterUserKeys.add(key);
        } else {
          final map = chapterOppMoves.putIfAbsent(key, () => {});
          final prev = map[step.repertoireMove.uci];
          map[step.repertoireMove.uci] = (move: step.repertoireMove, count: (prev?.count ?? 0) + 1);
        }
      }
    }

    List<RepertoireNode> buildChildren(Position pos, Set<String> visited, int depth) {
      if (depth >= maxPly) return const [];
      final key = fenKey(pos.fen);
      if (visited.contains(key)) return const [];
      final nextVisited = {...visited, key};

      if (pos.turn == group.side) {
        if (!chapterUserKeys.contains(key) && !userNodes.containsKey(key)) {
          return const [];
        }
        final decision = resolvedDecisions[key];
        if (decision == null) return const [];

        final parsed = _parseUciMove(pos, decision.chosenMove.uci);
        if (parsed == null) return const [];
        final nextPos = pos.playUnchecked(parsed);
        final repMove = normalmoveToRepertoireMove(parsed, pos);

        if (decision.fix != null) {
          collectedFixesByKey[key] = decision.fix!;
        }

        final grandChildren = buildChildren(nextPos, nextVisited, depth + 1);
        nodeCounter++;
        return [
          RepertoireNode(
            id: 'gen-node-$nodeCounter',
            fen: nextPos.fen,
            fenKey: fenKey(nextPos.fen),
            incomingMove: repMove,
            comment: decision.comment,
            children: grandChildren,
          ),
        ];
      } else {
        final oppMap = chapterOppMoves[key] ?? allOppMovesByKey[key];
        if (oppMap == null || oppMap.isEmpty) return const [];

        final candidates = oppMap.values.toList();
        candidates.sort((a, b) {
          final aHasFix = _oppMoveLeadsToFix(
            pos,
            a.move.uci,
            side: group.side,
            resolvedDecisions: resolvedDecisions,
            oppMovesByKey: chapterOppMoves,
            visited: nextVisited,
          );
          final bHasFix = _oppMoveLeadsToFix(
            pos,
            b.move.uci,
            side: group.side,
            resolvedDecisions: resolvedDecisions,
            oppMovesByKey: chapterOppMoves,
            visited: nextVisited,
          );
          if (aHasFix != bHasFix) return bHasFix ? 1 : -1;
          return b.count.compareTo(a.count);
        });

        final children = <RepertoireNode>[];
        for (final cand in candidates) {
          final leadsToFix = _oppMoveLeadsToFix(
            pos,
            cand.move.uci,
            side: group.side,
            resolvedDecisions: resolvedDecisions,
            oppMovesByKey: chapterOppMoves,
            visited: nextVisited,
          );
          if (children.length >= maxOpponentBranches && !leadsToFix) {
            continue;
          }
          final parsed = _parseUciMove(pos, cand.move.uci);
          if (parsed == null) continue;
          final nextPos = pos.playUnchecked(parsed);
          final repMove = normalmoveToRepertoireMove(parsed, pos);
          final grandChildren = buildChildren(nextPos, nextVisited, depth + 1);
          // Trim trailing opponent moves so every line ends on a user decision.
          if (grandChildren.isEmpty) continue;

          nodeCounter++;
          children.add(
            RepertoireNode(
              id: 'gen-node-$nodeCounter',
              fen: nextPos.fen,
              fenKey: fenKey(nextPos.fen),
              incomingMove: repMove,
              children: grandChildren,
            ),
          );
        }
        return children;
      }
    }

    final rootChildren = buildChildren(Chess.initial, const {}, 0);
    if (rootChildren.isEmpty) continue;

    nodeCounter++;
    final rootNode = RepertoireNode(
      id: 'gen-root-$nodeCounter',
      fen: kInitialFEN,
      fenKey: fenKey(kInitialFEN),
      children: rootChildren,
    );

    chapters.add(
      Chapter(
        id: 'gen-chapter-${chapters.length + 1}',
        studyId: studyId,
        title: entry.key,
        sourceOrder: chapters.length,
        root: rootNode,
        orientation: group.side,
        opening: group.openingFamily,
      ),
    );
  }

  if (chapters.isEmpty) return null;

  final study = Study(
    id: studyId,
    title: studyTitle,
    pgnHash: '',
    createdAt: latestGameAt ?? DateTime.utc(2026),
  );
  final pgnText = studyToPgn(study: study, chapters: chapters);

  final sortedFixes = collectedFixesByKey.values.toList()..sort((a, b) => a.ply.compareTo(b.ply));

  return GeneratedOpeningStudy(
    title: studyTitle,
    openingFamily: group.openingFamily,
    side: group.side,
    pgnText: pgnText,
    gameCount: group.games.length,
    mistakeFixes: sortedFixes,
    chapterCount: chapters.length,
    latestGameAt: latestGameAt,
  );
}

_ResolvedUserDecision _resolveCandidateDecision(
  _UserNodeStats nodeStats, {
  required PolyglotBook? book,
}) {
  final pos = nodeStats.position;
  final mostPlayed = nodeStats.mostPlayed;

  // 1. If the user's habitual (most-played) move was flagged as a mistake in analysis,
  // replace it with the best recommended move (or a known good alternative).
  if (mostPlayed.totalMistakes > 0) {
    final bestFix = _pickBestReplacementMove(
      nodeStats,
      badMoveUci: mostPlayed.move.uci,
      book: book,
    );
    if (bestFix != null && bestFix.uci != mostPlayed.move.uci) {
      final severity = mostPlayed.worstSeverity;
      final comment = _formatMistakeFixComment(
        mistakeSan: mostPlayed.move.san ?? mostPlayed.move.uci,
        correctSan: bestFix.san ?? bestFix.uci,
        playCount: mostPlayed.playCount,
        severity: severity,
      );
      return _ResolvedUserDecision(
        chosenMove: bestFix,
        fix: OpeningMistakeFix(
          fenKey: nodeStats.fenKeyStr,
          ply: nodeStats.ply,
          mistakeSan: mostPlayed.move.san ?? mostPlayed.move.uci,
          correctSan: bestFix.san ?? bestFix.uci,
          mistakePlayCount: mostPlayed.playCount,
          severity: severity,
          comment: comment,
        ),
        comment: comment,
      );
    }
  }

  // 2. If the user's most-played move was clean, check if they also played a secondary
  // mistake move in this exact position; keeping their main move corrects that mistake.
  final secondaryMistakes =
      nodeStats.playedMoves.values
          .where((m) => m.move.uci != mostPlayed.move.uci && m.totalMistakes > 0)
          .toList()
        ..sort((a, b) => b.totalMistakes.compareTo(a.totalMistakes));
  if (secondaryMistakes.isNotEmpty) {
    final bad = secondaryMistakes.first;
    final severity = bad.worstSeverity;
    final mainSan = mostPlayed.move.san ?? mostPlayed.move.uci;
    final badSan = bad.move.san ?? bad.move.uci;
    final comment = _formatMistakeFixComment(
      mistakeSan: badSan,
      correctSan: mainSan,
      playCount: bad.playCount,
      severity: severity,
    );
    return _ResolvedUserDecision(
      chosenMove: mostPlayed.move,
      fix: OpeningMistakeFix(
        fenKey: nodeStats.fenKeyStr,
        ply: nodeStats.ply,
        mistakeSan: badSan,
        correctSan: mainSan,
        mistakePlayCount: bad.playCount,
        severity: severity,
        comment: comment,
      ),
      comment: comment,
    );
  }

  // 3. Fallback for unanalysed games: if a Polyglot opening book is available and the
  // user's habitual move in a known book position (ply <= 16) is off-book (< 2% weight)
  // with a losing record, replace it with the main book move.
  if (book != null && nodeStats.ply >= 3 && nodeStats.ply <= 16) {
    final bookMoves = book.movesFor(pos);
    if (bookMoves.isNotEmpty) {
      final totalWeight = bookMoves.fold<int>(0, (sum, m) => sum + m.weight);
      final match = bookMoves.where((m) => m.uci == mostPlayed.move.uci).firstOrNull;
      final isOffBook = match == null || (totalWeight > 0 && match.weight / totalWeight < 0.02);
      final score = (mostPlayed.wins + 0.5 * mostPlayed.draws) / mostPlayed.playCount;
      if (isOffBook && score < 0.45 && mostPlayed.losses > mostPlayed.wins) {
        final topBookMove = _parseUciMove(pos, bookMoves.first.uci);
        if (topBookMove != null && topBookMove.uci != mostPlayed.move.uci) {
          final repBook = normalmoveToRepertoireMove(topBookMove, pos);
          final badSan = mostPlayed.move.san ?? mostPlayed.move.uci;
          final goodSan = repBook.san ?? repBook.uci;
          final comment = _formatMistakeFixComment(
            mistakeSan: badSan,
            correctSan: goodSan,
            playCount: mostPlayed.playCount,
            severity: MistakeSeverity.mistake,
          );
          return _ResolvedUserDecision(
            chosenMove: repBook,
            fix: OpeningMistakeFix(
              fenKey: nodeStats.fenKeyStr,
              ply: nodeStats.ply,
              mistakeSan: badSan,
              correctSan: goodSan,
              mistakePlayCount: mostPlayed.playCount,
              severity: MistakeSeverity.mistake,
              comment: comment,
            ),
            comment: comment,
          );
        }
      }
    }
  }

  return _ResolvedUserDecision(chosenMove: mostPlayed.move);
}

RepertoireMove? _pickBestReplacementMove(
  _UserNodeStats nodeStats, {
  required String badMoveUci,
  required PolyglotBook? book,
}) {
  final fixes = nodeStats.recommendedFixes.values.where((f) => f.move.uci != badMoveUci).toList()
    ..sort((a, b) {
      final countCmp = b.count.compareTo(a.count);
      if (countCmp != 0) return countCmp;
      return b.severity.index.compareTo(a.severity.index);
    });
  if (fixes.isNotEmpty) {
    return fixes.first.move;
  }

  final cleanAlternates =
      nodeStats.playedMoves.values
          .where((m) => m.move.uci != badMoveUci && m.totalMistakes == 0)
          .toList()
        ..sort((a, b) => b.playCount.compareTo(a.playCount));
  if (cleanAlternates.isNotEmpty) {
    return cleanAlternates.first.move;
  }

  if (book != null) {
    final bookMoves = book.movesFor(nodeStats.position);
    for (final bm in bookMoves) {
      if (bm.uci == badMoveUci) continue;
      final parsed = _parseUciMove(nodeStats.position, bm.uci);
      if (parsed != null) {
        return normalmoveToRepertoireMove(parsed, nodeStats.position);
      }
    }
  }

  return null;
}

String _formatMistakeFixComment({
  required String mistakeSan,
  required String correctSan,
  required int playCount,
  required MistakeSeverity severity,
}) {
  final countLabel = playCount == 1 ? 'once' : '$playCount times';
  return 'Fixes your ${severity.label} $mistakeSan (played $countLabel). $correctSan is best.';
}

bool _subtreeHasSeriousMistake(
  Position pos, {
  required Side side,
  required Map<String, _UserNodeStats> userNodes,
  required Map<String, Map<String, ({RepertoireMove move, int count})>> allOppMovesByKey,
  required Map<String, _ResolvedUserDecision> candidateDecisions,
  required Set<String> visited,
}) {
  final key = fenKey(pos.fen);
  if (visited.contains(key)) return false;
  final nextVisited = {...visited, key};

  if (pos.turn == side) {
    final cand = candidateDecisions[key];
    if (cand == null) return false;
    if (cand.fix != null && cand.fix!.severity != MistakeSeverity.inaccuracy) {
      return true;
    }
    final nodeStats = userNodes[key];
    if (nodeStats == null) return false;
    final parsed = _parseUciMove(pos, nodeStats.mostPlayed.move.uci);
    if (parsed == null) return false;
    return _subtreeHasSeriousMistake(
      pos.playUnchecked(parsed),
      side: side,
      userNodes: userNodes,
      allOppMovesByKey: allOppMovesByKey,
      candidateDecisions: candidateDecisions,
      visited: nextVisited,
    );
  } else {
    final oppMoves = allOppMovesByKey[key];
    if (oppMoves == null) return false;
    for (final opp in oppMoves.values) {
      final parsed = _parseUciMove(pos, opp.move.uci);
      if (parsed == null) continue;
      if (_subtreeHasSeriousMistake(
        pos.playUnchecked(parsed),
        side: side,
        userNodes: userNodes,
        allOppMovesByKey: allOppMovesByKey,
        candidateDecisions: candidateDecisions,
        visited: nextVisited,
      )) {
        return true;
      }
    }
    return false;
  }
}

bool _oppMoveLeadsToFix(
  Position pos,
  String oppMoveUci, {
  required Side side,
  required Map<String, _ResolvedUserDecision> resolvedDecisions,
  required Map<String, Map<String, ({RepertoireMove move, int count})>> oppMovesByKey,
  required Set<String> visited,
}) {
  final parsed = _parseUciMove(pos, oppMoveUci);
  if (parsed == null) return false;
  return _positionLeadsToFix(
    pos.playUnchecked(parsed),
    side: side,
    resolvedDecisions: resolvedDecisions,
    oppMovesByKey: oppMovesByKey,
    visited: visited,
  );
}

bool _positionLeadsToFix(
  Position pos, {
  required Side side,
  required Map<String, _ResolvedUserDecision> resolvedDecisions,
  required Map<String, Map<String, ({RepertoireMove move, int count})>> oppMovesByKey,
  required Set<String> visited,
}) {
  final key = fenKey(pos.fen);
  if (visited.contains(key)) return false;
  final nextVisited = {...visited, key};

  if (pos.turn == side) {
    final decision = resolvedDecisions[key];
    if (decision == null) return false;
    if (decision.fix != null) return true;
    final parsed = _parseUciMove(pos, decision.chosenMove.uci);
    if (parsed == null) return false;
    return _positionLeadsToFix(
      pos.playUnchecked(parsed),
      side: side,
      resolvedDecisions: resolvedDecisions,
      oppMovesByKey: oppMovesByKey,
      visited: nextVisited,
    );
  } else {
    final oppMap = oppMovesByKey[key];
    if (oppMap == null) return false;
    for (final opp in oppMap.values) {
      final parsed = _parseUciMove(pos, opp.move.uci);
      if (parsed == null) continue;
      if (_positionLeadsToFix(
        pos.playUnchecked(parsed),
        side: side,
        resolvedDecisions: resolvedDecisions,
        oppMovesByKey: oppMovesByKey,
        visited: nextVisited,
      )) {
        return true;
      }
    }
    return false;
  }
}

bool _gamesInBucketTouchFix(
  List<_ReplayedGame> games, {
  required Side side,
  required Map<String, _ResolvedUserDecision> resolvedDecisions,
}) {
  return _countFixesInBucket(games, side, resolvedDecisions) > 0;
}

int _countFixesInBucket(
  List<_ReplayedGame> games,
  Side side,
  Map<String, _ResolvedUserDecision> resolvedDecisions,
) {
  final fixedKeys = <String>{};
  for (final game in games) {
    for (final step in game.steps) {
      if (step.posBefore.turn != side) continue;
      final key = fenKey(step.posBefore.fen);
      if (resolvedDecisions[key]?.fix != null) {
        fixedKeys.add(key);
      }
    }
  }
  return fixedKeys.length;
}

({MistakeSeverity severity, RepertoireMove? bestMove})? _detectStepMistake(
  _ReplayedStep step,
  Side userSide,
) {
  final evalAfter = step.evalAfter;
  if (evalAfter == null) return null;

  MistakeSeverity? severity;
  final judgment = evalAfter.judgmentName?.trim().toLowerCase();
  if (judgment == 'blunder') {
    severity = MistakeSeverity.blunder;
  } else if (judgment == 'mistake') {
    severity = MistakeSeverity.mistake;
  } else if (judgment == 'inaccuracy') {
    severity = MistakeSeverity.inaccuracy;
  } else {
    final cpBefore = _evalToUserCp(step.evalBefore, userSide, isInitial: step.plyIndex == 0);
    final cpAfter = _evalToUserCp(evalAfter, userSide, isInitial: false);
    if (cpBefore != null && cpAfter != null && cpBefore >= -300) {
      final drop = cpBefore - cpAfter;
      if (drop >= 200) {
        severity = MistakeSeverity.blunder;
      } else if (drop >= 120) {
        severity = MistakeSeverity.mistake;
      } else if (drop >= 80) {
        severity = MistakeSeverity.inaccuracy;
      }
    }
  }

  if (severity == null) return null;

  final bestNormal =
      _parseUciMove(step.posBefore, evalAfter.bestUci) ??
      _parseFirstVariationSan(step.posBefore, evalAfter.variation) ??
      _parseBestFromComment(step.posBefore, evalAfter.judgmentComment);
  final bestRep = bestNormal != null
      ? normalmoveToRepertoireMove(bestNormal, step.posBefore)
      : null;

  return (severity: severity, bestMove: bestRep);
}

int? _evalToUserCp(LichessPlyAnalysis? eval, Side userSide, {required bool isInitial}) {
  if (eval == null) {
    return isInitial ? 20 : null;
  }
  final sign = userSide == Side.white ? 1 : -1;
  if (eval.mate != null) {
    final m = eval.mate!;
    final whiteMateScore = m > 0 ? 1000 : -1000;
    return sign * whiteMateScore;
  }
  if (eval.cp != null) {
    return sign * eval.cp!;
  }
  return null;
}

NormalMove? _parseUciMove(Position pos, String? rawUci) {
  if (rawUci == null) return null;
  final trimmed = rawUci.trim();
  if (trimmed.isEmpty) return null;

  final parsed = Move.parse(trimmed);
  if (parsed is NormalMove) {
    if (pos.isLegal(parsed)) {
      return parsed;
    }
    if (pos.board.roleAt(parsed.from) == Role.king) {
      if (trimmed == 'e1g1' || trimmed == 'e8g8') {
        final castle = pos.parseSan('O-O');
        if (castle is NormalMove) return castle;
      } else if (trimmed == 'e1c1' || trimmed == 'e8c8') {
        final castle = pos.parseSan('O-O-O');
        if (castle is NormalMove) return castle;
      }
    }
  }
  return null;
}

NormalMove? _parseFirstVariationSan(Position pos, String? variation) {
  if (variation == null) return null;
  final tokens = variation.trim().split(RegExp(r'\s+'));
  for (final token in tokens) {
    if (token.isEmpty) continue;
    if (RegExp(r'^\d+\.+$').hasMatch(token)) continue;
    final cleaned = token.replaceFirst(RegExp(r'^\d+\.+'), '');
    if (cleaned.isEmpty) continue;
    final parsed = pos.parseSan(cleaned);
    if (parsed is NormalMove) return parsed;
    break;
  }
  return null;
}

NormalMove? _parseBestFromComment(Position pos, String? comment) {
  if (comment == null || comment.isEmpty) return null;
  final match = RegExp(
    r'([O0]-[O0](?:-[O0])?|[KQRBN]?[a-h]?[1-8]?x?[a-h][1-8](?:=[QRBN])?[+#]?)\s+was\s+best',
  ).firstMatch(comment);
  if (match == null) return null;
  final san = match.group(1)!.replaceAll('0', 'O');
  final parsed = pos.parseSan(san);
  return parsed is NormalMove ? parsed : null;
}
