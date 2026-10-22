// SPEC coverage: none. No invariant in SPEC.md names any behaviour of
// `lib/src/model/user/user.dart` — the spec covers persistence, import, the
// review engine, architecture boundaries and performance budgets, and none of
// them is about the user model. The contracts pinned below are therefore the
// model's own observable behaviour: what it holds, what it derives, and what
// it reports. They are pinned so that a change which breaks them fails a test.
//
// This is the first test file for this model: `scripts/autonomous/config.json`
// maps `lib/src/<...>/<name>.dart` to `test/<name>_test.dart`, which resolves
// this file to `test/user_test.dart` — a path that does not exist, so the file
// was never auditable. This file sits next to the lib file instead, under
// `test/model/user/`, and is the one the mutation round runs against.

import 'package:chess_srs/src/model/common/id.dart';
import 'package:chess_srs/src/model/common/perf.dart';
import 'package:chess_srs/src/model/user/profile.dart';
import 'package:chess_srs/src/model/user/user.dart';
import 'package:deep_pick/deep_pick.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';

const testUserId = UserId('abc');
const testUsername = 'thibault';

/// The perf map every user in this file carries unless a test says otherwise.
const emptyPerfs = IMap<Perf, UserPerf>.empty();

UserPerf perf({
  int rating = 1500,
  int ratingDeviation = 50,
  int progression = 0,
  int? games,
  int? runs,
  bool? provisional,
}) => UserPerf(
  rating: rating,
  ratingDeviation: ratingDeviation,
  progression: progression,
  games: games,
  runs: runs,
  provisional: provisional,
);

