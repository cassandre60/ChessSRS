import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

final reviewNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'review');

/// The app's only navigator. Four call sites resolve a navigator through this provider rather
/// than reaching for [reviewNavigatorKey] directly, which keeps them working if the key ever
/// moves.
final currentNavigatorKeyProvider = Provider<GlobalKey<NavigatorState>>(
  (ref) => reviewNavigatorKey,
);

/// A [NavigatorObserver] that keeps track of the routes currently on the
/// navigator it observes, so that code can query whether a named route is
/// present in the stack (which Flutter does not expose publicly).
class RouteStackObserver extends NavigatorObserver {
  final List<Route<dynamic>> _stack = [];

  /// Whether a route with the given [name] is currently in the stack.
  ///
  /// If [arguments] is provided, the route's [RouteSettings.arguments] must also
  /// be equal to it.
  bool containsRoute(String name, {Object? arguments}) => _stack.any(
    (route) =>
        route.settings.name == name && (arguments == null || route.settings.arguments == arguments),
  );

  /// Clears the tracked stack. Only useful in tests, where the global instance
  /// is shared across test cases.
  @visibleForTesting
  void clear() => _stack.clear();

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute != null ? _stack.indexOf(oldRoute) : -1;
    if (index >= 0 && newRoute != null) {
      _stack[index] = newRoute;
    } else {
      if (oldRoute != null) _stack.remove(oldRoute);
      if (newRoute != null) _stack.add(newRoute);
    }
  }
}

/// Tracks the stack of routes on the root navigator (see [rootNavRouteStackObserver]
/// registration in `app.dart`).
final RouteStackObserver rootNavRouteStackObserver = RouteStackObserver();

final RouteObserver<PageRoute<void>> rootNavPageRouteObserver = RouteObserver<PageRoute<void>>();
