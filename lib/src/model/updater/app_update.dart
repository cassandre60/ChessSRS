// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:pub_semver/pub_semver.dart';

enum UpdateStatus { idle, checking, upToDate, available, downloading, readyToInstall, error }

class AppReleaseInfo {
  const AppReleaseInfo({
    required this.tagName,
    required this.version,
    required this.releaseUrl,
    this.releaseNotes,
    this.apkDownloadUrl,
    this.apkSize,
    required this.isNewer,
  });

  final String tagName;
  final Version version;
  final Uri releaseUrl;
  final String? releaseNotes;
  final Uri? apkDownloadUrl;
  final int? apkSize;
  final bool isNewer;

  @override
  String toString() =>
      'AppReleaseInfo(tag: $tagName, version: $version, isNewer: $isNewer, apk: $apkDownloadUrl)';
}

class AppUpdateState {
  const AppUpdateState({
    this.status = UpdateStatus.idle,
    this.releaseInfo,
    this.downloadProgress = 0.0,
    this.downloadedFilePath,
    this.errorMessage,
  });

  final UpdateStatus status;
  final AppReleaseInfo? releaseInfo;
  final double downloadProgress;
  final String? downloadedFilePath;
  final String? errorMessage;

  AppUpdateState copyWith({
    UpdateStatus? status,
    AppReleaseInfo? releaseInfo,
    double? downloadProgress,
    String? downloadedFilePath,
    String? errorMessage,
  }) {
    return AppUpdateState(
      status: status ?? this.status,
      releaseInfo: releaseInfo ?? this.releaseInfo,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      downloadedFilePath: downloadedFilePath ?? this.downloadedFilePath,
      errorMessage: errorMessage,
    );
  }

  @override
  String toString() =>
      'AppUpdateState(status: $status, progress: $downloadProgress, error: $errorMessage)';
}
