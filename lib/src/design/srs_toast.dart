// The Diagram toast.
//
// Its own file for the same reason as `srs_dialog.dart` and `srs_search_field.dart`: this is a
// self-contained behaviour with a timer and an overlay entry, not a leaf primitive, and
// `primitives.dart` stays a Material-free leaf set.
//
// design/docs/03-components.md §12: "Toast: ink pill (`ink` bg, `ground` text 14/500), bottom 24,
// centered, padding 11/18, fades in 160 ms (translate 10px), visible 2.4 s. One line, no
// actions." The demo's `.toast` rule is the source for the rest: `border-radius: 999px`,
// `max-width: calc(100% - 32px)`, `text-align: center`, and z-index 40 -- above the scrim (10)
// and the sheet (20), per `02-tokens.md` §4.
//
// There is deliberately no error variant. The demo has 27 `toast(` calls and no error styling;
// §12 gives errors a *screen* state instead (title 32/400, an `ink2` sentence, a `Try again`
// pill, a `Copy details` text button). See [SrsToastTone].
import 'dart:async';

import 'package:chess_srs/src/design/tokens.dart';
import 'package:flutter/widgets.dart';

/// The three tones callers may ask for.
///
/// The design specifies one appearance, so [error] and [success] render identically to [info]
/// today. The parameter is kept because 53 call sites pass it and removing it would be a
/// 53-file diff for no visible gain -- but it currently buys nothing, and a caller that needs
/// the user to notice a failure should be an error *state* (§12), not a differently-tinted
/// pill. `showSnackBar` passes this straight through so the migration is invisible.
enum SrsToastTone { info, success, error }

/// Shows a toast, replacing any toast already on screen.
///
/// One at a time: two stacked toasts is not a state the design describes, and a rapid sequence
/// of confirmations would otherwise queue up and read as a backlog.
void showSrsToast(BuildContext context, String message, {SrsToastTone tone = SrsToastTone.info}) {
  // Two lookups, because the two callers need different ones. A widget's context finds the
  // Overlay by walking up. But a `GlobalKey<NavigatorState>.currentContext` -- which is how the
  // deep-link service gets a context, so it can navigate before the first frame -- sits *above*
  // its own Overlay, and walking up from there finds nothing. `ScaffoldMessenger` did not have
  // that problem, which is why this went unnoticed until the toast stopped being a SnackBar:
  // deep-link error toasts were simply never inserted.
  final overlay =
      Overlay.maybeOf(context, rootOverlay: true) ??
      Navigator.maybeOf(context, rootNavigator: true)?.overlay;
  if (overlay == null) return;

  // `tone` is accepted and deliberately not rendered -- see [SrsToastTone]. Not plumbed
  // through to a difference the design does not describe.
  _active?.dismiss();
  final entry = _SrsToastEntry(overlay, message);
  _active = entry;
  entry.show();
}

/// The toast currently on screen, if any, so a second one can replace it rather than stack.
_SrsToastEntry? _active;

class _SrsToastEntry {
  _SrsToastEntry(this.overlay, this.message);

  final OverlayState overlay;
  final String message;

  OverlayEntry? _entry;

  void show() {
    final overlayEntry = OverlayEntry(
      builder: (context) => _SrsToastHost(message: message, onDismissed: dismiss),
    );
    _entry = overlayEntry;
    overlay.insert(overlayEntry);
  }

  void dismiss() {
    _entry?.remove();
    _entry = null;
    if (identical(_active, this)) _active = null;
  }
}

/// Fades and rises in, then removes itself.
///
/// Two phases rather than one controller, because the spec's 160 ms is the *entry* and the
/// 2400 ms is how long it stays put; a single reversed animation would make the dwell time
/// depend on the exit.
class _SrsToastHost extends StatefulWidget {
  const _SrsToastHost({required this.message, required this.onDismissed});

  final String message;
  final VoidCallback onDismissed;

  @override
  State<_SrsToastHost> createState() => _SrsToastHostState();
}

class _SrsToastHostState extends State<_SrsToastHost> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
  );
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    _controller.forward();
    // The dwell timer lives here, not on the entry, so that tearing the tree down cancels it.
    // Held on the entry it would outlive the overlay and fire into a defunct navigator --
    // which is exactly what happens when a toast is showing and the user navigates away.
    _hide = Timer(const Duration(milliseconds: 2400), widget.onDismissed);
  }

  @override
  void dispose() {
    _hide?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.srs;
    final curved = CurvedAnimation(parent: _controller, curve: SrsMotion.ease);

    // A full-screen Positioned with an Align, rather than Positioned(bottom: 24) wrapped in a
    // Center: with only `bottom` set, a Stack hands the child loose height, so the Center's
    // size -- and therefore the toast's resting offset -- depends on how the child resolves
    // that. Aligning inside a full-height box and padding by the spec's 24 is exact.
    return Positioned.fill(
      child: IgnorePointer(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.only(bottom: 24 + MediaQuery.paddingOf(context).bottom),
            child: FadeTransition(
              opacity: curved,
              child: SlideTransition(
                // 10px rise, per the spec.
                position: Tween<Offset>(
                  begin: const Offset(0, 0.14),
                  end: Offset.zero,
                ).animate(curved),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 360),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                  decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(999)),
                  child: Text(
                    widget.message,
                    textAlign: TextAlign.center,
                    // "One line" is the spec, so a long message truncates rather than growing a
                    // second line the design has no spacing for.
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: SrsText.ui,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: c.ground,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
