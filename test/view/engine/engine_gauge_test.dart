import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chess_srs/src/model/common/eval.dart';
import 'package:chess_srs/src/model/common/id.dart';
import 'package:chess_srs/src/model/engine/evaluation_context.dart';
import 'package:chess_srs/src/view/engine/engine_gauge.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../test_provider_scope.dart';

void main() {
  testWidgets('EngineGauge shows 0.0 when eval is 0', (WidgetTester tester) async {
    final params = (
      isLocalEngineAvailable: true,
      orientation: Side.white,
      position: Chess.initial.makeSanUnchecked(Move.parse('e2e4')!).$1,
      savedEval: null,
      serverEval: const ExternalEval(cp: 0, mate: null),
      filters: (
        context: const EvaluationContext(
          id: StringId('test'),
          variant: Variant.standard,
          initialPosition: Chess.initial,
        ),
        path: null,
      ),
    );

    final widget = await makeTestProviderScopeApp(
      tester,
      home: Scaffold(
        body: SizedBox(height: 400, child: EngineGauge(params: params)),
      ),
    );

    await tester.pumpWidget(widget);
    // The gauge has an animation, we need to wait for it.
    await tester.pumpAndSettle();

    expect(find.text('0.0'), findsOneWidget);
  });

  testWidgets('EngineGauge shows 0.0 (no sign) for small positive eval', (
    WidgetTester tester,
  ) async {
    final params = (
      isLocalEngineAvailable: true,
      orientation: Side.white,
      position: Chess.initial.makeSanUnchecked(Move.parse('e2e4')!).$1,
      savedEval: null,
      serverEval: const ExternalEval(cp: 2, mate: null),
      filters: (
        context: const EvaluationContext(
          id: StringId('test'),
          variant: Variant.standard,
          initialPosition: Chess.initial,
        ),
        path: null,
      ),
    );

    final widget = await makeTestProviderScopeApp(
      tester,
      home: Scaffold(
        body: SizedBox(height: 400, child: EngineGauge(params: params)),
      ),
    );

    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();

    expect(find.text('0.0'), findsOneWidget);
    expect(find.text('+0.0'), findsNothing);
  });

  testWidgets('EngineGauge shows 0.0 when game is a draw', (WidgetTester tester) async {
    final drawPosition = Chess.fromSetup(Setup.parseFen('k7/8/K7/8/8/8/8/8 w - - 0 1'));
    final params = (
      isLocalEngineAvailable: true,
      orientation: Side.white,
      position: drawPosition,
      savedEval: null,
      serverEval: null,
      filters: (
        context: const EvaluationContext(
          id: StringId('test'),
          variant: Variant.standard,
          initialPosition: Chess.initial,
        ),
        path: null,
      ),
    );

    final widget = await makeTestProviderScopeApp(
      tester,
      home: Scaffold(
        body: SizedBox(height: 400, child: EngineGauge(params: params)),
      ),
    );

    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();

    expect(find.text('0.0'), findsOneWidget);
  });

  EngineGaugeParams paramsFor({required bool local, ExternalEval? server, Position? position}) => (
    isLocalEngineAvailable: local,
    orientation: Side.white,
    position: position ?? Chess.initial.makeSanUnchecked(Move.parse('e2e4')!).$1,
    savedEval: null,
    serverEval: server,
    filters: (
      context: const EvaluationContext(
        id: StringId('test'),
        variant: Variant.standard,
        initialPosition: Chess.initial,
      ),
      path: null,
    ),
  );

  testWidgets('gauge is dimmed only when local engine is unavailable and there is no server eval', (
    WidgetTester tester,
  ) async {
    const gaugeKey = Key('engine-gauge-under-test');

    Future<double> pumpOpacity({required bool local, ExternalEval? server}) async {
      await tester.pumpWidget(
        await makeTestProviderScopeApp(
          tester,
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: EngineGauge(
                key: gaugeKey,
                params: paramsFor(local: local, server: server),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester
          .widget<Opacity>(
            find.descendant(of: find.byKey(gaugeKey), matching: find.byType(Opacity)),
          )
          .opacity;
    }

    // No local engine and no server eval -> disabled (0.5).
    expect(await pumpOpacity(local: false, server: null), 0.5);
    // No local engine but a server eval is available -> full opacity (1.0).
    // Kills the `&&` -> `||` mutation of the opacity condition.
    expect(await pumpOpacity(local: false, server: const ExternalEval(cp: 0, mate: null)), 1.0);
    // Local engine available (even without server eval) -> full opacity (1.0).
    // Kills the `serverEval == null` -> `!= null` mutation.
    expect(await pumpOpacity(local: true, server: null), 1.0);
  });

  testWidgets('a drawn game centers the eval at the bottom for a white board', (
    WidgetTester tester,
  ) async {
    final drawPosition = Chess.fromSetup(Setup.parseFen('k7/8/K7/8/8/8/8/8 w - - 0 1'));

    await tester.pumpWidget(
      await makeTestProviderScopeApp(
        tester,
        home: Scaffold(
          body: SizedBox(
            height: 400,
            child: EngineGauge(
              params: paramsFor(local: true, server: null, position: drawPosition),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // A draw has animationValue 0.5 -> the label sits at the bottom for a white
    // board. Mutating `winner == null` to `!= null` drives animationValue to 0.0
    // and flips the label to the top, so this assertion fails on that mutant.
    expect(tester.getCenter(find.text('0.0')).dy, greaterThan(200));
  });
}
