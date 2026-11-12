import 'package:chess_srs/src/model/common/id.dart';
import 'package:chess_srs/src/model/game/game_socket_events.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FenSocketEvent.fromJson', () {
    test('parses fen, last move and clocks', () {
      final event = FenSocketEvent.fromJson({
        'id': 'game1234',
        'fen': 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1',
        'lm': 'e2e4',
        'wc': 180,
        'bc': 175.5,
      });

      expect(event.id, const GameId('game1234'));
      expect(event.fen, 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1');
      expect(event.lastMove, Move.parse('e2e4'));
      expect(event.whiteClock, const Duration(seconds: 180));
      expect(event.blackClock, const Duration(milliseconds: 175500));
    });
  });

  group('ServerEvalEvent.fromJson', () {
    test('parses root-only tree as complete with no evals', () {
      final event = ServerEvalEvent.fromJson({
        'tree': {'ply': 0},
      });

      expect(event.evals, isEmpty);
      expect(event.isAnalysisComplete, isTrue);
      expect(event.analysis, isNull);
      expect(event.division, isNull);
    });

    test('extracts evals, variations and marks analysis incomplete when eval missing', () {
      final event = ServerEvalEvent.fromJson({
        'tree': {
          'ply': 0,
          'children': [
            {
              'ply': 1,
              'san': 'e4',
              'eval': {'cp': 20, 'best': 'e7e5'},
              'children': [
                {
                  'ply': 2,
                  'san': 'e5',
                  'eval': {'cp': 15},
                  'children': [
                    {
                      'ply': 3,
                      'san': 'Nf3',
                      // missing eval with child means incomplete
                      'children': [
                        {
                          'ply': 4,
                          'san': 'Nc6',
                          'eval': {'mate': 3},
                        },
                      ],
                    },
                    {
                      'ply': 3,
                      'san': 'Bc4',
                      'eval': {'cp': 5},
                    },
                  ],
                },
                {
                  'ply': 2,
                  'san': 'c5',
                  'eval': {'cp': 35},
                },
              ],
            },
          ],
        },
      });

      expect(event.isAnalysisComplete, isFalse);
      expect(event.evals.length, 4);

      expect(event.evals[0].cp, 20);
      expect(event.evals[0].bestMove, 'e7e5');
      expect(event.evals[0].variation, isNull);

      expect(event.evals[1].cp, 15);
      expect(event.evals[1].variation, 'c5');

      expect(event.evals[2].cp, isNull);
      expect(event.evals[2].mate, isNull);
      expect(event.evals[2].variation, 'Bc4');

      expect(event.evals[3].mate, 3);
      expect(event.evals[3].variation, isNull);
    });

    test('maps judgment glyphs and parses analysis/division', () {
      final event = ServerEvalEvent.fromJson({
        'tree': {
          'ply': 0,
          'children': [
            {
              'ply': 1,
              'san': 'Qh5',
              'eval': {'cp': -120},
              'glyphs': [
                {'id': 4},
              ],
              'comments': [
                {'text': 'Loses material'},
              ],
            },
          ],
        },
        'analysis': {
          'id': 'an123456',
          'white': {
            'inaccuracy': 1,
            'mistake': 2,
            'blunder': 3,
            'acpl': 42,
            'accuracy': 88,
            'phases': {'opening': 90, 'middlegame': 85, 'endgame': 80},
          },
          'black': {'inaccuracy': 4, 'mistake': 5, 'blunder': 6},
        },
        'division': {'middle': 24, 'end': 51},
      });

      expect(event.isAnalysisComplete, isTrue);
      expect(event.evals.single.judgment, (name: 'Blunder', comment: 'Loses material'));
      expect(event.division, (middle: 24, end: 51));

      final analysis = event.analysis;
      expect(analysis, isNotNull);
      expect(analysis!.id, const GameId('an123456'));
      expect(analysis.white.inaccuracies, 1);
      expect(analysis.white.mistakes, 2);
      expect(analysis.white.blunders, 3);
      expect(analysis.white.acpl, 42);
      expect(analysis.white.accuracy, 88);
      expect(analysis.white.phases, (opening: 90, middlegame: 85, endgame: 80));

      expect(analysis.black.inaccuracies, 4);
      expect(analysis.black.mistakes, 5);
      expect(analysis.black.blunders, 6);
      expect(analysis.black.acpl, isNull);
      expect(analysis.black.accuracy, isNull);
      expect(analysis.black.phases, isNull);
    });

    test('maps known nag ids and unknown to empty judgment name', () {
      ServerEvalEvent eventForNag(int nag) => ServerEvalEvent.fromJson({
        'tree': {
          'ply': 0,
          'children': [
            {
              'ply': 1,
              'san': 'Nf3',
              'eval': {'cp': 0},
              'glyphs': [
                {'id': nag},
              ],
              'comments': [
                {'text': 'note'},
              ],
            },
          ],
        },
      });

      expect(eventForNag(6).evals.single.judgment?.name, 'Inaccuracy');
      expect(eventForNag(2).evals.single.judgment?.name, 'Mistake');
      expect(eventForNag(4).evals.single.judgment?.name, 'Blunder');
      expect(eventForNag(1).evals.single.judgment?.name, '');
    });

    test('skips root ply and leaf mate-without-eval nodes', () {
      final event = ServerEvalEvent.fromJson({
        'tree': {
          'ply': 0,
          'eval': {'cp': 0},
          'children': [
            {
              'ply': 1,
              'san': 'f3',
              'eval': {'cp': -50},
              'children': [
                {
                  'ply': 2,
                  'san': 'e5',
                  'eval': {'mate': -1},
                },
              ],
            },
            {
              'ply': 2,
              'san': 'Qh4#',
              // checkmate leaf: no eval and no children, must not be added
            },
          ],
        },
      });

      expect(event.evals.map((e) => e.mate ?? e.cp).toList(), [-50, -1]);
      expect(event.isAnalysisComplete, isTrue);
    });
  });
}
