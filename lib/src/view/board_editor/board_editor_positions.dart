// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/model/board_editor/position.dart';
import 'package:chess_srs/src/utils/l10n_context.dart';
import 'package:chess_srs/src/utils/navigation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Position library for the board editor: the built-in openings and endgames.
/// A segmented switch instead of the Material tab bar, with the same swipeable pages.
class BoardEditorPositionsScreen extends ConsumerStatefulWidget {
  const BoardEditorPositionsScreen({required this.onPositionSelected, super.key});

  final void Function(Position position) onPositionSelected;

  static Route<dynamic> buildRoute({required void Function(Position position) onPositionSelected}) {
    return buildScreenRoute(
      screen: BoardEditorPositionsScreen(onPositionSelected: onPositionSelected),
    );
  }

  @override
  ConsumerState<BoardEditorPositionsScreen> createState() => _BoardEditorPositionsScreenState();
}

class _BoardEditorPositionsScreenState extends ConsumerState<BoardEditorPositionsScreen> {
  late final PageController _pages;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _pages = PageController();
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.srs;
    return Scaffold(
      backgroundColor: c.ground,
      body: SafeArea(
        child: Column(
          children: [
            SrsPageHead(
              label: context.l10n.loadPosition,
              onBack: () => Navigator.of(context).maybePop(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SrsSegmented<int>(
                  options: {0: context.l10n.openings, 1: context.l10n.endgamePositions},
                  value: _index,
                  onChanged: (i) {
                    setState(() => _index = i);
                    _pages.animateToPage(
                      i,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                    );
                  },
                ),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (i) => setState(() => _index = i),
                children: [
                  _PositionList(
                    loader: _loadOpenings,
                    onPositionSelected: widget.onPositionSelected,
                  ),
                  _PositionList(
                    loader: _loadEndgames,
                    onPositionSelected: widget.onPositionSelected,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<List<Position>> _loadOpenings() async {
  final s = await rootBundle.loadString('assets/positions.json');
  final result = <Position>[];
  for (final opening in (jsonDecode(s) as List<dynamic>).cast<Map<String, dynamic>>()) {
    for (final position in (opening['positions'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      result.add(Position.fromJson(position));
    }
  }
  return result;
}

Future<List<Position>> _loadEndgames() async {
  final s = await rootBundle.loadString('assets/endgames.json');
  return (jsonDecode(s) as List<dynamic>)
      .cast<Map<String, dynamic>>()
      .map(Position.fromJson)
      .toList();
}

class _PositionList extends StatefulWidget {
  const _PositionList({required this.loader, required this.onPositionSelected});

  final Future<List<Position>> Function() loader;
  final void Function(Position position) onPositionSelected;

  @override
  State<_PositionList> createState() => _PositionListState();
}

class _PositionListState extends State<_PositionList> with AutomaticKeepAliveClientMixin {
  late final Future<List<Position>> _positions = widget.loader();

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder(
      future: _positions,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text(snapshot.error.toString()));
        }
        final positions = snapshot.data;
        if (positions == null) {
          // Local asset data resolves within a frame: blank, never a spinner.
          return const SizedBox.shrink();
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          itemCount: positions.length,
          itemBuilder: (context, index) {
            final position = positions[index];
            return SrsSettingsRow(
              label: position.name,
              onTap: () => widget.onPositionSelected(position),
            );
          },
        );
      },
    );
  }
}
