import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chess_srs/src/model/common/service/move_feedback.dart';
import 'package:chess_srs/src/model/common/service/sound_service.dart';
import 'package:chess_srs/src/model/settings/board_preferences.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockSoundService extends Mock implements SoundService {}

class _FakeBoardPreferences extends BoardPreferences {
  _FakeBoardPreferences(this.prefs);

  final BoardPrefs prefs;

  @override
  BoardPrefs build() => prefs;
}

late ProviderContainer container;
late _MockSoundService soundService;
final List<MethodCall> platformCalls = <MethodCall>[];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(Variant.atomic);
    registerFallbackValue(Sound.move);
  });

  setUp(() {
    platformCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        platformCalls.add(call);
        return null;
      },
    );
    soundService = _MockSoundService();
    when(() => soundService.playCaptureSound(any())).thenAnswer((_) async {});
    when(() => soundService.play(any())).thenAnswer((_) async {});
    container = ProviderContainer(
      overrides: [
        soundServiceProvider.overrideWithValue(soundService),
        boardPreferencesProvider.overrideWith(
          () => _FakeBoardPreferences(BoardPrefs.defaults.copyWith(hapticFeedback: true)),
        ),
      ],
    );
  });

  tearDown(() {
    container.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });

  MoveFeedbackService service() => container.read(moveFeedbackServiceProvider);

  Iterable<MethodCall> hapticCalls() =>
      platformCalls.where((c) => c.method == 'HapticFeedback.vibrate').toList();

  test('moveFeedback plays the move sound', () {
    final moveFeedback = service();
    moveFeedback.moveFeedback();
    verify(() => soundService.play(Sound.move)).called(1);
  });

  test('moveFeedback triggers light haptic when haptic feedback is enabled', () {
    final moveFeedback = service();
    moveFeedback.moveFeedback();
    expect(hapticCalls(), hasLength(1));
    expect(hapticCalls().single.arguments, 'HapticFeedbackType.lightImpact');
  });

  test('moveFeedback with check=true triggers medium haptic', () {
    final moveFeedback = service();
    moveFeedback.moveFeedback(check: true);
    expect(hapticCalls(), hasLength(1));
    expect(hapticCalls().single.arguments, 'HapticFeedbackType.mediumImpact');
  });

  test('captureFeedback plays the capture sound for the variant', () {
    final moveFeedback = service();
    moveFeedback.captureFeedback(Variant.atomic);
    verify(() => soundService.playCaptureSound(Variant.atomic)).called(1);
  });

  test('captureFeedback triggers light haptic when haptic feedback is enabled', () {
    final moveFeedback = service();
    moveFeedback.captureFeedback(Variant.atomic);
    expect(hapticCalls(), hasLength(1));
    expect(hapticCalls().single.arguments, 'HapticFeedbackType.lightImpact');
  });

  test('captureFeedback with check=true triggers medium haptic', () {
    final moveFeedback = service();
    moveFeedback.captureFeedback(Variant.atomic, check: true);
    expect(hapticCalls(), hasLength(1));
    expect(hapticCalls().single.arguments, 'HapticFeedbackType.mediumImpact');
  });
}
