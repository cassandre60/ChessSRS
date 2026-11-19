// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/model/common/id.dart';
import 'package:chess_srs/src/model/common/speed.dart';
import 'package:chess_srs/src/model/explorer/opening_explorer.dart';
import 'package:chess_srs/src/model/explorer/opening_explorer_preferences.dart';
import 'package:chess_srs/src/model/user/user.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OpeningExplorerPrefs defaults', () {
    test('uses master db with default sub-preferences', () {
      final prefs = OpeningExplorerPrefs.defaults();

      expect(prefs.db, OpeningDatabase.master);
      expect(prefs.masterDb, MasterDb.defaults);
      expect(prefs.masterDb.sinceYear, MasterDb.kEarliestYear);
      expect(prefs.lichessDb, LichessDb.defaults);
      expect(prefs.lichessDb.speeds, LichessDb.kAvailableSpeeds.remove(Speed.ultraBullet));
      expect(prefs.lichessDb.ratings, LichessDb.kAvailableRatings.remove(400));
      expect(prefs.lichessDb.since, LichessDb.earliestDate);

      expect(prefs.playerDb.username, isNull);
      expect(prefs.playerDb.side, Side.white);
      expect(prefs.playerDb.speeds, PlayerDb.kAvailableSpeeds);
      expect(prefs.playerDb.gameModes, GameMode.values.toISet());
      expect(prefs.playerDb.since, PlayerDb.earliestDate);
    });

    test('propagates user name to player db defaults', () {
      const user = LightUser(id: UserId('u1'), name: 'Magnus');
      final prefs = OpeningExplorerPrefs.defaults(user: user);

      expect(prefs.playerDb.username, 'Magnus');
      expect(prefs.playerDb.side, Side.white);
    });
  });

  group('OpeningExplorerPrefs serialization', () {
    test('master db round-trips through json', () {
      const masterDb = MasterDb(sinceYear: 2000);
      expect(MasterDb.fromJson(masterDb.toJson()), masterDb);
    });

    test('lichess db round-trips through json', () {
      final lichessDb = LichessDb(
        speeds: ISet(const {Speed.blitz, Speed.rapid}),
        ratings: ISet(const {1600, 1800}),
        since: DateTime.utc(2020, 1, 1),
      );

      expect(LichessDb.fromJson(lichessDb.toJson()), lichessDb);
    });

    test('player db round-trips through json', () {
      final playerDb = PlayerDb(
        username: 'test-user',
        side: Side.black,
        speeds: ISet(const {Speed.classical}),
        gameModes: ISet(const {GameMode.rated}),
        since: DateTime.utc(2021, 6, 1),
      );

      expect(PlayerDb.fromJson(playerDb.toJson()), playerDb);
      expect(playerDb.toJson(), containsPair('username', 'test-user'));
      expect(playerDb.toJson(), containsPair('side', 'black'));
    });

    test('round-trips default player db through json', () {
      final playerDb = PlayerDb.defaults(
        user: const LightUser(id: UserId('u2'), name: 'Nepo'),
      );

      expect(PlayerDb.fromJson(playerDb.toJson()), playerDb);
      expect(playerDb.username, 'Nepo');
    });
  });

  group('opening explorer db constants', () {
    test('master db date map includes expected labels', () {
      expect(MasterDb.datesMap.keys, contains('All time'));
      expect(MasterDb.datesMap['All time'], MasterDb.kEarliestYear);
      expect(MasterDb.datesMap.length, 4);
    });

    test('lichess db exposes speed, rating and date options', () {
      expect(LichessDb.kAvailableSpeeds, hasLength(6));
      expect(LichessDb.kAvailableRatings, containsAll([400, 2500]));
      expect(LichessDb.datesMap.keys, containsAll(['Last year', 'Last 5 years', 'All time']));
      expect(LichessDb.datesMap['All time'], LichessDb.earliestDate);
    });

    test('player db exposes speed and date options', () {
      expect(PlayerDb.kAvailableSpeeds, hasLength(6));
      expect(PlayerDb.datesMap.keys, contains('This month'));
      expect(PlayerDb.datesMap['All time'], PlayerDb.earliestDate);
    });
  });
}