void main() {
  group('LightUser', () {
    test('is not a patron when no patron color is set', () {
      expect(const LightUser(id: testUserId, name: testUsername).isPatron, isFalse);
    });

    test('is a patron when a patron color is set', () {
      expect(const LightUser(id: testUserId, name: testUsername, patronColor: 3).isPatron, isTrue);
    });

    test('is a bot only for the exact BOT title', () {
      expect(const LightUser(id: testUserId, name: 'bot', title: 'BOT').isBot, isTrue);
      expect(const LightUser(id: testUserId, name: 'bot', title: 'Bot').isBot, isFalse);
      expect(const LightUser(id: testUserId, name: 'gm', title: 'GM').isBot, isFalse);
      expect(const LightUser(id: testUserId, name: 'gm').isBot, isFalse);
    });

    test('round trips through JSON', () {
      const user = LightUser(
        id: testUserId,
        name: testUsername,
        title: 'GM',
        flair: '♞',
        patronColor: 2,
        isOnline: true,
      );

      expect(LightUser.fromJson(user.toJson()), user);
    });
  });

  group('LightUser pick extension', () {
    test('returns a LightUser value unchanged', () {
      const user = LightUser(id: testUserId, name: testUsername);

      expect(pick(user).asLightUserOrThrow(), user);
    });

    test('reads every field of a map', () {
      final user = pick(<String, dynamic>{
        'id': 'abc',
        'username': testUsername,
        'title': 'GM',
        'flair': '♞',
        'patronColor': 4,
        'online': true,
      }).asLightUserOrThrow();

      expect(user.id, testUserId);
      expect(user.name, testUsername);
      expect(user.title, 'GM');
      expect(user.flair, '♞');
      expect(user.patronColor, 4);
      expect(user.isOnline, isTrue);
    });

    test('falls back to the name when the map has no username', () {
      final user = pick(<String, dynamic>{'id': 'abc', 'name': testUsername}).asLightUserOrThrow();

      expect(user.name, testUsername);
      expect(user.id, testUserId);
    });

    test('derives the id from the name, lower cased, when the map has no id', () {
      final user = pick(<String, dynamic>{'username': 'Thibault'}).asLightUserOrThrow();

      expect(user.id.value, 'thibault');
    });

    test('throws when the value is neither a user nor a map', () {
      expect(() => pick(42).asLightUserOrThrow(), throwsA(isA<PickException>()));
    });

    test('throws when the map has neither a username nor a name', () {
      expect(
        () => pick(<String, dynamic>{'id': 'abc'}).asLightUserOrThrow(),
        throwsA(isA<PickException>()),
      );
    });

    test('asLightUserOrNull returns null for a null value', () {
      expect(pick(null).asLightUserOrNull(), isNull);
    });

    test('asLightUserOrNull returns null for an unusable value', () {
      expect(pick(42).asLightUserOrNull(), isNull);
      expect(pick(<String, dynamic>{'id': 'abc'}).asLightUserOrNull(), isNull);
    });

    test('asLightUserOrNull returns the user for a usable map', () {
      final user = pick(<String, dynamic>{
        'id': 'abc',
        'username': testUsername,
      }).asLightUserOrNull();

      expect(user?.id, testUserId);
      expect(user?.name, testUsername);
    });
  });

  group('User', () {
    User build({
      String username = testUsername,
      String? title,
      String? flair,
      int? patronColor,
      Profile? profile,
    }) => User(
      id: testUserId,
      username: username,
      title: title,
      flair: flair,
      patronColor: patronColor,
      profile: profile,
      perfs: emptyPerfs,
    );

    test('lightUser carries the public identity of the user', () {
      final user = build(title: 'GM', flair: '♞', patronColor: 2);

      expect(
        user.lightUser,
        const LightUser(
          id: testUserId,
          name: testUsername,
          title: 'GM',
          flair: '♞',
          patronColor: 2,
        ),
      );
    });

    test('lightUser takes the name from the username, not from the id', () {
      expect(build().lightUser.name, testUsername);
      expect(build().lightUser.id, testUserId);
    });

    test('lightUser invents no title for a user without one', () {
      expect(build().lightUser.title, isNull);
      expect(build().lightUser.flair, isNull);
      expect(build().lightUser.patronColor, isNull);
      expect(build().lightUser.isPatron, isFalse);
    });

    test('is a bot only for the exact BOT title', () {
      expect(build(title: 'BOT').isBot, isTrue);
      expect(build(title: 'Bot').isBot, isFalse);
      expect(build(title: 'GM').isBot, isFalse);
      expect(build().isBot, isFalse);
    });

    test('copying a user leaves the original untouched', () {
      final user = build();
      final copy = user.copyWith(username: 'someone else');

      expect(user.username, testUsername);
      expect(user.lightUser.name, testUsername);
      expect(copy.username, 'someone else');
      expect(copy.lightUser.name, 'someone else');
    });
  });

  group('User.initials', () {
    User build({required String username, String? realName}) => User(
      id: testUserId,
      username: username,
      profile: realName == null ? null : Profile(realName: realName),
      perfs: emptyPerfs,
    );

    test('takes the first letter of the first two words of the real name', () {
      expect(build(username: 'jd', realName: 'John Doe').initials, 'JD');
    });

    test('takes the first letter of the only word of a one word real name', () {
      expect(build(username: 'ada', realName: 'Ada').initials, 'A');
    });

    test('takes at most the first two words of a longer real name', () {
      expect(build(username: 'alk', realName: 'Ada Lovelace King').initials, 'AL');
    });

    test('uppercases the initials', () {
      expect(build(username: 'jd', realName: 'john doe').initials, 'JD');
    });

    test('falls back to the first letter of the username without a profile', () {
      expect(build(username: testUsername).initials, 'T');
    });

    test('falls back to the username when the profile has no real name', () {
      const user = User(
        id: testUserId,
        username: testUsername,
        profile: Profile(country: 'France'),
        perfs: emptyPerfs,
      );

      expect(user.initials, 'T');
    });
  });

  group('User.fromServerJson', () {
    test('reads the identity, the flags and the timestamps', () {
      final user = User.fromServerJson(<String, dynamic>{
        'id': 'abc',
        'username': testUsername,
        'title': 'GM',
        'flair': '♞',
        'patronColor': 3,
        'disabled': false,
        'tosViolation': true,
        'verified': true,
        'createdAt': 1290415680000,
        'seenAt': 1290415680000,
        'perfs': <String, dynamic>{},
      });

      expect(user.id, testUserId);
      expect(user.username, testUsername);
      expect(user.title, 'GM');
      expect(user.flair, '♞');
      expect(user.patronColor, 3);
      expect(user.disabled, isFalse);
      expect(user.tosViolation, isTrue);
      expect(user.verified, isTrue);
      expect(user.createdAt, DateTime.fromMillisecondsSinceEpoch(1290415680000));
      expect(user.seenAt, DateTime.fromMillisecondsSinceEpoch(1290415680000));
      expect(user.perfs.length, 0);
    });

    test('keeps every optional field null when the server omits it', () {
      final user = User.fromServerJson(<String, dynamic>{
        'id': 'abc',
        'username': testUsername,
        'perfs': <String, dynamic>{},
      });

      expect(user.title, isNull);
      expect(user.flair, isNull);
      expect(user.patronColor, isNull);
      expect(user.disabled, isNull);
      expect(user.tosViolation, isNull);
      expect(user.verified, isNull);
      expect(user.createdAt, isNull);
      expect(user.seenAt, isNull);
      expect(user.playTime, isNull);
      expect(user.profile, isNull);
      expect(user.count, isNull);
      expect(user.followable, isNull);
      expect(user.following, isNull);
      expect(user.blocking, isNull);
      expect(user.canChallenge, isNull);
      expect(user.kid, isNull);
      expect(user.playban, isNull);
    });

    test('reads the play time in seconds', () {
      final user = User.fromServerJson(<String, dynamic>{
        'id': 'abc',
        'username': testUsername,
        'perfs': <String, dynamic>{},
        'playTime': <String, dynamic>{'total': 1000, 'tv': 60},
      });

      expect(user.playTime?.total, const Duration(seconds: 1000));
      expect(user.playTime?.tv, const Duration(seconds: 60));
    });

    test('reads the profile', () {
      final user = User.fromServerJson(<String, dynamic>{
        'id': 'abc',
        'username': testUsername,
        'perfs': <String, dynamic>{},
        'profile': <String, dynamic>{'country': 'France', 'realName': 'John Doe'},
      });

      expect(user.profile?.country, 'France');
      expect(user.profile?.realName, 'John Doe');
    });

    test('reads the game count', () {
      final user = User.fromServerJson(<String, dynamic>{
        'id': 'abc',
        'username': testUsername,
        'perfs': <String, dynamic>{},
        'count': <String, dynamic>{'all': 2340, 'bookmark': 3},
      });

      expect(user.count?.all, 2340);
      expect(user.count?.bookmark, 3);
    });

    test('reads the play ban', () {
      final user = User.fromServerJson(<String, dynamic>{
        'id': 'abc',
        'username': testUsername,
        'perfs': <String, dynamic>{},
        'playban': <String, dynamic>{'date': 1290415680000, 'mins': 1440},
      });

      expect(user.playban?.date, DateTime.fromMillisecondsSinceEpoch(1290415680000));
      expect(user.playban?.duration, const Duration(minutes: 1440));
    });

    test('reads the perfs with the regular parser', () {
      final user = User.fromServerJson(<String, dynamic>{
        'id': 'abc',
        'username': testUsername,
        'perfs': <String, dynamic>{
          'blitz': <String, dynamic>{
            'games': 10,
            'rating': 1500,
            'rd': 50,
            'prog': 5,
            'prov': false,
          },
        },
      });

      expect(user.perfs.length, 1);
      final blitz = user.perfs[Perf.blitz];
      expect(blitz?.rating, 1500);
      expect(blitz?.ratingDeviation, 50);
      expect(blitz?.progression, 5);
      expect(blitz?.games, 10);
      expect(blitz?.runs, isNull);
      expect(blitz?.provisional, isFalse);
    });

    test('reads the storm and streak perfs with the streak parser', () {
      final user = User.fromServerJson(<String, dynamic>{
        'id': 'abc',
        'username': testUsername,
        'perfs': <String, dynamic>{
          'storm': <String, dynamic>{'runs': 5, 'score': 12},
        },
      });

      expect(user.perfs.length, 1);
      final storm = user.perfs[Perf.storm];
      expect(storm?.rating, 12);
      expect(storm?.runs, 5);
      expect(storm?.games, isNull);
      expect(storm?.ratingDeviation, 0);
      expect(storm?.progression, 0);
    });

    test('reads the streak perf with the streak parser', () {
      final user = User.fromServerJson(<String, dynamic>{
        'id': 'abc',
        'username': testUsername,
        'perfs': <String, dynamic>{
          'streak': <String, dynamic>{'runs': 3, 'score': 7},
        },
      });

      expect(user.perfs.length, 1);
      final streak = user.perfs[Perf.streak];
      expect(streak?.rating, 7);
      expect(streak?.runs, 3);
      expect(streak?.games, isNull);
      expect(streak?.ratingDeviation, 0);
      expect(streak?.progression, 0);
    });

    test('reads a user without any perfs', () {
      final user = User.fromServerJson(<String, dynamic>{'id': 'abc', 'username': testUsername});

      expect(user.perfs.length, 0);
    });

    test('drops the perfs it does not know', () {
      final user = User.fromServerJson(<String, dynamic>{
        'id': 'abc',
        'username': testUsername,
        'perfs': <String, dynamic>{
          'blitz': <String, dynamic>{'games': 10, 'rating': 1500, 'rd': 50, 'prog': 5},
          'notAPerf': <String, dynamic>{'games': 1, 'rating': 1, 'rd': 1, 'prog': 1},
        },
      });

      expect(user.perfs.length, 1);
      expect(user.perfs.containsKey(Perf.blitz), isTrue);
      expect(user.perfs[Perf.blitz]?.rating, 1500);
    });
  });

  group('UserGameCount', () {
    test('reads the total and the bookmarked count', () {
      final count = UserGameCount.fromJson(<String, dynamic>{'all': 2340, 'bookmark': 3});

      expect(count.all, 2340);
      expect(count.bookmark, 3);
    });

    test('requires the total and the bookmarked count', () {
      expect(
        () => UserGameCount.fromJson(<String, dynamic>{'all': 2340}),
        throwsA(isA<PickException>()),
      );
      expect(
        () => UserGameCount.fromJson(<String, dynamic>{'bookmark': 3}),
        throwsA(isA<PickException>()),
      );
    });
  });

  group('PlayTime', () {
    test('reads the total and the tv time in seconds', () {
      final playTime = PlayTime.fromJson(<String, dynamic>{'total': 1000, 'tv': 60});

      expect(playTime.total, const Duration(seconds: 1000));
      expect(playTime.tv, const Duration(seconds: 60));
    });
  });

  group('UserPerf', () {
    test('reads the rating, the deviation and the progression', () {
      final userPerf = UserPerf.fromJson(<String, dynamic>{
        'games': 10,
        'rating': 1500,
        'rd': 50,
        'prog': 5,
        'prov': true,
      });

      expect(userPerf.rating, 1500);
      expect(userPerf.ratingDeviation, 50);
      expect(userPerf.progression, 5);
      expect(userPerf.games, 10);
      expect(userPerf.runs, isNull);
      expect(userPerf.provisional, isTrue);
    });

    test('numberOfGamesOrRuns is the number of games when there are games', () {
      expect(perf(games: 10, runs: 4).numberOfGamesOrRuns, 10);
    });

    test('numberOfGamesOrRuns is the number of runs when there are no games', () {
      expect(perf(runs: 4).numberOfGamesOrRuns, 4);
    });

    test('numberOfGamesOrRuns is zero when there is neither games nor runs', () {
      expect(perf().numberOfGamesOrRuns, 0);
    });
  });

  group('UserStatus', () {
    test('reads the id, the name and the presence flags', () {
      final status = UserStatus.fromJson(<String, dynamic>{
        'id': 'abc',
        'name': testUsername,
        'online': true,
        'playing': false,
      });

      expect(status.id, testUserId);
      expect(status.name, testUsername);
      expect(status.online, isTrue);
      expect(status.playing, isFalse);
    });

    test('keeps the presence flags null when the server omits them', () {
      final status = UserStatus.fromJson(<String, dynamic>{'id': 'abc', 'name': testUsername});

      expect(status.online, isNull);
      expect(status.playing, isNull);
    });
  });

  group('UserActivityTournament', () {
    test('reads the tournament id and name from the nested object', () {
      final tournament = UserActivityTournament.fromJson(<String, dynamic>{
        'tournament': <String, dynamic>{'id': 'tour1', 'name': 'Some cup'},
        'nbGames': 10,
        'score': 42,
        'rank': 3,
        'rankPercent': 12,
      });

      expect(tournament.id, 'tour1');
      expect(tournament.name, 'Some cup');
      expect(tournament.nbGames, 10);
      expect(tournament.score, 42);
      expect(tournament.rank, 3);
      expect(tournament.rankPercent, 12);
    });
  });

  group('UserActivityStreak', () {
    test('reads the runs and the score', () {
      final streak = UserActivityStreak.fromJson(<String, dynamic>{'runs': 5, 'score': 12});

      expect(streak.runs, 5);
      expect(streak.score, 12);
    });
  });

  group('UserActivityScore', () {
    test('reads the results and the rating before and after', () {
      final score = UserActivityScore.fromJson(<String, dynamic>{
        'win': 3,
        'loss': 1,
        'draw': 2,
        'rp': <String, dynamic>{'before': 1500, 'after': 1520},
      });

      expect(score.win, 3);
      expect(score.loss, 1);
      expect(score.draw, 2);
      expect(score.ratingBefore, 1500);
      expect(score.ratingAfter, 1520);
    });
  });

  group('UserActivity', () {
    final startTime = DateTime.utc(2023, 4, 18);
    final endTime = DateTime.utc(2023, 4, 19);

    const score = UserActivityScore(
      win: 1,
      loss: 0,
      draw: 0,
      ratingBefore: 1500,
      ratingAfter: 1510,
    );

    UserActivity build({
      IMap<Perf, UserActivityScore>? games,
      int? followInNb,
      int? followOutNb,
      int? tournamentNb,
      UserActivityTournament? bestTournament,
      UserActivityScore? puzzles,
      UserActivityStreak? streak,
      UserActivityStreak? storm,
      IMap<Perf, UserActivityScore>? correspondenceEnds,
      int? correspondenceMovesNb,
      int? correspondenceGamesNb,
    }) => UserActivity(
      startTime: startTime,
      endTime: endTime,
      games: games,
      followInNb: followInNb,
      followOutNb: followOutNb,
      tournamentNb: tournamentNb,
      bestTournament: bestTournament,
      puzzles: puzzles,
      streak: streak,
      storm: storm,
      correspondenceEnds: correspondenceEnds,
      correspondenceMovesNb: correspondenceMovesNb,
      correspondenceGamesNb: correspondenceGamesNb,
    );

    test('is empty when no activity is reported', () {
      final activity = build();

      expect(activity.isEmpty, isTrue);
      expect(activity.isNotEmpty, isFalse);
    });

    test('is not empty when games are reported', () {
      final activity = build(games: IMap(const {Perf.blitz: score}));

      expect(activity.isEmpty, isFalse);
      expect(activity.isNotEmpty, isTrue);
    });

    test('is not empty when followed users are reported', () {
      final activity = build(followInNb: 1);

      expect(activity.isEmpty, isFalse);
      expect(activity.isNotEmpty, isTrue);
    });

    test('is not empty when following users are reported', () {
      final activity = build(followOutNb: 1);

      expect(activity.isEmpty, isFalse);
      expect(activity.isNotEmpty, isTrue);
    });

    test('is not empty when a tournament count is reported', () {
      final activity = build(tournamentNb: 1);

      expect(activity.isEmpty, isFalse);
      expect(activity.isNotEmpty, isTrue);
    });

    test('is not empty when the best tournament is reported', () {
      final activity = build(
        bestTournament: const UserActivityTournament(
          id: 'tour1',
          name: 'Some cup',
          nbGames: 10,
          score: 42,
          rank: 3,
          rankPercent: 12,
        ),
      );

      expect(activity.isEmpty, isFalse);
      expect(activity.isNotEmpty, isTrue);
    });

    test('is not empty when puzzles are reported', () {
      final activity = build(puzzles: score);

      expect(activity.isEmpty, isFalse);
      expect(activity.isNotEmpty, isTrue);
    });

    test('is not empty when the streak is reported', () {
      final activity = build(streak: const UserActivityStreak(runs: 5, score: 12));

      expect(activity.isEmpty, isFalse);
      expect(activity.isNotEmpty, isTrue);
    });

    test('is not empty when the storm is reported', () {
      final activity = build(storm: const UserActivityStreak(runs: 5, score: 12));

      expect(activity.isEmpty, isFalse);
      expect(activity.isNotEmpty, isTrue);
    });

    test('is not empty when the correspondence ends are reported', () {
      final activity = build(correspondenceEnds: IMap(const {Perf.correspondence: score}));

      expect(activity.isEmpty, isFalse);
      expect(activity.isNotEmpty, isTrue);
    });

    test('is not empty when the correspondence move count is reported', () {
      final activity = build(correspondenceMovesNb: 3);

      expect(activity.isEmpty, isFalse);
      expect(activity.isNotEmpty, isTrue);
    });

    test('is not empty when the correspondence game count is reported', () {
      final activity = build(correspondenceGamesNb: 3);

      expect(activity.isEmpty, isFalse);
      expect(activity.isNotEmpty, isTrue);
    });
  });

  group('UserStreak', () {
    test('a game streak keeps the number of games played', () {
      const streak = UserStreak.gameStreak(
        gamesPlayed: 5,
        isValueEmpty: false,
        startGame: null,
        endGame: null,
      );

      expect(streak, isA<UserGameStreak>());
      expect((streak as UserGameStreak).gamesPlayed, 5);
      expect(streak.isValueEmpty, isFalse);
    });

    test('a time streak keeps the time played', () {
      const streak = UserStreak.timeStreak(
        timePlayed: Duration(minutes: 30),
        isValueEmpty: true,
        startGame: null,
        endGame: null,
      );

      expect(streak, isA<UserTimeStreak>());
      expect((streak as UserTimeStreak).timePlayed, const Duration(minutes: 30));
      expect(streak.isValueEmpty, isTrue);
    });
  });

  group('UserPerfGame', () {
    UserPerfGame build({
      int? opponentRating,
      String? opponentId,
      String? opponentName,
      String? opponentTitle,
    }) => UserPerfGame(
      finishedAt: DateTime.utc(2023, 4, 18),
      gameId: const GameId('abcd1234'),
      opponentRating: opponentRating,
      opponentId: opponentId,
      opponentName: opponentName,
      opponentTitle: opponentTitle,
    );

    test('builds the opponent from the id, the name and the title', () {
      final game = build(
        opponentRating: 1500,
        opponentId: 'abc',
        opponentName: testUsername,
        opponentTitle: 'GM',
      );

      expect(game.opponent, const LightUser(id: testUserId, name: testUsername, title: 'GM'));
    });

    test('has no opponent without an opponent id', () {
      expect(build(opponentName: testUsername).opponent, isNull);
    });

    test('has no opponent without an opponent name', () {
      expect(build(opponentId: 'abc').opponent, isNull);
    });

    test('has no opponent for a game without one', () {
      expect(build().opponent, isNull);
    });
  });

  group('Crosstable', () {
    test('reads the number of games and the scores of the users', () {
      final crosstable = Crosstable.fromJson(<String, dynamic>{
        'nbGames': 4,
        'users': <String, dynamic>{'alice': 2.5, 'bob': 1.5},
      });

      expect(crosstable.nbGames, 4);
      expect(crosstable.users.length, 2);
      expect(crosstable.users[const UserId('alice')], 2.5);
      expect(crosstable.users[const UserId('bob')], 1.5);
      expect(crosstable.matchup, isNull);
    });

    test('reads the matchup when the server sends one', () {
      final crosstable = Crosstable.fromJson(<String, dynamic>{
        'nbGames': 4,
        'users': <String, dynamic>{'alice': 2.5},
        'matchup': <String, dynamic>{
          'nbGames': 2,
          'users': <String, dynamic>{'alice': 1.0},
        },
      });

      expect(crosstable.matchup?.nbGames, 2);
      expect(crosstable.matchup?.users[const UserId('alice')], 1.0);
    });
  });

  group('UserRatingHistory', () {
    test('keeps the perf and the points', () {
      final point = UserRatingHistoryPoint(date: DateTime.utc(2023, 1, 1), elo: 1500);
      final history = UserRatingHistoryPerf(perf: Perf.blitz, points: IList([point]));

      expect(history.perf, Perf.blitz);
      expect(history.points.length, 1);
      expect(history.points.first.date, DateTime.utc(2023, 1, 1));
      expect(history.points.first.elo, 1500);
    });
  });
}
