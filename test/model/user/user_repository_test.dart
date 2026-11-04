import 'package:chess_srs/src/model/common/id.dart';
import 'package:chess_srs/src/model/common/perf.dart';
import 'package:chess_srs/src/model/user/user.dart';
import 'package:chess_srs/src/model/user/user_repository.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';

import '../../test_container.dart';
import '../../test_helpers.dart';

const testUserId = UserId('test');

void main() {
  group('UserRepository.getUser', () {
    test('json read, minimal example', () async {
      final mockClient = MockClient((request) {
        if (request.url.path == '/api/user/$testUserId') {
          return mockResponse('''
{
  "id": "$testUserId",
  "username": "$testUserId",
  "createdAt": 1290415680000,
  "seenAt": 1290415680000,
  "perfs": {
  }
}
''', 200);
        }
        return mockResponse('', 404);
      });
      final container = await lichessClientContainer(mockClient);

      final repo = container.read(userRepositoryProvider);

      final result = await repo.getUser(testUserId);

      expect(result, isA<User>());
      expect(result.id, testUserId);
    });

    test('json read, full example', () async {
      final mockClient = MockClient((request) {
        if (request.url.path == '/api/user/$testUserId') {
          return mockResponse('''
{
  "id": "$testUserId",
  "username": "$testUserId",
  "createdAt": 1290415680000,
  "seenAt": 1290415680000,
  "title": "GM",
  "patron": true,
  "patronColor": 1,
  "perfs": {
    "blitz": {
      "games": 2340,
      "rating": 1681,
      "rd": 30,
      "prog": 10
    },
    "rapid": {
      "games": 2340,
      "rating": 1677,
      "rd": 30,
      "prog": 10
    },
    "classical": {
      "games": 2340,
      "rating": 1618,
      "rd": 30,
      "prog": 10
    }
  },
  "profile": {
    "country": "France",
    "location": "Lille",
    "bio": "test bio",
    "firstName": "John",
    "lastName": "Doe",
    "fideRating": 1800,
    "links": "http://test.com"
  }
}
''', 200);
        }
        return mockResponse('', 404);
      });
      final container = await lichessClientContainer(mockClient);
      final repo = container.read(userRepositoryProvider);

      final result = await repo.getUser(testUserId);

      expect(result, isA<User>());
      expect(result.id, testUserId);
      expect(result.title, 'GM');
      expect(result.profile?.country, 'France');
    });

    test('getUser does not add the challenge query by default', () async {
      final mockClient = MockClient((request) {
        if (request.url.path == '/api/user/$testUserId' &&
            !request.url.queryParameters.containsKey('challenge')) {
          return mockResponse('''
{
  "id": "$testUserId",
  "username": "$testUserId",
  "createdAt": 1290415680000,
  "seenAt": 1290415680000,
  "perfs": {
  }
}
''', 200);
        }
        return mockResponse('', 404);
      });
      final container = await lichessClientContainer(mockClient);
      final repo = container.read(userRepositoryProvider);

      final result = await repo.getUser(testUserId);

      expect(result, isA<User>());
      expect(result.id, testUserId);
    });
  });

  group('UserRepository.getPerfStats', () {
    const testPerf = Perf.rapid;
    final path = '/api/user/$testUserId/perf/${testPerf.name}';

    test('json read, minimal example', () async {
      final mockClient = MockClient((request) {
        if (request.url.path == path) {
          return mockResponse('''
{
  "user": {
    "name": "$testUserId"
  },
  "perf": {
    "glicko": {
      "rating": 1500,
      "deviation": 50,
      "provisional": false
    },
    "nb": 5,
    "progress": 20
  },
  "stat": {
    "count": {
      "berserk": 0,
      "win": 2,
      "all": 5,
      "seconds": 10000,
      "opAvg": 1500,
      "draw": 1,
      "tour": 0,
      "disconnects": 1,
      "rated": 3,
      "loss": 2
    }
  }
}
''', 200);
        }
        return mockResponse('', 404);
      });

      final container = await lichessClientContainer(mockClient);
      final repo = container.read(userRepositoryProvider);

      final result = await repo.getPerfStats(testUserId, testPerf);

      expect(result, isA<UserPerfStats>());
      expect(result.rating, 1500);
    });

    test('json read, full example', () async {
      final mockClient = MockClient((request) {
        if (request.url.path == path) {
          return mockResponse('''
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
      "id": "$testUserId",
      "name": "$testUserId",
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
''', 200);
        }
        return mockResponse('', 404);
      });

      final container = await lichessClientContainer(mockClient);
      final repo = container.read(userRepositoryProvider);

      final result = await repo.getPerfStats(testUserId, testPerf);

      expect(result, isA<UserPerfStats>());
      expect(result.rating, 1500.42);
      expect(result.bestWins?.length, 5);
      expect(result.worstLosses?.length, 5);
      expect(result.rank, 1000);
    });
  });

  group('UserRepository.getUsersStatuses', () {
    test('json read, minimal example', () async {
      final ids = ISet(const {UserId('maia1'), UserId('maia5'), UserId('maia9')});

      final mockClient = MockClient((request) {
        if (request.url.path == '/api/users/status') {
          return mockResponse('[]', 200);
        }
        return mockResponse('', 404);
      });

      final container = await lichessClientContainer(mockClient);
      final repo = container.read(userRepositoryProvider);
      final result = await repo.getUsersStatuses(ids);

      expect(result, isA<IList<UserStatus>>());
      expect(result.isEmpty, true);
    });

    test('json read, full example', () async {
      final ids = ISet(const {UserId('maia1'), UserId('maia5'), UserId('maia9')});
      final mockClient = MockClient((request) {
        if (request.url.path == '/api/users/status') {
          return mockResponse('''
[
  {
    "id": "maia1",
    "name": "maia1",
    "online": true,
    "playing": true
  },
  {
    "id": "maia5",
    "name": "maia5",
    "online": false
  },
  {
    "id": "maia9",
    "name": "maia9",
    "online": true
  }
]
''', 200);
        }
        return mockResponse('', 404);
      });

      final container = await lichessClientContainer(mockClient);
      final repo = container.read(userRepositoryProvider);
      final result = await repo.getUsersStatuses(ids);

      expect(result, isA<IList<UserStatus>>());
      expect(result.length, 3);
    });
  });

  test('UserRepository.getUserActivity minimal example', () async {
    final mockClient = MockClient((request) {
      if (request.url.path == '/api/user/testUser/activity') {
        return mockResponse(userActivityResponse, 200);
      }
      return mockResponse('', 404);
    });

    final container = await lichessClientContainer(mockClient);
    final repo = container.read(userRepositoryProvider);
    final result = await repo.getActivity(const UserId('testUser'));

    expect(result, isA<IList<UserActivity>>());
    expect(result.length, 7);
  });
}

