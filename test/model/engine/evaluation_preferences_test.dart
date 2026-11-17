import 'package:chess_srs/src/model/engine/evaluation_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multistockfish/multistockfish.dart';

void main() {
  group('ChessEnginePref', () {
    test('sfLight exposes label, short label and flavor', () {
      expect(ChessEnginePref.sfLight.label, 'Stockfish 19 (1MB)');
      expect(ChessEnginePref.sfLight.shortLabel, 'SF 19 1MB');
      expect(ChessEnginePref.sfLight.flavor, StockfishFlavor.light);
    });

    test('sfLatest exposes label, short label and flavor', () {
      expect(ChessEnginePref.sfLatest.label, 'Stockfish 19 (94MB)');
      expect(ChessEnginePref.sfLatest.shortLabel, 'SF 19');
      expect(ChessEnginePref.sfLatest.flavor, StockfishFlavor.latestNoNNUE);
    });
  });

  group('EngineEvaluationPrefState', () {
    test('defaults match expected engine evaluation settings', () {
      const state = EngineEvaluationPrefState.defaults;

      expect(state.isEnabled, isTrue);
      expect(state.numEvalLines, 2);
      expect(state.numEngineCores, 1);
      expect(state.engineSearchTime, const Duration(seconds: 4));
      expect(state.enginePref, ChessEnginePref.sfLight);
    });

    test('toJson/fromJson round-trip preserves values', () {
      const state = EngineEvaluationPrefState(
        isEnabled: false,
        numEvalLines: 3,
        numEngineCores: 4,
        engineSearchTime: Duration(seconds: 12),
        enginePref: ChessEnginePref.sfLatest,
      );

      final json = state.toJson();
      final restored = EngineEvaluationPrefState.fromJson(json);

      expect(json['isEnabled'], isFalse);
      expect(json['numEvalLines'], 3);
      expect(json['numEngineCores'], 4);
      expect(json['engineSearchTime'], 12);
      expect(json['enginePref'], 'sfLatest');
      expect(restored, state);
    });

    test('fromJson applies defaults for missing search time and engine pref', () {
      final state = EngineEvaluationPrefState.fromJson({
        'isEnabled': true,
        'numEvalLines': 1,
        'numEngineCores': 2,
      });

      expect(state.engineSearchTime, const Duration(seconds: 6));
      expect(state.enginePref, ChessEnginePref.sfLight);
    });

    test('fromJson maps unknown engine pref to sfLight', () {
      final state = EngineEvaluationPrefState.fromJson({
        'isEnabled': true,
        'numEvalLines': 1,
        'numEngineCores': 1,
        'engineSearchTime': 8,
        'enginePref': 'unknownEngine',
      });

      expect(state.enginePref, ChessEnginePref.sfLight);
      expect(state.engineSearchTime, const Duration(seconds: 8));
    });
  });

  group('engine search time constants', () {
    test('available times are ascending and end with max engine search time', () {
      expect(kAvailableEngineSearchTimes, isNotEmpty);
      expect(kAvailableEngineSearchTimes.last, kMaxEngineSearchTime);
      expect(kMaxEngineSearchTime, const Duration(hours: 1));

      for (var i = 1; i < kAvailableEngineSearchTimes.length; i++) {
        expect(
          kAvailableEngineSearchTimes[i] > kAvailableEngineSearchTimes[i - 1],
          isTrue,
          reason: 'search times must be strictly ascending',
        );
      }
    });

    test('available times include default and documented presets', () {
      expect(kAvailableEngineSearchTimes, contains(const Duration(seconds: 2)));
      expect(
        kAvailableEngineSearchTimes,
        contains(EngineEvaluationPrefState.defaults.engineSearchTime),
      );
      expect(kAvailableEngineSearchTimes, contains(const Duration(seconds: 30)));
    });
  });
}
