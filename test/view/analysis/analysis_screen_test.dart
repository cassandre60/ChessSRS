import 'dart:async';
import 'dart:convert';

import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/model/analysis/analysis_controller.dart';
import 'package:chess_srs/src/model/analysis/analysis_preferences.dart';
import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chess_srs/src/model/common/id.dart';
import 'package:chess_srs/src/model/engine/evaluation_mixin.dart';
import 'package:chess_srs/src/model/engine/evaluation_preferences.dart';
import 'package:chess_srs/src/model/engine/position_evaluator.dart';
import 'package:chess_srs/src/model/settings/board_preferences.dart';
import 'package:chess_srs/src/model/settings/preferences_storage.dart';
import 'package:chess_srs/src/network/http.dart';
import 'package:chess_srs/src/network/socket.dart';
import 'package:chess_srs/src/view/analysis/analysis_layout.dart';
import 'package:chess_srs/src/view/analysis/analysis_screen.dart';
import 'package:chess_srs/src/view/engine/engine_button.dart';
import 'package:chess_srs/src/view/engine/engine_gauge.dart';
import 'package:chess_srs/src/view/engine/engine_lines.dart';
import 'package:chess_srs/src/view/more/more_tab_screen.dart';
import 'package:chess_srs/src/widgets/move_times_chart.dart';
import 'package:chess_srs/src/widgets/pgn.dart';
import 'package:chess_srs/src/widgets/pockets.dart';
import 'package:chess_srs/src/widgets/variations_bar.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

import '../../model/engine/fake_engine.dart';
import '../../network/fake_websocket_channel.dart';
import '../../test_helpers.dart';
import '../../test_provider_scope.dart';
import '../engine/test_engine_app.dart';

