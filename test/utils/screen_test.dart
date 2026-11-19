// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/constants.dart';
import 'package:chess_srs/src/utils/screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('estimateHeightMinusBoard', () {
    test('subtracts view padding, board width and chrome from the screen height', () {
      const size = Size(400, 800);
      const viewPadding = EdgeInsets.only(top: 20, bottom: 40);
      const mediaQuery = MediaQueryData(size: size, padding: viewPadding, viewPadding: viewPadding);

      // 800 - (20 + 40) - 400 (board width) - toolbar - bottom bar.
      expect(
        estimateHeightMinusBoard(mediaQuery),
        800 - 60 - 400 - kToolbarHeight - kBottomBarHeight,
      );
    });

    test('returns the full height when nothing is padded or overlaid', () {
      const size = Size(400, 800);
      const mediaQuery = MediaQueryData(size: size);

      expect(estimateHeightMinusBoard(mediaQuery), 800 - 400 - kToolbarHeight - kBottomBarHeight);
    });

    test('honours vertical view padding only', () {
      const size = Size(320, 568);
      const viewPadding = EdgeInsets.only(top: 47, bottom: 63);
      const mediaQuery = MediaQueryData(size: size, padding: viewPadding, viewPadding: viewPadding);

      expect(
        estimateHeightMinusBoard(mediaQuery),
        568 - 110 - 320 - kToolbarHeight - kBottomBarHeight,
      );
    });
  });

  group('pocketSquareSize', () {
    test('divides the board size into an eighth-sized grid', () {
      expect(pocketSquareSize(boardSize: 800, isTablet: false), 100);
    });

    test('scales pocket squares down on tablets to avoid overflow', () {
      // Tablets show the pockets at a reduced size so piece-sized targets do not overflow.
      expect(pocketSquareSize(boardSize: 800, isTablet: true), closeTo(70, 0.0001));
    });
  });

  group('FormFactor', () {
    test('exposes the documented breakpoints', () {
      expect(FormFactor.handset, 300);
      expect(FormFactor.tablet, 600);
      expect(FormFactor.desktop, 900);
    });
  });

  group('ScreenType', () {
    test('orders watch < handset < tablet < desktop', () {
      expect(ScreenType.watch < ScreenType.handset, isTrue);
      expect(ScreenType.handset < ScreenType.tablet, isTrue);
      expect(ScreenType.tablet < ScreenType.desktop, isTrue);
      expect(ScreenType.watch <= ScreenType.watch, isTrue);
      expect(ScreenType.desktop > ScreenType.desktop, isFalse);
      expect(ScreenType.tablet >= ScreenType.tablet, isTrue);
    });
  });

  group('getScreenType', () {
    testWidgets('returns desktop for screens wider than the desktop breakpoint', (tester) async {
      late ScreenType type;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(1000, 1200)),
          child: Builder(
            builder: (context) {
              type = getScreenType(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(type, ScreenType.desktop);
    });

    testWidgets('returns tablet for screens wider than the tablet breakpoint', (tester) async {
      late ScreenType type;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(700, 800)),
          child: Builder(
            builder: (context) {
              type = getScreenType(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(type, ScreenType.tablet);
    });

    testWidgets('returns handset for screens wider than the handset breakpoint', (tester) async {
      late ScreenType type;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(400, 800)),
          child: Builder(
            builder: (context) {
              type = getScreenType(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(type, ScreenType.handset);
    });

    testWidgets('returns watch for screens smaller than the handset breakpoint', (tester) async {
      late ScreenType type;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(200, 400)),
          child: Builder(
            builder: (context) {
              type = getScreenType(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(type, ScreenType.watch);
    });
  });

  group('isTabletOrLarger', () {
    testWidgets('is false on a handset-sized screen', (tester) async {
      var result = true;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(400, 800)),
          child: Builder(
            builder: (context) {
              result = isTabletOrLarger(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(result, isFalse);
    });

    testWidgets('is true on a tablet-sized screen', (tester) async {
      var result = false;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(700, 800)),
          child: Builder(
            builder: (context) {
              result = isTabletOrLarger(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(result, isTrue);
    });
  });

  group('isShortVerticalScreen', () {
    testWidgets('flags screens with too little height left after the board', (tester) async {
      tester.view.physicalSize = const Size(320, 400) * tester.view.devicePixelRatio;
      addTearDown(tester.view.resetPhysicalSize);

      var short = false;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(320, 400)),
          child: Builder(
            builder: (context) {
              short = isShortVerticalScreen(context);
              return const SizedBox();
            },
          ),
        ),
      );

      // 400 - 320 (board) - toolbar - bottom bar = -32, well under the 200px threshold.
      expect(short, isTrue);
    });

    testWidgets('is false when enough height remains after the board', (tester) async {
      tester.view.physicalSize = const Size(400, 800) * tester.view.devicePixelRatio;
      addTearDown(tester.view.resetPhysicalSize);

      var short = true;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(400, 800)),
          child: Builder(
            builder: (context) {
              short = isShortVerticalScreen(context);
              return const SizedBox();
            },
          ),
        ),
      );

      // 800 - 400 (board) - toolbar - bottom bar = 288, above the 200px threshold.
      expect(short, isFalse);
    });
  });
}
