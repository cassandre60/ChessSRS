import 'package:chess_srs/src/constants.dart';
import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/model/auth/auth_user.dart';
import 'package:chess_srs/src/model/common/perf.dart';
import 'package:chess_srs/src/model/user/user.dart';
import 'package:chess_srs/src/network/http.dart';
import 'package:chess_srs/src/view/user/game_history_screen.dart';
import 'package:chess_srs/src/view/user/perf_stats_screen.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

import '../../model/auth/fake_auth_repository.dart';
import '../../test_helpers.dart';
import '../../test_provider_scope.dart';

final client = MockClient((request) {
  if (request.url.path == '/api/user/${fakeUser.id}/perf/${testPerf.name}') {
    return mockResponse(userPerfStatsResponse, 200);
  }
  if (request.url.path == '/api/user/${fakeUser.id}/rating-history') {
    return mockResponse(userRatingHistoryResponse, 200);
  }
  return mockResponse('', 404);
});

final zeroGamesClient = MockClient((request) {
  if (request.url.path == '/api/user/${fakeUser.id}/perf/${testPerf.name}') {
    return mockResponse(userPerfStatsZeroGamesResponse, 200);
  }
  if (request.url.path == '/api/user/${fakeUser.id}/rating-history') {
    return mockResponse('[]', 200);
  }
  return mockResponse('', 404);
});

/// The same perf stats, but with a rating history the chart can actually draw:
/// three rapid points spread over a year.
final chartClient = MockClient((request) {
  if (request.url.path == '/api/user/${fakeUser.id}/perf/${testPerf.name}') {
    return mockResponse(userPerfStatsResponse, 200);
  }
  if (request.url.path == '/api/user/${fakeUser.id}/rating-history') {
    return mockResponse(userRatingHistoryWithPointsResponse, 200);
  }
  return mockResponse('', 404);
});

/// The same, but with a single rapid point: one point is not a history.
final onePointHistoryClient = MockClient((request) {
  if (request.url.path == '/api/user/${fakeUser.id}/perf/${testPerf.name}') {
    return mockResponse(userPerfStatsResponse, 200);
  }
  if (request.url.path == '/api/user/${fakeUser.id}/rating-history') {
    return mockResponse(userRatingHistoryOnePointResponse, 200);
  }
  return mockResponse('', 404);
});

/// The same stats, but with a win streak that is still running.
final openStreakClient = MockClient((request) {
  if (request.url.path == '/api/user/${fakeUser.id}/perf/${testPerf.name}') {
    return mockResponse(userPerfStatsOpenStreakResponse, 200);
  }
  if (request.url.path == '/api/user/${fakeUser.id}/rating-history') {
    return mockResponse('[]', 200);
  }
  return mockResponse('', 404);
});

/// A user with a blitz perf that has games behind it and a settled rating: the
/// perf switcher has something to offer.
final userWithGamesPerfs = User(
  id: fakeUser.id,
  username: fakeUser.username,
  perfs: IMap(const {
    Perf.blitz: UserPerf(rating: 1500, ratingDeviation: 10, progression: 0, games: 5),
  }),
);

/// The same, but the only candidate sits exactly on the deviation threshold:
/// a rating that is not yet settled is not worth switching to.
final userAtDeviationThresholdPerfs = User(
  id: fakeUser.id,
  username: fakeUser.username,
  perfs: IMap(const {
    Perf.blitz: UserPerf(
      rating: 1500,
      ratingDeviation: kClueLessDeviation,
      progression: 0,
      games: 5,
    ),
  }),
);

/// The signed-in viewer, on the same account as the profile being shown.
final signedInViewer = AuthUser(
  token: 'testToken',
  user: LightUser(id: fakeUser.id, name: fakeUser.username),
);

