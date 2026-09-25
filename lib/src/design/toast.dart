// Toast: the design's only transient feedback surface.
//
// Design source: the demo's `.toast` rules and design/docs/03-components.md §12 —
// an ink pill on the ground, `ground` text 14/500, padding 11/18, radius 999, 24 from
// the bottom, centred, one line, no actions. It fades in over 160ms while rising 10px,
// stays 2.4s, and never takes pointer input.
//
// The prototype has exactly one toast element and reuses it, so showing a new message
// replaces the message already on screen rather than stacking a second pill.
import 'dart:async';

import 'package:chess_srs/src/design/tokens.dart';
import 'package:flutter/widgets.dart';

/// Key of the painted pill, so tests can measure the pill rather than the full-width
/// [Align] that positions it.
const kSrsToastPillKey = ValueKey('srs-toast-pill');

/// Shows [message] in the design's toast pill, replacing any toast already visible.
///
/// The toast removes itself after [SrsMotion.toastVisible]. Requires a [BuildContext]
/// with an [Overlay] ancestor, which the app root always provides.
void showSrsToast(BuildContext context, String message) {
  _SrsToastHost.of(Overlay.of(context)).show(message);
}

/// The toast pill. Exposed for tests; prefer [showSrsToast].
class SrsToast extends StatelessWidget {
  const SrsToast(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final c = context.srs;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Container(
          key: kSrsToastPillKey,
          constraints: const BoxConstraints(maxWidth: 328),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(999)),
          child: Text(
            message,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: SrsText.toast(c.ground),
          ),
        ),
      ),
    );
  }
}

/// Hosts at most one toast for an [Overlay].
///
/// The host is an overlay entry of its own, so its [Timer] is cancelled when the overlay
/// is disposed. A static registry of timers outlives the widget tree and trips the test
/// framework's "a Timer is still pending" invariant.
class _SrsToastHost {
  static _SrsToastHost of(OverlayState overlay) =>
      _hosts[overlay] ??= _SrsToastHost._insertInto(overlay);

  static _SrsToastHost _insertInto(OverlayState overlay) {
    final host = _SrsToastHost._();
    overlay.insert(OverlayEntry(builder: (_) => _SrsToastView(host: host)));
    return host;
  }

  /// Keyed weakly by the overlay, so a disposed overlay drops its host and the host's
  /// timer with it.
  static final Expando<_SrsToastHost> _hosts = Expando<_SrsToastHost>('srs-toast');

  _SrsToastHost._();

  String? message;
  Timer? timer;
  final _listeners = <VoidCallback>[];

  void show(String value) {
    message = value;
    timer?.cancel();
    timer = Timer(SrsMotion.toastVisible, hide);
    _notify();
  }

  void hide() {
    timer?.cancel();
    timer = null;
    message = null;
    _notify();
  }

  void _notify() {
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }

  /// Called when the owning overlay is disposed.
  void dispose() {
    timer?.cancel();
    timer = null;
    message = null;
    _listeners.clear();
  }
}

class _SrsToastView extends StatefulWidget {
  const _SrsToastView({required this.host});

  final _SrsToastHost host;

  @override
  State<_SrsToastView> createState() => _SrsToastViewState();
}

class _SrsToastViewState extends State<_SrsToastView> {
  @override
  void initState() {
    super.initState();
    widget.host._listeners.add(_onChange);
  }

  @override
  void didUpdateWidget(_SrsToastView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.host != widget.host) {
      oldWidget.host._listeners.remove(_onChange);
      widget.host._listeners.add(_onChange);
    }
  }

  @override
  void dispose() {
    widget.host._listeners.remove(_onChange);
    // The view is an overlay entry, so its disposal means the overlay is going away.
    // Cancel the pending auto-dismiss here: a timer owned by a plain object would
    // outlive the tree and trip the test framework's pending-timer invariant.
    widget.host.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.host.message;
    if (message == null) return const SizedBox.shrink();

    final duration = SrsMotion.resolve(context, SrsMotion.scrim);
    return Positioned.fill(
      child: IgnorePointer(
        child: ExcludeSemantics(
          // Keyed on the message so a replacement toast replays the fade and rise.
          child: TweenAnimationBuilder<double>(
            key: ValueKey(message),
            tween: Tween<double>(begin: 0, end: 1),
            duration: duration,
            curve: SrsMotion.ease,
            builder: (context, t, _) => Opacity(
              opacity: t,
              child: Transform.translate(offset: Offset(0, 10 * (1 - t)), child: SrsToast(message)),
            ),
          ),
        ),
      ),
    );
  }
}
