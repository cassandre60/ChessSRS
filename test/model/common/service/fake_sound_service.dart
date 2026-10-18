import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chess_srs/src/model/common/service/sound_service.dart';
import 'package:chess_srs/src/model/settings/general_preferences.dart';

/// The [SoundService] UI tests mount so that nothing is ever audible in a test.
///
/// Walks are recorded, so a test can assert on the wiring — that play() was
/// called for the right sound — instead of merely that it completed. Walks are
/// recorded unchanged: the gate semantics of the real service (enabled,
/// master volume) are deliberately NOT re-implemented here; the real service's
/// own tests pin that contract (test/model/common/service/sound_service_test.dart).
class FakeSoundService implements SoundService {
  /// The sounds requested of this fake, in call order.
  final List<Sound> recorded = [];

  @override
  Future<void> play(Sound sound, {double? volume}) async {
    recorded.add(sound);
  }

  @override
  Future<void> playCaptureSound(Variant variant, {double? volume}) =>
      play(variant == Variant.atomic ? Sound.explosion : Sound.capture, volume: volume);

  @override
  Future<void> changeTheme(SoundTheme theme, {bool playSound = false}) async {}

  @override
  Future<void> release() async {}
}
