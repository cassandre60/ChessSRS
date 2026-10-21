import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Various system utilities.
class System {
  const System._();

  static const _channel = MethodChannel('mobile.lichess.org/system');

  static const instance = System._();

  /// Returns the system total RAM in megabytes.
  Future<int?> getTotalRam() async {
    try {
      return await _channel.invokeMethod<int>('getTotalRam');
    } on PlatformException catch (e) {
      debugPrint('Failed to get total RAM: ${e.message}');
      return null;
    } on MissingPluginException catch (_) {
      return null;
    }
  }

  /// Returns the default browser's package name and version, or `null` if it can't be determined.
  ///
  /// Only available on Android (returns `null` on other platforms).
  Future<({String package, String? version})?> getDefaultBrowser() async {
    if (!Platform.isAndroid) {
      return null;
    }
    try {
      final info = await _channel.invokeMapMethod<String, String?>('getDefaultBrowser');
      final package = info?['package'];
      if (package == null) {
        return null;
      }
      return (package: package, version: info?['version']);
    } on PlatformException catch (e) {
      debugPrint('Failed to get default browser: ${e.message}');
      return null;
    } on MissingPluginException catch (_) {
      return null;
    }
  }

  /// Clear all user data from the app.
  ///
  /// Only available on Android.
  Future<bool> clearUserData() async {
    if (Platform.isAndroid) {
      try {
        final result = await _channel.invokeMethod<bool>('clearApplicationUserData');
        return result ?? false;
      } on PlatformException catch (e) {
        debugPrint('Failed to clear user data: ${e.message}');
        return false;
      }
    }

    throw UnimplementedError('This method is only available on Android');
  }

  /// Checks whether the app has permission to request package installs on Android.
  Future<bool> canRequestPackageInstalls() async {
    if (!Platform.isAndroid) {
      return false;
    }
    try {
      final res = await _channel.invokeMethod<bool>('canRequestPackageInstalls');
      return res ?? false;
    } on PlatformException catch (e) {
      debugPrint('Failed to check install permission: ${e.message}');
      return false;
    } on MissingPluginException catch (_) {
      return false;
    }
  }

  /// Opens the system settings screen for unknown app install permission on Android.
  Future<bool> openInstallPermissionSettings() async {
    if (!Platform.isAndroid) {
      return false;
    }
    try {
      final res = await _channel.invokeMethod<bool>('openInstallPermissionSettings');
      return res ?? false;
    } on PlatformException catch (e) {
      debugPrint('Failed to open install settings: ${e.message}');
      return false;
    } on MissingPluginException catch (_) {
      return false;
    }
  }

  /// Installs an APK file from a local path via Android's package installer.
  Future<bool> installApk(String filePath) async {
    if (!Platform.isAndroid) {
      return false;
    }
    try {
      final res = await _channel.invokeMethod<bool>('installApk', {'filePath': filePath});
      return res ?? false;
    } on PlatformException catch (e) {
      debugPrint('Failed to invoke install APK: ${e.message}');
      return false;
    } on MissingPluginException catch (_) {
      return false;
    }
  }
}

/// A provider that returns OS version of an Android device.
final androidVersionProvider = FutureProvider<AndroidBuildVersion?>((ref) async {
  if (!Platform.isAndroid) {
    return null;
  }
  final info = await DeviceInfoPlugin().androidInfo;
  return info.version;
});
