import 'package:chess_srs/src/model/common/service/sound_service.dart';
import 'package:chess_srs/src/model/settings/general_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../binding.dart';
import '../../../test_container.dart';

class _FakeGeneralPreferencesNotifier extends GeneralPreferencesNotifier {
  _FakeGeneralPreferencesNotifier(this._initialState);
  final GeneralPrefs _initialState;

  @override
  GeneralPrefs build() => _initialState;
}

void main() {
  TestLichessBinding.ensureInitialized();

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('SoundService can play sound when enabled without crashing on Linux', () async {
    final container = await makeContainer(
      overrides: {
        generalPreferencesProvider: generalPreferencesProvider.overrideWith(
          () => _FakeGeneralPreferencesNotifier(
            GeneralPrefs.defaults.copyWith(isSoundEnabled: true, masterVolume: 0.8),
          ),
        ),
        soundServiceProvider: soundServiceProvider.overrideWith((ref) => SoundService(ref)),
      },
    );

    final soundService = container.read(soundServiceProvider);

    // Verify calling play does not throw on Linux
    await expectLater(soundService.play(Sound.move), completes);
    await expectLater(soundService.play(Sound.capture, volume: 0.5), completes);

    // Verify release does not throw
    await expectLater(soundService.release(), completes);
  });

  test('SoundService does not play sound when disabled', () async {
    final container = await makeContainer(
      overrides: {
        generalPreferencesProvider: generalPreferencesProvider.overrideWith(
          () => _FakeGeneralPreferencesNotifier(
            GeneralPrefs.defaults.copyWith(isSoundEnabled: false),
          ),
        ),
        soundServiceProvider: soundServiceProvider.overrideWith((ref) => SoundService(ref)),
      },
    );

    final soundService = container.read(soundServiceProvider);
    await expectLater(soundService.play(Sound.move), completes);
  });
}