const userActivityResponse = '''
[{"interval":{"start":1681948800000,"end":1682035200000},"follows":{"in":{"ids":["jc-peru","supercarro"]}}},{"interval":{"start":1681862400000,"end":1681948800000},"puzzles":{"score":{"win":6,"loss":0,"draw":0,"rp":{"before":2677,"after":2736}}},"follows":{"in":{"ids":["hayden1461","ilyas-basit","senjukuwaragi","deinchayamagmeinetns","chesswgm","wojciechstark","albertlem","zokirov9292","marcosmm11","merinovegor_13-7","umitaliacar","jamespro0221","jacky09","daniel1028","adison98"],"nb":23}}},{"interval":{"start":1681776000000,"end":1681862400000},"follows":{"in":{"ids":["drceltic","dominikk33king","sir-gianortega-13","epergalth57w","hojjat1368","thebarin1","geoff123","betul38","benjaminh12675","sivtsovvanya","darkpattern","osmaneren47","drgregoryhouseee","kayratitiz","nonvincoseperdo"],"nb":18}}},{"interval":{"start":1681689600000,"end":1681776000000},"games":{"ultraBullet":{"win":10,"loss":0,"draw":0,"rp":{"before":2745,"after":2769}},"bullet":{"win":5,"loss":3,"draw":0,"rp":{"before":3081,"after":3074}},"rapid":{"win":1,"loss":0,"draw":0,"rp":{"before":2611,"after":2625}}},"follows":{"in":{"ids":["thefateofall","mario6ajedrez","rajveergrover1232","ykylas2014","se7vthe","muhamed12143","kdmfan","trantuankhachess","admsamohamad","sakurablossoms","freeeeeeeze1","ata201200x","mbmohnish","alex_dchig","alikhan-7"],"nb":18}}},{"interval":{"start":1681603200000,"end":1681689600000},"puzzles":{"score":{"win":24,"loss":10,"draw":0,"rp":{"before":2628,"after":2677}}},"follows":{"in":{"ids":["dalibord","musfik050390","xqliotvgm","momdsamu","radiantranger64","aarohdeshmukhihsdl","baggirou","grandmasterflash95","wo0do","leon_pogosian2009","anandhu_sadurangam","ane_mnda_bng","nek-ngatiem","haider123","j03l5065igu3z"],"nb":19}}},{"interval":{"start":1681516800000,"end":1681603200000},"games":{"bullet":{"win":40,"loss":30,"draw":5,"rp":{"before":3097,"after":3081}},"ultraBullet":{"win":14,"loss":5,"draw":2,"rp":{"before":2717,"after":2745}},"threeCheck":{"win":2,"loss":0,"draw":0,"rp":{"before":2575,"after":2588}}},"tournaments":{"nb":1,"best":[{"tournament":{"id":"apr23lta","name":"Titled Arena April '23"},"nbGames":73,"score":124,"rank":3,"rankPercent":1}]},"follows":{"in":{"ids":["ikoroduboy","noahlz","behnamjafarii","tutam","nikmakval","x73marda","torretalkantar","jurassicpark00","zubera1","lionel2schmidt","abhi73","sakumi_chess","dabolistic2","like2readbooks","ojaykings"],"nb":53}}},{"interval":{"start":1681430400000,"end":1681516800000},"follows":{"in":{"ids":["talabra","mooshroom42","granpandita","imraaaa_li","relaxplayer","qwwerty","ivanchu26","nyrav_chess_beast","newfloki","m0xvtwio","jumanak","rakeshmajumder10","jeanlucpicard7","sparrowtang","iamsickmind"],"nb":27}}}]
''';
