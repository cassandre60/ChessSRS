// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/model/engine/evaluation_mixin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('likelyNodesFor', () {
    test('estimates nodes at the observed rate', () {
      // 1000 nodes in 100ms projects to 10000 in 1000ms.
      expect(
        likelyNodesFor(
          targetTime: const Duration(milliseconds: 1000),
          nodes: 1000,
          elapsed: const Duration(milliseconds: 100),
        ),
        10000,
      );
    });

    test('returns null for zero elapsed time instead of throwing', () {
      // The engine's first near-instant infos report 0ms elapsed; dividing
      // by it yields Infinity, and Infinity.round() throws inside the eval
      // listener, killing all later local evals for that work.
      expect(
        likelyNodesFor(
          targetTime: const Duration(milliseconds: 1000),
          nodes: 1000,
          elapsed: Duration.zero,
        ),
        isNull,
      );
    });

    test('returns null for negative node counts', () {
      expect(
        likelyNodesFor(
          targetTime: const Duration(milliseconds: 1000),
          nodes: -1,
          elapsed: const Duration(milliseconds: 100),
        ),
        isNull,
      );
    });
  });
}