void main() {
  group('PerfStatsScreen', () {
    testWidgets('meets accessibility guidelines', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();

      final app = await makeTestProviderScopeApp(
        tester,
        home: PerfStatsScreen(user: fakeUser, perf: testPerf),
        overrides: {
          lichessClientProvider: lichessClientProvider.overrideWith((ref) {
            return LichessClient(client, ref);
          }),
        },
      );

      await tester.pumpWidget(app);

      // wait for auth state and perf stats
      await tester.pump(const Duration(milliseconds: 50));

      await meetsTapTargetGuideline(tester);
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      if (debugDefaultTargetPlatformOverride == TargetPlatform.android) {
        await expectLater(tester, meetsGuideline(textContrastGuideline));
      }
      handle.dispose();
    }, variant: kPlatformVariant);

    testWidgets('screen loads, required stats are shown', (WidgetTester tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: PerfStatsScreen(user: fakeUser, perf: testPerf),
        overrides: {
          lichessClientProvider: lichessClientProvider.overrideWith((ref) {
            return LichessClient(client, ref);
          }),
        },
      );

      await tester.pumpWidget(app);

      // wait for auth state and perf stats
      await tester.pump(const Duration(milliseconds: 50));

      final requiredStatsValues = [
        '50.24', // Deviation
        '20', // Progression in last 12 games
        '0', // Berserked games
        '0', // Tournament games
        '3', // Rated games
        '2', // Won games
        '2', // Lost games
        '1', // Drawn games
        '1', // Disconnections
      ];

      // rating
      expect(find.text('1500'), findsOneWidget);

      for (final val in requiredStatsValues) {
        expect(find.widgetWithText(Card, val), findsAtLeastNWidgets(1));
      }
    }, variant: kPlatformVariant);

    testWidgets('a perf with zero games does not crash the stat columns', (
      WidgetTester tester,
    ) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: PerfStatsScreen(user: fakeUser, perf: testPerf),
        overrides: {
          lichessClientProvider: lichessClientProvider.overrideWith((ref) {
            return LichessClient(zeroGamesClient, ref);
          }),
        },
      );

      await tester.pumpWidget(app);

      // wait for auth state and perf stats
      await tester.pump(const Duration(milliseconds: 50));

      expect(tester.takeException(), isNull);
      expect(find.byType(ErrorWidget), findsNothing);
      expect(find.text('0%'), findsWidgets);
    }, variant: kPlatformVariant);
  });

  group('PerfStatsScreen details', () {
    testWidgets('the rank is spelled out, not left as the unknown marker', (
      WidgetTester tester,
    ) async {
      await pumpPerfStats(tester, client: client);

      // SPEC INV-062. The rank is one of the numbers this screen exists to
      // show, so it is shown as a number and never as the "unknown" marker.
      final rankCard = find.ancestor(of: find.text('Rank'), matching: find.byType(Card)).first;
      final values = tester
          .widgetList<Text>(find.descendant(of: rankCard, matching: find.byType(Text)))
          .map((t) => t.data)
          .whereType<String>()
          .where((data) => data != 'Rank')
          .toList();
      expect(values, hasLength(1));
      // The fixture's rank is 1000; the separator is the locale's, the digits
      // are not.
      expect(values.single.replaceAll(RegExp('[^0-9]'), ''), '1000');
    }, variant: kPlatformVariant);

    testWidgets('the percentile line names the profile owner when signed out', (
      WidgetTester tester,
    ) async {
      await pumpPerfStats(tester, client: client);

      // SPEC INV-061. The standing line is read by the player it names.
      expect(find.text('test is better than 50.00% of Rapid players.'), findsOneWidget);
    }, variant: kPlatformVariant);

    testWidgets('the percentile line addresses the viewer as "you" when signed in', (
      WidgetTester tester,
    ) async {
      await pumpPerfStats(tester, client: client, authUser: signedInViewer);

      // SPEC INV-061. The standing line addresses the viewer as "you" when the
      // profile on screen is the viewer's own.
      expect(find.text('You are better than 50.00% of Rapid players.'), findsOneWidget);
    }, variant: kPlatformVariant);

    testWidgets('the best rated victories are listed with the games they were won in', (
      WidgetTester tester,
    ) async {
      await pumpPerfStats(tester, client: client);
      await scrollToTheEnd(tester);

      // SPEC INV-062. The list of best wins is the screen's payoff, so it is
      // present and each entry says when the game was played.
      expect(find.text('Best rated victories'), findsOneWidget);
      expect(find.text('testOpponentName'), findsWidgets);
      expect(find.text('Jan 10, 2023'), findsOneWidget);
    }, variant: kPlatformVariant);

    testWidgets('the highest and the lowest rating are shown with their game', (
      WidgetTester tester,
    ) async {
      await pumpPerfStats(tester, client: client);

      // SPEC INV-062. The rating extremes are the numbers a player checks
      // first, and the game they were played in dates them.
      expect(find.text('1515'), findsOneWidget);
      expect(find.text('1336'), findsOneWidget);
      expect(find.text('Jan 20, 2023'), findsWidgets);
      expect(find.text('Nov 26, 2022'), findsOneWidget);
    }, variant: kPlatformVariant);

    testWidgets('the longest streak is the left column and the current one the right', (
      WidgetTester tester,
    ) async {
      await pumpPerfStats(tester, client: client);

      // SPEC INV-062. The two streak columns are read side by side, so the
      // longest streak has to be the one on the left, with its value under it.
      final longest = tester.getTopLeft(find.text('Longest streak ').first).dx;
      final current = tester.getTopLeft(find.text('Current streak ').first).dx;
      final threeGames = tester.getTopLeft(find.text('3 games').first).dx;
      expect(longest, lessThan(current));
      // The longest losing streak is 3 games.
      expect(longest, lessThan(threeGames));
      expect(threeGames, lessThan(current));
    }, variant: kPlatformVariant);

    testWidgets('a streak shows the games it spans', (WidgetTester tester) async {
      await pumpPerfStats(tester, client: client);

      // SPEC INV-062. A streak is only meaningful with the games it spans, so
      // the arrow between the start and the end game is drawn.
      expect(find.byIcon(Icons.arrow_downward_rounded), findsWidgets);
      expect(find.text('Jan 11, 2023'), findsWidgets);
    }, variant: kPlatformVariant);

    testWidgets('a streak with no end game shows no span', (WidgetTester tester) async {
      await pumpPerfStats(tester, client: openStreakClient);

      // SPEC INV-062. A streak that is still running has a start but no end,
      // so there is no span to draw.
      expect(find.byIcon(Icons.arrow_downward_rounded), findsNothing);
      expect(find.text('Jan 12, 2023'), findsNothing);
    }, variant: kPlatformVariant);

    testWidgets('every percentage is over the total number of games', (WidgetTester tester) async {
      await pumpPerfStats(tester, client: client);

      // SPEC INV-061. The percentages are the readable form of the counts, so
      // each one is that count over the total number of games.
      expect(statValue(tester, 'Wins'), '40%');
      expect(statValue(tester, 'Draws'), '20%');
      expect(statValue(tester, 'Losses'), '40%');
      expect(statValue(tester, 'Rated'), '60%');
      expect(statValue(tester, 'Tournament'), '0%');
      expect(statValue(tester, 'Berserked'), '0%');
      expect(statValue(tester, 'Disconnections'), '20%');
    }, variant: kPlatformVariant);

    testWidgets('the progression card says what it measures', (WidgetTester tester) async {
      final handle = tester.ensureSemantics();
      await pumpPerfStats(tester, client: client);

      // SPEC INV-062. The progression is over the last twelve games, and it
      // carries the rating change over those games.
      final node = find.bySemanticsLabel(RegExp('Progression over the last'));
      expect(node, findsAtLeastNWidgets(1));
      expect(
        tester.getSemantics(node.first).getSemanticsData().label,
        matches(RegExp(r'last 12 games\s*\n20')),
      );
      handle.dispose();
    }, variant: kPlatformVariant);

    testWidgets('the average opponent and the time played are spelled out', (
      WidgetTester tester,
    ) async {
      await pumpPerfStats(tester, client: client);

      // SPEC INV-062. The average opponent is a rating, rounded; the time
      // played is a duration a player can read.
      expect(statValue(tester, 'Average opponent'), '1401');
      expect(statValue(tester, 'Time spent playing'), '16 minutes');
    }, variant: kPlatformVariant);

    testWidgets('only the draws percentage is the shaded one', (WidgetTester tester) async {
      await pumpPerfStats(tester, client: client);

      // SPEC INV-061. One card per row, one of them shaded: the draws are the
      // muted one, the rest stay legible.
      final wins = statValueColour(tester, 'Wins');
      final draws = statValueColour(tester, 'Draws');
      expect(draws.a, closeTo(wins.a / 2, 0.0001));
    }, variant: kPlatformVariant);

    testWidgets('the perf switcher is offered when another perf has games', (
      WidgetTester tester,
    ) async {
      await pumpPerfStats(tester, client: client, user: userWithGamesPerfs);

      // SPEC INV-062. The switcher is the one control that navigates, so it
      // has to be live when there is somewhere to go.
      final button = tester.widget<SrsIconButton>(find.byType(SrsIconButton));
      expect(button.onPressed, isNotNull);
    }, variant: kPlatformVariant);

    testWidgets('the perf switcher is not offered for an unsettled rating', (
      WidgetTester tester,
    ) async {
      await pumpPerfStats(tester, client: client, user: userAtDeviationThresholdPerfs);

      // SPEC INV-062. A rating whose deviation sits on the threshold is not
      // settled yet, so there is no second perf to switch to.
      final button = tester.widget<SrsIconButton>(find.byType(SrsIconButton));
      expect(button.onPressed, isNull);
    }, variant: kPlatformVariant);

    testWidgets('the rating chart is drawn for the perf being shown', (WidgetTester tester) async {
      await pumpPerfStats(tester, client: chartClient);

      // SPEC INV-062. The chart is the history of the perf on screen, not of
      // some other perf the account also plays.
      expect(find.byType(LineChart), findsOneWidget);
    }, variant: kPlatformVariant);

    testWidgets('a single rating history point draws no chart', (WidgetTester tester) async {
      await pumpPerfStats(tester, client: onePointHistoryClient);

      // SPEC INV-062. One point is not a history, so there is no chart to draw.
      expect(find.byType(LineChart), findsNothing);
    }, variant: kPlatformVariant);

    testWidgets('the chart plots the rating history of the selected window', (
      WidgetTester tester,
    ) async {
      await pumpPerfStats(tester, client: chartClient);

      final data = tester.widget<LineChart>(find.byType(LineChart)).data;

      // SPEC INV-062. The chart shows the selected window of the history: the
      // three months that end on the last point, at the ratings it carries.
      final firstDate = DateTime.utc(2022, 1, 1);
      final lastDate = DateTime.utc(2023, 1, 10);
      final windowStart = DateTime.utc(2022, 10, 10);
      expect(data.minX, windowStart.difference(firstDate).inDays.toDouble());
      expect(data.maxX, lastDate.difference(firstDate).inDays.toDouble());
      // The lowest plotted rating is the July point the window carries, and
      // the highest is the last point.
      expect(data.minY, 1400.0);
      expect(data.maxY, 1500.0);

      final spots = data.lineBarsData.first.spots;
      expect(spots.length, data.maxX.toInt() - data.minX.toInt() + 1);
      expect(spots.first.x, data.minX);
      expect(spots.last.x, data.maxX);
    }, variant: kPlatformVariant);

    testWidgets('every window the history spans is offered', (WidgetTester tester) async {
      await pumpPerfStats(tester, client: chartClient);

      // SPEC INV-062. The history spans a year, so every window over it is
      // offered to the player.
      for (final label in ['1W', '1M', '3M', '1Y', 'ALL']) {
        expect(find.text(label), findsOneWidget);
      }
    }, variant: kPlatformVariant);

    testWidgets('the selected window is the one that is highlighted', (WidgetTester tester) async {
      await pumpPerfStats(tester, client: chartClient);

      // SPEC INV-062. The player has to be able to see which window the chart
      // is showing.
      expect(rangeButtonColour(tester, '3M'), isNotNull);
      for (final label in ['1W', '1M', '1Y', 'ALL']) {
        expect(rangeButtonColour(tester, label), isNull);
      }
    }, variant: kPlatformVariant);

    testWidgets('choosing a window moves the chart to that window', (WidgetTester tester) async {
      await pumpPerfStats(tester, client: chartClient);

      // SPEC INV-062. The range buttons are the controls over the chart, so
      // choosing one moves the chart to the window it names.
      final firstDate = DateTime.utc(2022, 1, 1);
      await tester.tap(find.text('1M'));
      await settle(tester);
      expect(
        tester.widget<LineChart>(find.byType(LineChart)).data.minX,
        DateTime.utc(2022, 12, 10).difference(firstDate).inDays.toDouble(),
      );

      await tester.tap(find.text('1Y'));
      await settle(tester);
      expect(
        tester.widget<LineChart>(find.byType(LineChart)).data.minX,
        DateTime.utc(2022, 1, 10).difference(firstDate).inDays.toDouble(),
      );
    }, variant: kPlatformVariant);

    testWidgets('the chart keeps its axes and its decorations', (WidgetTester tester) async {
      await pumpPerfStats(tester, client: chartClient);

      final data = tester.widget<LineChart>(find.byType(LineChart)).data;
      final bar = data.lineBarsData.first;

      // SPEC INV-062. The chart is only readable if it keeps the frame, the
      // grid and the axis labels it draws itself.
      expect(bar.dotData.show, isFalse);
      expect(bar.belowBarData.show, isTrue);
      expect(data.borderData.show, isTrue);
      expect(data.gridData.show, isTrue);
      expect(data.gridData.drawVerticalLine, isFalse);
      expect(data.lineTouchData.touchTooltipData.fitInsideHorizontally, isTrue);
      expect(data.lineTouchData.touchTooltipData.fitInsideVertically, isTrue);
      expect(data.titlesData.rightTitles.sideTitles.showTitles, isFalse);
      expect(data.titlesData.topTitles.sideTitles.showTitles, isFalse);
      expect(data.titlesData.bottomTitles.sideTitles.showTitles, isTrue);
      expect(data.titlesData.leftTitles.sideTitles.showTitles, isTrue);

      final indicator = data.lineTouchData.getTouchedSpotIndicator;
      expect(indicator(bar, [0]).single!.touchedSpotDotData.show, isTrue);
    }, variant: kPlatformVariant);

    testWidgets('the chart hides the labels at both ends of the axis', (WidgetTester tester) async {
      await pumpPerfStats(tester, client: chartClient);

      // SPEC INV-062. The two end labels would sit on top of the axis frame,
      // so the interior ones are the ones that are drawn.
      final bottom = find.byWidgetPredicate(
        (w) => w is SideTitleWidget && w.meta.axisSide == AxisSide.bottom,
      );
      expect(bottom, findsNWidgets(3));
    }, variant: kPlatformVariant);

    testWidgets('the view games row is announced as a button', (WidgetTester tester) async {
      final handle = tester.ensureSemantics();
      await pumpPerfStats(tester, client: client);

      // SPEC INV-062. The row navigates, so it is announced as a button, and
      // its name is said once.
      final node = find.bySemanticsLabel(RegExp('View the games'));
      expect(node, findsOneWidget);
      final data = tester.getSemantics(node.first).getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.flagsCollection.isEnabled.toBoolOrNull(), isTrue);
      expect(data.label.split('View the games').length - 1, 1);
      handle.dispose();
    }, variant: kPlatformVariant);

    testWidgets('the total games row opens the online game history for this perf', (
      WidgetTester tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpPerfStats(tester, client: client);

      // SPEC INV-062. The row says how many games there are, and leads to the
      // games of this perf, on the server.
      final node = find.bySemanticsLabel(RegExp('Total games'));
      expect(node, findsAtLeastNWidgets(1));
      expect(
        tester.getSemantics(node.first).getSemanticsData().label,
        matches(RegExp(r'Total games\s*\n5')),
      );

      await tester.tap(find.textContaining('Total games').first);
      await settle(tester);

      final history = find.byType(GameHistoryScreen);
      expect(history, findsOneWidget);
      final screen = tester.widget<GameHistoryScreen>(history.first);
      expect(screen.isOnline, isTrue);
      expect(screen.gameFilter.perfs, ISet<Perf>(const {testPerf}));
      handle.dispose();
    }, variant: kPlatformVariant);
  });
}

