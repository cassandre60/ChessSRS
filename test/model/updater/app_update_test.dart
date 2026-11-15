// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/model/updater/app_update.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pub_semver/pub_semver.dart';

void main() {
  group('UpdateStatus', () {
    test('has expected values in stable order', () {
      expect(UpdateStatus.values, const [
        UpdateStatus.idle,
        UpdateStatus.checking,
        UpdateStatus.upToDate,
        UpdateStatus.available,
        UpdateStatus.downloading,
        UpdateStatus.readyToInstall,
        UpdateStatus.error,
      ]);
      expect(UpdateStatus.values.map((s) => s.name).toList(), const [
        'idle',
        'checking',
        'upToDate',
        'available',
        'downloading',
        'readyToInstall',
        'error',
      ]);
    });
  });

  group('AppReleaseInfo', () {
    test('stores required and optional fields', () {
      final version = Version.parse('1.8.0');
      final releaseUrl = Uri.parse('https://github.com/cassandre60/ChessSRS/releases/tag/v1.8.0');
      final apkUrl = Uri.parse(
        'https://github.com/cassandre60/ChessSRS/releases/download/v1.8.0/chesssrs.apk',
      );

      final info = AppReleaseInfo(
        tagName: 'v1.8.0',
        version: version,
        releaseUrl: releaseUrl,
        releaseNotes: 'Bug fixes',
        apkDownloadUrl: apkUrl,
        apkSize: 10485760,
        isNewer: true,
      );

      expect(info.tagName, 'v1.8.0');
      expect(info.version, version);
      expect(info.releaseUrl, releaseUrl);
      expect(info.releaseNotes, 'Bug fixes');
      expect(info.apkDownloadUrl, apkUrl);
      expect(info.apkSize, 10485760);
      expect(info.isNewer, isTrue);
    });

    test('defaults optional fields to null', () {
      final info = AppReleaseInfo(
        tagName: 'v1.7.0',
        version: Version.parse('1.7.0'),
        releaseUrl: Uri.parse('https://example.com/release'),
        isNewer: false,
      );

      expect(info.releaseNotes, isNull);
      expect(info.apkDownloadUrl, isNull);
      expect(info.apkSize, isNull);
      expect(info.isNewer, isFalse);
    });

    test('toString includes key fields', () {
      final info = AppReleaseInfo(
        tagName: 'v2.0.0',
        version: Version.parse('2.0.0'),
        releaseUrl: Uri.parse('https://example.com/r'),
        apkDownloadUrl: Uri.parse('https://example.com/app.apk'),
        isNewer: true,
      );

      expect(
        info.toString(),
        'AppReleaseInfo(tag: v2.0.0, version: 2.0.0, isNewer: true, apk: https://example.com/app.apk)',
      );
    });
  });

  group('AppUpdateState', () {
    test('defaults to idle with zero progress and no details', () {
      const state = AppUpdateState();

      expect(state.status, UpdateStatus.idle);
      expect(state.releaseInfo, isNull);
      expect(state.downloadProgress, 0.0);
      expect(state.downloadedFilePath, isNull);
      expect(state.errorMessage, isNull);
    });

    test('copyWith preserves status and progress when omitted', () {
      final release = AppReleaseInfo(
        tagName: 'v1.8.0',
        version: Version.parse('1.8.0'),
        releaseUrl: Uri.parse('https://example.com/release'),
        isNewer: true,
      );
      final state = AppUpdateState(
        status: UpdateStatus.downloading,
        releaseInfo: release,
        downloadProgress: 0.5,
        downloadedFilePath: '/tmp/app.apk',
        errorMessage: 'warn',
      );

      final copy = state.copyWith();

      expect(copy.status, UpdateStatus.downloading);
      expect(copy.downloadProgress, 0.5);
      // releaseInfo/downloadedFilePath use ?? so they are preserved when omitted
      expect(copy.releaseInfo, same(release));
      expect(copy.downloadedFilePath, '/tmp/app.apk');
      // errorMessage has no ?? in copyWith so it is reset when omitted
      expect(copy.errorMessage, isNull);
    });

    test('copyWith replaces provided fields', () {
      final oldRelease = AppReleaseInfo(
        tagName: 'v1.7.0',
        version: Version.parse('1.7.0'),
        releaseUrl: Uri.parse('https://example.com/old'),
        isNewer: false,
      );
      final newRelease = AppReleaseInfo(
        tagName: 'v1.8.0',
        version: Version.parse('1.8.0'),
        releaseUrl: Uri.parse('https://example.com/new'),
        isNewer: true,
      );
      final state = AppUpdateState(
        status: UpdateStatus.available,
        releaseInfo: oldRelease,
        downloadProgress: 0.0,
      );

      final copy = state.copyWith(
        status: UpdateStatus.readyToInstall,
        releaseInfo: newRelease,
        downloadProgress: 1.0,
        downloadedFilePath: '/tmp/new.apk',
        errorMessage: 'done',
      );

      expect(copy.status, UpdateStatus.readyToInstall);
      expect(copy.releaseInfo, same(newRelease));
      expect(copy.downloadProgress, 1.0);
      expect(copy.downloadedFilePath, '/tmp/new.apk');
      expect(copy.errorMessage, 'done');
    });

    test('toString includes status, progress and error', () {
      const state = AppUpdateState(
        status: UpdateStatus.error,
        downloadProgress: 0.25,
        errorMessage: 'network',
      );

      expect(
        state.toString(),
        'AppUpdateState(status: UpdateStatus.error, progress: 0.25, error: network)',
      );
    });
  });
}
