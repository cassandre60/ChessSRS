import 'dart:async';
import 'dart:io' show Directory;

import 'package:chess_srs/src/constants.dart';
import 'package:chess_srs/src/db/secure_storage.dart';
import 'package:chess_srs/src/model/auth/auth_storage.dart';
import 'package:chess_srs/src/model/auth/auth_user.dart';
import 'package:chess_srs/src/model/engine/engine_utils.dart';
import 'package:chess_srs/src/utils/string.dart';
import 'package:chess_srs/src/utils/system.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart'
    show getApplicationDocumentsDirectory, getApplicationSupportDirectory;

typedef PreloadedData = ({
  PackageInfo packageInfo,
  BaseDeviceInfo deviceInfo,
  AuthUser? authUser,
  String sri,
  int engineMaxMemoryInMb,
  Directory? appDocumentsDirectory,
  Directory? appSupportDirectory,
});

/// A provider that preloads various data needed throughout the app.
///
/// Deliberately does not validate the stored session token. It used to, as a fire-and-forget
/// side effect of this provider, and that was wrong twice over: nothing could observe or await it,
/// and its result was unscoped — `authStorage.delete()` removed whichever session happened to be
/// stored when the response arrived, so an account that signed in during the request's five-second
/// window was signed straight back out. Startup validation now goes through
/// [startupTokenCheckProvider], which reuses the fenced, already-tested `AuthController.checkToken`.
final preloadedDataProvider = FutureProvider<PreloadedData>((Ref ref) async {
  final authStorage = ref.read(authStorageProvider);

  final (
    pInfo,
    deviceInfo,
    sri,
    authUser,
    physicalMemory,
    appDocumentsDirectory,
    appSupportDirectory,
  ) = await (
    PackageInfo.fromPlatform(),
    DeviceInfoPlugin().deviceInfo,
    _readOrCreateSri(),
    authStorage.read(),
    System.instance.getTotalRam(),
    _getDirectoryOrNull(getApplicationDocumentsDirectory),
    _getDirectoryOrNull(getApplicationSupportDirectory),
  ).wait;

  return (
    packageInfo: pInfo,
    deviceInfo: deviceInfo,
    authUser: authUser,
    sri: sri,
    engineMaxMemoryInMb: engineMaxMemoryFor(physicalMemory ?? 256),
    appDocumentsDirectory: appDocumentsDirectory,
    appSupportDirectory: appSupportDirectory,
  );
}, name: 'PreloadedDataProvider');

/// Reads the stored socket random identifier, generating and persisting a
/// new one if none exists yet or if secure storage turns out to be
/// unreadable.
Future<String> _readOrCreateSri() async {
  try {
    final storedSri = await SecureStorage.instance.read(key: kSRIStorageKey);
    if (storedSri != null) return storedSri;
    final newSri = genRandomString(12);
    await SecureStorage.instance.write(key: kSRIStorageKey, value: newSri);
    return newSri;
  } on PlatformException catch (_) {
    // Clear all secure storage if an error occurs because it probably means the
    // key has been lost. If clearing fails too (e.g. no keyring service is
    // available on the platform, as on some Linux desktop environments), fall
    // back to an ephemeral in-memory SRI so the app can still start.
    try {
      await SecureStorage.instance.deleteAll();
    } on PlatformException catch (_) {
      // Ignore: secure storage is unusable on this platform/session.
    }
    return genRandomString(12);
  }
}

/// Runs [getDirectory], returning `null` instead of throwing if it fails.
Future<Directory?> _getDirectoryOrNull(Future<Directory> Function() getDirectory) async {
  try {
    return await getDirectory();
  } catch (_) {
    return null;
  }
}
