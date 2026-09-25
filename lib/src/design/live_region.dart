// Polite live region for outcome announcements.
//
// The demo carries a screen-reader-only status node (`<div class="sr" role="status"
// aria-live="polite">`) and writes two sentences into it (prototype `say()`):
//
//   "Correct. {san}."
//   "Not this move. The repertoire move is {san}."
//
// design/docs/04-screens-and-flows.md §6 requires the same. Flutter's equivalent is a
// semantics node with `liveRegion: true`.
//
// The tricky part is re-announcement: assistive technology only speaks a live region when
// its content *changes*, so the same sentence twice in a row (two identical wrong moves)
// would be silent the second time. Keying the node on the message makes the framework
// build a fresh node each time, so it speaks again.
import 'package:flutter/widgets.dart';

/// Announces [message] to assistive technology whenever it changes.
///
/// Renders nothing visible, and nothing at all while [message] is empty, so it can sit
/// anywhere in the tree without affecting layout. The label lives on the semantics node
/// rather than in a `Text`, so the region occupies no space in the layout at all.
class SrsLiveRegion extends StatelessWidget {
  const SrsLiveRegion(this.message, {super.key});

  /// The sentence to announce. Empty means "say nothing".
  final String message;

  @override
  Widget build(BuildContext context) {
    if (message.isEmpty) return const SizedBox.shrink();
    return Semantics(
      // A new node per message, so an identical consecutive message is still spoken.
      key: ValueKey(message),
      container: true,
      liveRegion: true,
      label: message,
      child: const SizedBox.shrink(),
    );
  }
}
