import 'package:chess_srs/src/model/analysis/common_analysis_prefs.dart';
import 'package:chess_srs/src/model/settings/preferences_storage.dart';
import 'package:chess_srs/src/model/study/study_filter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'study_preferences.freezed.dart';
part 'study_preferences.g.dart';

enum SchedulerType {
  @JsonValue('fsrs')
  fsrs,
  @JsonValue('simple')
  simple,
  @JsonValue('easeScaling')
  easeScaling;

  String get label => switch (this) {
    SchedulerType.fsrs => 'ChessFSRS (DSR Power-Law)',
    SchedulerType.simple => 'Simple Doubling (2x)',
    SchedulerType.easeScaling => 'Parametric Scaling (chessrs)',
  };

  String get description => switch (this) {
    SchedulerType.fsrs =>
      'Domain-adapted FSRS-5 continuous DSR model with target retention and binary grading',
    SchedulerType.simple => 'Exponential doubling interval ladder (1d, 2d, 4d, 8d...)',
    SchedulerType.easeScaling =>
      'chessrs formula with tunable ease multiplier and geometric scaling factor',
  };
}

final studyPreferencesProvider = NotifierProvider<StudyPreferencesNotifier, StudyPrefs>(
  StudyPreferencesNotifier.new,
  name: 'StudyPreferencesProvider',
);

class StudyPreferencesNotifier extends Notifier<StudyPrefs> with PreferencesStorage<StudyPrefs> {
  @override
  @protected
  final prefCategory = PrefCategory.study;

  @override
  @protected
  StudyPrefs get defaults => StudyPrefs.defaults;

  @override
  StudyPrefs fromJson(Map<String, dynamic> json) => StudyPrefs.fromJson(json);

  @override
  StudyPrefs build() {
    return fetch();
  }

  Future<void> setListOrder(StudyListOrder order) {
    return save(state.copyWith(listOrder: order));
  }

  Future<void> toggleShowVariationArrows() {
    return save(state.copyWith(showVariationArrows: !state.showVariationArrows));
  }

  Future<void> toggleShowEvaluationGauge() {
    return save(state.copyWith(showEvaluationGauge: !state.showEvaluationGauge));
  }

  Future<void> toggleShowEngineLines() {
    return save(state.copyWith(showEngineLines: !state.showEngineLines));
  }

  Future<void> toggleShowMoveHistory() {
    return save(state.copyWith(showMoveHistory: !state.showMoveHistory));
  }

  Future<void> setShowMoveHistory(bool show) {
    return save(state.copyWith(showMoveHistory: show));
  }

  Future<void> toggleAnnotations() {
    return save(state.copyWith(showAnnotations: !state.showAnnotations));
  }

  Future<void> setShowAnnotations(bool show) {
    return save(state.copyWith(showAnnotations: show));
  }

  Future<void> togglePgnComments() {
    return save(state.copyWith(showPgnComments: !state.showPgnComments));
  }

  Future<void> toggleShowBestMoveArrow() {
    return save(state.copyWith(showBestMoveArrow: !state.showBestMoveArrow));
  }

  Future<void> toggleInlineNotation() {
    return save(state.copyWith(inlineNotation: !state.inlineNotation));
  }

  Future<void> toggleSmallBoard() {
    return save(state.copyWith(smallBoard: !state.smallBoard));
  }

  Future<void> toggleAnimateOpponentPreMove() {
    return save(state.copyWith(animateOpponentPreMove: !state.animateOpponentPreMove));
  }

  Future<void> setSchedulerType(SchedulerType type) {
    return save(state.copyWith(schedulerType: type));
  }

  Future<void> setSchedulerEase(double ease) {
    return save(state.copyWith(schedulerEase: ease));
  }

  Future<void> setSchedulerScaling(double scaling) {
    return save(state.copyWith(schedulerScaling: scaling));
  }

  Future<void> setTargetRetention(double retention) {
    return save(state.copyWith(targetRetention: retention));
  }

  Future<void> setMaxDailyReviews(int limit) {
    return save(state.copyWith(maxDailyReviews: limit));
  }

  Future<void> toggleSrsDiagnostics() {
    return save(state.copyWith(srsDiagnostics: !state.srsDiagnostics));
  }
}

@Freezed(fromJson: true, toJson: true)
sealed class StudyPrefs with _$StudyPrefs implements Serializable, CommonAnalysisPrefs {
  const StudyPrefs._();

  const factory StudyPrefs({
    required bool showVariationArrows,
    @JsonKey(defaultValue: true) required bool showEvaluationGauge,
    @JsonKey(defaultValue: true) required bool showEngineLines,
    @JsonKey(defaultValue: true) required bool showBestMoveArrow,
    @JsonKey(defaultValue: true) required bool showAnnotations,
    @JsonKey(defaultValue: true) required bool showPgnComments,
    @JsonKey(defaultValue: true) required bool animateOpponentPreMove,
    @JsonKey(defaultValue: false) required bool inlineNotation,
    @JsonKey(defaultValue: false) required bool smallBoard,
    @JsonKey(defaultValue: false) required bool srsDiagnostics,
    @JsonKey(defaultValue: true) required bool showMoveHistory,
    @JsonKey(defaultValue: StudyListOrder.hot) required StudyListOrder listOrder,
    @JsonKey(defaultValue: SchedulerType.simple) required SchedulerType schedulerType,
    @JsonKey(defaultValue: 0.88) required double targetRetention,
    @JsonKey(defaultValue: 2.5) required double schedulerEase,
    @JsonKey(defaultValue: 1.5) required double schedulerScaling,
    @JsonKey(defaultValue: 100) required int maxDailyReviews,
  }) = _StudyPrefs;

  static const defaults = StudyPrefs(
    showVariationArrows: false,
    showEvaluationGauge: true,
    showEngineLines: true,
    showBestMoveArrow: true,
    showAnnotations: true,
    showPgnComments: true,
    animateOpponentPreMove: true,
    inlineNotation: false,
    smallBoard: false,
    srsDiagnostics: false,
    showMoveHistory: true,
    listOrder: StudyListOrder.hot,
    schedulerType: SchedulerType.simple,
    targetRetention: 0.88,
    schedulerEase: 2.5,
    schedulerScaling: 1.5,
    maxDailyReviews: 100,
  );

  factory StudyPrefs.fromJson(Map<String, dynamic> json) {
    return _$StudyPrefsFromJson(json);
  }
}
