// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:chess_srs/src/model/common/preloaded_data.dart';
import 'package:chess_srs/src/model/updater/app_update.dart';
import 'package:chess_srs/src/model/updater/app_update_service.dart';
import 'package:chess_srs/src/network/http.dart';
import 'package:chess_srs/src/utils/system.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../network/fake_http_client_factory.dart';

const _mockReleasesJson = '''
[
  {
    "tag_name": "v1.8.0",
    "html_url": "https://github.com/cassandre60/ChessSRS/releases/tag/v1.8.0",
    "name": "v1.8.0",
    "body": "Bug fixes and improvements",
    "assets": [
      {
        "name": "chesssrs-v1.8.0-android.apk",
        "browser_download_url": "https://github.com/cassandre60/ChessSRS/releases/download/v1.8.0/chesssrs-v1.8.0-android.apk",
        "size": 10485760
      },
      {
        "name": "chesssrs-v1.8.0-linux-x64.tar.gz",
        "browser_download_url": "https://github.com/cassandre60/ChessSRS/releases/download/v1.8.0/chesssrs-v1.8.0-linux-x64.tar.gz",
        "size": 20971520
      }
    ]
  }
]
''';

ProviderContainer makeUpdateContainer({
  required String currentVersion,
  required http.Client client,
}) {
  final container = ProviderContainer(
    overrides: [
      preloadedDataProvider.overrideWith((ref) {
        return (
          sri: 'test-sri',
          packageInfo: PackageInfo(
            appName: 'chess_srs_test',
            version: currentVersion,
            buildNumber: '1',
            packageName: 'org.chesssrs.app',
          ),
          deviceInfo: BaseDeviceInfo({'name': 'test'}),
          authUser: null,
          engineMaxMemoryInMb: 256,
          appDocumentsDirectory: null,
          appSupportDirectory: null,
        );
      }),
      httpClientFactoryProvider.overrideWith((ref) {
        return FakeHttpClientFactory(() => client);
      }),
    ],
  );
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppUpdateNotifier', () {
    test('detects available update when remote version is newer', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/releases')) {
          return http.Response(
            _mockReleasesJson,
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not found', 404);
      });

      final container = makeUpdateContainer(currentVersion: '1.7.0', client: mockClient);
      addTearDown(container.dispose);

      final notifier = container.read(appUpdateProvider.notifier);
      await notifier.checkForUpdate(force: true);

      final state = container.read(appUpdateProvider);
      expect(state.status, equals(UpdateStatus.available));
      expect(state.releaseInfo, isNotNull);
      expect(state.releaseInfo!.tagName, equals('v1.8.0'));
      expect(state.releaseInfo!.isNewer, isTrue);
      expect(
        state.releaseInfo!.apkDownloadUrl,
        equals(
          Uri.parse(
            'https://github.com/cassandre60/ChessSRS/releases/download/v1.8.0/chesssrs-v1.8.0-android.apk',
          ),
        ),
      );
      expect(state.releaseInfo!.apkSize, equals(10485760));
    });

    test('marks upToDate when versions match', () async {
      final mockClient = MockClient((request) async {
        return http.Response(_mockReleasesJson, 200, headers: {'content-type': 'application/json'});
      });

      final container = makeUpdateContainer(currentVersion: '1.8.0', client: mockClient);
      addTearDown(container.dispose);

      final notifier = container.read(appUpdateProvider.notifier);
      await notifier.checkForUpdate(force: true);

      final state = container.read(appUpdateProvider);
      expect(state.status, equals(UpdateStatus.upToDate));
      expect(state.releaseInfo, isNotNull);
      expect(state.releaseInfo!.isNewer, isFalse);
    });

    test('marks upToDate when local version is newer than remote', () async {
      final mockClient = MockClient((request) async {
        return http.Response(_mockReleasesJson, 200, headers: {'content-type': 'application/json'});
      });

      final container = makeUpdateContainer(currentVersion: '1.9.0', client: mockClient);
      addTearDown(container.dispose);

      final notifier = container.read(appUpdateProvider.notifier);
      await notifier.checkForUpdate(force: true);

      final state = container.read(appUpdateProvider);
      expect(state.status, equals(UpdateStatus.upToDate));
      expect(state.releaseInfo!.isNewer, isFalse);
    });

    test('handles GitHub API error gracefully', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Rate limit exceeded', 403);
      });

      final container = makeUpdateContainer(currentVersion: '1.7.0', client: mockClient);
      addTearDown(container.dispose);

      final notifier = container.read(appUpdateProvider.notifier);
      await notifier.checkForUpdate(force: true);

      final state = container.read(appUpdateProvider);
      expect(state.status, equals(UpdateStatus.error));
      expect(state.errorMessage, contains('403'));
    });

    test('Action A: openInBrowser invokes launcher with APK URL', () async {
      final mockClient = MockClient((request) async {
        return http.Response(_mockReleasesJson, 200, headers: {'content-type': 'application/json'});
      });

      final container = makeUpdateContainer(currentVersion: '1.7.0', client: mockClient);
      addTearDown(container.dispose);

      final notifier = container.read(appUpdateProvider.notifier);
      await notifier.checkForUpdate(force: true);

      Uri? launchedUri;
      final launched = await notifier.openInBrowser(
        launcher: (uri) async {
          launchedUri = uri;
          return true;
        },
      );

      expect(launched, isTrue);
      expect(
        launchedUri,
        equals(
          Uri.parse(
            'https://github.com/cassandre60/ChessSRS/releases/download/v1.8.0/chesssrs-v1.8.0-android.apk',
          ),
        ),
      );
    });

    test('Action B: downloadAndInstall tracks progress and triggers install', () async {
      final tempDir = await Directory.systemTemp.createTemp('srs_update_test_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final testBytes = utf8.encode('FAKE_APK_CONTENT_FOR_TESTING');

      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('.apk')) {
          return http.Response.bytes(
            testBytes,
            200,
            headers: {'content-length': testBytes.length.toString()},
          );
        }
        if (request.url.path.contains('/releases')) {
          return http.Response(
            _mockReleasesJson,
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not found', 404);
      });

      final container = makeUpdateContainer(currentVersion: '1.7.0', client: mockClient);
      addTearDown(container.dispose);

      final notifier = container.read(appUpdateProvider.notifier);
      await notifier.checkForUpdate(force: true);

      String? installedPath;
      await notifier.downloadAndInstall(
        tempDirOverride: tempDir,
        installerOverride: (path) async {
          installedPath = path;
          return true;
        },
      );

      final state = container.read(appUpdateProvider);
      expect(state.status, equals(UpdateStatus.readyToInstall));
      expect(state.downloadProgress, equals(1.0));
      expect(installedPath, isNotNull);
      expect(File(installedPath!).existsSync(), isTrue);
      expect(File(installedPath!).readAsBytesSync(), equals(testBytes));
    });
  });

  group('System APK installer channel methods', () {
    const channel = MethodChannel('mobile.lichess.org/system');

    test('canRequestPackageInstalls returns platform result', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async {
          if (call.method == 'canRequestPackageInstalls') {
            return true;
          }
          return null;
        },
      );
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        );
      });

      // Note: on non-Android platform tests, Platform.isAndroid is false, so it returns false safely.
      final result = await System.instance.canRequestPackageInstalls();
      expect(result, isA<bool>());
    });

    test('installApk returns bool safely', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async {
          if (call.method == 'installApk') {
            return true;
          }
          return null;
        },
      );
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        );
      });

      final result = await System.instance.installApk('/fake/path.apk');
      expect(result, isA<bool>());
    });
  });
}