void main() {
  // ignore: avoid_dynamic_calls
  final sanMoves = jsonDecode(gameResponse)['moves'] as String;

  tearDown(() {
    clearSavedStandaloneAnalysis();
  });

  group('Analysis Screen', () {
    testWidgets('displays correct move and position', (tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: AnalysisScreen(
          options: AnalysisOptions.pgn(
            id: const StringId('standalone'),
            orientation: Side.white,
            pgn: sanMoves,
            isComputerAnalysisAllowed: false,
            variant: Variant.standard,
          ),
        ),
      );

      await tester.pumpWidget(app);
      expect(find.byType(Chessboard), findsOneWidget);
      expect(getBoardPieces(tester).length, 25);
      final currentMove = find.textContaining('Qe1#');
      expect(currentMove, findsOneWidget);
      expect(
        tester
            .widget<InlineMove>(find.ancestor(of: currentMove, matching: find.byType(InlineMove)))
            .isCurrentMove,
        isTrue,
      );
    });

    testWidgets('move backwards and forward', (tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: AnalysisScreen(
          options: AnalysisOptions.pgn(
            id: const StringId('standalone'),
            orientation: Side.white,
            pgn: sanMoves,
            isComputerAnalysisAllowed: false,
            variant: Variant.standard,
          ),
        ),
      );

      await tester.pumpWidget(app);

      // cannot go forward
      expect(tester.widget<SrsTextButton>(find.byKey(const Key('goto-next'))).onPressed, isNull);

      // can go back
      expect(
        tester.widget<SrsTextButton>(find.byKey(const Key('goto-previous'))).onPressed,
        isNotNull,
      );

      // goto previous move
      await tester.tap(find.byKey(const Key('goto-previous')));
      await tester.pumpAndSettle();
      // The tree view debounces path changes (kFastReplayDebounceDelay);
      // pump it explicitly: the old bar's long splash animation used to
      // advance fake time past the delay by accident.
      await tester.pump(kFastReplayDebounceDelay);

      final currentMove = find.textContaining('Kc1');
      expect(currentMove, findsOneWidget);
      expect(
        tester
            .widget<InlineMove>(find.ancestor(of: currentMove, matching: find.byType(InlineMove)))
            .isCurrentMove,
        isTrue,
      );
    });
    testWidgets('displays the clocks of a game played with a time control', (tester) async {
      const pgn =
          '[White "white"]\n'
          '[Black "black"]\n'
          '[TimeControl "300+3"]\n\n'
          '1. e4 { [%clk 0:05:01] } e5 { [%clk 0:05:02] } '
          '2. Nf3 { [%clk 0:04:55] } Nc6 { [%clk 0:04:50] } *';

      final app = await makeTestProviderScopeApp(
        tester,
        home: const AnalysisScreen(
          options: AnalysisOptions.pgn(
            id: StringId('otb_test'),
            orientation: Side.white,
            pgn: pgn,
            isComputerAnalysisAllowed: false,
            variant: Variant.standard,
          ),
        ),
      );

      await tester.pumpWidget(app);

      // The last move is black's, so black shows the clock of that move and white the one it
      // still had after its own last move.
      expect(find.text('04:50'), findsOneWidget);
      expect(find.text('04:55'), findsOneWidget);

      // Stepping back a move moves both clocks back with it.
      await tester.tap(find.byKey(const Key('goto-previous')));
      await tester.pumpAndSettle();
      expect(find.text('04:55'), findsOneWidget);
      expect(find.text('05:02'), findsOneWidget);

      // At the root neither side has played, so there is nothing to show.
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const Key('goto-previous')));
        await tester.pumpAndSettle();
      }
      expect(find.text('05:01'), findsNothing);
      expect(find.text('05:02'), findsNothing);
    });

    testWidgets('offers a move times chart for a game played with a time control', (tester) async {
      const pgn =
          '[White "white"]\n'
          '[Black "black"]\n'
          '[TimeControl "300+3"]\n\n'
          '1. e4 { [%clk 0:05:01] } e5 { [%clk 0:05:02] } '
          '2. Nf3 { [%clk 0:04:55] } Nc6 { [%clk 0:04:50] } *';

      final app = await makeTestProviderScopeApp(
        tester,
        home: const AnalysisScreen(
          options: AnalysisOptions.pgn(
            id: StringId('otb_test'),
            orientation: Side.white,
            pgn: pgn,
            isComputerAnalysisAllowed: false,
            variant: Variant.standard,
          ),
        ),
      );

      await tester.pumpWidget(app);

      expect(find.byIcon(AnalysisTab.moveTimes.icon), findsOneWidget);
      await tester.tap(find.byIcon(AnalysisTab.moveTimes.icon));
      await tester.pumpAndSettle();

      final chart = tester.widget<MoveTimesChart>(find.byType(MoveTimesChart));
      expect(chart.params.clocks, const [
        Duration(minutes: 5, seconds: 1),
        Duration(minutes: 5, seconds: 2),
        Duration(minutes: 4, seconds: 55),
        Duration(minutes: 4, seconds: 50),
      ]);
      // Each side's first move is free; after that the increment is part of what was spent.
      expect(chart.params.moveTimes, const [
        Duration.zero,
        Duration.zero,
        Duration(seconds: 9),
        Duration(seconds: 15),
      ]);
    });

    testWidgets('offers no move times chart for a game played without a clock', (tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: AnalysisScreen(
          options: AnalysisOptions.pgn(
            id: const StringId('standalone'),
            orientation: Side.white,
            pgn: sanMoves,
            isComputerAnalysisAllowed: false,
            variant: Variant.standard,
          ),
        ),
      );

      await tester.pumpWidget(app);

      expect(find.byIcon(AnalysisTab.moveTimes.icon), findsNothing);
    });

    testWidgets('Variations bar displays variations and can be tapped', (tester) async {
      // A PGN where black has two responses to 1. e4 : e5 and c5
      const pgn = '1. e4 e5 (1... c5)';

      final app = await makeTestProviderScopeApp(
        tester,
        home: const AnalysisScreen(
          options: AnalysisOptions.pgn(
            id: StringId('test-id'),
            pgn: pgn,
            orientation: Side.white,
            variant: Variant.standard,
            isComputerAnalysisAllowed: false,
            initialMoveCursor: 0,
          ),
        ),
      );

      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      // The bar should not be visible when at the root (the root only has 1 child: 1. e4)
      // So e5 should only be visible in the notation but not in the variations bar
      expect(find.text('e5'), findsOneWidget);
      expect(
        find.descendant(of: find.byType(VariationsBar), matching: find.text('e4')),
        findsNothing,
      );

      // go next to play 1. e4
      await tester.tap(find.byKey(const Key('goto-next')));
      await tester.pump();

      // The variations bar should now display both e5 and c5
      expect(find.byType(VariationsBar), findsOneWidget);
      expect(
        find.descendant(of: find.byType(VariationsBar), matching: find.text('e5')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byType(VariationsBar), matching: find.text('c5')),
        findsOneWidget,
      );

      // Tap the 'c5' variation in the VariationsBar
      await tester.tap(find.descendant(of: find.byType(VariationsBar), matching: find.text('c5')));
      await tester.pump();

      // Verify that the tree successfully jumped to c5
      expect(boardHasPiece(tester, Square.c5, Piece.blackPawn), isTrue);
      await tester.tap(find.byKey(const Key('goto-previous')));
      await tester.pump();
      // The variations bar should now display both e5 and c5 again
      expect(find.byType(VariationsBar), findsOneWidget);
      expect(
        find.descendant(of: find.byType(VariationsBar), matching: find.text('e5')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byType(VariationsBar), matching: find.text('c5')),
        findsOneWidget,
      );
      //pressing next should play the mainline move e5, not c5
      await tester.tap(find.byKey(const Key('goto-next')));
      await tester.pump();
      expect(boardHasPiece(tester, Square.e5, Piece.blackPawn), isTrue);
    });

    testWidgets('change variant in standalone analysis', (tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: const AnalysisScreen(options: AnalysisOptions.standalone(variant: Variant.standard)),
      );

      await tester.pumpWidget(app);

      expect(find.byType(PocketsMenu), findsNothing);

      await tester.tap(find.bySemanticsLabel('Menu'));
      await tester.pumpAndSettle(); // wait for menu to open

      expect(find.text('Variant'), findsOneWidget);

      await tester.tap(find.text('Variant'));
      await tester.pumpAndSettle(); // wait for dialog to open

      expect(find.textContaining('Standard'), findsNWidgets(2)); // title and description
      expect(find.textContaining('Chess960'), findsNothing);
      expect(find.textContaining('From Position'), findsNothing);
      expect(find.textContaining('Antichess'), findsOneWidget);
      expect(find.textContaining('King of the Hill'), findsOneWidget);
      expect(find.textContaining('Three-Check'), findsOneWidget);
      expect(find.textContaining('Atomic'), findsOneWidget);
      expect(find.textContaining('Horde'), findsOneWidget);
      expect(find.textContaining('Racing Kings'), findsOneWidget);
      expect(find.textContaining('Crazyhouse'), findsOneWidget);

      await tester.ensureVisible(find.textContaining('Horde')); // scroll if needed
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Horde'));
      await tester.pumpAndSettle(); // wait for dialog to close and new variant to be loaded

      expect(find.byType(PocketsMenu), findsNothing);

      // Horde starting position should be loaded:
      expect(boardHasPiece(tester, Square.b5, Piece.whitePawn), isTrue);

      // Change to crazhouse, pockets should be displayed:
      await tester.tap(find.bySemanticsLabel('Menu'));
      await tester.pumpAndSettle(); // wait for menu to open
      await tester.tap(find.text('Variant'));
      await tester.pumpAndSettle(); // wait for dialog to open
      await tester.ensureVisible(find.textContaining('Crazyhouse')); // scroll if needed
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Crazyhouse'));
      await tester.pumpAndSettle(); // wait for dialog to close and new variant to be loaded

      // One for white, one for black
      expect(find.byType(PocketsMenu), findsNWidgets(2));
    });

    testWidgets('Cannot change variant in PGN analysis', (tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: const AnalysisScreen(
          options: AnalysisOptions.pgn(
            id: StringId('standalone'),
            pgn: '',
            isComputerAnalysisAllowed: false,
            orientation: Side.white,
            variant: Variant.standard,
          ),
        ),
      );

      await tester.pumpWidget(app);

      expect(find.byType(PocketsMenu), findsNothing);

      await tester.tap(find.bySemanticsLabel('Menu'));
      await tester.pumpAndSettle(); // wait for menu to open

      expect(find.text('Variant'), findsNothing);
    });

    testWidgets('Crazyhouse support DropMoves for both sides', (tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: const AnalysisScreen(
          options: AnalysisOptions.pgn(
            id: StringId('standalone'),
            orientation: Side.white,
            pgn: '''
              [Variant "Crazyhouse"]
              [FEN "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR[] w KQkq - 0 1"]
              1. e4 d5 2. exd5 Qxd5
            ''',
            isComputerAnalysisAllowed: false,
            variant: Variant.crazyhouse,
          ),
        ),
      );

      await tester.pumpWidget(app);

      expect(find.byType(PocketsMenu), findsNWidgets(2));

      await playDropMove(tester, Side.white, Role.pawn, 'a4');
      expect(boardHasPiece(tester, Square.a4, Piece.whitePawn), isTrue);

      // Illegal drop move for black, should not be played
      await playDropMove(tester, Side.black, Role.queen, 'h5');
      expect(boardHasPiece(tester, Square.h5, Piece.blackQueen), isFalse);

      await playDropMove(tester, Side.black, Role.pawn, 'h5');
      expect(boardHasPiece(tester, Square.h5, Piece.blackPawn), isTrue);
    });

    testWidgets('Continue against computer', (tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: const AnalysisScreen(
          options: AnalysisOptions.pgn(
            id: StringId('standalone'),
            orientation: Side.white,
            pgn: '',
            isComputerAnalysisAllowed: true,
            variant: Variant.atomic,
          ),
        ),
      );

      await tester.pumpWidget(app);

      await tester.tap(find.bySemanticsLabel('Menu'));
      await tester.pumpAndSettle(); // wait for menu to open
      await tester.tap(find.text('Continue from here'));
      await tester.pumpAndSettle(); // wait for dialog to open

      await tester.tap(find.text('Play against computer'));
      await tester.pumpAndSettle(); // wait for play menu to open
      // Variant we set previously should be preselected
      expect(find.textContaining('Atomic'), findsOneWidget);
    });
  });

  group('Analysis Tree View', () {
    Future<void> buildTree(
      WidgetTester tester,
      String pgn,
      PgnTreeDisplayMode displayMode, {
      AnalysisOptions? options,
      MockClient? mockClient,
    }) async {
      final app = await makeTestProviderScopeApp(
        tester,
        defaultPreferences: {
          PrefCategory.analysis.storageKey: jsonEncode(
            AnalysisPrefs.defaults
                .copyWith(inlineNotation: displayMode == PgnTreeDisplayMode.inlineNotation)
                .toJson(),
          ),
          PrefCategory.engineEvaluation.storageKey: jsonEncode(
            EngineEvaluationPrefState.defaults.copyWith(isEnabled: false).toJson(),
          ),
        },
        home: AnalysisScreen(
          options:
              options ??
              AnalysisOptions.pgn(
                id: const StringId('standalone'),
                orientation: Side.white,
                pgn: pgn,
                isComputerAnalysisAllowed: false,
                variant: Variant.standard,
              ),
        ),
        overrides: {
          if (mockClient != null)
            lichessClientProvider: lichessClientProvider.overrideWith((ref) {
              return LichessClient(mockClient, ref);
            }),
        },
      );

      await tester.pumpWidget(app);
    }

    Text parentText(WidgetTester tester, String move) {
      return tester.widget<Text>(find.ancestor(of: find.text(move), matching: find.byType(Text)));
    }

    void expectSameLine(WidgetTester tester, Iterable<String> moves) {
      final line = parentText(tester, moves.first);

      for (final move in moves.skip(1)) {
        final moveText = find.text(move);
        expect(moveText, findsOneWidget);
        expect(parentText(tester, move), line);
      }
    }

    void expectDifferentLines(WidgetTester tester, List<String> moves) {
      for (int i = 0; i < moves.length; i++) {
        for (int j = i + 1; j < moves.length; j++) {
          expect(parentText(tester, moves[i]), isNot(parentText(tester, moves[j])));
        }
      }
    }

    group('PgnTreeDisplayMode.inlineNotation', () {
      testWidgets('inline notation displays short sideline as inline', (tester) async {
        await buildTree(
          tester,
          '1. e4 e5 (1... d5 2. exd5) 2. Nf3 *',
          PgnTreeDisplayMode.inlineNotation,
        );

        final mainline = find.ancestor(of: find.text('1. e4'), matching: find.byType(Text));
        expect(mainline, findsOneWidget);

        expectSameLine(tester, ['1. e4', 'e5', '1… d5', '2. exd5', '2. Nf3']);
      });

      testWidgets('inline notation displays long sideline on its own line', (tester) async {
        await buildTree(
          tester,
          '1. e4 e5 (1... d5 2. exd5 Qxd5 3. Nc3 Qd8 4. d4 Nf6) 2. Nc3 *',
          PgnTreeDisplayMode.inlineNotation,
        );

        expectSameLine(tester, ['1. e4', 'e5']);
        expectSameLine(tester, ['1… d5', '2. exd5', 'Qxd5', '3. Nc3', 'Qd8', '4. d4', 'Nf6']);
        expectSameLine(tester, ['2. Nc3']);

        expectDifferentLines(tester, ['1. e4', '1… d5', '2. Nc3']);
      });

      testWidgets('inline notation displays sideline with branching on its own line', (
        tester,
      ) async {
        await buildTree(
          tester,
          '1. e4 e5 (1... d5 2. exd5 (2. Nc3)) *',
          PgnTreeDisplayMode.inlineNotation,
        );

        expectSameLine(tester, ['1. e4', 'e5']);

        // 2nd branch is rendered inline again
        expectSameLine(tester, ['1… d5', '2. exd5', '2. Nc3']);

        expectDifferentLines(tester, ['1. e4', '1… d5']);
      });

      testWidgets('multiple sidelines', (tester) async {
        await buildTree(
          tester,
          '1. e4 e5 (1... d5 2. exd5) (1... Nf6 2. e5) 2. Nf3 Nc6 (2... a5) *',
          PgnTreeDisplayMode.inlineNotation,
        );

        expectSameLine(tester, ['1. e4', 'e5']);
        expectSameLine(tester, ['1… d5', '2. exd5']);
        expectSameLine(tester, ['1… Nf6', '2. e5']);
        expectSameLine(tester, ['2. Nf3', 'Nc6', '2… a5']);

        expectDifferentLines(tester, ['1. e4', '1… d5', '1… Nf6', '2. Nf3']);
      });

      testWidgets('collapses lines with nesting > 2', (tester) async {
        await buildTree(
          tester,
          '1. e4 e5 (1... d5 2. Nc3 (2. h4 h5 (2... Nc6 3. d3) (2... Qd7))) *',
          PgnTreeDisplayMode.inlineNotation,
        );

        expectSameLine(tester, ['1. e4', 'e5']);
        expectSameLine(tester, ['1… d5']);
        expectSameLine(tester, ['2. Nc3']);
        expectSameLine(tester, ['2. h4']);

        expect(find.text('2… h5'), findsNothing);
        expect(find.text('2… Nc6'), findsNothing);
        expect(find.text('3. d3'), findsNothing);
        expect(find.text('2… Qd7'), findsNothing);

        // sidelines with nesting > 2 are collapsed -> expand them
        expect(find.byIcon(Icons.add_box), findsOneWidget);

        await tester.tap(find.byIcon(Icons.add_box));
        await tester.pumpAndSettle();

        expectSameLine(tester, ['2… h5']);
        expectSameLine(tester, ['2… Nc6', '3. d3']);
        expectSameLine(tester, ['2… Qd7']);

        final d3 = find.text('3. d3');
        await tester.longPress(d3);
        await tester.pumpAndSettle();

        await tester.tap(find.text('Collapse variations'));

        // need to wait for current move change debounce delay
        await tester.pumpAndSettle(const Duration(milliseconds: 200));

        // Sidelines should be collapsed again
        expect(find.byIcon(Icons.add_box), findsOneWidget);

        expect(find.text('2… h5'), findsNothing);
        expect(find.text('2… Nc6'), findsNothing);
        expect(find.text('3. d3'), findsNothing);
        expect(find.text('2… Qd7'), findsNothing);
      });

      testWidgets('Expanding one line does not expand the following one (regression test)', (
        tester,
      ) async {
        /// Will be rendered as:
        /// -------------------
        /// 1. e4 e5
        /// |- 1... d5 2. Nf3 (2.Nc3)
        /// 2. Nf3
        /// |- 2. a4 d5 (2... f5)
        /// -------------------
        await buildTree(
          tester,
          '1. e4 e5 (1... d5 2. Nf3 (2. Nc3)) 2. Nf3 (2. a4 d5 (2... f5))',
          PgnTreeDisplayMode.inlineNotation,
        );

        expect(find.byIcon(Icons.add_box), findsNothing);

        // Collapse both lines
        await tester.longPress(find.text('1… d5'));
        await tester.pumpAndSettle(); // wait for context menu to appear
        await tester.tap(find.text('Collapse variations'));

        // wait for dialog to close and tree to refresh
        await tester.pumpAndSettle(const Duration(milliseconds: 200));

        await tester.longPress(find.text('2. a4'));
        await tester.pumpAndSettle(); // wait for context menu to appear
        await tester.tap(find.text('Collapse variations'));

        // wait for dialog to close and tree to refresh
        await tester.pumpAndSettle(const Duration(milliseconds: 200));

        // In this state, there used to be a bug where expanding the first line would
        // also expand the second line.
        expect(find.byIcon(Icons.add_box), findsNWidgets(2));
        await tester.tap(find.byIcon(Icons.add_box).first);

        // need to wait for current move change debounce delay
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.add_box), findsOneWidget);

        // Second sideline should still be collapsed
        expect(find.text('2. a4'), findsNothing);
      });

      testWidgets('subtrees not part of the current mainline part are cached', (tester) async {
        await buildTree(
          tester,
          '1. e4 e5 (1... d5 2. exd5) (1... Nf6 2. e5) 2. Nf3 Nc6 (2... a5) *',
          PgnTreeDisplayMode.inlineNotation,
        );

        // will be rendered as:
        // -------------------
        // 1. e4 e5              <-- first mainline part
        // |- 1... d5 2. exd5
        // |- 1... Nf6 2. e5
        // 2. Nf3 Nc6 (2... a5)  <-- second mainline part
        //         ^
        //         |
        //         current move

        final firstMainlinePart = parentText(tester, '1. e4');
        final secondMainlinePart = parentText(tester, '2. Nf3');

        expect(
          tester
              .widgetList<InlineMove>(
                find.ancestor(of: find.textContaining('Nc6'), matching: find.byType(InlineMove)),
              )
              .last
              .isCurrentMove,
          isTrue,
        );

        await tester.tap(find.byKey(const Key('goto-previous')));
        // need to wait for current move change debounce delay
        await tester.pumpAndSettle(const Duration(milliseconds: 200));

        expect(
          tester
              .widgetList<InlineMove>(
                find.ancestor(of: find.textContaining('Nf3'), matching: find.byType(InlineMove)),
              )
              .last
              .isCurrentMove,
          isTrue,
        );

        // first mainline part has not changed since the current move is
        // not part of it
        expect(identical(firstMainlinePart, parentText(tester, '1. e4')), isTrue);

        final secondMainlinePartOnMoveNf3 = parentText(tester, '2. Nf3');

        // second mainline part has changed since the current move is part of it
        expect(secondMainlinePart, isNot(secondMainlinePartOnMoveNf3));

        await tester.tap(find.byKey(const Key('goto-previous')));
        // need to wait for current move change debounce delay
        await tester.pumpAndSettle(const Duration(milliseconds: 200));

        expect(
          tester
              .widgetList<InlineMove>(
                find.ancestor(of: find.textContaining('e5'), matching: find.byType(InlineMove)),
              )
              .first
              .isCurrentMove,
          isTrue,
        );

        final firstMainlinePartOnMoveE5 = parentText(tester, '1. e4');
        final secondMainlinePartOnMoveE5 = parentText(tester, '2. Nf3');

        // first mainline part has changed since the current move is part of it
        expect(firstMainlinePart, isNot(firstMainlinePartOnMoveE5));

        // second mainline part has changed since the current move is not part of it
        // anymore
        expect(secondMainlinePartOnMoveNf3, isNot(secondMainlinePartOnMoveE5));

        await tester.tap(find.byKey(const Key('goto-previous')));
        // need to wait for current move change debounce delay
        await tester.pumpAndSettle(const Duration(milliseconds: 200));

        expect(
          tester
              .firstWidget<InlineMove>(
                find.ancestor(of: find.textContaining('e4'), matching: find.byType(InlineMove)),
              )
              .isCurrentMove,
          isTrue,
        );

        final firstMainlinePartOnMoveE4 = parentText(tester, '1. e4');
        final secondMainlinePartOnMoveE4 = parentText(tester, '2. Nf3');

        // first mainline part has changed since the current move is part of it
        expect(firstMainlinePartOnMoveE4, isNot(firstMainlinePartOnMoveE5));

        // second mainline part has not changed since the current move is not part of it
        expect(identical(secondMainlinePartOnMoveE5, secondMainlinePartOnMoveE4), isTrue);
      });

      testWidgets(
        'Select first move of sideline if mainline part has only one move (regression test)',
        (tester) async {
          /// Will be rendered as:
          /// -------------------
          /// 1. e4
          /// |- 1. d4
          /// |- 1. c4
          /// -------------------
          await buildTree(tester, '1. e4 (1. d4) (1. c4)', PgnTreeDisplayMode.inlineNotation);

          await tester.tap(find.text('1. d4'));
          // need to wait for current move change debounce delay
          await tester.pumpAndSettle(const Duration(milliseconds: 200));

          final e4NodeBeforeTap = parentText(tester, '1. e4');

          await tester.tap(find.text('1. c4'));
          // need to wait for current move change debounce delay
          await tester.pumpAndSettle(const Duration(milliseconds: 200));

          final e4NodeAfterTap = parentText(tester, '1. e4');

          // There was a bug where the subtree would not be rebuilt here
          expect(e4NodeBeforeTap, isNot(e4NodeAfterTap));
        },
      );
    });

    group('Copy line PGN', () {
      /// Records every text the app writes to the clipboard.
      List<String> captureClipboard({Future<void>? response}) {
        final copied = <String>[];
        final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(SystemChannels.platform, (methodCall) async {
          if (methodCall.method == 'Clipboard.setData') {
            final arguments = methodCall.arguments as Map<Object?, Object?>;
            copied.add(arguments['text']! as String);
            if (response != null) await response;
          }
          return null;
        });
        addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));
        return copied;
      }

      const pgn = '1. e4 e5 (1... c5 2. Nf3 (2. c3)) 2. Nf3 Nc6 (2... d6) 3. Bb5';

      for (final displayMode in PgnTreeDisplayMode.values) {
        group(displayMode.name, () {
          testWidgets('copies the main line without the sidelines branching off it', (
            tester,
          ) async {
            final copied = captureClipboard();
            await buildTree(tester, pgn, displayMode);

            await tester.longPress(find.text('e5'));
            await tester.pumpAndSettle();

            expect(find.text('Copy variation PGN'), findsNothing);
            await tester.tap(find.text('Copy main line PGN'));
            await tester.pumpAndSettle();

            expect(copied, ['1. e4 e5 2. Nf3 Nc6 3. Bb5']);
            expect(
              find.descendant(of: find.byType(SnackBar), matching: find.text('PGN copied.')),
              findsOneWidget,
            );
          });

          testWidgets('copies a variation with the sidelines after the pressed move', (
            tester,
          ) async {
            final copied = captureClipboard();
            await buildTree(tester, pgn, displayMode);

            await tester.longPress(find.text('1… c5'));
            await tester.pumpAndSettle();

            expect(find.text('Copy main line PGN'), findsNothing);
            await tester.tap(find.text('Copy variation PGN'));
            await tester.pumpAndSettle();

            expect(copied, ['1. e4 c5 2. Nf3 ( 2. c3 )']);
          });

          testWidgets('confirms copying after the move menu has closed', (tester) async {
            final response = Completer<void>();
            final copied = captureClipboard(response: response.future);
            await buildTree(tester, pgn, displayMode);

            await tester.longPress(find.text('e5'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Copy main line PGN'));
            await tester.pumpAndSettle();

            expect(find.byType(BottomSheet), findsNothing);
            expect(copied, ['1. e4 e5 2. Nf3 Nc6 3. Bb5']);
            expect(find.text('PGN copied.'), findsNothing);

            response.complete();
            await tester.pumpAndSettle();

            expect(
              find.descendant(of: find.byType(SnackBar), matching: find.text('PGN copied.')),
              findsOneWidget,
            );
          });
        });
      }
    });

    group('PgnTreeDisplayMode.twoColumn', () {
      Row parentRow(WidgetTester tester, String move) {
        return tester.firstWidget<Row>(
          find.ancestor(of: find.text(move), matching: find.byType(Row)),
        );
      }

      testWidgets('two column view does NOT display short sideline on its own line', (
        tester,
      ) async {
        await buildTree(tester, '1. e4 (1. d4 2. d5) 1... e5 *', PgnTreeDisplayMode.twoColumn);

        expect(parentRow(tester, 'e4'), isNot(parentRow(tester, 'e5')));
      });

      testWidgets('two column view adds "..." if mainline part starts with black move', (
        tester,
      ) async {
        await buildTree(
          tester,
          '1. e4 (1. d4 2. d5) 1... e5 2. Nf3 Nc6 *',
          PgnTreeDisplayMode.twoColumn,
        );

        // Test that it's rendered like this:
        /// 1  e4 ...
        /// |- 1. d4 2. d5
        /// 1 ... e5
        /// 2 Nf3 Nc6
        ///
        /// ... and not like this:
        /// 1  e4 ...
        /// |- 1. d4 2. d5
        /// 1 e5
        /// 2 Nf3 Nc6

        expect(find.text('...'), findsNWidgets(2));
      });
    });

    // more engine evaluation test files are to be found in /test/view/engine/
    group('Engine evaluation:', () {
      group('in move tree', () {
        testWidgets('evals are displayed', (tester) async {
          await makeEngineTestApp(tester, isCloudEvalEnabled: false);
          await playMove(tester, 'e2', 'e4');
          expect(find.byType(InlineMove), findsOne);
          // ensure that the eval is displayed and pending eval throttle time is over
          await tester.pump(kRequestEvalDebounceDelay + kEngineEvalEmissionThrottleDelay);
          expect(find.widgetWithText(InlineMove, '+0.2'), findsOne);
          await playMove(tester, 'e7', 'e5');
          await tester.pump(kLocalEngineAfterCloudEvalDelay + kEngineEvalEmissionThrottleDelay);
          expect(find.widgetWithText(InlineMove, '+0.2'), findsNWidgets(2));
        });

        testWidgets(
          'computer variations are displayed in the move tree when server analysis is enabled',
          (tester) async {
            await makeEngineTestApp(tester, gameId: const GameId('xze7RH66'));

            expect(find.text('Loading…'), findsOne);
            // wait for the game to be loaded
            await tester.pump(const Duration(milliseconds: 50));

            expect(find.text('Mistake. dxe6 was best.'), findsOne);
            expect(find.text('13. dxe6'), findsOne);
          },
        );

        testWidgets(
          'computer variations are not displayed in the move tree when server analysis is disabled',
          (tester) async {
            await makeEngineTestApp(
              tester,
              isServerAnalysisEnabled: false,
              gameId: const GameId('xze7RH66'),
            );

            expect(find.text('Loading…'), findsOne);
            // wait for the game to be loaded
            await tester.pump(const Duration(milliseconds: 50));

            expect(find.text('Mistake. dxe6 was best.'), findsNothing);
            expect(find.text('13. dxe6'), findsNothing);
          },
        );

        testWidgets('eval is updated in move tree when it corresponds to current path', (
          tester,
        ) async {
          await makeEngineTestApp(tester, isCloudEvalEnabled: false);

          // Make a move (1. e4)
          await playMove(tester, 'e2', 'e4');
          expect(find.byType(InlineMove), findsOne);

          // Before any eval is emitted, no eval should be displayed
          expect(find.widgetWithText(InlineMove, '+0.2'), findsNothing);

          await tester.pump(kRequestEvalDebounceDelay + kEngineEvalEmissionThrottleDelay);

          expect(find.widgetWithText(InlineMove, '+0.2'), findsOne);
        });

        testWidgets('different positions show different evals in move tree', (tester) async {
          final stockfish = AnalysisTestEngine();
          await makeEngineTestApp(tester, isCloudEvalEnabled: false, stockfish: stockfish);

          await playMove(tester, 'e2', 'e4');
          await tester.pump(kRequestEvalDebounceDelay);

          // check engine is started
          expect(stockfish.isRunning, isTrue);

          stockfish.emitNextDepth();
          await tester.pump(kEngineEvalEmissionThrottleDelay);

          expect(stockfish.requestedPositions.length, 1);

          // should see depth 6
          expect(find.widgetWithText(EngineButton, '6'), findsOne);

          // e4 should show +0.2 (ply 1 -> cp 20)
          expect(find.widgetWithText(InlineMove, '+0.2'), findsOne);

          await playMove(tester, 'e7', 'e5');
          expect(find.byType(InlineMove), findsNWidgets(2));

          await tester.pump(kRequestEvalDebounceDelay + kEngineEvalEmissionThrottleDelay);

          expect(stockfish.requestedPositions.length, 2);

          stockfish.emitDepthRange(toDepth: 10);
          await tester.pump(kEngineEvalEmissionThrottleDelay);

          expect(find.widgetWithText(EngineButton, '10'), findsOne);

          // After e5, position has ply=2, so cp=30 which displays as +0.3
          expect(find.widgetWithText(InlineMove, '+0.2'), findsOne);
          expect(find.widgetWithText(InlineMove, '+0.3'), findsOne);
        });
      });

      group('Engine analysis on move navigation', () {
        testWidgets('evaluation is debounced when jumping quickly between moves', (tester) async {
          final stockfish = AnalysisTestEngine();
          await makeEngineTestApp(tester, isCloudEvalEnabled: false, stockfish: stockfish);

          // Make several moves
          await playMove(tester, 'e2', 'e4');
          await playMove(tester, 'e7', 'e5');
          await playMove(tester, 'g1', 'f3');
          await playMove(tester, 'b8', 'c6');

          // Wait for initial eval request
          await tester.pump(kRequestEvalDebounceDelay);

          // Clear the tracking to start fresh for navigation test
          stockfish.resetTracking();

          // Rapidly navigate through moves (faster than debounce delay of 250ms)
          await tester.tap(find.byKey(const Key('goto-previous')));
          await tester.pump(const Duration(milliseconds: 50));

          await tester.tap(find.byKey(const Key('goto-previous')));
          await tester.pump(const Duration(milliseconds: 50));

          await tester.tap(find.byKey(const Key('goto-previous')));
          await tester.pump(const Duration(milliseconds: 50));

          // Due to debouncing, no eval requests should have been sent yet
          expect(stockfish.requestedPositions, isEmpty);

          // Wait for the debounce delay to elapse
          await tester.pump(kRequestEvalDebounceDelay);

          // Only ONE eval request should have been sent (for the final position)
          expect(stockfish.requestedPositions.length, 1);

          // Verify it's for the correct position (after 1. e4)
          expect(stockfish.requestedPositions.first, contains('4P3'));

          // Emit eval for this position
          stockfish.emitNextDepth();
          await tester.pump();

          // Eval should be displayed (depth 6) with arrow
          expect(find.widgetWithText(EngineButton, '$kMinEngineDepth'), findsOne);
          expect(find.widgetWithText(InlineMove, '+0.2'), findsOne);
          expect(find.byType(BoardShapeWidget), findsOne);
        });
      });

      group('Engine lines', () {
        testWidgets('are displayed', (tester) async {
          await makeEngineTestApp(tester);
          // ensure that the eval is displayed and pending eval throttle time is over
          await tester.pump(kRequestEvalDebounceDelay + kEngineEvalEmissionThrottleDelay);
          expect(find.byType(Engineline), findsOne);
          expect(find.widgetWithText(Engineline, '1. e4 e5 2. Nf3 Nc6 3. Bb5 Nf6 '), findsOne);
        });

        testWidgets('are not displayed if computer analysis is not allowed', (tester) async {
          await makeEngineTestApp(tester, isComputerAnalysisAllowed: false);
          // ensure that the eval is displayed and pending eval throttle time is over
          await tester.pump(kRequestEvalDebounceDelay + kEngineEvalEmissionThrottleDelay);
          expect(find.byType(Engineline), findsNothing);
        });

        testWidgets('are not displayed if computer analysis is not enabled (on an analysed game)', (
          tester,
        ) async {
          await makeEngineTestApp(
            tester,
            gameId: const GameId('xze7RH66'),
            isServerAnalysisEnabled: false,
            isEngineEnabled: false,
          );
          // ensure that the eval is displayed and pending eval throttle time is over
          await tester.pump(kRequestEvalDebounceDelay + kEngineEvalEmissionThrottleDelay);
          expect(find.byType(Engineline), findsNothing);
        });

        testWidgets('are not displayed if engine is disabled by user preferences', (tester) async {
          await makeEngineTestApp(tester, isEngineEnabled: false);
          // ensure that the eval is displayed and pending eval throttle time is over
          await tester.pump(kRequestEvalDebounceDelay + kEngineEvalEmissionThrottleDelay);
          expect(find.byType(Engineline), findsNothing);
        });

        testWidgets('are not displayed if they are disabled by user preferences', (tester) async {
          await makeEngineTestApp(tester, numEvalLines: 0);
          // ensure that the eval is displayed and pending eval throttle time is over
          await tester.pump(kRequestEvalDebounceDelay + kEngineEvalEmissionThrottleDelay);
          expect(find.byType(Engineline), findsNothing);
        });

        testWidgets('can be tapped to play a drop move in crazyhouse', (tester) async {
          final stockfish = CrazyhouseDropMoveEngine();
          fakeEngine = stockfish;
          addTearDown(() => fakeEngine = FakeEngine());

          final app = await makeTestProviderScopeApp(
            tester,
            defaultPreferences: {
              PrefCategory.engineEvaluation.storageKey: jsonEncode(
                EngineEvaluationPrefState.defaults
                    .copyWith(numEvalLines: 1, isEnabled: true)
                    .toJson(),
              ),
            },
            home: const AnalysisScreen(
              options: AnalysisOptions.pgn(
                id: StringId('standalone'),
                orientation: Side.white,
                // Position after 1.e4 d5 2.exd5 Qxd5: white has a pawn in pocket
                pgn: '''
                [Variant "Crazyhouse"]
                [FEN "rnb1kbnr/ppp1pppp/8/3q4/8/8/PPPP1PPP/RNBQKBNR[Pp] w KQkq - 0 3"]
              ''',
                isComputerAnalysisAllowed: true,
                variant: Variant.crazyhouse,
              ),
            ),
            overrides: {
              webSocketChannelFactoryProvider: webSocketChannelFactoryProvider.overrideWith(
                (_) => FakeWebSocketChannelFactory(
                  (uri) => FakeWebSocketChannel(uri, serverHandlers: {}),
                ),
              ),
            },
          );
          await tester.pumpWidget(app);

          // Wait for engine to start and emit eval
          await tester.pump(kRequestEvalDebounceDelay + kEngineEvalEmissionThrottleDelay);

          // Engine line starting with a drop move should be displayed
          expect(find.byType(Engineline), findsOneWidget);

          // Tapping the engine line plays P@c4 (drop move)
          await tester.tap(find.byType(Engineline));
          await tester.pumpAndSettle();

          // White pawn should appear on c4 after the drop move
          expect(boardHasPiece(tester, Square.c4, Piece.whitePawn), isTrue);
        });
      });

      group('Engine gauge', () {
        testWidgets('is not displayed if computer analysis is not allowed', (tester) async {
          await makeEngineTestApp(tester, isComputerAnalysisAllowed: false);
          // ensure that the eval is displayed and pending eval throttle time is over
          await tester.pump(kRequestEvalDebounceDelay + kEngineEvalEmissionThrottleDelay);
          expect(find.byType(EngineGauge), findsNothing);
        });

        testWidgets('is not displayed if computer analysis is not enabled (on an analysed game)', (
          tester,
        ) async {
          await makeEngineTestApp(
            tester,
            isServerAnalysisEnabled: false,
            isEngineEnabled: false,
            gameId: const GameId('xze7RH66'),
          );
          // ensure that the eval is displayed and pending eval throttle time is over
          await tester.pump(kRequestEvalDebounceDelay + kEngineEvalEmissionThrottleDelay);
          expect(find.byType(EngineGauge), findsNothing);
        });

        testWidgets('is not displayed if engine is disabled by user preferences', (tester) async {
          await makeEngineTestApp(tester, isEngineEnabled: false);
          // ensure that the eval is displayed and pending eval throttle time is over
          await tester.pump(kRequestEvalDebounceDelay + kEngineEvalEmissionThrottleDelay);
          expect(find.byType(EngineGauge), findsNothing);
        });

        testWidgets('is displayed if engine is available', (tester) async {
          await makeEngineTestApp(tester);
          // ensure that the eval is displayed and pending eval throttle time is over
          await tester.pump(kRequestEvalDebounceDelay + kEngineEvalEmissionThrottleDelay);
          expect(find.byType(EngineGauge), findsOne);
          expect(find.widgetWithText(EngineGauge, '+0.2'), findsOne);
        });

        testWidgets('is displayed on an analysed game, even if engine eval is disabled', (
          tester,
        ) async {
          await makeEngineTestApp(tester, isEngineEnabled: false, gameId: const GameId('xze7RH66'));

          expect(find.text('Loading…'), findsOne);
          // wait for the game to be loaded
          await tester.pump(const Duration(milliseconds: 50));

          expect(find.byType(EngineGauge), findsOne);
          expect(find.widgetWithText(EngineGauge, '#'), findsOne);
        });
      });

      group('Engine best move arrow', () {
        testWidgets('is not displayed if best move arrow is disabled', (tester) async {
          await makeEngineTestApp(tester, showBestMoveArrow: false);
          // ensure that the eval is displayed and pending eval throttle time is over
          await tester.pump(kRequestEvalDebounceDelay + kEngineEvalEmissionThrottleDelay);
          expect(find.byType(BoardShapeWidget), findsNothing);
        });

        testWidgets('is not displayed if computer analysis is not allowed', (tester) async {
          await makeEngineTestApp(tester, isComputerAnalysisAllowed: false);
          // ensure that the eval is displayed and pending eval throttle time is over
          await tester.pump(kRequestEvalDebounceDelay + kEngineEvalEmissionThrottleDelay);
          expect(find.byType(BoardShapeWidget), findsNothing);
        });

        testWidgets('is not displayed if engine is disabled by user preferences', (tester) async {
          await makeEngineTestApp(tester, isEngineEnabled: false);
          // ensure that the eval is displayed and pending eval throttle time is over
          await tester.pump(kRequestEvalDebounceDelay + kEngineEvalEmissionThrottleDelay);
          expect(find.byType(BoardShapeWidget), findsNothing);
        });

        testWidgets('is displayed if engine is available', (tester) async {
          await makeEngineTestApp(tester);
          // ensure that the eval is displayed and pending eval throttle time is over
          await tester.pump(kRequestEvalDebounceDelay + kEngineEvalEmissionThrottleDelay);
          expect(find.byType(BoardShapeWidget), findsOne);
        });

        testWidgets('is displayed even when number of engine lines is set to 0', (tester) async {
          await makeEngineTestApp(tester, numEvalLines: 0);
          // ensure that the eval is displayed and pending eval throttle time is over
          await tester.pump(kRequestEvalDebounceDelay + kEngineEvalEmissionThrottleDelay);
          expect(find.byType(BoardShapeWidget), findsOne);
        });
      });

      group('show threat button', () {
        testWidgets('is visible when engine is available and position is normal', (tester) async {
          await makeEngineTestApp(tester, pgn: 'e4 e5');

          await tester.tap(find.bySemanticsLabel('Menu'));
          await tester.pumpAndSettle();

          expect(find.text('Show threat'), findsOneWidget);
        });

        testWidgets('is hidden when king is in check', (tester) async {
          await makeEngineTestApp(
            tester,
            // Ends with Qxe5+: black king is in check
            pgn: 'e4 e5 Qh5 Nf6 Qxe5+',
          );

          await tester.tap(find.bySemanticsLabel('Menu'));
          await tester.pumpAndSettle();

          expect(find.text('Show threat'), findsNothing);
        });

        testWidgets('is hidden when position is checkmate', (tester) async {
          await makeEngineTestApp(
            tester,
            pgn: sanMoves, // ends with checkmate
          );

          await tester.tap(find.bySemanticsLabel('Menu'));
          await tester.pumpAndSettle();

          expect(find.text('Show threat'), findsNothing);
        });

        testWidgets('is hidden when opponent would be in stalemate', (tester) async {
          await makeEngineTestApp(
            tester,
            pgn: '''
[Variant "From Position"]
[FEN "5bnr/4p1pq/4Qpkr/7p/7P/4P3/PPPP1PP1/RNB1KBNR w KQ - 2 10"]
''',
          );

          await tester.tap(find.bySemanticsLabel('Menu'));
          await tester.pumpAndSettle();

          expect(find.text('Show threat'), findsNothing);
        });

        testWidgets('is hidden when position is stalemate for both sides', (tester) async {
          await makeEngineTestApp(
            tester,
            pgn: '''
[Variant "From Position"]
[FEN "8/8/8/pp6/qp6/kp6/1p6/1K6 b - - 0 1"]
''',
          );

          await tester.tap(find.bySemanticsLabel('Menu'));
          await tester.pumpAndSettle();

          expect(find.text('Show threat'), findsNothing);
        });

        testWidgets('is visible when position is stalemate but opponent can move', (tester) async {
          await makeEngineTestApp(
            tester,
            pgn: '''
[Variant "From Position"]
[FEN "5bnr/4p1pq/4Qpkr/7p/7P/4P3/PPPP1PP1/RNB1KBNR b KQ - 2 10"]
''',
          );

          await tester.tap(find.bySemanticsLabel('Menu'));
          await tester.pumpAndSettle();

          expect(find.text('Show threat'), findsOneWidget);
        });
      });
    });

    group('Castling', () {
      const String castlingSetupPgn =
          '1. e4 e5 2. Nf3 Nf6 3. Bc4 Bc5 4. d3 d6 5. Bd2 Bd7 6. Nc3 Nc6 7. Qe2 Qe7';

      for (final castlingMethod in CastlingMethod.values) {
        testWidgets('respect castling preference ($castlingMethod)', (tester) async {
          final app = await makeTestProviderScopeApp(
            tester,
            defaultPreferences: {
              PrefCategory.board.storageKey: jsonEncode(
                BoardPrefs.defaults.copyWith(castlingMethod: castlingMethod).toJson(),
              ),
            },
            home: const AnalysisScreen(
              options: AnalysisOptions.pgn(
                id: StringId('standalone'),
                orientation: Side.white,
                pgn: castlingSetupPgn,
                isComputerAnalysisAllowed: false,
                variant: Variant.standard,
                initialMoveCursor: 14,
              ),
            ),
          );

          await tester.pumpWidget(app);

          expect(boardHasPiece(tester, Square.e1, Piece.whiteKing), isTrue);

          final boardRect = tester.getRect(find.byType(Chessboard));
          await tester.tapAt(squareOffset(Square.e1, boardRect));
          await tester.pump();

          final validMoves = getBoardValidMoves(tester);
          switch (castlingMethod) {
            case CastlingMethod.kingOverRook:
              // kingOverRook acts as either kingTwoSquares or kingOverRook
              expect(validMoves.contains(Square.f1), isTrue);
              expect(validMoves.contains(Square.g1), isTrue);
              expect(validMoves.contains(Square.h1), isTrue);
              expect(validMoves.contains(Square.c1), isTrue);
              expect(validMoves.contains(Square.d1), isTrue);
              expect(validMoves.contains(Square.a1), isTrue);
            case CastlingMethod.kingTwoSquares:
              expect(validMoves.contains(Square.f1), isTrue);
              expect(validMoves.contains(Square.g1), isTrue);
              expect(validMoves.contains(Square.h1), isFalse);
              expect(validMoves.contains(Square.c1), isTrue);
              expect(validMoves.contains(Square.d1), isTrue);
              expect(validMoves.contains(Square.a1), isFalse);
          }
        });
      }

      for (final castlingMethod in CastlingMethod.values) {
        testWidgets('Chess960 castling: $castlingMethod', (tester) async {
          final app = await makeTestProviderScopeApp(
            tester,
            defaultPreferences: {
              PrefCategory.board.storageKey: jsonEncode(
                BoardPrefs.defaults.copyWith(castlingMethod: castlingMethod).toJson(),
              ),
            },
            home: AnalysisScreen(
              key: ValueKey(castlingMethod),
              options: const AnalysisOptions.pgn(
                id: StringId('standalone'),
                orientation: Side.white,
                pgn: castlingSetupPgn,
                isComputerAnalysisAllowed: false,
                variant: Variant.chess960,
                initialMoveCursor: 14,
              ),
            ),
          );

          await tester.pumpWidget(app);

          final boardRect = tester.getRect(find.byType(Chessboard));
          await tester.tapAt(squareOffset(Square.e1, boardRect));

          await tester.pump();

          // in chess960, castling is only king over rook, no matter the preference
          final validMoves = getBoardValidMoves(tester);
          expect(validMoves.contains(Square.f1), isTrue);
          expect(validMoves.contains(Square.g1), isFalse);
          expect(validMoves.contains(Square.h1), isTrue);
          expect(validMoves.contains(Square.c1), isFalse);
          expect(validMoves.contains(Square.d1), isTrue);
          expect(validMoves.contains(Square.a1), isTrue);
        });
      }
    });
    testWidgets('saves and restores root and path when navigating away and back', (tester) async {
      // open from More tab and navigate to board analysis
      final app = await makeTestProviderScopeApp(
        tester,
        home: const MoreTabScreen(),
        defaultPreferences: {
          PrefCategory.engineEvaluation.storageKey: jsonEncode(
            EngineEvaluationPrefState.defaults.copyWith(isEnabled: false).toJson(),
          ),
        },
      );

      await tester.pumpWidget(app);

      // Tap on "Analysis" button in More tab
      await tester.tap(find.text('Analysis board'));
      await tester.pumpAndSettle();

      // Change variant to Racing Kings to verify that variant is also saved/restored correctly
      await tester.tap(find.bySemanticsLabel('Menu'));
      await tester.pumpAndSettle(); // wait for menu to open
      await tester.tap(find.text('Variant'));
      await tester.pumpAndSettle(); // wait for variant selection dialog to open
      await tester.ensureVisible(find.textContaining('Racing Kings'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Racing Kings'));
      await tester.pumpAndSettle(); // wait for variant to change

      // Make some moves
      await playMove(tester, 'e2', 'd4');
      await playMove(tester, 'a2', 'a3');
      await playMove(tester, 'h2', 'g3');

      // Verify we made the moves
      expect(find.textContaining('Nd4'), findsOneWidget);
      expect(find.textContaining('Ka3'), findsOneWidget);
      expect(find.textContaining('Kg3'), findsOneWidget);

      // go back a move
      await tester.tap(find.byKey(const Key('goto-previous')));
      await tester.pump();

      expect(boardHasPiece(tester, Square.d4, Piece.whiteKnight), isTrue);
      expect(boardHasPiece(tester, Square.a3, Piece.blackKing), isTrue);
      expect(boardHasPiece(tester, Square.g3, Piece.whiteKing), isFalse);

      // Navigate back to More tab
      await tester.tap(
        find.descendant(of: find.byType(SrsPageHead), matching: find.text('Review')),
      );
      await tester.pumpAndSettle();

      // Verify we're back at More tab
      expect(find.text('Tools'), findsOneWidget);

      // Navigate to board analysis again
      await tester.tap(find.text('Analysis board'));
      await tester.pumpAndSettle();

      // Verify moves are still present and session was restored
      expect(find.textContaining('Nd4'), findsOneWidget);
      expect(find.textContaining('Ka3'), findsOneWidget);
      expect(find.textContaining('Kg3'), findsOneWidget);

      // Verify board state is correct
      expect(boardHasPiece(tester, Square.d4, Piece.whiteKnight), isTrue);
      expect(boardHasPiece(tester, Square.a3, Piece.blackKing), isTrue);
      expect(boardHasPiece(tester, Square.g3, Piece.whiteKing), isFalse);
    });
    testWidgets('Clear moves clears standalone analysis', (tester) async {
      // Open from More tab and navigate to board analysis
      final app = await makeTestProviderScopeApp(
        tester,
        home: const MoreTabScreen(),
        defaultPreferences: {
          PrefCategory.engineEvaluation.storageKey: jsonEncode(
            EngineEvaluationPrefState.defaults.copyWith(isEnabled: false).toJson(),
          ),
        },
      );

      await tester.pumpWidget(app);

      // Open analysis board
      await tester.tap(find.text('Analysis board'));
      await tester.pumpAndSettle();

      // Make some moves
      await playMove(tester, 'e2', 'e4');
      await playMove(tester, 'e7', 'e5');
      await playMove(tester, 'f2', 'f4');

      // Verify we made the moves
      expect(find.textContaining('f4'), findsOneWidget);
      expect(boardHasPiece(tester, Square.f4, Piece.whitePawn), isTrue);

      //open menu
      await tester.tap(find.text('Menu'));
      await tester.pump();

      //tap Clear moves
      expect(find.text('Clear moves'), findsOneWidget);
      await tester.tap(find.text('Clear moves'));
      await tester.pump();

      // The tree view debounces path changes; let it apply before asserting.
      await tester.pump(kFastReplayDebounceDelay);

      //verify moves are cleared
      expect(find.textContaining('e4'), findsNothing);
      expect(boardHasPiece(tester, Square.e4, Piece.whitePawn), isFalse);

      // Navigate back to More tab
      await tester.tap(
        find.descendant(of: find.byType(SrsPageHead), matching: find.text('Review')),
      );
      await tester.pumpAndSettle();

      // Verify we're back at More tab
      expect(find.text('Tools'), findsOneWidget);

      // Navigate to board analysis again
      await tester.tap(find.text('Analysis board'));
      await tester.pumpAndSettle();

      // Verify moves are no longer present and analysis was cleared
      expect(find.textContaining('e4'), findsNothing);
      expect(boardHasPiece(tester, Square.e4, Piece.whitePawn), isFalse);
    });

    testWidgets('Opening a position from board editor overwrites saved standalone analysis', (
      tester,
    ) async {
      // Open from More tab and navigate to board analysis
      final app = await makeTestProviderScopeApp(
        tester,
        home: const MoreTabScreen(),
        defaultPreferences: {
          PrefCategory.engineEvaluation.storageKey: jsonEncode(
            EngineEvaluationPrefState.defaults.copyWith(isEnabled: false).toJson(),
          ),
        },
      );

      await tester.pumpWidget(app);

      // Open analysis board
      await tester.tap(find.text('Analysis board'));
      await tester.pumpAndSettle();

      // Make some moves
      await playMove(tester, 'e2', 'e4');
      await playMove(tester, 'e7', 'e5');
      await playMove(tester, 'f2', 'f4');

      // Verify we made the moves
      expect(find.textContaining('f4'), findsOneWidget);
      expect(boardHasPiece(tester, Square.f4, Piece.whitePawn), isTrue);

      // Navigate back to More tab
      await tester.tap(
        find.descendant(of: find.byType(SrsPageHead), matching: find.text('Review')),
      );
      await tester.pumpAndSettle();

      // Verify we're back at More tab
      expect(find.text('Tools'), findsOneWidget);

      // Navigate to board editor
      await tester.tap(find.text('Board editor'));
      await tester.pumpAndSettle();

      //make moves that result in a different position than the previous analysis
      await dragFromTo(tester, 'd2', 'd4');
      await dragFromTo(tester, 'd7', 'd5');

      //Open analysis from editor
      expect(find.byKey(const Key('analysis-board-button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('analysis-board-button')));
      await tester.pumpAndSettle();

      // Verify board state is correct and previous analysis was overwritten
      expect(boardHasPiece(tester, Square.d4, Piece.whitePawn), isTrue);
      expect(boardHasPiece(tester, Square.d5, Piece.blackPawn), isTrue);
      expect(boardHasPiece(tester, Square.f4, Piece.whitePawn), isFalse);
    });
  });
}

const gameResponse = '''
{"id":"qVChCOTc","rated":false,"variant":"standard","speed":"blitz","perf":"blitz","createdAt":1673443822389,"lastMoveAt":1673444036416,"status":"mate","players":{"white":{"aiLevel":1},"black":{"user":{"name":"veloce","patron":true,"id":"veloce"},"rating":1435,"provisional":true}},"winner":"black","opening":{"eco":"C20","name":"King's Pawn Game: Wayward Queen Attack, Kiddie Countergambit","ply":4},"moves":"e4 e5 Qh5 Nf6 Qxe5+ Be7 b3 d6 Qb5+ Bd7 Qxb7 Nc6 Ba3 Rb8 Qa6 Nxe4 Bb2 O-O Nc3 Nb4 Nf3 Nxa6 Nd5 Nb4 Nxe7+ Qxe7 Nd4 Qf6 f4 Qe7 Ke2 Ng3+ Kd1 Nxh1 Bc4 Nf2+ Kc1 Qe1#","clocks":[18003,18003,17915,17627,17771,16691,17667,16243,17475,15459,17355,14779,17155,13795,16915,13267,14771,11955,14451,10995,14339,10203,13899,9099,12427,8379,12003,7547,11787,6691,11355,6091,11147,5763,10851,5099,10635,4657],"clock":{"initial":180,"increment":0,"totalTime":180}}
''';

Future<void> dragFromTo(WidgetTester tester, String from, String to) async {
  final fromOffset = editorSquareOffset(tester, Square.fromName(from));
  await tester.dragFrom(fromOffset, editorSquareOffset(tester, Square.fromName(to)) - fromOffset);
  await tester.pumpAndSettle();
}

Offset editorSquareOffset(WidgetTester tester, Square square) {
  final editor = find.byType(ChessboardEditor);
  final squareSize = tester.getSize(editor).width / 8;

  return tester.getTopLeft(editor) +
      Offset(
        square.file.value * squareSize + squareSize / 2,
        (7 - square.rank.value) * squareSize + squareSize / 2,
      );
}
