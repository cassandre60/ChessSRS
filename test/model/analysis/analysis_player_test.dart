import 'package:chess_srs/src/model/analysis/analysis_player.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AnalysisPlayer.fromPgnHeaders', () {
    test('returns null when player name is missing', () {
      final headers = <String, String>{}.lock;

      expect(AnalysisPlayer.fromPgnHeaders(headers, Side.white), isNull);
      expect(AnalysisPlayer.fromPgnHeaders(headers, Side.black), isNull);
    });

    test('returns null when player name is a placeholder', () {
      final headers = <String, String>{'White': '?', 'Black': '?'}.lock;

      expect(AnalysisPlayer.fromPgnHeaders(headers, Side.white), isNull);
      expect(AnalysisPlayer.fromPgnHeaders(headers, Side.black), isNull);
    });

    test('creates white player from PGN headers', () {
      final headers = <String, String>{
        'White': 'Magnus Carlsen',
        'WhiteTitle': 'GM',
        'WhiteElo': '2830',
        'Black': 'Opponent',
      }.lock;

      final player = AnalysisPlayer.fromPgnHeaders(headers, Side.white);

      expect(player, isNotNull);
      expect(player!.name, 'Magnus Carlsen');
      expect(player.side, Side.white);
      expect(player.title, 'GM');
      expect(player.rating, 2830);
    });

    test('creates black player from PGN headers', () {
      final headers = <String, String>{
        'White': 'Opponent',
        'Black': 'Hikaru Nakamura',
        'BlackTitle': 'GM',
        'BlackElo': '2789',
      }.lock;

      final player = AnalysisPlayer.fromPgnHeaders(headers, Side.black);

      expect(player, isNotNull);
      expect(player!.name, 'Hikaru Nakamura');
      expect(player.side, Side.black);
      expect(player.title, 'GM');
      expect(player.rating, 2789);
    });

    test('omits missing title and invalid rating', () {
      final headers = <String, String>{'White': 'Anonymous', 'WhiteElo': 'not-a-number'}.lock;

      final player = AnalysisPlayer.fromPgnHeaders(headers, Side.white);

      expect(player, isNotNull);
      expect(player!.name, 'Anonymous');
      expect(player.side, Side.white);
      expect(player.title, isNull);
      expect(player.rating, isNull);
    });

    test('omits rating when elo header is absent', () {
      final headers = <String, String>{'Black': 'Player', 'BlackTitle': 'IM'}.lock;

      final player = AnalysisPlayer.fromPgnHeaders(headers, Side.black);

      expect(player, isNotNull);
      expect(player!.title, 'IM');
      expect(player.rating, isNull);
    });
  });
}
