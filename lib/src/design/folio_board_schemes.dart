// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// Folio board colour schemes: flat-square alternatives to the hatched Diagram board,
// taken from the look-judge demo (`.opencode/plan/visual-demo.html`, board switch).
// Paper is warm paper/stone; Slate is its cooler sibling. Neither is SRS-backed, so
// they render identically in both app themes like every other chessground preset —
// the per-theme Folio token integration (grain veil, accent washes) is later work.
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter/widgets.dart' show Color;

/// Warm paper/stone squares (`#FFF9F1` / `#EEE6D3`).
const paperBoardScheme = ChessboardColorScheme(
  lightSquare: Color(0xfffff9f1),
  darkSquare: Color(0xffeee6d3),
  background: SolidColorChessboardBackground(
    lightSquare: Color(0xfffff9f1),
    darkSquare: Color(0xffeee6d3),
  ),
  whiteCoordBackground: SolidColorChessboardBackground(
    lightSquare: Color(0xfffff9f1),
    darkSquare: Color(0xffeee6d3),
    coordinates: true,
  ),
  blackCoordBackground: SolidColorChessboardBackground(
    lightSquare: Color(0xfffff9f1),
    darkSquare: Color(0xffeee6d3),
    coordinates: true,
    orientation: Side.black,
  ),
  lastMove: HighlightDetails(solidColor: Color(0x809cc700)),
  selected: HighlightDetails(solidColor: Color(0x6014551e)),
  validMoves: Color(0x4014551e),
  validPremoves: Color(0x40203085),
);

/// Cooler light/dark squares (`#E9EEF3` / `#D6DEE8`).
const slateBoardScheme = ChessboardColorScheme(
  lightSquare: Color(0xffe9eef3),
  darkSquare: Color(0xffd6dee8),
  background: SolidColorChessboardBackground(
    lightSquare: Color(0xffe9eef3),
    darkSquare: Color(0xffd6dee8),
  ),
  whiteCoordBackground: SolidColorChessboardBackground(
    lightSquare: Color(0xffe9eef3),
    darkSquare: Color(0xffd6dee8),
    coordinates: true,
  ),
  blackCoordBackground: SolidColorChessboardBackground(
    lightSquare: Color(0xffe9eef3),
    darkSquare: Color(0xffd6dee8),
    coordinates: true,
    orientation: Side.black,
  ),
  lastMove: HighlightDetails(solidColor: Color(0x809cc700)),
  selected: HighlightDetails(solidColor: Color(0x6014551e)),
  validMoves: Color(0x4014551e),
  validPremoves: Color(0x40203085),
);
