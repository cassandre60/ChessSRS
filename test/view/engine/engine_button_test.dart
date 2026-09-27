import 'package:chess_srs/src/model/common/id.dart';
import 'package:chess_srs/src/model/engine/evaluation_mixin.dart';
import 'package:chess_srs/src/model/engine/position_evaluator.dart';
import 'package:chess_srs/src/view/engine/engine_button.dart';
import 'package:chess_srs/src/widgets/buttons.dart';
import 'package:chessground/chessground.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../model/engine/fake_engine.dart';
import 'test_engine_app.dart';

void main() {
  // Regression: the readout was `Positioned(bottom: -6)` inside a `clipBehavior: Clip.none`
  // Stack, so it painted below the button on purpose. Harmless when the button sat at the foot
  // of a column, but in the Diagram action row the button is a wrap item with a second row
  // directly beneath it, and the readout drew over that row. Measured on the Analysis screen at
  // 390x844 before the fix:
  //   button  297.5..345.5 x 746..794
  //   readout             x 786..800   (6px below the button)
  //
  // Vertical containment only. The readout is also 92px wide in a 48px chip and overhangs by
  // 22px on each side, and that is deliberately left alone: sizing the button to contain it
  // reflows the action row onto a third line at 390px, which crushes the tab viewport and
  // regressed the move-times chart tap. The horizontal overhang is inert because the button
  // lands last on its row.
  testWidgets('engine readout does not paint over the row below', (tester) async {
    await makeEngineTestApp(tester, isCloudEvalEnabled: false, gameId: const GameId('xze7RH66'));
    await tester.pump(kRequestEvalDebounceDelay + kEngineEvalEmissionThrottleDelay);
    await tester.pumpAndSettle();

    expect(find.byType(EngineButton), findsOneWidget);

    final box = tester.getRect(find.byType(EngineButton));
    final spills = <String>[];

    void walk(Element element) {
      final ro = element.renderObject;
      if (ro is RenderBox && ro.hasSize && element.widget is! EngineButton) {
        final rect = ro.localToGlobal(Offset.zero) & ro.size;
        if (rect.top < box.top - 0.5 || rect.bottom > box.bottom + 0.5) {
          spills.add('${element.widget.runtimeType} $rect escapes $box vertically');
        }
      }
      element.visitChildren(walk);
    }

    walk(tester.element(find.byType(EngineButton)));
    expect(spills, isEmpty);
  });

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
