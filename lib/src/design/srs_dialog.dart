// Centred dialog card: rename, delete, export options, and the other small confirmations.
//
// Lives apart from `primitives.dart`, which is deliberately Material-free (it imports only
// `package:flutter/widgets.dart`). A centred card needs Material's `Dialog` and `showDialog`,
// and weakening that file's constraint to accommodate one widget would be the wrong trade.
//
// design/docs/03-components.md: "centered card on `surface`, radius 16, padding 24, max width
// 400, sheet shadow, scrim; title 20/600; body 15 `ink2`; actions right-aligned". The demo's
// `.dlg` and `.dlg-act` rules give the rest: width min(400px, 100% - 32px), a 6px gap between
// actions, 22px above them, right-aligned and wrapping.
import 'package:chess_srs/src/design/tokens.dart';
import 'package:material_ui/material_ui.dart';

// ---------------------------------------------------------------------------
// SrsDialog — centred card for rename, delete, export options and the like
//
// design/docs/03-components.md: "centered card on `surface`, radius 16, padding 24, max width
// 400, sheet shadow, scrim; title 20/600; body 15 `ink2`; actions right-aligned".
// The demo's `.dlg` and `.dlg-act` rules give the rest: width min(400px, 100% - 32px), a 6px gap
// between actions, 22px above them, and a 150ms fade with a 180ms rise.
// ---------------------------------------------------------------------------
class SrsDialog extends StatelessWidget {
  const SrsDialog({super.key, this.title, this.titleWidget, this.body, this.content, this.actions});

  /// Addresses the card itself rather than the full-screen [Dialog] route.
  static const cardKey = ValueKey('srs-dialog-card');

  final String? title;

  /// Richer title, for the cases a word cannot express -- a status badge beside a code. Takes
  /// precedence over [title], which is then only the accessibility label.
  final Widget? titleWidget;

  /// Plain-text body, set in 15px `ink2`. Ignored when [content] is given.
  final String? body;

  /// Arbitrary body, for the cases a sentence cannot express (a text field, a form).
  final Widget? content;

  final List<Widget>? actions;

  /// Shows this dialog as a centred, scrimmed route.
  static Future<T?> show<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool barrierDismissible = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierColor: context.srs.scrim,
      builder: builder,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.srs;
    return Dialog(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Material(
        // The card is a Material, not just a coloured box: Material widgets such as TextField
        // require a Material ancestor within the closest LookupBoundary, and the rename dialog
        // puts a TextField here. It also carries the spec's "card on `surface`, radius 16".
        key: SrsDialog.cardKey,
        type: MaterialType.transparency,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: DecoratedBox(
            decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (titleWidget != null)
                    titleWidget!
                  else if (title != null)
                    Text(
                      title!,
                      style: SrsText.titleSmall(
                        c.ink,
                      ).copyWith(fontSize: 20, fontWeight: FontWeight.w600),
                    ),
                  if (content != null) ...[
                    if (title != null || titleWidget != null) const SizedBox(height: 14),
                    content!,
                  ] else if (body != null) ...[
                    if (title != null) const SizedBox(height: 10),
                    // 15px, per the spec's "body 15 ink2". SrsText.body is 17 on a narrow
                    // measure, which is the reading column's size rather than a dialog's.
                    Text(body!, style: SrsText.body(false, c.ink2).copyWith(fontSize: 15)),
                  ],
                  if (actions != null && actions!.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    // Right-aligned, 6px apart, wrapping on a narrow dialog: demo `.dlg-act`.
                    Wrap(
                      alignment: WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 6,
                      children: actions!,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
