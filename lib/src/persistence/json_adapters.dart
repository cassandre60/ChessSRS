// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:chess_srs/src/domain/domain.dart';

Map<String, dynamic> repertoireMoveToJson(RepertoireMove move) => {
  'from': move.from,
  'to': move.to,
  if (move.promotion != null) 'promotion': move.promotion,
  if (move.san != null) 'san': move.san,
};

RepertoireMove repertoireMoveFromJson(Map<String, dynamic> json) => RepertoireMove(
  from: json['from'] as String,
  to: json['to'] as String,
  promotion: json['promotion'] as String?,
  san: json['san'] as String?,
);

Map<String, dynamic> repertoireNodeToJson(RepertoireNode node) => {
  'id': node.id,
  'fen': node.fen,
  'fenKey': node.fenKey,
  if (node.incomingMove != null) 'incomingMove': repertoireMoveToJson(node.incomingMove!),
  if (node.comment != null) 'comment': node.comment,
  if (node.children.isNotEmpty)
    'children': node.children.map(repertoireNodeToJson).toList(growable: false),
};

RepertoireNode repertoireNodeFromJson(Map<String, dynamic> json) {
  final incoming = json['incomingMove'] != null
      ? repertoireMoveFromJson(Map<String, dynamic>.from(json['incomingMove'] as Map))
      : null;
  final rawChildren = json['children'] as List<dynamic>?;
  final children = rawChildren != null
      ? rawChildren
            .map((c) => repertoireNodeFromJson(Map<String, dynamic>.from(c as Map)))
            .toList(growable: false)
      : const <RepertoireNode>[];
  return RepertoireNode(
    id: json['id'] as String,
    fen: json['fen'] as String,
    fenKey: json['fenKey'] as String,
    incomingMove: incoming,
    comment: json['comment'] as String?,
    children: children,
  );
}

String encodeExpectedMoves(List<RepertoireMove> moves) =>
    jsonEncode(moves.map(repertoireMoveToJson).toList(growable: false));

List<RepertoireMove> decodeExpectedMoves(String raw) {
  final list = jsonDecode(raw) as List<dynamic>;
  return list
      .map((m) => repertoireMoveFromJson(Map<String, dynamic>.from(m as Map)))
      .toList(growable: false);
}

Map<String, dynamic> reviewStateToJson(ReviewState state) => {
  'decisionId': state.decisionId,
  'firstReviewedAt': state.firstReviewedAt?.toUtc().toIso8601String(),
  'lastReviewedAt': state.lastReviewedAt?.toUtc().toIso8601String(),
  'nextDueAt': state.nextDueAt?.toUtc().toIso8601String(),
  'repetitionCount': state.repetitionCount,
  'lapseCount': state.lapseCount,
  'stability': state.stability,
  'difficulty': state.difficulty,
};

ReviewState reviewStateFromJson(Map<String, dynamic> json) => ReviewState(
  decisionId: json['decisionId'] as String,
  firstReviewedAt: json['firstReviewedAt'] != null
      ? DateTime.parse(json['firstReviewedAt'] as String).toUtc()
      : null,
  lastReviewedAt: json['lastReviewedAt'] != null
      ? DateTime.parse(json['lastReviewedAt'] as String).toUtc()
      : null,
  nextDueAt: json['nextDueAt'] != null ? DateTime.parse(json['nextDueAt'] as String).toUtc() : null,
  repetitionCount: (json['repetitionCount'] as num?)?.toInt() ?? 0,
  lapseCount: (json['lapseCount'] as num?)?.toInt() ?? 0,
  stability: (json['stability'] as num?)?.toDouble() ?? 0.0,
  difficulty: (json['difficulty'] as num?)?.toDouble() ?? 5.0,
);

Map<String, dynamic> reviewEventToJson(ReviewEvent event) => {
  'decisionId': event.decisionId,
  'when': event.when.toUtc().toIso8601String(),
  'result': event.result.name,
  'oldState': reviewStateToJson(event.oldState),
  'newState': reviewStateToJson(event.newState),
};

ReviewEvent reviewEventFromJson(Map<String, dynamic> json) => ReviewEvent(
  decisionId: json['decisionId'] as String,
  when: DateTime.parse(json['when'] as String).toUtc(),
  result: ReviewResult.values.byName(json['result'] as String),
  oldState: reviewStateFromJson(Map<String, dynamic>.from(json['oldState'] as Map)),
  newState: reviewStateFromJson(Map<String, dynamic>.from(json['newState'] as Map)),
);
