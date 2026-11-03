// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/model/game/offline_computer_game.dart';
import 'package:chess_srs/src/model/game/player.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

const _base = {
  'id': 'ocg_deadbeef',
  'meta': {
    'createdAt': '2026-08-01T12:00:00.000',
    'rated': false,
    'variant': 'standard',
    'speed': 'classical',
    'perf': 'classical',
  },
  'initialFen': null,
  'status': 'started',
  'steps': '[{"fen":"$kInitialFEN","rule":"chess","uci":null,"san":null}]',
  'playerSide': 'white',
  'casual': true,
  'practiceMode': false,
  'opponentSpec': {'type': 'stockfish', 'level': 'level7'},
};

OfflineComputerGame _game({String status = 'started', String playerSide = 'white'}) {
  return OfflineComputerGame.fromJson({
    ..._base,
    'status': status,
    'playerSide': playerSide,
  }).copyWith(
    humanPlayer: const Player(onGame: true, name: 'human'),
    enginePlayer: const Player(onGame: false, name: 'engine'),
  );
}

void main() {
  test('abortable is true for a freshly started game', () {
    final game = _game();
    expect(game.abortable, isTrue);
  });

  test('abortable is false for a non-playable (aborted) game', () {
    final game = _game(status: 'aborted');
    expect(game.abortable, isFalse);
  });

  test('resignable is false for a freshly started (abortable) game', () {
    final game = _game();
    expect(game.resignable, isFalse);
  });

  test('resignable is false for a non-playable (aborted) game', () {
    final game = _game(status: 'aborted');
    expect(game.resignable, isFalse);
  });

  test('white and black point at the human/engine for a white-sided game', () {
    final game = _game();
    expect(game.white.name, 'human');
    expect(game.black.name, 'engine');
  });

  test('enginePlayerFor marks the engine as onGame', () {
    expect(enginePlayerFor(const StockfishOpponentSpec(StockfishLevel.level1)).onGame, isTrue);
    expect(enginePlayerFor(const MaiaOpponentSpec(MaiaRating.maia1100)).onGame, isTrue);
  });

  test('white and black point at the engine/human for a black-sided game', () {
    final game = _game(playerSide: 'black');
    expect(game.white.name, 'engine');
    expect(game.black.name, 'human');
  });
}
