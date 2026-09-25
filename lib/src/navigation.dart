// The app's root navigator, and the route observers attached to it.
//
// This file used to hold the whole bottom-tab machinery: `BottomTab`,
// `MainTabScaffoldProperties`, the per-tab navigator keys and scroll controllers. The
// visual identity removed the navigation bar ("No navigation bar. The board owns the
// screen; everything else is behind one button" — demo, *What replaced what*), and
// `app.dart` has mounted `ReviewScreen` as `home` ever since, so none of that was
// reachable. It has been deleted, along with `tab_scaffold.dart` and `view/more/`.
//
// What remains here is what the app actually still uses: the root navigator key, and the
// two observers registered in `app.dart`.
//
// The navigator key used to be reachable as `currentNavigatorKeyProvider`, which returned
// the *tab* navigator key. That key was never mounted, so its `currentContext` was always
// null and the five services that used it — app deep links, quick actions, share intents,
// engine errors and the weights download — silently did nothing. The key is now the one
// `MaterialApp` is actually given.

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The root navigator, as mounted by `MaterialApp` in `app.dart`.
///
/// `app.dart` reads this same key for `MaterialApp.navigatorKey`, so there is exactly one
/// navigator. Read `.currentContext` from it to push a route or show a dialog from a
/// service that has no `BuildContext` of its own; it is null until the first frame.
final rootNavigatorKeyProvider = Provider<GlobalKey<NavigatorState>>(
  (ref) => GlobalKey<NavigatorState>(debugLabel: 'root'),
);

/// A [NavigatorObserver] that keeps track of the routes currently on the
/// navigator it observes, so that code can query whether a named route is
/// present in the stack (which Flutter does not expose publicly).
class RouteStackObserver extends NavigatorObserver {
  final List<Route<dynamic>> _stack = [];

  /// Whether a route with the given [name] is currently in the stack.
  ///
  /// If [arguments] is provided, the route's [RouteSettings.arguments] must also be
  /// equal to it.
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
