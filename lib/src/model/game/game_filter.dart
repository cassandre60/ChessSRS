import 'package:chess_srs/src/model/common/perf.dart';
import 'package:chess_srs/src/model/user/user.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'game_filter.freezed.dart';

/// A provider for [GameFilter].
final gameFilterProvider = NotifierProvider.autoDispose
    .family<GameFilter, GameFilterState, GameFilterState?>(
      GameFilter.new,
      name: 'GameFilterProvider',
    );

class GameFilter extends Notifier<GameFilterState> {
  GameFilter(this.filter);

  final GameFilterState? filter;

  @override
  GameFilterState build() {
    return filter ?? const GameFilterState();
  }

  void setFilter(GameFilterState filter) =>
      state = state.copyWith(perfs: filter.perfs, side: filter.side);
}

@freezed
sealed class GameFilterState with _$GameFilterState {
  const GameFilterState._();

  const factory GameFilterState({
    @Default(ISet<Perf>.empty()) ISet<Perf> perfs,
    Side? side,
    User? opponent,
  }) = _GameFilterState;

  int get count {
    final fields = [perfs, side];
    return fields.where((field) => field is Iterable ? field.isNotEmpty : field != null).length;
  }
}
