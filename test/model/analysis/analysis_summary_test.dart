// Copyright (C) 2026 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:chess_srs/src/model/analysis/analysis_summary.dart';
import 'package:deep_pick/deep_pick.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';

Response _responseWithHeader(String? header) =>
    Response('', 200, headers: header == null ? const {} : {'x-lichess-analysis': header});

String _header({
  Map<String, dynamic>? division,
  required Map<String, dynamic> white,
  required Map<String, dynamic> black,
}) => jsonEncode({
  ...?division == null ? null : {'division': division},
  'summary': {'white': white, 'black': black},
});

const _white = {'inaccuracy': 3, 'mistake': 2, 'blunder': 1, 'acpl': 30, 'accuracy': 80};
const _black = {'inaccuracy': 5, 'mistake': 4, 'blunder': 2, 'acpl': 45, 'accuracy': 70};

void main() {
  group('readAnalysisSummaryFromHeader', () {
    test('returns null when the analysis header is absent', () {
      expect(readAnalysisSummaryFromHeader(_responseWithHeader(null)), isNull);
    });

    test('parses the summary for both players, including division', () {
      final summary = readAnalysisSummaryFromHeader(
        _responseWithHeader(
          _header(division: {'middle': 40, 'end': 80}, white: _white, black: _black),
        ),
      );

      expect(summary, isNotNull);
      expect(summary!.division?.middlegame, 40);
      expect(summary.division?.endgame, 80);
      expect(summary.white.inaccuracies, 3);
      expect(summary.white.mistakes, 2);
      expect(summary.white.blunders, 1);
      expect(summary.white.acpl, 30);
      expect(summary.white.accuracy, 80);
      expect(summary.black.inaccuracies, 5);
      expect(summary.black.mistakes, 4);
      expect(summary.black.blunders, 2);
      expect(summary.black.acpl, 45);
      expect(summary.black.accuracy, 70);
    });

    test('division is null when the header omits it', () {
      final summary = readAnalysisSummaryFromHeader(
        _responseWithHeader(_header(white: _white, black: _black)),
      );

      expect(summary, isNotNull);
      expect(summary!.division, isNull);
    });

    test('optional acpl and accuracy stay null when omitted', () {
      const sparseWhite = {'inaccuracy': 0, 'mistake': 0, 'blunder': 0};
      const sparseBlack = {'inaccuracy': 1, 'mistake': 0, 'blunder': 0};

      final summary = readAnalysisSummaryFromHeader(
        _responseWithHeader(_header(white: sparseWhite, black: sparseBlack)),
      );

      expect(summary, isNotNull);
      expect(summary!.white.acpl, isNull);
      expect(summary.white.accuracy, isNull);
      expect(summary.black.acpl, isNull);
      expect(summary.black.accuracy, isNull);
    });

    test('throws when the summary key is missing', () {
      expect(
        () => readAnalysisSummaryFromHeader(
          _responseWithHeader(jsonEncode(<String, dynamic>{'division': <String, dynamic>{}})),
        ),
        throwsA(isA<PickException>()),
      );
    });

    test('throws when a player summary is missing a required count', () {
      final badHeader = _header(
        white: <String, dynamic>{'mistake': 2, 'blunder': 1},
        black: _black,
      );

      expect(
        () => readAnalysisSummaryFromHeader(_responseWithHeader(badHeader)),
        throwsA(isA<PickException>()),
      );
    });
  });
}
