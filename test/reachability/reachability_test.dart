// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// Reachability: every source file in lib/ is imported, directly or transitively, from the
// entry point.
//
// This exists because of a bug that a linter could not see and that a doc asserted was
// impossible. `AccountMenuButton` was never instantiated anywhere, so `AccountMenuScreen`
// was unreachable, so `showSignInOptions` and `signOut` were unreachable. Nobody could
// sign in or sign out. `docs/audit-disposition.md` recorded this as "reachable", citing a
// line *inside* the unreachable subtree — the same mistake this test exists to make
// impossible to repeat. Fixed in PR #84.
//
// The traversal follows `import` and `export` directives, because ten files in lib/ are
// re-export barrels (`design/design.dart`, `domain/domain.dart`, `persistence.dart` and
// friends) and following imports alone would report the whole design system as dead.
//
// Generated files are excluded from the *expected* set, not from the graph: a `.freezed.dart`
// or `.g.dart` is reached by way of the source file that declares it, and checking those
// directly would produce noise that changes every time codegen output is renamed.
//
// The baseline is the point. This gate cannot be added to CI on a codebase that already has
// unreachable files, because it would fail on the first run and stay red until someone did a
// cleanup nobody asked for. So KNOWN_UNREACHABLE pins the current backlog: the test fails on
// anything *new*, and a file leaves the baseline only when it is deleted. That makes this a
// ratchet rather than a cleanup mandate — the backlog can only shrink, and shrinking it is
// ordinary work rather than a prerequisite for adding the check.
//
// It is a graph test, not a symbol test. It cannot see a class that is imported but never
// constructed — the actual defect in PR #84 passed this check, because the file *was*
// imported by the settings screen. What it catches is the wider class: whole files nothing
// imports, which is how cut features and abandoned experiments accumulate. Symbol-level
// reachability needs a real resolver, not a regex, and a regex that guesses is worse than
// none — it reported `game_common_widgets.dart` as dead while `analysis_screen.dart` was
// still calling its top-level functions.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The compilation entry point. Everything the app can actually do starts here.
const _entryPoint = 'lib/main.dart';

/// Files that are legitimately not reachable from [_entryPoint].
///
/// Each is a known leftover: mostly surfaces of cut features, some inherited widgets the
/// reskin replaced. They are listed rather than deleted because deleting them is a separate
/// decision (some are reachable again the moment their feature returns) and because a ratchet
/// with a baseline is enforceable now, whereas a cleanup is not.
///
/// Keep this sorted, and give a line of context when adding an entry — an unexplained entry
/// is indistinguishable from a bug that was suppressed.
const _knownUnreachable = <String, String>{
  'lib/src/model/clock/chess_clock.dart':
      'Imported only by its own test. Chess-clock logic from the cut game surfaces; no live '
      'screen drives it.',
  'lib/src/model/common/game.dart':
      'Zero references in lib/ or test/. Shared game types left behind by the game cuts.',
  'lib/src/model/game/game_preferences.dart':
      'Zero references in lib/ or test/. Superseded by the offline-computer preferences.',
  'lib/src/styles/social_icons.dart':
      'Zero references. Lichess iconography, replaced per D016 (visual identity is '
      'independent of Lichess Mobile).',
  'lib/src/utils/image.dart':
      'Zero references. Image colour extraction for a cut feature; nothing calls '
      'imageWorkerFactoryProvider or extractColorsFromImageProvider.',

  // Cut-feature surfaces. Each still has a test, which is how they were found: a test can
  // outlive the screen it tests without anything noticing.
  'lib/src/view/settings/account_preferences_screen.dart':
      'Account preferences, with a test but no importer. Whether to keep it is a product '
      'decision now that PR #84 revived the account cluster, not a cleanup — do not '
      'delete it on the strength of this test.',
  'lib/src/view/user/user_profile.dart': 'Inherited from the cut user/profile surfaces.',
  'lib/src/view/user/user_activity.dart': 'Inherited from the cut user-activity surfaces.',
  'lib/src/view/study/study_list_screen.dart':
      'Cut study browser, still tested but unimported. The library sheet replaced it.',
  'lib/src/view/study/study_screen.dart': 'Cut study browser; the sheet replaced it.',
  'lib/src/view/study/create_study_chapter_bottom_sheet.dart': 'Superseded by the import flow.',
  'lib/src/view/chat/chat_screen.dart': 'Chat was cut; the file is retained for the cut record.',

  'lib/src/view/game/game_common_widgets.dart':
      'NOT DELETABLE, despite having an unreachable class. Two top-level functions here are '
      'still called from game_list_tile.dart and analysis_screen.dart. It is listed only '
      'because a symbol-based scan flagged its class; if a future cleanup uses a '
      'class-name heuristic it will delete a file the analysis screen depends on.',
};

/// Whether [path] is generated by build_runner and therefore not hand-maintained.
bool _isGenerated(String path) => path.endsWith('.g.dart') || path.endsWith('.freezed.dart');

