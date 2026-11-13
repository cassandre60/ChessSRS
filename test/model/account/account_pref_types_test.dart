import 'package:chess_srs/src/model/account/account_pref_types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BooleanPref', () {
    test('fromJson accepts bool and int values', () {
      expect(BooleanPref.fromJson(true).value, isTrue);
      expect(BooleanPref.fromJson(false).value, isFalse);
      expect(BooleanPref.fromJson(1).value, isTrue);
      expect(BooleanPref.fromJson(0).value, isFalse);
      expect(BooleanPref.fromJson(-2).value, isTrue);
    });

    test('fromJson falls back to false for unsupported values', () {
      expect(BooleanPref.fromJson('true').value, isFalse);
      expect(BooleanPref.fromJson(null).value, isFalse);
    });

    test('toJson and toFormData reflect value', () {
      expect(const BooleanPref(true).toJson(), isTrue);
      expect(const BooleanPref(false).toJson(), isFalse);
      expect(const BooleanPref(true).toFormData, '1');
      expect(const BooleanPref(false).toFormData, '0');
    });

    test('fromInt maps known values and rejects unknown', () {
      expect(BooleanPref.fromInt(1).value, isTrue);
      expect(BooleanPref.fromInt(0).value, isFalse);
      expect(() => BooleanPref.fromInt(2), throwsException);
    });
  });

  group('enum prefs', () {
    test('expose stable numeric values and form data', () {
      expect(Zen.no.value, 0);
      expect(Zen.yes.toFormData, '1');
      expect(Zen.gameAuto.value, 2);

      expect(ShowRatings.no.value, 0);
      expect(ShowRatings.exceptInGame.toFormData, '2');
      expect(PieceNotation.letter.value, 1);

      expect(AutoQueen.never.value, 1);
      expect(AutoQueen.premove.toFormData, '2');
      expect(AutoQueen.always.value, 3);

      expect(AutoThreefold.time.value, 2);
      expect(Takeback.casual.value, 2);
      expect(Moretime.always.toFormData, '3');
      expect(ClockTenths.lessThan10s.value, 1);
      expect(Challenge.friends.value, 3);
      expect(Message.never.value, 1);
    });

    test('fromInt round-trips known values', () {
      expect(Zen.fromInt(0), Zen.no);
      expect(Zen.fromInt(1), Zen.yes);
      expect(Zen.fromInt(2), Zen.gameAuto);
      expect(ShowRatings.fromInt(2), ShowRatings.exceptInGame);
      expect(PieceNotation.fromInt(1), PieceNotation.letter);
      expect(AutoQueen.fromInt(3), AutoQueen.always);
      expect(AutoThreefold.fromInt(1), AutoThreefold.never);
      expect(Takeback.fromInt(2), Takeback.casual);
      expect(Moretime.fromInt(3), Moretime.always);
      expect(ClockTenths.fromInt(0), ClockTenths.never);
      expect(Challenge.fromInt(4), Challenge.registered);
      expect(Message.fromInt(2), Message.friends);
    });

    test('fromInt rejects unknown values', () {
      expect(() => Zen.fromInt(-1), throwsException);
      expect(() => ShowRatings.fromInt(3), throwsException);
      expect(() => PieceNotation.fromInt(2), throwsException);
      expect(() => AutoQueen.fromInt(0), throwsException);
      expect(() => AutoThreefold.fromInt(4), throwsException);
      expect(() => Takeback.fromInt(0), throwsException);
      expect(() => Moretime.fromInt(4), throwsException);
      expect(() => ClockTenths.fromInt(3), throwsException);
      expect(() => Challenge.fromInt(0), throwsException);
      expect(() => Message.fromInt(0), throwsException);
      expect(() => SubmitMoveChoice.fromInt(3), throwsException);
    });
  });

  group('SubmitMove', () {
    test('combines choices as a bitmask and round-trips ints', () {
      final submit = SubmitMove(const {SubmitMoveChoice.correspondence, SubmitMoveChoice.rapid});

      expect(submit.value, SubmitMoveChoice.correspondence.value | SubmitMoveChoice.rapid.value);
      expect(submit.toFormData, submit.value.toString());
      expect(submit.toJson(), submit.value);
      expect(submit.choices.contains(SubmitMoveChoice.correspondence), isTrue);
      expect(submit.choices.contains(SubmitMoveChoice.rapid), isTrue);
      expect(submit.choices.contains(SubmitMoveChoice.blitz), isFalse);

      final decoded = SubmitMove.fromInt(submit.value);
      expect(decoded.choices, submit.choices);
      expect(SubmitMove.fromInt(0).choices, isEmpty);
    });

    test('fromJson accepts ints and falls back to empty choices', () {
      expect(SubmitMove.fromJson(16).choices, {SubmitMoveChoice.blitz});
      expect(SubmitMove.fromJson('16').choices, isEmpty);
      expect(SubmitMove.fromJson(null).choices, isEmpty);
    });

    test('SubmitMoveChoice values are stable', () {
      expect(SubmitMoveChoice.unlimited.value, 1);
      expect(SubmitMoveChoice.correspondence.value, 2);
      expect(SubmitMoveChoice.classical.value, 4);
      expect(SubmitMoveChoice.rapid.value, 8);
      expect(SubmitMoveChoice.blitz.value, 16);
      expect(SubmitMoveChoice.fromInt(1), SubmitMoveChoice.unlimited);
      expect(SubmitMoveChoice.fromInt(16), SubmitMoveChoice.blitz);
    });
  });

  group('AccountPrefState', () {
    test('default preferences expose expected baseline values', () {
      expect(defaultAccountPreferences.zenMode, Zen.no);
      expect(defaultAccountPreferences.pieceNotation, PieceNotation.symbol);
      expect(defaultAccountPreferences.showRatings, ShowRatings.yes);
      expect(defaultAccountPreferences.premove.value, isTrue);
      expect(defaultAccountPreferences.autoQueen, AutoQueen.premove);
      expect(defaultAccountPreferences.autoThreefold, AutoThreefold.always);
      expect(defaultAccountPreferences.takeback, Takeback.always);
      expect(defaultAccountPreferences.moretime, Moretime.always);
      expect(defaultAccountPreferences.clockTenths, ClockTenths.lessThan10s);
      expect(defaultAccountPreferences.clockSound.value, isTrue);
      expect(defaultAccountPreferences.confirmResign.value, isTrue);
      expect(defaultAccountPreferences.follow.value, isTrue);
      expect(defaultAccountPreferences.challenge, Challenge.registered);
      expect(defaultAccountPreferences.message, Message.always);
      expect(defaultAccountPreferences.submitMove.choices, {SubmitMoveChoice.correspondence});
    });

    test('fromJson falls back to defaults on malformed payloads', () {
      expect(AccountPrefState.fromJson({'zenMode': 'not-an-int'}), defaultAccountPreferences);
    });
  });
}
