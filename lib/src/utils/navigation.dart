import 'package:material_ui/material_ui.dart';

/// A page route that always builds the same screen widget.
///
/// This is useful to inspect new screens being pushed to the Navigator in tests.
abstract class ScreenRoute<T extends Object?> extends PageRoute<T> {
  /// The widget that this page route always builds.
  Widget get screen;
}

/// A [MaterialPageRoute] that always builds the same screen widget.
class MaterialScreenRoute<T extends Object?> extends MaterialPageRoute<T>
    implements ScreenRoute<T> {
  MaterialScreenRoute({
    required this.screen,
    super.settings,
    super.maintainState,
    super.fullscreenDialog,
    super.allowSnapshotting,
    this.overrideTransitionDuration,
  }) : super(builder: (_) => screen);

  @override
  final Widget screen;

  final Duration? overrideTransitionDuration;

  @override
  Duration get transitionDuration => overrideTransitionDuration ?? super.transitionDuration;
}

/// Builds a new route for the [screen].
Route<T> buildScreenRoute<T>({
  required Widget screen,
  bool fullscreenDialog = false,
  RouteSettings? settings,
  Duration? transitionDuration,
}) {
  return MaterialScreenRoute<T>(
    screen: screen,
    fullscreenDialog: fullscreenDialog,
    settings: settings,
    overrideTransitionDuration: transitionDuration,
  );
}
