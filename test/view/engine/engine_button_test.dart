import 'package:chess_srs/src/model/common/id.dart';
import 'package:chess_srs/src/model/engine/evaluation_mixin.dart';
import 'package:chess_srs/src/model/engine/position_evaluator.dart';
import 'package:chess_srs/src/view/engine/engine_button.dart';
import 'package:chess_srs/src/widgets/buttons.dart';
import 'package:chessground/chessground.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../model/engine/fake_engine.dart';
import 'test_engine_app.dart';

void main() {
  testWidgets('Engine button is not displayed if computer analysis is not allowed', (tester) async {
    await makeEngineTestApp(tester, isComputerAnalysisAllowed: false);
    expect(find.byType(EngineButton), findsNothing);
  });

  testWidgets('Engine starts immediately after the request eval delay', (tester) async {
    // loads a finished game, disable cloud eval because it is usually not available in mid/end game
    await makeEngineTestApp(tester, isCloudEvalEnabled: false, gameId: const GameId('xze7RH66'));

    // A "Loading…" label, not a CircularProgressIndicator: the restyle replaced the spinner with
    // a quiet text state (analysis_screen.dart). The assertion still means what it always meant --
    // there is a loading state, and it goes away once the game arrives -- it just no longer looks
    // for a widget the screen stopped rendering. Asserting on a string is more brittle than
    // asserting on a spinner type; recorded rather than glossed over.
    expect(find.text('Loading\u2026'), findsOne);
    // wait for the game to be loaded
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Loading\u2026'), findsNothing);
    expect(find.byType(Chessboard), findsOne);
    expect(find.byType(EngineButton), findsOne);

    // engine not yet started, so it still displays initial state
    expect(find.widgetWithText(EngineButton, '-'), findsOne);

    // wait for engine
    await tester.pump(kRequestEvalDebounceDelay + kEngineEvalEmissionThrottleDelay);
    expect(find.widgetWithText(EngineButton, '16'), findsOne);
  });

  testWidgets('No engine is started when the user has turned the engine off', (tester) async {
    final stockfish = FakeEngine();
    await makeEngineTestApp(
      tester,
      isEngineEnabled: false,
      isCloudEvalEnabled: false,
      gameId: const GameId('xze7RH66'),
      stockfish: stockfish,
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(kRequestEvalDebounceDelay + kEngineEvalEmissionThrottleDelay);

    // Opening a screen with the engine off asks for no evaluation, so no engine is ever created:
    // an engine nobody is going to use must not be started, on this screen or the next.
    expect(stockfish.startCount, 0);
  });

  testWidgets('Long pressing the engine button opens the engine popup', (tester) async {
    await makeEngineTestApp(tester, isCloudEvalEnabled: false, gameId: const GameId('xze7RH66'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(kRequestEvalDebounceDelay + kEngineEvalEmissionThrottleDelay);

    await tester.longPress(
      find.descendant(of: find.byType(EngineButton), matching: find.byType(SemanticIconButton)),
    );
    await tester.pumpAndSettle();

    // The popup lists the engine name in a Diagram row.
    expect(find.textContaining('Stockfish'), findsOneWidget);
  });
}
