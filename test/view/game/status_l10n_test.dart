// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/l10n/l10n.dart';
import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chess_srs/src/model/game/game_status.dart';
import 'package:chess_srs/src/utils/l10n_context.dart';
import 'package:chess_srs/src/view/game/status_l10n.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// `gameStatusL10n` turns a finished game's machine status into the one line the
/// game list shows. The mapping is not one-to-one: the same status picks a
/// different message per side (who resigned, who timed out) and per variant
/// (how a variant ended), and the draw status is disambiguated by the board and
/// by repetition. A swapped winner branch is invisible to the compiler and
/// silently tells the user the wrong player lost.
void main() {
  /// Pumps a localizations-aware app and returns a context below the
  /// localizations, so `context.l10n` resolves exactly as in production.
  Future<BuildContext> pumpLocalizedContext(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(body: SizedBox.shrink()),
      ),
    );
    return tester.element(find.byType(Scaffold));
  }

  String statusText(
    BuildContext context, {
    required GameStatus status,
    Variant variant = Variant.standard,
    Position? lastPosition,
    Side? winner,
    bool? isThreefoldRepetition,
  }) {
    return gameStatusL10n(
      context,
      variant: variant,
      status: status,
      lastPosition: lastPosition ?? Position.initialPosition(Rule.chess),
      winner: winner,
      isThreefoldRepetition: isThreefoldRepetition,
    );
  }

  group('statuses that carry no side', () {
    testWidgets('map to their own message', (tester) async {
      final context = await pumpLocalizedContext(tester);
      final l10n = context.l10n;

      expect(statusText(context, status: GameStatus.started), l10n.playingRightNow);
      expect(statusText(context, status: GameStatus.aborted), l10n.gameAborted);
      expect(statusText(context, status: GameStatus.mate), l10n.checkmate);
      expect(statusText(context, status: GameStatus.stalemate), l10n.stalemate);
      expect(statusText(context, status: GameStatus.unknownFinish), l10n.finished);
      expect(statusText(context, status: GameStatus.cheat), l10n.cheatDetected);
    });

    testWidgets('the side-specific messages are distinguishable', (tester) async {
      // The assertions below compare against a named l10n key; if two keys ever
      // rendered the same English text those comparisons would stop proving the
      // branch. Pin that they differ.
      final context = await pumpLocalizedContext(tester);
      final l10n = context.l10n;

      expect(l10n.whiteResigned, isNot(l10n.blackResigned));
      expect(l10n.whiteTimeOut, isNot(l10n.blackTimeOut));
      expect(l10n.whiteLeftTheGame, isNot(l10n.blackLeftTheGame));
      expect(l10n.whiteDidntMove, isNot(l10n.blackDidntMove));
    });
  });

  group('resignation names the player who resigned, not the winner', () {
    testWidgets('black wins means white resigned', (tester) async {
      final context = await pumpLocalizedContext(tester);

      expect(
        statusText(context, status: GameStatus.resign, winner: Side.black),
        context.l10n.whiteResigned,
      );
    });

    testWidgets('white wins means black resigned', (tester) async {
      final context = await pumpLocalizedContext(tester);

      expect(
        statusText(context, status: GameStatus.resign, winner: Side.white),
        context.l10n.blackResigned,
      );
    });
  });

  group('no-start names the player who did not move', () {
    testWidgets('black wins means white did not move', (tester) async {
      final context = await pumpLocalizedContext(tester);

      expect(
        statusText(context, status: GameStatus.noStart, winner: Side.black),
        context.l10n.whiteDidntMove,
      );
    });

    testWidgets('white wins means black did not move', (tester) async {
      final context = await pumpLocalizedContext(tester);

      expect(
        statusText(context, status: GameStatus.noStart, winner: Side.white),
        context.l10n.blackDidntMove,
      );
    });
  });

  group('timeout and out-of-time name the losing side', () {
    testWidgets('a decisive result names the player who ran out', (tester) async {
      final context = await pumpLocalizedContext(tester);
      final l10n = context.l10n;

      expect(
        statusText(context, status: GameStatus.timeout, winner: Side.black),
        l10n.whiteLeftTheGame,
      );
      expect(
        statusText(context, status: GameStatus.timeout, winner: Side.white),
        l10n.blackLeftTheGame,
      );
      expect(
        statusText(context, status: GameStatus.outoftime, winner: Side.black),
        l10n.whiteTimeOut,
      );
      expect(
        statusText(context, status: GameStatus.outoftime, winner: Side.white),
        l10n.blackTimeOut,
      );
    });

    testWidgets('a drawn result falls back to the side to move', (tester) async {
      final context = await pumpLocalizedContext(tester);
      final l10n = context.l10n;

      final blackToMove = Chess.fromSetup(
        Setup.parseFen('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR b KQkq - 0 1'),
      );

      expect(
        statusText(context, status: GameStatus.timeout),
        '${l10n.whiteLeftTheGame} • ${l10n.draw}',
      );
      expect(
        statusText(context, status: GameStatus.timeout, lastPosition: blackToMove),
        '${l10n.blackLeftTheGame} • ${l10n.draw}',
      );
      expect(
        statusText(context, status: GameStatus.outoftime),
        '${l10n.whiteTimeOut} • ${l10n.draw}',
      );
      expect(
        statusText(context, status: GameStatus.outoftime, lastPosition: blackToMove),
        '${l10n.blackTimeOut} • ${l10n.draw}',
      );
    });
  });

  group('draw disambiguates its cause', () {
    testWidgets('insufficient material wins over repetition', (tester) async {
      final context = await pumpLocalizedContext(tester);
      final l10n = context.l10n;

      final bareKings = Chess.fromSetup(Setup.parseFen('k7/8/8/8/8/8/8/K7 w - - 0 1'));
      expect(bareKings.isInsufficientMaterial, isTrue);

      expect(
        statusText(
          context,
          status: GameStatus.draw,
          lastPosition: bareKings,
          isThreefoldRepetition: true,
        ),
        '${l10n.insufficientMaterial} • ${l10n.draw}',
      );
    });

    testWidgets('repetition is named when material is sufficient', (tester) async {
      final context = await pumpLocalizedContext(tester);
      final l10n = context.l10n;

      expect(
        statusText(context, status: GameStatus.draw, isThreefoldRepetition: true),
        '${l10n.threefoldRepetition} • ${l10n.draw}',
      );
    });

    testWidgets('a plain draw is just a draw', (tester) async {
      final context = await pumpLocalizedContext(tester);
      final l10n = context.l10n;

      expect(statusText(context, status: GameStatus.draw, isThreefoldRepetition: false), l10n.draw);
      expect(statusText(context, status: GameStatus.draw), l10n.draw);
    });

    testWidgets('an insufficient-material claim says so', (tester) async {
      final context = await pumpLocalizedContext(tester);

      expect(
        statusText(context, status: GameStatus.insufficientMaterialClaim),
        '${context.l10n.insufficientMaterial} • ${context.l10n.draw}',
      );
    });
  });

  group('variant endings name the variant', () {
    testWidgets('each known variant has its own message', (tester) async {
      final context = await pumpLocalizedContext(tester);
      final l10n = context.l10n;

      expect(
        statusText(context, status: GameStatus.variantEnd, variant: Variant.kingOfTheHill),
        l10n.kingInTheCenter,
      );
      expect(
        statusText(context, status: GameStatus.variantEnd, variant: Variant.racingKings),
        l10n.raceFinished,
      );
      expect(
        statusText(context, status: GameStatus.variantEnd, variant: Variant.threeCheck),
        l10n.threeChecks,
      );
      expect(
        statusText(context, status: GameStatus.variantEnd, variant: Variant.antichess),
        l10n.variantEnding,
      );
    });
  });

  group('statuses the app does not localize', () {
    testWidgets('fall back to the enum name', (tester) async {
      final context = await pumpLocalizedContext(tester);

      expect(statusText(context, status: GameStatus.created), 'GameStatus.created');
      expect(statusText(context, status: GameStatus.unknown), 'GameStatus.unknown');
    });
  });
}