/// Pumps the perf stats screen and lets the data land.
///
/// The wait is a bounded number of frames rather than an unbounded settle:
/// the loading spinner is an endless animation, so settling on it would hang.
Future<void> pumpPerfStats(
  WidgetTester tester, {
  required MockClient client,
  User? user,
  AuthUser? authUser,
}) async {
  final app = await makeTestProviderScopeApp(
    tester,
    home: PerfStatsScreen(user: user ?? fakeUser, perf: testPerf),
    authUser: authUser,
    overrides: {
      lichessClientProvider: lichessClientProvider.overrideWith((ref) {
        return LichessClient(client, ref);
      }),
    },
  );

  await tester.pumpWidget(app);
  await tester.pump(const Duration(milliseconds: 50));
  await settle(tester);
}

/// Advances the clock by a bounded number of frames.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Scrolls the stats list to its end, so the last section is built.
Future<void> scrollToTheEnd(WidgetTester tester) async {
  await tester.drag(find.byType(ListView), const Offset(0, -3000));
  await settle(tester);
}

/// The value shown by the stat card titled [stat].
String statValue(WidgetTester tester, String stat) {
  final card = find.ancestor(of: find.text(stat), matching: find.byType(Card)).first;
  final texts = tester
      .widgetList<Text>(find.descendant(of: card, matching: find.byType(Text)))
      .map((t) => t.data)
      .whereType<String>()
      .toList();
  return texts.last;
}