/// Every non-generated Dart source file under [root], as repo-relative paths.
List<String> _sourceFiles(Directory root) {
  final out = <String>[];
  for (final entity in root.listSync(recursive: true)) {
    if (entity is! File) continue;
    final path = entity.path.replaceAll('\\', '/');
    if (!path.endsWith('.dart')) continue;
    if (_isGenerated(path)) continue;
    out.add(path);
  }
  return out..sort();
}

/// Repo-relative targets named by this package's `import` and `export` directives in [source].
///
/// Handles both forms this codebase uses, and the second one is not optional:
/// `domain.dart` re-exports its whole subtree as `export 'review/review_session.dart';` —
/// relative, not `package:`. A traversal that reads only `package:` URIs misses every
/// relative directive, and misses them silently, reporting the entire domain layer as dead.
///
/// Deliberately narrow about what it will not guess: `dart:` and third-party packages are
/// ignored rather than resolved, because a resolver that invents answers produces false
/// "reachable" results, and that is the one direction in which this test fails safely.
Set<String> _packageTargets(String source) {
  final file = File(source);
  if (!file.existsSync()) return const {};
  final dir = source.substring(0, source.lastIndexOf('/'));
  final found = <String>{};

  for (final line in file.readAsLinesSync()) {
    final match = RegExp(r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''').firstMatch(line);
    if (match == null) continue;
    final uri = match.group(1)!;

    // `dart:` is the SDK; anything with a package prefix that is not ours is a dependency.
    // Neither is a file in lib/, so neither is an edge in this graph.
    if (uri.startsWith('dart:')) continue;
    if (uri.contains(':') && !uri.startsWith('package:chess_srs/')) continue;

    final List<String> candidates;
    if (uri.startsWith('package:chess_srs/')) {
      final tail = uri.substring('package:chess_srs/'.length);
      candidates = ['lib/$tail', tail];
    } else {
      // Relative to the importing file, normalized so `../` cannot produce a path that
      // exists by accident from the wrong base.
      candidates = [_normalize('$dir/$uri')];
    }

    final resolved = candidates.where((p) => File(p).existsSync()).toList();
    if (resolved.isEmpty) continue; // Unresolvable: recorded as no edge, not as a guess.
    found.add(resolved.first);
  }
  return found;
}

/// Collapse `.` and `..` segments in a repo-relative path.
String _normalize(String path) {
  final out = <String>[];
  for (final segment in path.split('/')) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..') {
      if (out.isNotEmpty) out.removeLast();
      continue;
    }
    out.add(segment);
  }
  return out.join('/');
}

/// Every source file transitively imported or exported from [entry].
Set<String> _reachableFrom(String entry) {
  final seen = <String>{};
  final queue = <String>[entry];
  while (queue.isNotEmpty) {
    final current = queue.removeLast();
    if (!seen.add(current)) continue;
    queue.addAll(_packageTargets(current));
  }
  return seen;
}

void main() {
  test('every non-generated file in lib/ is reachable from the entry point', () {
    final lib = Directory.current.path.endsWith('/test') ? Directory('../lib') : Directory('lib');
    expect(lib.existsSync(), isTrue, reason: 'run from the package root; found ${lib.path}');

    final sources = _sourceFiles(lib);
    final reachable = _reachableFrom(_entryPoint);

    final unreachable = <String>[
      for (final path in sources)
        if (!reachable.contains(path) && !_knownUnreachable.containsKey(path)) path,
    ];

    expect(
      unreachable,
      isEmpty,
      reason:
          'These files are not imported, exported, or otherwise reachable from $_entryPoint, '
          'so nothing in the app can use them. Delete the file, or — if it is a genuine '
          'leftover and you are not deleting it today — add it to _knownUnreachable in '
          'test/reachability/reachability_test.dart with a line saying why.\n'
          'Unreachable:\n  ${unreachable.join('\n  ')}',
    );
  });

  test('the unreachable baseline still refers to files that exist', () {
    // Without this the baseline silently rots: delete a file, leave its entry, and the list
    // grows a plausible-looking permanent excuse for a path that no longer exists.
    final stale = <String>[
      for (final entry in _knownUnreachable.keys)
        if (!File(entry).existsSync()) entry,
    ];
    expect(
      stale,
      isEmpty,
      reason:
          'These are in _knownUnreachable but no longer exist. Remove the entries — that is '
          'the ratchet working:\n  ${stale.join('\n  ')}',
    );
  });

  test('the traversal actually traverses', () {
    // A reachability test that returns the empty set passes everything. Pin the traversal
    // against a file that is known to be reachable, so a broken regex fails loudly instead
    // of reporting the whole tree as dead.
    final reachable = _reachableFrom(_entryPoint);
    expect(reachable, contains(_entryPoint));
    expect(reachable, contains('lib/src/app.dart'));
    expect(
      reachable.length,
      greaterThan(50),
      reason: 'the app has hundreds of files; finding $reachable.length suggests a broken parse',
    );
  });

  test('re-export barrels are followed, not just imports', () {
    // `design/design.dart` is only ever reached through `export` directives from a single
    // entry in the design layer. If the traversal dropped `export`, the entire design system
    // would read as dead.
    final reachable = _reachableFrom(_entryPoint);
    expect(
      reachable,
      contains('lib/src/design/design.dart'),
      reason: 'reached via export; a traversal following imports only would miss it',
    );
  });
}
