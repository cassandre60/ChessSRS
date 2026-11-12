import 'package:chess_srs/src/model/common/id.dart';
import 'package:deep_pick/deep_pick.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StringId', () {
    test('wraps value and exposes string operations', () {
      const id = StringId('abc');
      expect(id.value, 'abc');
      expect(id.length, 3);
      expect(id.startsWith('ab'), isTrue);
      expect(id.startsWith('x'), isFalse);
      expect(id.toJson(), 'abc');
      expect(StringId.fromJson('xyz'), const StringId('xyz'));
    });
  });

  group('GameAnyId / GameId / GameFullId', () {
    test('GameAnyId derives game and full ids from 12-char value', () {
      final anyId = GameAnyId('abcdefghwxyz');
      expect(anyId.value, 'abcdefghwxyz');
      expect(anyId.gameId, const GameId('abcdefgh'));
      expect(anyId.isFullId, isTrue);
      expect(anyId.gameFullId, const GameFullId('abcdefghwxyz'));
    });

    test('GameAnyId with 8-char value has no full id', () {
      final anyId = GameAnyId('abcdefgh');
      expect(anyId.gameId, const GameId('abcdefgh'));
      expect(anyId.isFullId, isFalse);
      expect(anyId.gameFullId, isNull);
    });

    test('GameId validates 8-char alnum/dash/underscore ids', () {
      expect(const GameId('abcd1234').isValid, isTrue);
      expect(const GameId('ab-cd_12').isValid, isTrue);
      expect(const GameId('abc defg').isValid, isFalse);
      expect(const GameId('abcd!234').isValid, isFalse);
    });

    test('json round-trips for game id types', () {
      expect(GameId.fromJson('abcdefgh'), const GameId('abcdefgh'));
      expect(
        GameFullId.fromJson('abcdefghwxyz'),
        const GameFullId('abcdefghwxyz'),
      );
      expect(GameAnyId.fromJson('abcdefgh'), GameAnyId('abcdefgh'));
    });
  });

  group('simple id wrappers', () {
    test('UserId normalizes usernames to lowercase', () {
      expect(UserId.fromUserName('Thibault'), const UserId('thibault'));
      expect(UserId.fromJson('Player'), const UserId('Player'));
    });

    test('ChallengeId validates 8-char ids', () {
      expect(const ChallengeId('abcd1234').isValid, isTrue);
      expect(const ChallengeId('bad id!!').isValid, isFalse);
    });

    test('json constructors preserve values', () {
      expect(PuzzleId.fromJson('p1'), const PuzzleId('p1'));
      expect(ChallengeId.fromJson('abcd1234'), const ChallengeId('abcd1234'));
      expect(StudyId.fromJson('s1'), const StudyId('s1'));
      expect(TournamentId.fromJson('t1'), const TournamentId('t1'));
      expect(TeamId.fromJson('team'), const TeamId('team'));
      expect(StudyChapterId.fromJson('ch1'), const StudyChapterId('ch1'));
    });
  });

  group('IDPick', () {
    test('asStringIdOrThrow reads string values', () {
      expect(pick('abc').asStringIdOrThrow(), const StringId('abc'));
      expect(() => pick(1).asStringIdOrThrow(), throwsA(isA<PickException>()));
    });

    test('asUserIdOrThrow and asUserIdOrNull', () {
      expect(pick('Bob').asUserIdOrThrow(), const UserId('Bob'));
      expect(pick('Bob').asUserIdOrNull(), const UserId('Bob'));
      expect(pick(null).asUserIdOrNull(), isNull);
      expect(pick(123).asUserIdOrNull(), isNull);
      expect(() => pick(123).asUserIdOrThrow(), throwsA(isA<PickException>()));
    });

    test('game id picks parse and reject invalid types', () {
      expect(pick('abcdefgh').asGameIdOrThrow(), const GameId('abcdefgh'));
      expect(
        pick('abcdefghwxyz').asGameFullIdOrThrow(),
        const GameFullId('abcdefghwxyz'),
      );
      expect(
        pick('abcdefghwxyz').asGameFullIdOrNull(),
        const GameFullId('abcdefghwxyz'),
      );
      expect(pick(null).asGameFullIdOrNull(), isNull);
      expect(pick(1).asGameFullIdOrNull(), isNull);
      expect(() => pick(1).asGameIdOrThrow(), throwsA(isA<PickException>()));
    });

    test('other id picks parse expected string types', () {
      expect(pick('p1').asPuzzleIdOrThrow(), const PuzzleId('p1'));
      expect(
        pick('abcd1234').asChallengeIdOrThrow(),
        const ChallengeId('abcd1234'),
      );
      expect(
        pick('bt1').asBroadcastTournamentIdOrThrow(),
        const BroadcastTournamentId('bt1'),
      );
      expect(
        pick('br1').asBroadcastRoundIdOrThrow(),
        const BroadcastRoundId('br1'),
      );
      expect(
        pick('bg1').asBroadcastGameIdOrThrow(),
        const BroadcastGameId('bg1'),
      );
      expect(pick('team').asTeamIdOrThrow(), const TeamId('team'));
      expect(pick('study').asStudyIdOrThrow(), const StudyId('study'));
      expect(pick('tour').asTournamentIdOrThrow(), const TournamentId('tour'));
      expect(pick('tour').asTournamentIdOrNull(), const TournamentId('tour'));
      expect(pick(null).asTournamentIdOrNull(), isNull);
      expect(pick(1).asTournamentIdOrNull(), isNull);
    });

    test('asFideIdOrThrow requires a non-zero int', () {
      expect(pick(12345).asFideIdOrThrow(), const FideId(12345));
      expect(() => pick(0).asFideIdOrThrow(), throwsA(isA<PickException>()));
      expect(
        () => pick('123').asFideIdOrThrow(),
        throwsA(isA<PickException>()),
      );
    });
  });
}