/// The colour of the value shown by the stat card titled [stat].
Color statValueColour(WidgetTester tester, String stat) {
  final card = find.ancestor(of: find.text(stat), matching: find.byType(Card)).first;
  final texts = tester
      .widgetList<Text>(find.descendant(of: card, matching: find.byType(Text)))
      .toList();
  return texts.last.style!.color!;
}

/// The colour of the range button labelled [label]: null when it is not the
/// selected window.
Color? rangeButtonColour(WidgetTester tester, String label) {
  final card = find.ancestor(of: find.text(label), matching: find.byType(Card)).first;
  return tester.widget<Card>(card).color;
}

const testPerf = Perf.rapid;
final userPerfStatsZeroGamesResponse =
    '''
{
  "user": { "name": "${fakeUser.username}" },
  "perf": {
    "glicko": { "rating": 1837.0, "deviation": 215.18, "provisional": true },
    "nb": 0,
    "progress": 40
  },
  "rank": null,
  "percentile": null,
  "stat": {
    "count": {
      "berserk": 0, "win": 0, "all": 0, "seconds": 0,
      "opAvg": null, "draw": 0, "tour": 0, "disconnects": 0,
      "rated": 0, "loss": 0
    },
    "resultStreak": {
      "win": { "cur": {"v": 0}, "max": {"v": 0} },
      "loss": { "cur": {"v": 0}, "max": {"v": 0} }
    },
    "playStreak": {
      "nb": { "cur": {"v": 0}, "max": {"v": 0} },
      "time": { "cur": {"v": 0}, "max": {"v": 0} }
    },
    "worstLosses": { "results": [] },
    "bestWins": { "results": [] }
  }
}
''';
final userPerfStatsResponse =
    '''
{
  "user": {
    "name": "testOpponentName"
  },
  "perf": {
    "glicko": {
      "rating": 1500.42,
      "deviation": 50.24,
      "provisional": false
    },
    "nb": 5,
    "progress": 20
  },
  "rank": 1000,
  "percentile": 50.0,
  "stat": {
    "count": {
      "berserk": 0,
      "win": 2,
      "all": 5,
      "seconds": 1000,
      "opAvg": 1400.63,
      "draw": 1,
      "tour": 0,
      "disconnects": 1,
      "rated": 3,
      "loss": 2
    },
    "resultStreak": {
      "win": {
        "cur": {
          "v": 9,
          "from": {
            "at": "2023-01-12T03:36:37.842Z",
            "gameId": "ABcDeFgH"
          },
          "to": {
            "at": "2023-01-20T16:25:56.430Z",
            "gameId": "ABcDeFgH"
          }
        },
        "max": {
          "v": 9,
          "from": {
            "at": "2023-01-12T03:36:37.842Z",
            "gameId": "ABcDeFgH"
          },
          "to": {
            "at": "2023-01-20T16:25:56.430Z",
            "gameId": "ABcDeFgH"
          }
        }
      },
      "loss": {
        "cur": {
          "v": 0
        },
        "max": {
          "v": 3,
          "from": {
            "at": "2023-01-11T05:57:14.547Z",
            "gameId": "ABcDeFgH"
          },
          "to": {
            "at": "2023-01-11T06:52:05.350Z",
            "gameId": "ABcDeFgH"
          }
        }
      }
    },
    "lowest": {
      "int": 1336,
      "at": "2022-11-26T20:09:57.711Z",
      "gameId": "ABcDeFgH"
    },
    "_id": "danteculaciati/6",
    "worstLosses": {
      "results": [
        {
          "opRating": 1300,
          "opId": {
            "id": "testOpponent",
            "name": "testOpponentName",
            "title": null
          },
          "at": "2022-12-22T06:08:21.870Z",
          "gameId": "ABcDeFgH"
        },
        {
          "opRating": 1303,
          "opId": {
            "id": "testOpponent",
            "name": "testOpponentName",
            "title": null
          },
          "at": "2022-11-09T13:54:12.015Z",
          "gameId": "ABcDeFgH"
        },
        {
          "opRating": 1309,
          "opId": {
            "id": "testOpponent",
            "name": "testOpponentName",
            "title": null
          },
          "at": "2022-11-18T03:12:53.063Z",
          "gameId": "ABcDeFgH"
        },
        {
          "opRating": 1310,
          "opId": {
            "id": "testOpponent",
            "name": "testOpponentName",
            "title": null
          },
          "at": "2022-11-26T20:09:57.711Z",
          "gameId": "ABcDeFgH"
        },
        {
          "opRating": 1321,
          "opId": {
            "id": "testOpponent",
            "name": "testOpponentName",
            "title": null
          },
          "at": "2023-01-04T22:14:53.251Z",
          "gameId": "ABcDeFgH"
        }
      ]
    },
    "perfType": {
      "key": "rapid",
      "name": "testOpponentName"
    },
    "bestWins": {
      "results": [
        {
          "opRating": 1553,
          "opId": {
            "id": "testOpponent",
            "name": "testOpponentName",
            "title": null
          },
          "at": "2023-01-12T04:40:28.644Z",
          "gameId": "ABcDeFgH"
        },
        {
          "opRating": 1532,
          "opId": {
            "id": "testOpponent",
            "name": "testOpponentName",
            "title": null
          },
          "at": "2023-01-10T07:24:30.636Z",
          "gameId": "ABcDeFgH"
        },
        {
          "opRating": 1509,
          "opId": {
            "id": "testOpponent",
            "name": "testOpponentName",
            "title": null
          },
          "at": "2023-01-12T05:10:05.648Z",
          "gameId": "ABcDeFgH"
        },
        {
          "opRating": 1496,
          "opId": {
            "id": "testOpponent",
            "name": "testOpponentName",
            "title": null
          },
          "at": "2023-01-08T20:48:46.087Z",
          "gameId": "ABcDeFgH"
        },
        {
          "opRating": 1496,
          "opId": {
            "id": "testOpponent",
            "name": "testOpponentName",
            "title": null
          },
          "at": "2023-01-12T03:51:59.617Z",
          "gameId": "ABcDeFgH"
        }
      ]
    },
    "userId": {
      "id": "${fakeUser.id}",
      "name": "${fakeUser.username}",
      "title": null
    },
    "playStreak": {
      "nb": {
        "cur": {
          "v": 0
        },
        "max": {
          "v": 7,
          "from": {
            "at": "2023-01-12T03:28:45.629Z",
            "gameId": "ABcDeFgH"
          },
          "to": {
            "at": "2023-01-12T05:10:05.648Z",
            "gameId": "ABcDeFgH"
          }
        }
      },
      "time": {
        "cur": {
          "v": 0
        },
        "max": {
          "v": 5237,
          "from": {
            "at": "2023-01-11T05:37:11.306Z",
            "gameId": "ABcDeFgH"
          },
          "to": {
            "at": "2023-01-11T07:23:22.095Z",
            "gameId": "ABcDeFgH"
          }
        }
      },
      "lastDate": "2023-01-20T16:25:56.430Z"
    },
    "highest": {
      "int": 1515,
      "at": "2023-01-20T16:25:56.430Z",
      "gameId": "ABcDeFgH"
    }
  }
}
''';

