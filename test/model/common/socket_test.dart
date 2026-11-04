// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/model/common/socket.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SocketEvent.fromJson', () {
    test('unsupported payload triggers an assertion (debug)', () {
      expect(() => SocketEvent.fromJson(const {}), throwsA(isA<AssertionError>()));
    });
  });
}
