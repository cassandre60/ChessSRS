// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

/// Pure presentation helper: maps PGN comment shapes to chessground Shapes.
///
/// Single source of truth for the conversion previously triplicated byte-for-byte
/// in `game_analysis_board.dart`, `review_screen.dart` and `study_screen.dart`
/// (tech-debt item 1). The types come from the same entry points those files used —
/// `PgnCommentShape`/`CommentShapeColor` from `package:dartchess/dartchess.dart`,
/// `Shape`/`Arrow`/`Circle`/`ShapeColor` from `package:chessground/chessground.dart` —
/// so moving the extension changes its library, not what it resolves to.
library;

import 'package:chess_srs/src/model/settings/board_preferences.dart' show ShapeColor;
import 'package:chessground/chessground.dart' show Arrow, Circle, Shape;
import 'package:dartchess/dartchess.dart' show CommentShapeColor, PgnCommentShape;

extension PgnCommentShapeChessground on PgnCommentShape {
  Shape get chessground {
    final shapeColor = switch (color) {
      CommentShapeColor.green => ShapeColor.green,
      CommentShapeColor.red => ShapeColor.red,
      CommentShapeColor.blue => ShapeColor.blue,
      CommentShapeColor.yellow => ShapeColor.yellow,
    };
    return from != to
        ? Arrow(color: shapeColor.color, orig: from, dest: to)
        : Circle(color: shapeColor.color, orig: from);
  }
}
