import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/model/user/search_history.dart';
import 'package:chess_srs/src/model/user/user.dart';
import 'package:chess_srs/src/model/user/user_repository_providers.dart';
import 'package:chess_srs/src/styles/styles.dart';
import 'package:chess_srs/src/utils/l10n_context.dart';
import 'package:chess_srs/src/utils/navigation.dart';
import 'package:chess_srs/src/utils/rate_limit.dart';
import 'package:chess_srs/src/widgets/feedback.dart';
import 'package:chess_srs/src/widgets/list.dart';
import 'package:chess_srs/src/widgets/user_list_tile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

const _kSaveHistoryDebouncTimer = Duration(seconds: 2);

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({this.onUserTap, this.title, this.autoFocus = true, super.key});

  final void Function(LightUser)? onUserTap;
  final Widget? title;
  final bool autoFocus;

  static Route<dynamic> buildRoute({
    void Function(LightUser)? onUserTap,
    Widget? title,
    bool autoFocus = true,
  }) {
    return buildScreenRoute(
      screen: SearchScreen(onUserTap: onUserTap, title: title, autoFocus: autoFocus),
      fullscreenDialog: true,
    );
  }

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _searchController = TextEditingController();
  final saveHistoryDebouncer = Debouncer(_kSaveHistoryDebouncTimer);
  String? _term;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    super.dispose();
    _searchController.dispose();
  }

  void _onSearchChanged() {
    if (!mounted) return;

    final term = _searchController.text;
    if (term.length >= 3) {
      ref.read(autoCompleteUserProvider(term));
      setState(() {
        _term = term;
      });
      saveHistoryDebouncer.call(() {
        if (!mounted) return;
        ref.read(searchHistoryProvider.notifier).saveTerm(term);
      });
    } else {
      setState(() {
        _term = null;
      });
    }
  }

  // ignore: use_setters_to_change_properties
  void setSearchText(String text) {
    _searchController.text = text;
  }

  @override
  Widget build(BuildContext context) {
    final searchBar = SrsSearchField(
      placeholder: context.l10n.searchSearch,
      controller: _searchController,
      autofocus: widget.autoFocus,
      onChanged: (_) => _onSearchChanged(),
    );

    final body = _Body(_term, setSearchText, widget.onUserTap);

    // The search field was an AppBar title on one path and an AppBar `bottom` on the other,
    // chosen by whether the caller passed a title -- so the same screen put the field in a
    // different place depending on who opened it. It is a row under the head on both now.
    return Scaffold(
      backgroundColor: context.srs.ground,
      body: SafeArea(
        child: Column(
          children: [
            SrsPageHead(
              label: widget.title?.toString() ?? context.l10n.searchSearch,
              onBack: () => Navigator.of(context).maybePop(),
            ),
            Padding(padding: const EdgeInsets.fromLTRB(24, 4, 24, 12), child: searchBar),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body(this.term, this.onRecentSearchTap, this.onUserTap);

  final String? term;
  final void Function(String) onRecentSearchTap;
  final void Function(LightUser)? onUserTap;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (term != null) {
      return SafeArea(child: _UserList(term!, onUserTap));
    } else {
      final searchHistory = ref.watch(searchHistoryProvider).history;
      if (searchHistory.isEmpty) return const SizedBox.shrink();
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(child: SrsGroupHeader('Recent searches')),
                SrsTextButton(
                  label: context.l10n.mobileClearButton,
                  onPressed: () => ref.read(searchHistoryProvider.notifier).clear(),
                ),
              ],
            ),
            for (final term in searchHistory)
              SrsSettingsRow(label: term, onTap: () => onRecentSearchTap(term)),
          ],
        ),
      );
    }
  }
}

class _UserList extends ConsumerWidget {
  const _UserList(this.term, this.onUserTap);

  final String term;
  final void Function(LightUser)? onUserTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final autoComplete = ref.watch(autoCompleteUserProvider(term));

    return autoComplete.when(
      data: (userList) => userList.isNotEmpty
          ? SingleChildScrollView(
              child: ListSection(
                header: Row(
                  children: [
                    const Icon(Icons.person),
                    const SizedBox(width: 8),
                    Text(context.l10n.mobilePlayersMatchingSearchTerm(term)),
                  ],
                ),
                hasLeading: true,
                children: userList
                    .map(
                      (user) => UserListTile.fromLightUser(
                        user,
                        onTap: () {
                          if (onUserTap != null) {
                            onUserTap!.call(user);
                          }
                        },
                      ),
                    )
                    .toList(),
              ),
            )
          : Center(
              child: Text(context.l10n.mobileNoSearchResults, style: Styles.noResultTextStyle),
            ),
      error: (e, _) {
        debugPrint('Error loading search results: $e');
        return const Center(child: Text('Could not load search results.'));
      },
      loading: () => const Center(child: CenterLoadingIndicator()),
    );
  }
}
