// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:chess_srs/src/model/common/preloaded_data.dart';
import 'package:chess_srs/src/model/updater/app_update.dart';
import 'package:chess_srs/src/network/http.dart';
import 'package:chess_srs/src/utils/system.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:url_launcher/url_launcher.dart';

const kChessSrsReleasesApiUrl =
    'https://api.github.com/repos/cassandre60/ChessSRS/releases?per_page=5';

final appUpdateProvider = NotifierProvider<AppUpdateNotifier, AppUpdateState>(
  AppUpdateNotifier.new,
);

class AppUpdateNotifier extends Notifier<AppUpdateState> {
  DateTime? _lastCheckedAt;

  @override
  AppUpdateState build() {
    return const AppUpdateState();
  }

  /// Checks for newer releases from GitHub.
  /// Throttled to once every 30 minutes unless [force] is true.
  Future<void> checkForUpdate({bool force = false}) async {
    final now = DateTime.now();
    if (!force &&
        _lastCheckedAt != null &&
        now.difference(_lastCheckedAt!).inMinutes < 30 &&
        state.status != UpdateStatus.error &&
        state.status != UpdateStatus.idle) {
      return;
    }

    if (state.status == UpdateStatus.checking || state.status == UpdateStatus.downloading) {
      return;
    }

    state = state.copyWith(status: UpdateStatus.checking, errorMessage: null);

    try {
      final client = ref.read(defaultClientProvider);
      final currentVersionStr =
          ref.read(preloadedDataProvider).value?.packageInfo.version ?? '0.0.0';
      final currentVersion = _parseVersion(currentVersionStr);

      final response = await client.get(
        Uri.parse(kChessSrsReleasesApiUrl),
        headers: {'Accept': 'application/vnd.github.v3+json', 'User-Agent': 'ChessSRS-App'},
      );

      if (response.statusCode != 200) {
        state = state.copyWith(
          status: UpdateStatus.error,
          errorMessage: 'GitHub API returned HTTP ${response.statusCode}',
        );
        return;
      }

      if (response.body.trim().isEmpty) {
        _lastCheckedAt = now;
        state = state.copyWith(status: UpdateStatus.upToDate);
        return;
      }

      final dynamic decoded = jsonDecode(response.body);
      if (decoded is! List || decoded.isEmpty) {
        _lastCheckedAt = now;
        state = state.copyWith(status: UpdateStatus.upToDate);
        return;
      }

      final latest = decoded.first as Map<String, dynamic>;
      final tagName = latest['tag_name'] as String? ?? '';
      final releaseVersion = _parseVersion(tagName);
      final htmlUrl =
          latest['html_url'] as String? ?? 'https://github.com/cassandre60/ChessSRS/releases';
      final releaseNotes = latest['body'] as String?;

      Uri? apkDownloadUrl;
      int? apkSize;

      final assets = latest['assets'] as List<dynamic>? ?? const [];
      for (final rawAsset in assets) {
        if (rawAsset is! Map<String, dynamic>) continue;
        final name = rawAsset['name'] as String? ?? '';
        if (name.endsWith('.apk')) {
          final downloadUrl = rawAsset['browser_download_url'] as String?;
          if (downloadUrl != null) {
            apkDownloadUrl = Uri.tryParse(downloadUrl);
            apkSize = rawAsset['size'] as int?;
            break;
          }
        }
      }

      final isNewer = releaseVersion > currentVersion;
      final info = AppReleaseInfo(
        tagName: tagName,
        version: releaseVersion,
        releaseUrl: Uri.parse(htmlUrl),
        releaseNotes: releaseNotes,
        apkDownloadUrl: apkDownloadUrl,
        apkSize: apkSize,
        isNewer: isNewer,
      );

      _lastCheckedAt = now;
      state = state.copyWith(
        status: isNewer ? UpdateStatus.available : UpdateStatus.upToDate,
        releaseInfo: info,
      );
    } catch (e) {
      debugPrint('Error checking for app updates: $e');
      state = state.copyWith(status: UpdateStatus.error, errorMessage: 'Check failed: $e');
    }
  }

  /// Action A: Open the direct APK download or GitHub release page in an external browser.
  Future<bool> openInBrowser({Future<bool> Function(Uri url)? launcher}) async {
    final info = state.releaseInfo;
    final uri =
        info?.apkDownloadUrl ??
        info?.releaseUrl ??
        Uri.parse('https://github.com/cassandre60/ChessSRS/releases');
    final launch = launcher ?? (u) => launchUrl(u, mode: LaunchMode.externalApplication);
    try {
      return await launch(uri);
    } catch (e) {
      debugPrint('Failed to open update in browser: $e');
      return false;
    }
  }

  /// Action B: In-app download with progress updates, followed by launching the Android package installer.
  Future<void> downloadAndInstall({
    Directory? tempDirOverride,
    Future<bool> Function(String path)? installerOverride,
  }) async {
    final info = state.releaseInfo;
    if (info?.apkDownloadUrl == null) {
      await openInBrowser();
      return;
    }

    state = state.copyWith(
      status: UpdateStatus.downloading,
      downloadProgress: 0.0,
      errorMessage: null,
    );

    try {
      final client = ref.read(defaultClientProvider);
      final Directory dir;
      if (tempDirOverride != null) {
        dir = tempDirOverride;
      } else {
        dir = await getTemporaryDirectory();
      }

      final safeTag = info!.tagName.replaceAll(RegExp(r'[^\w.-]'), '_');
      final apkFile = File('${dir.path}/chesssrs-$safeTag-update.apk');

      final request = http.Request('GET', info.apkDownloadUrl!);
      request.headers['User-Agent'] = 'ChessSRS-App';
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw HttpException('Server responded with HTTP ${response.statusCode}');
      }

      final totalBytes = response.contentLength ?? info.apkSize ?? 0;
      var receivedBytes = 0;
      final sink = apkFile.openWrite();

      await for (final chunk in response.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) {
          final progress = (receivedBytes / totalBytes).clamp(0.0, 1.0);
          state = state.copyWith(downloadProgress: progress);
        }
      }

      await sink.flush();
      await sink.close();

      state = state.copyWith(
        status: UpdateStatus.readyToInstall,
        downloadedFilePath: apkFile.path,
        downloadProgress: 1.0,
      );

      if (installerOverride != null) {
        await installerOverride(apkFile.path);
      } else {
        await installDownloadedApk();
      }
    } catch (e) {
      debugPrint('Failed downloading update APK: $e');
      state = state.copyWith(status: UpdateStatus.error, errorMessage: 'Download failed: $e');
    }
  }

  /// Triggers the system installer for the downloaded APK.
  Future<bool> installDownloadedApk() async {
    final path = state.downloadedFilePath;
    if (path == null) {
      return false;
    }

    if (Platform.isAndroid) {
      final canInstall = await System.instance.canRequestPackageInstalls();
      if (!canInstall) {
        await System.instance.openInstallPermissionSettings();
      }
      return await System.instance.installApk(path);
    } else {
      // Non-Android platforms open browser release page
      return await openInBrowser();
    }
  }

  static Version _parseVersion(String raw) {
    var v = raw.trim();
    if (v.startsWith('v') || v.startsWith('V')) {
      v = v.substring(1);
    }
    // Remove build metadata or non-semver suffixes if needed
    final dashIndex = v.indexOf('+');
    if (dashIndex != -1) {
      v = v.substring(0, dashIndex);
    }
    try {
      return Version.parse(v);
    } catch (_) {
      // Fallback for non-semver or malformed strings
      return Version(0, 0, 0);
    }
  }
}
