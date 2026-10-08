// Copyright (C) 2026 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// SPEC INV-040, INV-041, INV-042.
// Guards the pure-domain boundary from inside the suite so the rule holds
// even where the Python gate does not run. Mirrors
// `.gates/banned-apis.json`; keep the two in sync.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Files where wall-clock reads would break deterministic scheduling.
const _clockRuledFiles = <String>{
  'scheduler.dart',
  'chess_fsrs_scheduler.dart',
  'graph_aware_review_coordinator.dart',
  'review_state.dart',
  'position_knowledge_state.dart',
  'review/review_engine.dart',
  'review/review_mode.dart',
  'review/review_prompt.dart',
  'review/review_scope.dart',
  'review/review_session.dart',
  'review/review_step_result.dart',
};

/// Import prefixes that must never appear in the pure domain.
final _bannedImports = <RegExp>[
  RegExp(r'''import\s+'package:flutter/'''),
  RegExp(r'''import\s+'dart:io' '''),
  RegExp(r'''import\s+'dart:io';'''),
  RegExp(r'''import\s+'dart:html'''),
  RegExp(r'''import\s+'dart:js'''),
  RegExp(r'''import\s+'package:sqflite'''),
  RegExp(r'''import\s+'package:chessground'''),
  RegExp(r'''import\s+'sqflite'''),
];

/// A wall-clock read outside a doc reference.
final _wallClock = RegExp(r'DateTime\.now');
final _docReference = RegExp(r'\[DateTime\.now\]');

List<File> _domainFiles() {
  final domain = Directory('lib/src/domain');
  expect(domain.existsSync(), isTrue, reason: 'run from the package root');
  return domain
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();
}

void main() {
  group('domain boundary (SPEC INV-040, INV-041, INV-042)', () {
    test('INV-040 domain imports no UI, database, or chessboard packages', () {
      final violations = <String>[];
      for (final file in _domainFiles()) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          for (final banned in _bannedImports) {
            if (banned.hasMatch(lines[i])) {
              violations.add('${file.path}:${i + 1}: ${lines[i].trim()}');
            }
          }
        }
      }
      expect(violations, isEmpty, reason: 'pure domain must stay UI/DB free');
    });

    test('INV-041 scheduling and review paths read time via Clock', () {
      final violations = <String>[];
      for (final file in _domainFiles()) {
        final relative = file.path.split('lib/src/domain/').last;
        if (!_clockRuledFiles.contains(relative)) continue;
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (_wallClock.hasMatch(lines[i]) && !_docReference.hasMatch(lines[i])) {
            violations.add('${file.path}:${i + 1}: ${lines[i].trim()}');
          }
        }
      }
      expect(violations, isEmpty, reason: 'inject Clock instead of reading the wall clock');
    });

    test('INV-042 domain performs no I/O', () {
      final violations = <String>[];
      for (final file in _domainFiles()) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.contains('dart:io') ||
              line.contains('package:http') ||
              line.contains('HttpClient')) {
            violations.add('${file.path}:${i + 1}: ${line.trim()}');
          }
        }
      }
      expect(violations, isEmpty, reason: 'domain computes; adapters persist and fetch');
    });
  });
}
