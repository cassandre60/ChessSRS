// The fixed search field at the top of a filterable list.
//
// Its own file for the same reason as `srs_dialog.dart`: `primitives.dart` imports only
// `package:flutter/widgets.dart` and stays Material-free, and a `TextField` cannot be built
// without Material. `SrsIconButton` stayed behind because it needs only `Icon`/`IconData`.
//
// design/docs/03-components.md §1: "padding 14/18, magnifier icon 18px stroke `ink3`, input 16,
// placeholder `Search` (`ink3`), bottom hairline. Filters rows by case-insensitive substring".
import 'package:chess_srs/src/design/primitives.dart';
import 'package:chess_srs/src/design/tokens.dart';
import 'package:material_ui/material_ui.dart';

// ---------------------------------------------------------------------------
// SrsSearchField — the fixed field at the top of a filterable list
//
// design/docs/03-components.md §1: "padding 14/18, magnifier icon 18px stroke `ink3`, input 16,
// placeholder `Search` (`ink3`), bottom hairline". The hairline is the only boundary, so the
// field sits on whatever the page behind it is rather than in a card.
// ---------------------------------------------------------------------------
class SrsSearchField extends StatelessWidget {
  const SrsSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.onClear,
    this.placeholder = 'Search',
    this.autofocus = false,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  /// Omitted when the caller has nothing to clear to.
  final VoidCallback? onClear;

  final String placeholder;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final c = context.srs;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.hairline)),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 18, color: c.ink3),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: autofocus,
              onChanged: onChanged,
              style: TextStyle(fontSize: 16, color: c.ink, fontFamily: SrsText.ui),
              cursorColor: c.accent,
              // The Material theme's own fill and underline would draw a second, unstyled
              // boundary under the hairline the spec asks for.
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.zero,
                hintText: placeholder,
                hintStyle: TextStyle(fontSize: 16, color: c.ink3, fontFamily: SrsText.ui),
              ),
            ),
          ),
          if (onClear != null)
            SrsIconButton(icon: Icons.close, tooltip: 'Clear search', onPressed: onClear),
        ],
      ),
    );
  }
}
