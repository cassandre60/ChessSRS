import 'package:chess_srs/src/model/common/chess.dart';
import 'package:dartchess/dartchess.dart';
import 'package:deep_pick/deep_pick.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('fenToEpd', () {
    test('strips halfmove clock and fullmove number', () {
      expect(
        fenToEpd('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'),
        'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -',
      );
    });

    test('keeps already short FEN-like input stable', () {
      expect(fenToEpd('8/8/8/8/8/8/8/8 w - -'), '8/8/8/8/8/8/8/8 w - -');
    });
  });

  group('positionIdentity', () {
    test('uses first four FEN fields', () {
      expect(
        positionIdentity('rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1'),
        'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3',
      );
    });

    test('returns malformed input as-is when fewer than four fields', () {
      expect(positionIdentity('8/8/8/8/8/8/8/8 w'), '8/8/8/8/8/8/8/8 w');
    });
  });

  group('normalizeUci', () {
    test('normalizes alternate castling notation to king-takes-rook form', () {
      expect(normalizeUci('e1c1'), 'e1a1');
      expect(normalizeUci('e1g1'), 'e1h1');
      expect(normalizeUci('e8c8'), 'e8a8');
      expect(normalizeUci('e8g8'), 'e8h8');
    });

    test('returns non-castling moves unchanged', () {
      expect(normalizeUci('e2e4'), 'e2e4');
      expect(normalizeUci('a7a8q'), 'a7a8q');
    });
  });

  group('altCastles / kingTakesRookCastles maps', () {
    test('are inverse mappings for supported entries', () {
      for (final entry in altCastles.entries) {
        expect(kingTakesRookCastles[entry.value], entry.key);
      }
      for (final entry in kingTakesRookCastles.entries) {
        expect(altCastles[entry.value], entry.key);
      }
    });
  });

  group('isPromotionPawnMove', () {
    test('detects white promotion pawn move that is not yet promoted', () {
      final pos = Chess.fromSetup(Setup.parseFen('4k3/P7/8/8/8/8/8/4K3 w - - 0 1'));
      final move = Move.parse('a7a8')! as NormalMove;
      expect(isPromotionPawnMove(pos, move), isTrue);
    });

    test('detects black promotion pawn move that is not yet promoted', () {
      final pos = Chess.fromSetup(Setup.parseFen('4k3/8/8/8/8/8/p7/4K3 b - - 0 1'));
      final move = Move.parse('a2a1')! as NormalMove;
      expect(isPromotionPawnMove(pos, move), isTrue);
    });

    test('is false when move already has promotion', () {
      final pos = Chess.fromSetup(Setup.parseFen('4k3/P7/8/8/8/8/8/4K3 w - - 0 1'));
      final move = Move.parse('a7a8q')! as NormalMove;
      expect(isPromotionPawnMove(pos, move), isFalse);
    });

    test('is false for non-pawn or non-promotion-rank moves', () {
      const pos = Chess.initial;
      final move = Move.parse('e2e4')! as NormalMove;
      expect(isPromotionPawnMove(pos, move), isFalse);
    });
  });

  group('SanMove', () {
    test('flags and normalization reflect SAN and variant', () {
      final castles = SanMove('O-O+', Move.parse('e1g1')!);
      expect(castles.isCheck, isTrue);
      expect(castles.isCheckmate, isFalse);
      expect(castles.isCapture, isFalse);
      expect(castles.isCastles, isTrue);
      expect(castles.normalizeUci(Variant.standard), 'e1h1');
      expect(castles.normalizeUci(Variant.chess960), 'e1g1');

      final captureMate = SanMove('Qxh7#', Move.parse('d3h7')!);
      expect(captureMate.isCapture, isTrue);
      expect(captureMate.isCheckmate, isTrue);
      expect(captureMate.isCastles, isFalse);
      expect(captureMate.normalizeUci(Variant.standard), 'd3h7');
    });

    test('isIrreversible follows checks, captures, pawn moves and variant rules', () {
      final check = SanMove('Bb5+', Move.parse('f1b5')!);
      final capture = SanMove('Nxe5', Move.parse('f3e5')!);
      final pawnMove = SanMove('e4', Move.parse('e2e4')!);
      final quietKnight = SanMove('Nf3', Move.parse('g1f3')!);

      expect(check.isIrreversible(Variant.standard), isTrue);
      expect(capture.isIrreversible(Variant.standard), isTrue);
      expect(capture.isIrreversible(Variant.crazyhouse), isFalse);
      expect(pawnMove.isIrreversible(Variant.standard), isTrue);
      expect(quietKnight.isIrreversible(Variant.standard), isFalse);
      expect(check.isIrreversible(Variant.threeCheck), isTrue);
    });

    test('round-trips through JSON', () {
      final move = SanMove('e4', Move.parse('e2e4')!);
      expect(SanMove.fromJson(move.toJson()), move);
    });
  });

  group('divisionFromPick', () {
    test('maps middle/end keys with nullable ints', () {
      final division = divisionFromPick(pick({'middle': 21, 'end': 42}).required());
      expect(division.middlegame, 21);
      expect(division.endgame, 42);
    });

    test('accepts missing phase values', () {
      final division = divisionFromPick(pick(<String, dynamic>{}).required());
      expect(division.middlegame, isNull);
      expect(division.endgame, isNull);
    });
  });

  group('Variant', () {
    test('fromRule maps dartchess rules to app variants', () {
      expect(Variant.fromRule(Rule.chess), Variant.standard);
      expect(Variant.fromRule(Rule.antichess), Variant.antichess);
      expect(Variant.fromRule(Rule.kingofthehill), Variant.kingOfTheHill);
      expect(Variant.fromRule(Rule.threecheck), Variant.threeCheck);
      expect(Variant.fromRule(Rule.atomic), Variant.atomic);
      expect(Variant.fromRule(Rule.horde), Variant.horde);
      expect(Variant.fromRule(Rule.racingKings), Variant.racingKings);
      expect(Variant.fromRule(Rule.crazyhouse), Variant.crazyhouse);
    });

    test('initialPosition returns expected positions or throws for special variants', () {
      expect(Variant.standard.initialPosition, Chess.initial);
      expect(Variant.antichess.initialPosition, Antichess.initial);
      expect(Variant.kingOfTheHill.initialPosition, KingOfTheHill.initial);
      expect(Variant.threeCheck.initialPosition, ThreeCheck.initial);
      expect(Variant.atomic.initialPosition, Atomic.initial);
      expect(Variant.crazyhouse.initialPosition, Crazyhouse.initial);
      expect(Variant.horde.initialPosition, Horde.initial);
      expect(Variant.racingKings.initialPosition, RacingKings.initial);

      expect(() => Variant.chess960.initialPosition, throwsArgumentError);
      expect(() => Variant.fromPosition.initialPosition, throwsArgumentError);
    });

    test('exposes rule, read/play support and castling/en-passant capabilities', () {
      expect(Variant.standard.rule, Rule.chess);
      expect(Variant.chess960.rule, Rule.chess);
      expect(Variant.fromPosition.rule, Rule.chess);
      expect(Variant.antichess.rule, Rule.antichess);

      expect(Variant.standard.isReadSupported, isTrue);
      expect(readSupportedVariants.contains(Variant.crazyhouse), isTrue);
      expect(playSupportedVariants.contains(Variant.standard), isTrue);
      expect(playSupportedVariants.contains(Variant.fromPosition), isTrue);

      expect(Variant.standard.sideCanCastle(Side.white), isTrue);
      expect(Variant.racingKings.sideCanCastle(Side.white), isFalse);
      expect(Variant.antichess.sideCanCastle(Side.black), isFalse);
      expect(Variant.horde.sideCanCastle(Side.white), isFalse);
      expect(Variant.horde.sideCanCastle(Side.black), isTrue);

      expect(Variant.standard.hasEnPassant, isTrue);
      expect(Variant.racingKings.hasEnPassant, isFalse);
    });

    test('nameMap and pgnName stay consistent', () {
      expect(Variant.nameMap['standard'], Variant.standard);
      expect(Variant.nameMap['chess960'], Variant.chess960);
      expect(Variant.nameMap.length, Variant.values.length);
      expect(Variant.standard.pgnName, 'Standard');
      expect(Variant.chess960.pgnName, 'Chess960');
      expect(Variant.fromPosition.pgnName, 'From Position');
      expect(Variant.kingOfTheHill.pgnName, 'King of the Hill');
    });
  });
}
