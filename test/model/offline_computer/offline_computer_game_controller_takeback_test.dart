import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chess_srs/src/model/common/eval.dart';
import 'package:chess_srs/src/model/common/id.dart';
import 'package:chess_srs/src/model/common/perf.dart';
import 'package:chess_srs/src/model/common/speed.dart';
import 'package:chess_srs/src/model/game/game.dart';
import 'package:chess_srs/src/model/game/game_status.dart';
import 'package:chess_srs/src/model/game/offline_computer_game.dart';
import 'package:chess_srs/src/model/offline_computer/computer_analysis.dart';
import 'package:chess_srs/src/model/offline_computer/offline_computer_game_controller.dart';
import 'package:chess_srs/src/model/offline_computer/offline_computer_game_storage.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_container.dart';
import '../engine/fake_engine.dart';

/// A casual offline game one move pair deep, back on the player's turn: 1.e4 e5, white to move.
///
/// The opening position — where a takeback from here lands — carries a stored analysis deep
/// enough to use for hints (deeper than the usable-for-hints threshold). With it, the hint
/// cycle after the takeback takes the already-available evaluation instead of starting a fresh
/// load, which isolates the takeback's own busy-flag bookkeeping from whatever the new analysis
/// does later.
OfflineComputerGame makeCasualGameAtPlayersTurnAfterOneMovePair() {
  const initial = Chess.initial;
  final (afterE4, e4San) = initial.makeSanUnchecked(Move.parse('e2e4')!);
  final (afterE4E5, e5San) = afterE4.makeSanUnchecked(Move.parse('e7e5')!);
  final openingAnalysis = ComputerAnalysis(
    eval: CloudEval(
      position: initial,
      depth: 24,
      nodes: 4096,
      pvs: [
        PvData(moves: ['d2d4'].lock, cp: 35),
      ].lock,
    ),
  );

  return OfflineComputerGame(
    id: const StringId('takeback-hint-load-test'),
    steps: [
      GameStep(position: initial, computerAnalysis: openingAnalysis),
      GameStep(position: afterE4, sanMove: SanMove(e4San, Move.parse('e2e4')!)),
      GameStep(position: afterE4E5, sanMove: SanMove(e5San, Move.parse('e7e5')!)),
    ].lock,
    meta: GameMeta(
      createdAt: DateTime.utc(2026, 1, 1),
      rated: false,
      variant: Variant.standard,
      speed: Speed.classical,
      perf: Perf.classical,
    ),
    initialFen: null,
    status: GameStatus.started,
    playerSide: Side.white,
    opponentSpec: const StockfishOpponentSpec(StockfishLevel.level1),
  );
}

void main() {
  setUp(() {
    fakeEngine = LegalMoveEngine();
  });

  test('takeback forgets the hint load on the position it left behind', () async {
    final container = await makeContainer();
    addTearDown(container.dispose);

    final controller = container.read(offlineComputerGameControllerProvider.notifier);
    controller.loadGame(
      SavedOfflineComputerGame(game: makeCasualGameAtPlayersTurnAfterOneMovePair()),
    );

    // The resumed game is 1.e4 e5 on the player's turn, with nothing stored on that step yet:
    // analysing it to make hints available is under way the moment the load returns.
    expect(container.read(offlineComputerGameControllerProvider).isLoadingHint, isTrue);

    // Taking back lands on the opening position, whose stored analysis is already deep enough
    // to use: the fresh hint cycle takes it without any loading. The load that was under way
    // for the abandoned position is not this turn's business, so it must not survive the state
    // update the takeback writes — otherwise the hint() gate (refuses while loading) strands
    // the hint button even though hints for the position at hand are ready.
    controller.takeback();

    final afterTakeback = container.read(offlineComputerGameControllerProvider);
    expect(afterTakeback.hintMoves, isNotNull);
    expect(afterTakeback.isLoadingHint, isFalse);
  });
}