/// A rating history the chart can draw: three rapid points spread over a
/// year, from 2022-01-01 to 2023-01-10.
///
/// The months are zero-based, as the API sends them.
const userRatingHistoryWithPointsResponse = '''
[
  {
    "name": "Bullet",
    "points": [
      [
        2016,
        0,
        2,
        2617
      ]
    ]
  },
  {
    "name": "Rapid",
    "points": [
      [
        2022,
        0,
        1,
        1400
      ],
      [
        2022,
        6,
        1,
        1450
      ],
      [
        2023,
        0,
        10,
        1500
      ]
    ]
  }
]
''';

/// The same, but with a single rapid point: one point is not a history.
const userRatingHistoryOnePointResponse = '''
[
  {
    "name": "Bullet",
    "points": [
      [
        2016,
        0,
        2,
        2617
      ]
    ]
  },
  {
    "name": "Rapid",
    "points": [
      [
        2023,
        0,
        10,
        1500
      ]
    ]
  }
]
''';

/// Stats whose win streak has a start game but no end game: a streak that is
/// still running.
const userPerfStatsOpenStreakResponse = '''
{
  "perf": {
    "glicko": { "rating": 1500.42, "deviation": 50.24, "provisional": false },
    "nb": 5,
    "progress": 20
  },
  "rank": null,
  "percentile": null,
  "stat": {
    "count": {
      "berserk": 0, "win": 2, "all": 5, "seconds": 1000,
      "opAvg": 1400.63, "draw": 1, "tour": 0, "disconnects": 1,
      "rated": 3, "loss": 2
    },
    "resultStreak": {
      "win": {
        "cur": {
          "v": 3,
          "from": { "at": "2023-01-12T03:28:45.629Z", "gameId": "ABcDeFgH" }
        },
        "max": {
          "v": 3,
          "from": { "at": "2023-01-12T03:28:45.629Z", "gameId": "ABcDeFgH" }
        }
      },
      "loss": { "cur": { "v": 0 }, "max": { "v": 0 } }
    },
    "playStreak": {
      "nb": { "cur": { "v": 0 }, "max": { "v": 0 } },
      "time": { "cur": { "v": 0 }, "max": { "v": 0 } }
    },
    "worstLosses": { "results": [] },
    "bestWins": { "results": [] }
  }
}
''';

const userRatingHistoryResponse = '''
[
  {
    "name": "Bullet",
    "points": [
      [
        2016,
        0,
        2,
        2617
      ]
    ]
  },
  {
    "name": "Blitz",
    "points": []
  },
  {
    "name": "Rapid",
    "points": []
  },
  {
    "name": "Classical",
    "points": []
  },
  {
    "name": "Correspondence",
    "points": []
  },
  {
    "name": "Chess960",
    "points": []
  },
  {
    "name": "King of the Hill",
    "points": []
  },
  {
    "name": "Three-check",
    "points": []
  },
  {
    "name": "Antichess",
    "points": []
  },
  {
    "name": "Atomic",
    "points": []
  },
  {
    "name": "Horde",
    "points": []
  },
  {
    "name": "Racing Kings",
    "points": []
  },
  {
    "name": "Crazyhouse",
    "points": []
  },
  {
    "name": "Puzzles",
    "points": []
  },
  {
    "name": "UltraBullet",
    "points": []
  }
]
''';
