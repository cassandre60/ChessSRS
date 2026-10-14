import 'package:chess_srs/src/model/analysis/analysis_controller.dart';
import 'package:chess_srs/src/model/analysis/analysis_preferences.dart';
import 'package:chess_srs/src/model/engine/position_evaluator.dart';
import 'package:chess_srs/src/view/analysis/analysis_board.dart';
import 'package:chess_srs/src/widgets/pgn_shapes.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class GameAnalysisBoard extends AnalysisBoard {
  const GameAnalysisBoard({
    required this.options,
    required super.boardSize,
    super.boardRadius,
    this.shouldReplaceChildOnUserMove = false,
  });

  final AnalysisOptions options;

  final bool shouldReplaceChildOnUserMove;

  @override
  ConsumerState<GameAnalysisBoard> createState() => _GameAnalysisBoardState();
}

class _GameAnalysisBoardState
    extends AnalysisBoardState<GameAnalysisBoard, AnalysisState, AnalysisPrefs> {
  @override
  AnalysisState? readCurrentState() => ref.read(analysisControllerProvider(widget.options)).value;

  @override
  void listenToStateChanges(void Function(AnalysisState? prev, AnalysisState? next) listener) =>
      ref.listenManual<AnalysisState?>(
        analysisControllerProvider(widget.options).select((v) => v.value),
        listener,
      );

  @override
  AnalysisState get analysisState =>
      ref.watch(analysisControllerProvider(widget.options)).requireValue;

  @override
  EngineEvaluationFilters get engineEvaluationFilters =>
      (context: analysisState.evaluationContext, path: analysisState.currentPath);

  @override
  String computeFen(AnalysisState state) => state.currentPosition.fen;

  @override
  AnalysisPrefs get analysisPrefs => ref.watch(analysisPreferencesProvider);

  @override
  bool get showAnnotations =>
      analysisState.isComputerAnalysisAllowed &&
      analysisState.isServerAnalysisEnabled &&
      analysisPrefs.showAnnotations;

  @override
  void onUserMove(Move move) => ref
      .read(analysisControllerProvider(widget.options).notifier)
      .onUserMove(move, shouldReplace: widget.shouldReplaceChildOnUserMove);

  @override
  ISet<Shape> get extraShapes {
    final analysisState = ref.watch(analysisControllerProvider(widget.options)).requireValue;
    final pgnShapes = ISet(analysisState.pgnShapes.map((shape) => shape.chessground));
    return pgnShapes;
  }
}
