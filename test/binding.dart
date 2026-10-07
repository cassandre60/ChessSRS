import 'package:chess_srs/src/binding.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

class FakeWakelockPlusPlatform extends WakelockPlusPlatformInterface {
  @override
  Future<void> toggle({required bool enable}) async {}

  @override
  Future<bool> get enabled async => true;
}

/// The binding instance used in tests.
TestLichessBinding get testBinding => TestLichessBinding.instance;

/// Lichess binding for testing.
class TestLichessBinding extends LichessBinding {
  TestLichessBinding() {
    // Logger.root.level = Level.ALL;
    // Logger.root.onRecord.listen((record) {
    //   // ignore: avoid_print
    //   print(
    //     '${DateFormat('H:m:s.S').format(record.time)} [${record.level}] ${record.loggerName}: ${record.message}',
    //   );
    // });
  }

  /// Initialize the binding if necessary, and ensure it is a [TestLichessBinding].
  ///
  /// If there is an existing binding but it is not a [TestLichessBinding],
  /// this method throws an error.
  ///
  /// Also initializes the Flutter binding, which the app widely assumes to exist: an
  /// [AppLifecycleListener] alone — the connectivity notifier and the socket pool both build one —
  /// throws without it.
  factory TestLichessBinding.ensureInitialized() {
    TestWidgetsFlutterBinding.ensureInitialized();
    if (_instance == null) {
      TestLichessBinding();
    }
    return instance;
  }

  /// The single instance of the binding.
  static TestLichessBinding get instance => LichessBinding.checkInstance(_instance);
  static TestLichessBinding? _instance;

  @override
  void initInstance() {
    super.initInstance();
    _instance = this;
    WakelockPlusPlatformInterface.instance = FakeWakelockPlusPlatform();
    _mockQuickActions();
  }

  /// Answers the quick actions plugin's channel with nothing.
  ///
  /// `QuickActionService.start` calls the plugin on Android and iOS only, and a test that pumps
  /// the real `Application` under `variant: kPlatformVariant` *is* Android and iOS. With no
  /// handler installed the call throws `MissingPluginException` from inside the app's startup,
  /// which aborts the boot part-way: anything after it never runs, and the error surfaces as a
  /// failure of whichever test happened to be pumping — or, if the boot had already finished, not
  /// at all. That last part is why this looked like a machine-speed problem rather than a missing
  /// mock: the outcome depended on whether the throw landed inside the test's window.
  ///
  /// Mocked here rather than in one test because any test that mounts the app hits it. A null
  /// response is the honest answer: the plugin reports no launch action, and setting shortcuts is
  /// a no-op.
  void _mockQuickActions() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/quick_actions'),
      (call) async => null,
    );
  }

  /// Set the initial values for shared preferences.
  Future<void> setInitialSharedPreferencesValues(Map<String, Object> values) async {
    for (final entry in values.entries) {
      if (entry.value is String) {
        await sharedPreferences.setString(entry.key, entry.value as String);
      } else if (entry.value is bool) {
        await sharedPreferences.setBool(entry.key, entry.value as bool);
      } else if (entry.value is double) {
        await sharedPreferences.setDouble(entry.key, entry.value as double);
      } else if (entry.value is int) {
        await sharedPreferences.setInt(entry.key, entry.value as int);
      } else if (entry.value is List<String>) {
        await sharedPreferences.setStringList(entry.key, entry.value as List<String>);
      } else {
        throw ArgumentError.value(
          entry.value,
          'values',
          'Unsupported value type: ${entry.value.runtimeType}',
        );
      }
    }
  }

  FakeSharedPreferences? _sharedPreferences;

  @override
  int numAppStarts = 1;

  @override
  FakeSharedPreferences get sharedPreferences {
    return _sharedPreferences ??= FakeSharedPreferences();
  }

  /// Replaces the shared preferences fake, to test how a slow write behaves.
  ///
  /// Must be called before anything reads [sharedPreferences]. Reset by [reset].
  set sharedPreferences(FakeSharedPreferences prefs) {
    _sharedPreferences = prefs;
  }

  /// Reset the binding instance.
  ///
  /// Should be called using [addTearDown] in tests.
  void reset() {
    _sharedPreferences = null;
    numAppStarts = 1;
  }
}

class FakeSharedPreferences implements SharedPreferencesWithCache {
  final Map<String, dynamic> _values = {};

  @override
  Future<bool> remove(String key) async {
    _values.remove(key);
    return true;
  }

  @override
  Future<void> clear({Set<String>? allowList}) async {
    _values.clear();
  }

  @override
  bool containsKey(String key) {
    return _values.containsKey(key);
  }

  @override
  String? getString(String key) {
    return _values[key] as String?;
  }

  @override
  bool? getBool(String key) {
    return _values[key] as bool?;
  }

  @override
  double? getDouble(String key) {
    return _values[key] as double?;
  }

  @override
  int? getInt(String key) {
    return _values[key] as int?;
  }

  @override
  List<String>? getStringList(String key) {
    return _values[key] as List<String>?;
  }

  @override
  Future<bool> setString(String key, String value) async {
    _values[key] = value;
    return true;
  }

  @override
  Future<void> setBool(String key, bool value) {
    _values[key] = value;
    return Future.value();
  }

  @override
  Future<void> setDouble(String key, double value) {
    _values[key] = value;
    return Future.value();
  }

  @override
  Future<void> setInt(String key, int value) {
    _values[key] = value;
    return Future.value();
  }

  @override
  Future<void> setStringList(String key, List<String> value) {
    _values[key] = value;
    return Future.value();
  }

  @override
  Object? get(String key) {
    return _values[key];
  }

  @override
  Set<String> get keys => _values.keys.toSet();

  @override
  Future<void> reloadCache() {
    return Future.value();
  }
}

/// A [FakeSharedPreferences] whose writes complete on the event queue, like the
/// real ones do: [SharedPreferencesWithCache] goes through a platform channel,
/// so its futures never complete in a microtask.
///
/// Use it to check that code awaiting a preference write actually observes the
/// new value. Set [writeDelay] to exaggerate the latency.
class SlowFakeSharedPreferences extends FakeSharedPreferences {
  SlowFakeSharedPreferences({this.writeDelay = Duration.zero});

  final Duration writeDelay;

  @override
  Future<bool> setString(String key, String value) async {
    await Future<void>.delayed(writeDelay);
    return await super.setString(key, value);
  }
}
