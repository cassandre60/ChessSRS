import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chess_srs/src/model/common/service/sound_service.dart';
import 'package:chess_srs/src/model/settings/general_preferences.dart';

class FakeSoundService implements SoundService {
  /// Every [ReviewSound] handed to [playReviewSound], in the order it was played.
  ///
  /// The design's own review feedback is what the review-flow tests assert on, so this
  /// records rather than swallowing. The theme [Sound]s stay unrecorded: they are covered
  /// by the board and analysis feedback, and nothing asserts on them here.
  final List<ReviewSound> reviewSounds = [];

  /// Every theme [Sound] handed to [play], in order.
  ///
  /// Recorded because a piece landing is a theme sound (`Sound.move`), not one of the
  /// design's [ReviewSound]s — see `design/docs/02-tokens.md` §6 and the note in
  /// MoveFeedbackService about which set plays where.
  final List<Sound> themeSounds = [];

  /// How many times [sound] was played.
  int countOf(ReviewSound sound) => reviewSounds.where((s) => s == sound).length;

  /// How many times the theme [sound] was played.
  int countTheme(Sound sound) => themeSounds.where((s) => s == sound).length;

  @override
  Future<void> play(Sound sound, {double? volume}) async {
    themeSounds.add(sound);
  }

  @override
  Future<void> playReviewSound(ReviewSound sound, {double volume = 1.0}) async {
    reviewSounds.add(sound);
  }

  @override
  Future<void> playCaptureSound(Variant variant, {double? volume}) async {}

  @override
  Future<void> changeTheme(SoundTheme theme, {bool playSound = false}) async {}

  @override
  Future<void> release() async {}
}
