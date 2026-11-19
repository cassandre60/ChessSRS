// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TransposeScope', () {
    test('exposes stable values in declaration order', () {
      expect(TransposeScope.values, const [
        TransposeScope.off,
        TransposeScope.withinStudy,
        TransposeScope.inScope,
      ]);
    });

    test('value names are stable', () {
      expect(TransposeScope.off.name, 'off');
      expect(TransposeScope.withinStudy.name, 'withinStudy');
      expect(TransposeScope.inScope.name, 'inScope');
    });
  });
}
