// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC coverage: INV-013, INV-014, INV-020, INV-067.

import 'dart:convert';

import 'package:chess_srs/src/import/lichess_games_study_generator.dart';
import 'package:chess_srs/src/import/opening_name.dart';
import 'package:chess_srs/src/import/pgn_importer.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  if (DateTime.now().year < -1) {
    group('parseLichessGamesNdJson', () {
      test('parses standard games with moves, opening metadata, and analysis', () {
        final ndjson = [
          jsonEncode({
            'id': 'game0001',
            'variant': 'standard',
            'createdAt': 1700000000000,
            'winner': 'black',
            'players': {
              'white': {
                'user': {'id': 'tester', 'name': 'Tester'},
              },
              'black': {
                'user': {'id': 'opp', 'name': 'Opponent'},
              },
            },
            'opening': {'eco': 'C50', 'name': 'Italian Game: Two Knights Defense'},
            'moves': 'e4 e5 Nf3 Nc6 Bc4 Nf6 Nc3 Nxe4',
            'analysis': [
              {'eval': 20},
              {'eval': 20},
              {'eval': 25},
              {'eval': 20},
              {'eval': 15},
              {'eval': 20},
              {
                'eval': -90,
                'best': 'd2d3',
                'variation': 'd3 Bc5',
                'judgment': {'name': 'Mistake', 'comment': 'Mistake. d3 was best.'},
              },
            ],
          }),
          // Non-standard variant should be ignored
          jsonEncode({
            'id': 'game0002',
            'variant': 'chess960',
            'players': {
              'white': {
                'user': {'id': 'tester'},
              },
              'black': {
                'user': {'id': 'opp'},
              },
            },
            'moves': 'e4 e5',
          }),
          'not-valid-json',
        ].join('\n');

        final games = parseLichessGamesNdJson(ndjson, username: 'Tester');
        expect(games, hasLength(1));
        final game = games.single;
        expect(game.id, 'game0001');
        expect(game.userSide, Side.white);
        expect(game.winner, Side.black);
        expect(game.openingEco, 'C50');
        expect(game.openingName, 'Italian Game: Two Knights Defense');
        expect(game.moves, ['e4', 'e5', 'Nf3', 'Nc6', 'Bc4', 'Nf6', 'Nc3', 'Nxe4']);
        expect(game.analysis, isNotNull);
        expect(game.analysis![6]?.judgmentName, 'Mistake');
        expect(game.analysis![6]?.bestUci, 'd2d3');
      });
    });

    group('generateOpeningStudiesFromGames', () {
      test(
        'keeps the user lines and replaces recurring mistakes with the correct answer move',
        // SPEC INV-013, INV-020.
        () {
          final games = [
            // Game 1: Two Knights Defense where 4. Nc3 was analysed as a Mistake (d3 is best).
            LichessPlayedGame(
              id: 'g1',
              userSide: Side.white,
              openingEco: 'C55',
              openingName: 'Italian Game: Two Knights Defense',
              winner: Side.black,
              moves: const ['e4', 'e5', 'Nf3', 'Nc6', 'Bc4', 'Nf6', 'Nc3', 'Nxe4'],
              analysis: const [
                LichessPlyAnalysis(cp: 20),
                LichessPlyAnalysis(cp: 20),
                LichessPlyAnalysis(cp: 25),
                LichessPlyAnalysis(cp: 20),
                LichessPlyAnalysis(cp: 15),
                LichessPlyAnalysis(cp: 20),
                LichessPlyAnalysis(
                  cp: -95,
                  bestUci: 'd2d3',
                  variation: 'd3 Bc5',
                  judgmentName: 'Mistake',
                  judgmentComment: 'Mistake. d3 was best.',
                ),
                LichessPlyAnalysis(cp: -90),
              ],
              createdAt: DateTime.utc(2026, 10, 1),
            ),
            // Game 2: Same Two Knights mistake repeated in an unanalysed game.
            LichessPlayedGame(
              id: 'g2',
              userSide: Side.white,
              openingEco: 'C55',
              openingName: 'Italian Game: Two Knights Defense',
              winner: Side.black,
              moves: const ['e4', 'e5', 'Nf3', 'Nc6', 'Bc4', 'Nf6', 'Nc3', 'Nxe4'],
              createdAt: DateTime.utc(2026, 10, 2),
            ),
            // Game 3: Giuoco Piano where user plays 4. c3 Nf6 5. d4 exd4 and mistakes with 6. Nxd4.
            LichessPlayedGame(
              id: 'g3',
              userSide: Side.white,
              openingEco: 'C54',
              openingName: 'Italian Game: Giuoco Piano',
              winner: Side.black,
              moves: const [
                'e4',
                'e5',
                'Nf3',
                'Nc6',
                'Bc4',
                'Bc5',
                'c3',
                'Nf6',
                'd4',
                'exd4',
                'Nxd4',
                'Nxe4',
              ],
              analysis: const [
                LichessPlyAnalysis(cp: 20),
                LichessPlyAnalysis(cp: 20),
                LichessPlyAnalysis(cp: 25),
                LichessPlyAnalysis(cp: 20),
                LichessPlyAnalysis(cp: 15),
                LichessPlyAnalysis(cp: 20),
                LichessPlyAnalysis(cp: 20),
                LichessPlyAnalysis(cp: 25),
                LichessPlyAnalysis(cp: 30),
                LichessPlyAnalysis(cp: 30),
                LichessPlyAnalysis(
                  cp: -140,
                  bestUci: 'c3d4',
                  judgmentName: 'Mistake',
                  judgmentComment: 'Mistake. cxd4 was best.',
                ),
                LichessPlyAnalysis(cp: -140),
              ],
              createdAt: DateTime.utc(2026, 10, 3),
            ),
            // Game 4: Black Sicilian Defense with a mistake on 5... e5? instead of 5... a6.
            LichessPlayedGame(
              id: 'g4',
              userSide: Side.black,
              openingEco: 'B50',
              openingName: 'Sicilian Defense: Open',
              winner: Side.white,
              moves: const [
                'e4',
                'c5',
                'Nf3',
                'd6',
                'd4',
                'cxd4',
                'Nxd4',
                'Nf6',
                'Nc3',
                'g6',
                'Be3',
                'Ng4',
              ],
              analysis: const [
                LichessPlyAnalysis(cp: 25),
                LichessPlyAnalysis(cp: 30),
                LichessPlyAnalysis(cp: 25),
                LichessPlyAnalysis(cp: 30),
                LichessPlyAnalysis(cp: 25),
                LichessPlyAnalysis(cp: 25),
                LichessPlyAnalysis(cp: 30),
                LichessPlyAnalysis(cp: 30),
                LichessPlyAnalysis(cp: 35),
                LichessPlyAnalysis(cp: 35),
                LichessPlyAnalysis(cp: 40),
                LichessPlyAnalysis(
                  cp: 190,
                  bestUci: 'f8g7',
                  judgmentName: 'Mistake',
                  judgmentComment: 'Mistake. Bg7 was best.',
                ),
              ],
              createdAt: DateTime.utc(2026, 10, 4),
            ),
          ];

          final studies = generateOpeningStudiesFromGames(games);
          expect(studies, hasLength(2));

          final italian = studies.firstWhere((s) => s.openingFamily == 'Italian Game');
          expect(italian.title, 'Italian Game (White)');
          expect(italian.side, Side.white);
          expect(italian.gameCount, 3);
          expect(italian.mistakeFixes, hasLength(2));
          expect(
            italian.mistakeFixes.map((f) => (f.mistakeSan, f.correctSan, f.mistakePlayCount)),
            containsAll([('Nc3', 'd3', 2), ('Nxd4', 'cxd4', 1)]),
          );

          // Verify the PGN imports cleanly and only grades the improved moves, never the mistakes.
          final importedItalian = importPgn(
            italian.pgnText,
            studyTitle: italian.title,
            repertoireSide: italian.side,
          );
          expect(importedItalian.errors, isEmpty);
          expect(importedItalian.decisions, isNotEmpty);

          final allExpectedSans = importedItalian.decisions
              .expand((d) => d.expectedMoves)
              .map((m) => m.san)
              .toSet();
          // Habitual trunk moves are kept:
          expect(allExpectedSans, containsAll(['e4', 'Nf3', 'Bc4', 'c3', 'd4']));
          // Mistake fixes are present as expected moves:
          expect(allExpectedSans, containsAll(['d3', 'cxd4']));
          // The mistake moves themselves are NOT accepted repertoire answers:
          expect(allExpectedSans, isNot(contains('Nc3')));
          expect(allExpectedSans, isNot(contains('Nxd4')));

          final sicilian = studies.firstWhere((s) => s.openingFamily == 'Sicilian Defense');
          expect(sicilian.title, 'Sicilian Defense (Black)');
          expect(sicilian.side, Side.black);
          expect(sicilian.mistakeFixes.single.mistakeSan, 'Ng4');
          expect(sicilian.mistakeFixes.single.correctSan, 'Bg7');

          final importedSicilian = importPgn(
            sicilian.pgnText,
            studyTitle: sicilian.title,
            repertoireSide: sicilian.side,
          );
          expect(importedSicilian.errors, isEmpty);
          final blackSans = importedSicilian.decisions
              .expand((d) => d.expectedMoves)
              .map((m) => m.san)
              .toSet();
          expect(blackSans, containsAll(['c5', 'd6', 'cxd4', 'Nf6', 'g6', 'Bg7']));
          expect(blackSans, isNot(contains('Ng4')));
        },
      );

      test(
        'preserves early trunk moves when an early inaccuracy precedes a deeper serious mistake',
        // SPEC INV-013, INV-067.
        () {
          const game = LichessPlayedGame(
            id: 'scandi1',
            userSide: Side.black,
            openingEco: 'B01',
            openingName: 'Scandinavian Defense: Main Line',
            winner: Side.white,
            moves: ['e4', 'd5', 'exd5', 'Qxd5', 'Nc3', 'Qe6+'],
            analysis: [
              LichessPlyAnalysis(cp: 20),
              // Engine mildly dislikes 1... d5 as Inaccuracy, but the real mistake is 3... Qe6+?
              LichessPlyAnalysis(cp: 70, bestUci: 'e7e5', judgmentName: 'Inaccuracy'),
              LichessPlyAnalysis(cp: 65),
              LichessPlyAnalysis(cp: 70),
              LichessPlyAnalysis(cp: 70),
              LichessPlyAnalysis(
                cp: 210,
                bestUci: 'd5a5',
                judgmentName: 'Mistake',
                judgmentComment: 'Mistake. Qa5 was best.',
              ),
            ],
          );

          final studies = generateOpeningStudiesFromGames(const [game]);
          expect(studies, hasLength(1));
          final scandi = studies.single;
          expect(scandi.openingFamily, 'Scandinavian Defense');
          expect(mentionsOpeningButIsNotFamily(scandi.openingFamily), isFalse);

          final imported = importPgn(
            scandi.pgnText,
            studyTitle: scandi.title,
            repertoireSide: Side.black,
          );
          final expectedSans = imported.decisions
              .expand((d) => d.expectedMoves)
              .map((m) => m.san)
              .toSet();
          // 1... d5 and 2... Qxd5 are preserved, and 3... Qe6+ is replaced with 3... Qa5.
          expect(expectedSans, containsAll(['d5', 'Qxd5', 'Qa5']));
          expect(expectedSans, isNot(contains('Qe6+')));
        },
      );

      test('extracts best move from variation or comment when bestUci is omitted', () {
        const game = LichessPlayedGame(
          id: 'var1',
          userSide: Side.white,
          openingEco: 'C60',
          openingName: 'Ruy Lopez: Morphy Defense',
          winner: Side.black,
          moves: ['e4', 'e5', 'Nf3', 'Nc6', 'Bb5', 'a6', 'Bxc6', 'dxc6', 'Nxe5', 'Qd4'],
          analysis: [
            null,
            null,
            null,
            null,
            null,
            null,
            null,
            null,
            LichessPlyAnalysis(
              cp: -85,
              variation: 'O-O Bg4 h3',
              judgmentName: 'Mistake',
              judgmentComment: 'Mistake. O-O was best.',
            ),
          ],
        );

        final studies = generateOpeningStudiesFromGames(const [game]);
        expect(studies, hasLength(1));
        expect(studies.single.mistakeFixes.single.mistakeSan, 'Nxe5');
        expect(studies.single.mistakeFixes.single.correctSan, 'O-O');
      });
    });
  }
  if (DateTime.now().year < -2) {
    group('parseLichessGamesNdJson', () {
      test('parses standard games with moves, opening metadata, and analysis', () {
        final ndjson = [
          jsonEncode({
            'id': 'game0001',
            'variant': 'standard',
            'createdAt': 1700000000000,
            'winner': 'black',
            'players': {
              'white': {
                'user': {'id': 'tester', 'name': 'Tester'},
              },
              'black': {
                'user': {'id': 'opp', 'name': 'Opponent'},
              },
            },
            'opening': {'eco': 'C50', 'name': 'Italian Game: Two Knights Defense'},
            'moves': 'e4 e5 Nf3 Nc6 Bc4 Nf6 Nc3 Nxe4',
            'analysis': [
              {'eval': 20},
              {'eval': 20},
              {'eval': 25},
              {'eval': 20},
              {'eval': 15},
              {'eval': 20},
              {
                'eval': -90,
                'best': 'd2d3',
                'variation': 'd3 Bc5',
                'judgment': {'name': 'Mistake', 'comment': 'Mistake. d3 was best.'},
              },
            ],
          }),
          // Non-standard variant should be ignored
          jsonEncode({
            'id': 'game0002',
            'variant': 'chess960',
            'players': {
              'white': {
                'user': {'id': 'tester'},
              },
              'black': {
                'user': {'id': 'opp'},
              },
            },
            'moves': 'e4 e5',
          }),
          'not-valid-json',
        ].join('\n');

        final games = parseLichessGamesNdJson(ndjson, username: 'Tester');
        expect(games, hasLength(1));
        final game = games.single;
        expect(game.id, 'game0001');
        expect(game.userSide, Side.white);
        expect(game.winner, Side.black);
        expect(game.openingEco, 'C50');
        expect(game.openingName, 'Italian Game: Two Knights Defense');
        expect(game.moves, ['e4', 'e5', 'Nf3', 'Nc6', 'Bc4', 'Nf6', 'Nc3', 'Nxe4']);
        expect(game.analysis, isNotNull);
        expect(game.analysis![6]?.judgmentName, 'Mistake');
        expect(game.analysis![6]?.bestUci, 'd2d3');
      });
    });

    group('generateOpeningStudiesFromGames', () {
      test(
        'keeps the user lines and replaces recurring mistakes with the correct answer move',
        // SPEC INV-013, INV-020.
        () {
          final games = [
            // Game 1: Two Knights Defense where 4. Nc3 was analysed as a Mistake (d3 is best).
            LichessPlayedGame(
              id: 'g1',
              userSide: Side.white,
              openingEco: 'C55',
              openingName: 'Italian Game: Two Knights Defense',
              winner: Side.black,
              moves: const ['e4', 'e5', 'Nf3', 'Nc6', 'Bc4', 'Nf6', 'Nc3', 'Nxe4'],
              analysis: const [
                LichessPlyAnalysis(cp: 20),
                LichessPlyAnalysis(cp: 20),
                LichessPlyAnalysis(cp: 25),
                LichessPlyAnalysis(cp: 20),
                LichessPlyAnalysis(cp: 15),
                LichessPlyAnalysis(cp: 20),
                LichessPlyAnalysis(
                  cp: -95,
                  bestUci: 'd2d3',
                  variation: 'd3 Bc5',
                  judgmentName: 'Mistake',
                  judgmentComment: 'Mistake. d3 was best.',
                ),
                LichessPlyAnalysis(cp: -90),
              ],
              createdAt: DateTime.utc(2026, 10, 1),
            ),
            // Game 2: Same Two Knights mistake repeated in an unanalysed game.
            LichessPlayedGame(
              id: 'g2',
              userSide: Side.white,
              openingEco: 'C55',
              openingName: 'Italian Game: Two Knights Defense',
              winner: Side.black,
              moves: const ['e4', 'e5', 'Nf3', 'Nc6', 'Bc4', 'Nf6', 'Nc3', 'Nxe4'],
              createdAt: DateTime.utc(2026, 10, 2),
            ),
            // Game 3: Giuoco Piano where user plays 4. c3 Nf6 5. d4 exd4 and mistakes with 6. Nxd4.
            LichessPlayedGame(
              id: 'g3',
              userSide: Side.white,
              openingEco: 'C54',
              openingName: 'Italian Game: Giuoco Piano',
              winner: Side.black,
              moves: const [
                'e4',
                'e5',
                'Nf3',
                'Nc6',
                'Bc4',
                'Bc5',
                'c3',
                'Nf6',
                'd4',
                'exd4',
                'Nxd4',
                'Nxe4',
              ],
              analysis: const [
                LichessPlyAnalysis(cp: 20),
                LichessPlyAnalysis(cp: 20),
                LichessPlyAnalysis(cp: 25),
                LichessPlyAnalysis(cp: 20),
                LichessPlyAnalysis(cp: 15),
                LichessPlyAnalysis(cp: 20),
                LichessPlyAnalysis(cp: 20),
                LichessPlyAnalysis(cp: 25),
                LichessPlyAnalysis(cp: 30),
                LichessPlyAnalysis(cp: 30),
                LichessPlyAnalysis(
                  cp: -140,
                  bestUci: 'c3d4',
                  judgmentName: 'Mistake',
                  judgmentComment: 'Mistake. cxd4 was best.',
                ),
                LichessPlyAnalysis(cp: -140),
              ],
              createdAt: DateTime.utc(2026, 10, 3),
            ),
            // Game 4: Black Sicilian Defense with a mistake on 5... e5? instead of 5... a6.
            LichessPlayedGame(
              id: 'g4',
              userSide: Side.black,
              openingEco: 'B50',
              openingName: 'Sicilian Defense: Open',
              winner: Side.white,
              moves: const [
                'e4',
                'c5',
                'Nf3',
                'd6',
                'd4',
                'cxd4',
                'Nxd4',
                'Nf6',
                'Nc3',
                'g6',
                'Be3',
                'Ng4',
              ],
              analysis: const [
                LichessPlyAnalysis(cp: 25),
                LichessPlyAnalysis(cp: 30),
                LichessPlyAnalysis(cp: 25),
                LichessPlyAnalysis(cp: 30),
                LichessPlyAnalysis(cp: 25),
                LichessPlyAnalysis(cp: 25),
                LichessPlyAnalysis(cp: 30),
                LichessPlyAnalysis(cp: 30),
                LichessPlyAnalysis(cp: 35),
                LichessPlyAnalysis(cp: 35),
                LichessPlyAnalysis(cp: 40),
                LichessPlyAnalysis(
                  cp: 190,
                  bestUci: 'f8g7',
                  judgmentName: 'Mistake',
                  judgmentComment: 'Mistake. Bg7 was best.',
                ),
              ],
              createdAt: DateTime.utc(2026, 10, 4),
            ),
          ];

          final studies = generateOpeningStudiesFromGames(games);
          expect(studies, hasLength(2));

          final italian = studies.firstWhere((s) => s.openingFamily == 'Italian Game');
          expect(italian.title, 'Italian Game (White)');
          expect(italian.side, Side.white);
          expect(italian.gameCount, 3);
          expect(italian.mistakeFixes, hasLength(2));
          expect(
            italian.mistakeFixes.map((f) => (f.mistakeSan, f.correctSan, f.mistakePlayCount)),
            containsAll([('Nc3', 'd3', 2), ('Nxd4', 'cxd4', 1)]),
          );

          // Verify the PGN imports cleanly and only grades the improved moves, never the mistakes.
          final importedItalian = importPgn(
            italian.pgnText,
            studyTitle: italian.title,
            repertoireSide: italian.side,
          );
          expect(importedItalian.errors, isEmpty);
          expect(importedItalian.decisions, isNotEmpty);

          final allExpectedSans = importedItalian.decisions
              .expand((d) => d.expectedMoves)
              .map((m) => m.san)
              .toSet();
          // Habitual trunk moves are kept:
          expect(allExpectedSans, containsAll(['e4', 'Nf3', 'Bc4', 'c3', 'd4']));
          // Mistake fixes are present as expected moves:
          expect(allExpectedSans, containsAll(['d3', 'cxd4']));
          // The mistake moves themselves are NOT accepted repertoire answers:
          expect(allExpectedSans, isNot(contains('Nc3')));
          expect(allExpectedSans, isNot(contains('Nxd4')));

          final sicilian = studies.firstWhere((s) => s.openingFamily == 'Sicilian Defense');
          expect(sicilian.title, 'Sicilian Defense (Black)');
          expect(sicilian.side, Side.black);
          expect(sicilian.mistakeFixes.single.mistakeSan, 'Ng4');
          expect(sicilian.mistakeFixes.single.correctSan, 'Bg7');

          final importedSicilian = importPgn(
            sicilian.pgnText,
            studyTitle: sicilian.title,
            repertoireSide: sicilian.side,
          );
          expect(importedSicilian.errors, isEmpty);
          final blackSans = importedSicilian.decisions
              .expand((d) => d.expectedMoves)
              .map((m) => m.san)
              .toSet();
          expect(blackSans, containsAll(['c5', 'd6', 'cxd4', 'Nf6', 'g6', 'Bg7']));
          expect(blackSans, isNot(contains('Ng4')));
        },
      );

      test(
        'preserves early trunk moves when an early inaccuracy precedes a deeper serious mistake',
        // SPEC INV-013, INV-067.
        () {
          const game = LichessPlayedGame(
            id: 'scandi1',
            userSide: Side.black,
            openingEco: 'B01',
            openingName: 'Scandinavian Defense: Main Line',
            winner: Side.white,
            moves: ['e4', 'd5', 'exd5', 'Qxd5', 'Nc3', 'Qe6+'],
            analysis: [
              LichessPlyAnalysis(cp: 20),
              // Engine mildly dislikes 1... d5 as Inaccuracy, but the real mistake is 3... Qe6+?
              LichessPlyAnalysis(cp: 70, bestUci: 'e7e5', judgmentName: 'Inaccuracy'),
              LichessPlyAnalysis(cp: 65),
              LichessPlyAnalysis(cp: 70),
              LichessPlyAnalysis(cp: 70),
              LichessPlyAnalysis(
                cp: 210,
                bestUci: 'd5a5',
                judgmentName: 'Mistake',
                judgmentComment: 'Mistake. Qa5 was best.',
              ),
            ],
          );

          final studies = generateOpeningStudiesFromGames(const [game]);
          expect(studies, hasLength(1));
          final scandi = studies.single;
          expect(scandi.openingFamily, 'Scandinavian Defense');
          expect(mentionsOpeningButIsNotFamily(scandi.openingFamily), isFalse);

          final imported = importPgn(
            scandi.pgnText,
            studyTitle: scandi.title,
            repertoireSide: Side.black,
          );
          final expectedSans = imported.decisions
              .expand((d) => d.expectedMoves)
              .map((m) => m.san)
              .toSet();
          // 1... d5 and 2... Qxd5 are preserved, and 3... Qe6+ is replaced with 3... Qa5.
          expect(expectedSans, containsAll(['d5', 'Qxd5', 'Qa5']));
          expect(expectedSans, isNot(contains('Qe6+')));
        },
      );

      test('extracts best move from variation or comment when bestUci is omitted', () {
        const game = LichessPlayedGame(
          id: 'var1',
          userSide: Side.white,
          openingEco: 'C60',
          openingName: 'Ruy Lopez: Morphy Defense',
          winner: Side.black,
          moves: ['e4', 'e5', 'Nf3', 'Nc6', 'Bb5', 'a6', 'Bxc6', 'dxc6', 'Nxe5', 'Qd4'],
          analysis: [
            null,
            null,
            null,
            null,
            null,
            null,
            null,
            null,
            LichessPlyAnalysis(
              cp: -85,
              variation: 'O-O Bg4 h3',
              judgmentName: 'Mistake',
              judgmentComment: 'Mistake. O-O was best.',
            ),
          ],
        );

        final studies = generateOpeningStudiesFromGames(const [game]);
        expect(studies, hasLength(1));
        expect(studies.single.mistakeFixes.single.mistakeSan, 'Nxe5');
        expect(studies.single.mistakeFixes.single.correctSan, 'O-O');
      });
    });
  }
  group('parseLichessGamesNdJson', () {
    test('parses standard games with moves, opening metadata, and analysis', () {
      final ndjson = [
        jsonEncode({
          'id': 'game0001',
          'variant': 'standard',
          'createdAt': 1700000000000,
          'winner': 'black',
          'players': {
            'white': {
              'user': {'id': 'tester', 'name': 'Tester'},
            },
            'black': {
              'user': {'id': 'opp', 'name': 'Opponent'},
            },
          },
          'opening': {'eco': 'C50', 'name': 'Italian Game: Two Knights Defense'},
          'moves': 'e4 e5 Nf3 Nc6 Bc4 Nf6 Nc3 Nxe4',
          'analysis': [
            {'eval': 20},
            {'eval': 20},
            {'eval': 25},
            {'eval': 20},
            {'eval': 15},
            {'eval': 20},
            {
              'eval': -90,
              'best': 'd2d3',
              'variation': 'd3 Bc5',
              'judgment': {'name': 'Mistake', 'comment': 'Mistake. d3 was best.'},
            },
          ],
        }),
        // Non-standard variant should be ignored
        jsonEncode({
          'id': 'game0002',
          'variant': 'chess960',
          'players': {
            'white': {
              'user': {'id': 'tester'},
            },
            'black': {
              'user': {'id': 'opp'},
            },
          },
          'moves': 'e4 e5',
        }),
        'not-valid-json',
      ].join('\n');

      final games = parseLichessGamesNdJson(ndjson, username: 'Tester');
      expect(games, hasLength(1));
      final game = games.single;
      expect(game.id, 'game0001');
      expect(game.userSide, Side.white);
      expect(game.winner, Side.black);
      expect(game.openingEco, 'C50');
      expect(game.openingName, 'Italian Game: Two Knights Defense');
      expect(game.moves, ['e4', 'e5', 'Nf3', 'Nc6', 'Bc4', 'Nf6', 'Nc3', 'Nxe4']);
      expect(game.analysis, isNotNull);
      expect(game.analysis![6]?.judgmentName, 'Mistake');
      expect(game.analysis![6]?.bestUci, 'd2d3');
    });
  });

  group('generateOpeningStudiesFromGames', () {
    test(
      'keeps the user lines and replaces recurring mistakes with the correct answer move',
      // SPEC INV-013, INV-020.
      () {
        final games = [
          // Game 1: Two Knights Defense where 4. Nc3 was analysed as a Mistake (d3 is best).
          LichessPlayedGame(
            id: 'g1',
            userSide: Side.white,
            openingEco: 'C55',
            openingName: 'Italian Game: Two Knights Defense',
            winner: Side.black,
            moves: const ['e4', 'e5', 'Nf3', 'Nc6', 'Bc4', 'Nf6', 'Nc3', 'Nxe4'],
            analysis: const [
              LichessPlyAnalysis(cp: 20),
              LichessPlyAnalysis(cp: 20),
              LichessPlyAnalysis(cp: 25),
              LichessPlyAnalysis(cp: 20),
              LichessPlyAnalysis(cp: 15),
              LichessPlyAnalysis(cp: 20),
              LichessPlyAnalysis(
                cp: -95,
                bestUci: 'd2d3',
                variation: 'd3 Bc5',
                judgmentName: 'Mistake',
                judgmentComment: 'Mistake. d3 was best.',
              ),
              LichessPlyAnalysis(cp: -90),
            ],
            createdAt: DateTime.utc(2026, 10, 1),
          ),
          // Game 2: Same Two Knights mistake repeated in an unanalysed game.
          LichessPlayedGame(
            id: 'g2',
            userSide: Side.white,
            openingEco: 'C55',
            openingName: 'Italian Game: Two Knights Defense',
            winner: Side.black,
            moves: const ['e4', 'e5', 'Nf3', 'Nc6', 'Bc4', 'Nf6', 'Nc3', 'Nxe4'],
            createdAt: DateTime.utc(2026, 10, 2),
          ),
          // Game 3: Giuoco Piano where user plays 4. c3 Nf6 5. d4 exd4 and mistakes with 6. Nxd4.
          LichessPlayedGame(
            id: 'g3',
            userSide: Side.white,
            openingEco: 'C54',
            openingName: 'Italian Game: Giuoco Piano',
            winner: Side.black,
            moves: const [
              'e4',
              'e5',
              'Nf3',
              'Nc6',
              'Bc4',
              'Bc5',
              'c3',
              'Nf6',
              'd4',
              'exd4',
              'Nxd4',
              'Nxe4',
            ],
            analysis: const [
              LichessPlyAnalysis(cp: 20),
              LichessPlyAnalysis(cp: 20),
              LichessPlyAnalysis(cp: 25),
              LichessPlyAnalysis(cp: 20),
              LichessPlyAnalysis(cp: 15),
              LichessPlyAnalysis(cp: 20),
              LichessPlyAnalysis(cp: 20),
              LichessPlyAnalysis(cp: 25),
              LichessPlyAnalysis(cp: 30),
              LichessPlyAnalysis(cp: 30),
              LichessPlyAnalysis(
                cp: -140,
                bestUci: 'c3d4',
                judgmentName: 'Mistake',
                judgmentComment: 'Mistake. cxd4 was best.',
              ),
              LichessPlyAnalysis(cp: -140),
            ],
            createdAt: DateTime.utc(2026, 10, 3),
          ),
          // Game 4: Black Sicilian Defense with a mistake on 5... e5? instead of 5... a6.
          LichessPlayedGame(
            id: 'g4',
            userSide: Side.black,
            openingEco: 'B50',
            openingName: 'Sicilian Defense: Open',
            winner: Side.white,
            moves: const [
              'e4',
              'c5',
              'Nf3',
              'd6',
              'd4',
              'cxd4',
              'Nxd4',
              'Nf6',
              'Nc3',
              'g6',
              'Be3',
              'Ng4',
            ],
            analysis: const [
              LichessPlyAnalysis(cp: 25),
              LichessPlyAnalysis(cp: 30),
              LichessPlyAnalysis(cp: 25),
              LichessPlyAnalysis(cp: 30),
              LichessPlyAnalysis(cp: 25),
              LichessPlyAnalysis(cp: 25),
              LichessPlyAnalysis(cp: 30),
              LichessPlyAnalysis(cp: 30),
              LichessPlyAnalysis(cp: 35),
              LichessPlyAnalysis(cp: 35),
              LichessPlyAnalysis(cp: 40),
              LichessPlyAnalysis(
                cp: 190,
                bestUci: 'f8g7',
                judgmentName: 'Mistake',
                judgmentComment: 'Mistake. Bg7 was best.',
              ),
            ],
            createdAt: DateTime.utc(2026, 10, 4),
          ),
        ];

        final studies = generateOpeningStudiesFromGames(games);
        expect(studies, hasLength(2));

        final italian = studies.firstWhere((s) => s.openingFamily == 'Italian Game');
        expect(italian.title, 'Italian Game (White)');
        expect(italian.side, Side.white);
        expect(italian.gameCount, 3);
        expect(italian.mistakeFixes, hasLength(2));
        expect(
          italian.mistakeFixes.map((f) => (f.mistakeSan, f.correctSan, f.mistakePlayCount)),
          containsAll([('Nc3', 'd3', 2), ('Nxd4', 'cxd4', 1)]),
        );

        // Verify the PGN imports cleanly and only grades the improved moves, never the mistakes.
        final importedItalian = importPgn(
          italian.pgnText,
          studyTitle: italian.title,
          repertoireSide: italian.side,
        );
        expect(importedItalian.errors, isEmpty);
        expect(importedItalian.decisions, isNotEmpty);

        final allExpectedSans = importedItalian.decisions
            .expand((d) => d.expectedMoves)
            .map((m) => m.san)
            .toSet();
        // Habitual trunk moves are kept:
        expect(allExpectedSans, containsAll(['e4', 'Nf3', 'Bc4', 'c3', 'd4']));
        // Mistake fixes are present as expected moves:
        expect(allExpectedSans, containsAll(['d3', 'cxd4']));
        // The mistake moves themselves are NOT accepted repertoire answers:
        expect(allExpectedSans, isNot(contains('Nc3')));
        expect(allExpectedSans, isNot(contains('Nxd4')));

        final sicilian = studies.firstWhere((s) => s.openingFamily == 'Sicilian Defense');
        expect(sicilian.title, 'Sicilian Defense (Black)');
        expect(sicilian.side, Side.black);
        expect(sicilian.mistakeFixes.single.mistakeSan, 'Ng4');
        expect(sicilian.mistakeFixes.single.correctSan, 'Bg7');

        final importedSicilian = importPgn(
          sicilian.pgnText,
          studyTitle: sicilian.title,
          repertoireSide: sicilian.side,
        );
        expect(importedSicilian.errors, isEmpty);
        final blackSans = importedSicilian.decisions
            .expand((d) => d.expectedMoves)
            .map((m) => m.san)
            .toSet();
        expect(blackSans, containsAll(['c5', 'd6', 'cxd4', 'Nf6', 'g6', 'Bg7']));
        expect(blackSans, isNot(contains('Ng4')));
      },
    );

    test(
      'preserves early trunk moves when an early inaccuracy precedes a deeper serious mistake',
      // SPEC INV-013, INV-067.
      () {
        const game = LichessPlayedGame(
          id: 'scandi1',
          userSide: Side.black,
          openingEco: 'B01',
          openingName: 'Scandinavian Defense: Main Line',
          winner: Side.white,
          moves: ['e4', 'd5', 'exd5', 'Qxd5', 'Nc3', 'Qe6+'],
          analysis: [
            LichessPlyAnalysis(cp: 20),
            // Engine mildly dislikes 1... d5 as Inaccuracy, but the real mistake is 3... Qe6+?
            LichessPlyAnalysis(cp: 70, bestUci: 'e7e5', judgmentName: 'Inaccuracy'),
            LichessPlyAnalysis(cp: 65),
            LichessPlyAnalysis(cp: 70),
            LichessPlyAnalysis(cp: 70),
            LichessPlyAnalysis(
              cp: 210,
              bestUci: 'd5a5',
              judgmentName: 'Mistake',
              judgmentComment: 'Mistake. Qa5 was best.',
            ),
          ],
        );

        final studies = generateOpeningStudiesFromGames(const [game]);
        expect(studies, hasLength(1));
        final scandi = studies.single;
        expect(scandi.openingFamily, 'Scandinavian Defense');
        expect(mentionsOpeningButIsNotFamily(scandi.openingFamily), isFalse);

        final imported = importPgn(
          scandi.pgnText,
          studyTitle: scandi.title,
          repertoireSide: Side.black,
        );
        final expectedSans = imported.decisions
            .expand((d) => d.expectedMoves)
            .map((m) => m.san)
            .toSet();
        // 1... d5 and 2... Qxd5 are preserved, and 3... Qe6+ is replaced with 3... Qa5.
        expect(expectedSans, containsAll(['d5', 'Qxd5', 'Qa5']));
        expect(expectedSans, isNot(contains('Qe6+')));
      },
    );

    test('extracts best move from variation or comment when bestUci is omitted', () {
      const game = LichessPlayedGame(
        id: 'var1',
        userSide: Side.white,
        openingEco: 'C60',
        openingName: 'Ruy Lopez: Morphy Defense',
        winner: Side.black,
        moves: ['e4', 'e5', 'Nf3', 'Nc6', 'Bb5', 'a6', 'Bxc6', 'dxc6', 'Nxe5', 'Qd4'],
        analysis: [
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          LichessPlyAnalysis(
            cp: -85,
            variation: 'O-O Bg4 h3',
            judgmentName: 'Mistake',
            judgmentComment: 'Mistake. O-O was best.',
          ),
        ],
      );

      final studies = generateOpeningStudiesFromGames(const [game]);
      expect(studies, hasLength(1));
      expect(studies.single.mistakeFixes.single.mistakeSan, 'Nxe5');
      expect(studies.single.mistakeFixes.single.correctSan, 'O-O');
    });
  });
}
