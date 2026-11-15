import 'package:chess_srs/src/utils/navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MaterialScreenRoute', () {
    test('stores screen and route properties', () {
      const screen = Placeholder();
      const settings = RouteSettings(name: '/test');

      final route = MaterialScreenRoute<void>(
        screen: screen,
        settings: settings,
        fullscreenDialog: true,
        maintainState: false,
        allowSnapshotting: false,
        overrideTransitionDuration: const Duration(milliseconds: 250),
      );

      expect(route.screen, same(screen));
      expect(route.settings, settings);
      expect(route.fullscreenDialog, isTrue);
      expect(route.maintainState, isFalse);
      expect(route.allowSnapshotting, isFalse);
      expect(route.overrideTransitionDuration, const Duration(milliseconds: 250));
      expect(route.transitionDuration, const Duration(milliseconds: 250));
      expect(route, isA<ScreenRoute<void>>());
      expect(route, isA<PageRoute<void>>());
    });

    test('leaves overrideTransitionDuration null by default', () {
      final route = MaterialScreenRoute<void>(screen: const Placeholder());

      expect(route.overrideTransitionDuration, isNull);
    });
  });

  group('buildScreenRoute', () {
    test('builds a MaterialScreenRoute with provided values', () {
      const screen = Placeholder();
      const settings = RouteSettings(name: '/route');

      final route = buildScreenRoute<void>(
        screen: screen,
        fullscreenDialog: true,
        settings: settings,
        transitionDuration: const Duration(milliseconds: 123),
      );

      expect(route, isA<MaterialScreenRoute<void>>());
      final materialRoute = route as MaterialScreenRoute<void>;
      expect(materialRoute.screen, same(screen));
      expect(materialRoute.fullscreenDialog, isTrue);
      expect(materialRoute.settings, settings);
      expect(materialRoute.overrideTransitionDuration, const Duration(milliseconds: 123));
      expect(materialRoute.transitionDuration, const Duration(milliseconds: 123));
    });

    test('builds route with default fullscreenDialog false', () {
      final route = buildScreenRoute<void>(screen: const Placeholder());

      expect(route, isA<MaterialScreenRoute<void>>());
      final materialRoute = route as MaterialScreenRoute<void>;
      expect(materialRoute.fullscreenDialog, isFalse);
      expect(materialRoute.overrideTransitionDuration, isNull);
    });
  });
}
