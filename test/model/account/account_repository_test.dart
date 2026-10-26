import 'package:chess_srs/src/model/account/account_preferences.dart';
import 'package:chess_srs/src/model/account/account_repository.dart';
import 'package:chess_srs/src/model/auth/auth_user.dart';
import 'package:chess_srs/src/model/common/id.dart';
import 'package:chess_srs/src/model/common/preloaded_data.dart';
import 'package:chess_srs/src/model/user/user.dart';
import 'package:chess_srs/src/network/http.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../network/fake_http_client_factory.dart';
import '../../test_container.dart';
import '../../test_helpers.dart';

void main() {
  group('AccountRepository', () {
    test('getPreferences', () async {
      const response = '''
{
  "prefs": {
    "dark": true,
    "transp": false,
    "bgImg": "http://example.com",
    "is3d": false,
    "theme": "blue",
    "pieceSet": "cburnett",
    "theme3d": "Black-White-Aluminium",
    "pieceSet3d": "Basic",
    "soundSet": "silent",
    "blindfold": 0,
    "autoQueen": 2,
    "autoThreefold": 2,
    "takeback": 3,
    "moretime": 3,
    "clockTenths": 1,
    "clockBar": true,
    "clockSound": true,
    "premove": true,
    "animation": 2,
    "captured": true,
    "follow": true,
    "highlight": true,
    "destination": true,
    "coords": 2,
    "replay": 2,
    "challenge": 4,
    "message": 3,
    "coordColor": 2,
    "submitMove": 4,
    "confirmResign": 1,
    "insightShare": 1,
    "keyboardMove": 0,
    "zen": 0,
    "pieceNotation": 0,
    "ratings": 1,
    "moveEvent": 2,
    "rookCastle": 1
  },
  "language": "en-GB"
}
''';

      final mockClient = MockClient((request) {
        if (request.url.path == '/api/account/preferences') {
          return mockResponse(response, 200);
        }
        return mockResponse('', 404);
      });

      final container = await lichessClientContainer(mockClient);
      final repo = container.read(accountRepositoryProvider);
      final result = await repo.getPreferences();

      expect(result, isA<AccountPrefState>());

      expect(result.autoQueen, AutoQueen.premove);
    });
  });

  group('accountProvider', () {
    test('fetches the profile when signed in', () async {
      final mockClient = MockClient((request) {
        if (request.url.path == '/api/account') {
          return mockResponse('{"id":"alice","username":"alice"}', 200);
        }
        return mockResponse('', 404);
      });

      final container = await makeContainer(
        overrides: {
          httpClientFactoryProvider: httpClientFactoryProvider.overrideWith((ref) {
            return FakeHttpClientFactory(() => mockClient);
          }),
          preloadedDataProvider: preloadedDataProvider.overrideWith(
            (ref) => _preloaded(authUser: _signedIn()),
          ),
        },
      );
      addTearDown(container.dispose);

      final sub = container.listen(accountProvider, (_, _) {});
      addTearDown(sub.close);

      final user = await container.read(accountProvider.future);
      expect(user, isNotNull);
      expect(user!.username, 'alice');
    });

    test('returns null when signed out', () async {
      final mockClient = MockClient((request) => mockResponse('', 404));
      final container = await makeContainer(
        overrides: {
          httpClientFactoryProvider: httpClientFactoryProvider.overrideWith((ref) {
            return FakeHttpClientFactory(() => mockClient);
          }),
          preloadedDataProvider: preloadedDataProvider.overrideWith(
            (ref) => _preloaded(authUser: null),
          ),
        },
      );
      addTearDown(container.dispose);

      final sub = container.listen(accountProvider, (_, _) {});
      addTearDown(sub.close);

      final user = await container.read(accountProvider.future);
      expect(user, isNull);
    });
  });

  group('kidModeProvider', () {
    test('defaults to false when signed out', () async {
      final mockClient = MockClient((request) => mockResponse('', 404));
      final container = await makeContainer(
        overrides: {
          httpClientFactoryProvider: httpClientFactoryProvider.overrideWith((ref) {
            return FakeHttpClientFactory(() => mockClient);
          }),
          preloadedDataProvider: preloadedDataProvider.overrideWith(
            (ref) => _preloaded(authUser: null),
          ),
        },
      );
      addTearDown(container.dispose);

      final sub = container.listen(kidModeProvider, (_, _) {});
      addTearDown(sub.close);

      final kid = await container.read(kidModeProvider.future);
      expect(kid, isFalse);
    });
  });
}

AuthUser _signedIn() => const AuthUser(
  token: 't',
  user: LightUser(id: UserId('alice'), name: 'alice'),
);

PreloadedData _preloaded({AuthUser? authUser}) => (
  sri: 'test-sri',
  packageInfo: PackageInfo(
    appName: 'chess_srs_test',
    version: '0.0.0',
    buildNumber: '0',
    packageName: 'chess_srs_test',
  ),
  deviceInfo: BaseDeviceInfo({
    'name': 'test',
    'model': 'test',
    'manufacturer': 'test',
    'systemName': 'test',
    'systemVersion': 'test',
    'identifierForVendor': 'test',
    'isPhysicalDevice': true,
  }),
  authUser: authUser,
  engineMaxMemoryInMb: 256,
  appDocumentsDirectory: null,
  appSupportDirectory: null,
);
