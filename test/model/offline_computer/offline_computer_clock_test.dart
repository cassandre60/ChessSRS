// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/model/offline_computer/offline_computer_clock.dart';
import 'package:chess_srs/src/model/offline_computer/offline_computer_game_preferences.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OfflineComputerClock', () {
    test('defaults to the offline computer game default time increment', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final state = container.read(offlineComputerClockProvider);
      expect(state.timeIncrement, OfflineComputerGamePrefs.defaults.timeIncrement);
      expect(state.timeIncrement.isInfinite, isTrue);
      expect(state.whiteTimeLeft, isNull);
      expect(state.blackTimeLeft, isNull);
      expect(state.activeClock, isNull);
      expect(state.active, isFalse);
      expect(state.flagSide, isNull);
    });

    test('switchSide is a no-op on an infinite clock', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container
          .read(offlineComputerClockProvider.notifier)
          .switchSide(newSideToMove: Side.black, addIncrement: true);

      final state = container.read(offlineComputerClockProvider);
      expect(state.activeClock, isNull);
      expect(state.active, isFalse);
      expect(state.whiteTimeLeft, isNull);
      expect(state.blackTimeLeft, isNull);
    });

    test('onMove is a no-op on an infinite clock', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(offlineComputerClockProvider.notifier).onMove(newSideToMove: Side.black);

      final state = container.read(offlineComputerClockProvider);
      expect(state.activeClock, isNull);
      expect(state.active, isFalse);
    });
  });
}
