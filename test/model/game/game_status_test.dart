import 'package:chess_srs/src/model/game/game_status.dart';
import 'package:deep_pick/deep_pick.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('can decode status name', () {
    final gameStatus = Pick('mate').asGameStatusOrThrow();
    expect(gameStatus, GameStatus.mate);
  });

  test('can decode status object', () {
    final gameStatus = Pick({'id': 30, 'name': 'mate'}).asGameStatusOrThrow();
    expect(gameStatus, GameStatus.mate);
  });

  test('can decode status int', () {
    final gameStatus = Pick(30).asGameStatusOrThrow();
    expect(gameStatus, GameStatus.mate);
  });
}
