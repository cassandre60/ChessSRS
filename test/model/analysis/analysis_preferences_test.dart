import 'package:chess_srs/src/model/analysis/analysis_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AnalysisPrefs', () {
    test('defaults match expected analysis settings', () {
      const prefs = AnalysisPrefs.defaults;

      expect(prefs.enableServerAnalysis, isTrue);
      expect(prefs.showEvaluationGauge, isTrue);
      expect(prefs.showEngineLines, isTrue);
      expect(prefs.showBestMoveArrow, isTrue);
      expect(prefs.showAnnotations, isTrue);
      expect(prefs.showPgnComments, isTrue);
      expect(prefs.inlineNotation, isFalse);
      expect(prefs.smallBoard, isFalse);
    });

    test('toJson/fromJson round-trips current preferences', () {
      const prefs = AnalysisPrefs(
        enableServerAnalysis: false,
        showEvaluationGauge: false,
        showEngineLines: false,
        showBestMoveArrow: false,
        showAnnotations: false,
        showPgnComments: false,
        inlineNotation: true,
        smallBoard: true,
      );

      expect(AnalysisPrefs.fromJson(prefs.toJson()), equals(prefs));
    });

    test('fromJson applies JsonKey defaults for omitted booleans', () {
      final prefs = AnalysisPrefs.fromJson(const <String, dynamic>{
        'showEvaluationGauge': false,
        'showBestMoveArrow': false,
        'showAnnotations': false,
        'showPgnComments': false,
      });

      expect(prefs.enableServerAnalysis, isTrue);
      expect(prefs.showEngineLines, isTrue);
      expect(prefs.inlineNotation, isFalse);
      expect(prefs.smallBoard, isFalse);
      expect(prefs.showEvaluationGauge, isFalse);
      expect(prefs.showBestMoveArrow, isFalse);
      expect(prefs.showAnnotations, isFalse);
      expect(prefs.showPgnComments, isFalse);
    });
  });
}
