import 'package:chess_srs/src/model/common/perf.dart';
import 'package:chess_srs/src/model/game/game_filter.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GameFilterState', () {
    test('defaults to no active filters', () {
      const state = GameFilterState();

      expect(state.perfs, isEmpty);
      expect(state.side, isNull);
      expect(state.opponent, isNull);
      expect(state.count, 0);
    });

    test('count includes non-empty perf selection', () {
      final state = GameFilterState(perfs: ISet(const {Perf.blitz, Perf.rapid}));

      expect(state.count, 1);
    });

    test('count includes selected side', () {
      const state = GameFilterState(side: Side.white);

      expect(state.count, 1);
    });

    test('count includes perfs and side independently', () {
      final state = GameFilterState(perfs: ISet(const {Perf.bullet}), side: Side.black);

      expect(state.count, 2);
    });

    test('empty perf set does not count as an active filter', () {
      const state = GameFilterState(perfs: ISetConst({}), side: Side.white);

      expect(state.count, 1);
    });
  });
}
