// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/model/settings/board_preferences.dart';
import 'package:chess_srs/src/widgets/pgn_shapes.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

// TECH-DEBT item 1: one extension, three consumers, byte-for-byte identical.
void main() {
  test('PgnCommentShape.chessground maps green arrow', () {
    const s = PgnCommentShape(color: CommentShapeColor.green, from: Square.e2, to: Square.e4);
    final shape = s.chessground;
    expect(shape, isA<Arrow>());
    final arrow = shape as Arrow;
    expect(arrow.color, ShapeColor.green.color);
    expect(arrow.orig, Square.e2);
    expect(arrow.dest, Square.e4);
  });

  test('PgnCommentShape.chessground maps yellow circle', () {
    const s = PgnCommentShape(color: CommentShapeColor.yellow, from: Square.e4, to: Square.e4);
    final shape = s.chessground;
    expect(shape, isA<Circle>());
    final circle = shape as Circle;
    expect(circle.color, ShapeColor.yellow.color);
    expect(circle.orig, Square.e4);
  });
}
