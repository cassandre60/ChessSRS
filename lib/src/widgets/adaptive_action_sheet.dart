import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/utils/l10n_context.dart';
import 'package:material_ui/material_ui.dart';

/// A sheet of text rows: the Diagram's action sheet.
///
/// One appearance on every platform. It used to branch on `TargetPlatform` — a
/// `CupertinoActionSheet` on iOS, a Material `Dialog` elsewhere — so the same menu was two
/// different-looking things. Ten call sites route through here, including the board editor's
/// `Menu` and `Variant`, so the branch was visible well beyond the screens it was written for.
///
/// `00-agent-brief.md` open decision 4, resolved 2026-09-28: keep platform *behaviours*, not
/// platform-specific *looks*. Scrolling, back gestures and haptics are untouched by this; only the
/// presentation changed.
///
/// The two implementations also differed *within* the platform branch: the Material one rendered
/// [BottomSheetAction.leading] and [BottomSheetAction.trailing] and the Cupertino one dropped both,
/// so an action could look different for a reason that had nothing to do with the platform. Both
/// are rendered now.
Future<T?> showAdaptiveActionSheet<T>({
  required BuildContext context,
  Widget? title,
  required List<BottomSheetAction> actions,
  bool isDismissible = true,
}) {
  final deviceHeight = MediaQuery.heightOf(context);

  return showSrsSheet<T>(
    context,
    SrsSheetSurface(
      maxHeight: deviceHeight * 0.7,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: DefaultTextStyle(style: SrsText.groupTitle(context.srs.ink3), child: title),
              ),
            for (final action in actions)
              Builder(
                // A Builder so [BottomSheetAction.makeLabel] gets the context immediately around
                // the row, which is what actions that position something relative to themselves
                // need -- the iPad share dialog is the one that depended on it.
                builder: (rowContext) => SrsSheetRow(
                  label: '',
                  labelWidget: action.makeLabel(rowContext),
                  leading: action.leading,
                  trailing: action.trailing,
                  onPressed: () {
                    if (action.dismissOnPress) {
                      Navigator.of(rowContext).pop();
                    }
                    action.onPressed();
                  },
                ),
              ),
            // A cancel row rather than a scrim-only exit: the sheet has to be dismissible by
            // keyboard and by anyone who cannot reliably hit a small scrim target.
            SrsSheetRow(label: context.l10n.cancel, onPressed: () => Navigator.of(context).pop()),
          ],
        ),
      ),
    ),
    isDismissible: isDismissible,
  );
}

/// A confirmation dialog.
///
/// Was a `CupertinoActionSheet` on iOS and a Material `AlertDialog` elsewhere, which meant the same
/// confirmation looked like two different questions depending on the device -- and on iOS it was a
/// single action with no cancel row, so dismissing it was the only way to say no.
///
/// `SrsDialog` per 03-components.md §11: title 20/600, actions right-aligned text button then pill.
Future<T?> showConfirmDialog<T>(
  BuildContext context, {
  required Widget title,
  required VoidCallback onConfirm,

  /// Retained for call-site compatibility. The design has no danger token -- a destructive action
  /// is signalled by its wording and its confirm dialog, not by painting the label -- so this no
  /// longer changes anything, exactly as `SrsSettingsRow.destructive` does not.
  bool isDestructiveAction = false,
}) {
  return showDialog<T>(
    context: context,
    builder: (context) => SrsDialog(
      title: title is Text ? (title.data ?? '') : '',
      actions: [
        SrsTextButton(label: context.l10n.cancel, onPressed: () => Navigator.of(context).pop()),
        SrsPillButton(
          label: context.l10n.mobileOkButton,
          onPressed: () {
            Navigator.of(context).pop();
            onConfirm();
          },
        ),
      ],
    ),
  );
}

/// The Actions model that will use on the ActionSheet.
class BottomSheetAction {
  /// A function that returns the label widget. (required)
  ///
  /// Typically a [Text] widget.
  ///
  /// This should not wrap. To enforce the single line limit, use
  /// [Text.maxLines].
  final Widget Function(BuildContext context) makeLabel;

  /// The callback that is called when the action item is tapped. (required)
  final VoidCallback onPressed;

  /// Whether the modal should be dismissed when an action is pressed.
  ///
  /// Default to true.
  final bool dismissOnPress;

  /// A widget to display after the label.
  ///
  /// Typically an [Icon] widget. (Android only).
  final Widget? trailing;

  /// A widget to display before the label.
  ///
  /// Typically an [Icon] or a [CircleAvatar] widget. Rendered on every platform now -- the two old
  /// implementations disagreed, and this is the one that has callers.
  final Widget? leading;

  /// Whether the action is destructive.
  ///
  /// No longer changes anything: the design has no danger token, so a destructive action is
  /// signalled by its wording and its confirm dialog rather than by painting the label. Retained so
  /// the existing call sites keep compiling. Matches `SrsSettingsRow.destructive`.
  final bool isDestructiveAction;

  /// Whether the action is the default action. Also inert, for the same reason.
  final bool isDefaultAction;

  BottomSheetAction({
    required this.makeLabel,
    required this.onPressed,
    this.dismissOnPress = true,
    this.trailing,
    this.leading,
    this.isDestructiveAction = false,
    this.isDefaultAction = false,
  });
}
