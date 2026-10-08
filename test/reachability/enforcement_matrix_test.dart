// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// The enforcement matrix in TEST_STRATEGY.md names a file for every invariant it claims to
// enforce. This checks those files exist.
//
// The failure this exists to prevent: an invariant recorded as enforced, pointing at a test
// that was renamed, moved, or deleted. The matrix keeps saying "Unit tests of the import
// pipeline" and nobody notices the tests are gone, because the sentence is prose and prose
// cannot be wrong. That is not a hypothetical — QUALITY.md 4.1 declared a 16ms bound for move
// validation for the whole life of this project with no test behind it, and the matrix had no
// row for it at all, so nothing in CI could have noticed.
//
// It checks the *target* column, not the whole document. The mechanism column legitimately
// names things that are not test files (`fvm flutter analyze`, `pubspec.yaml`), so the rule is
// deliberately narrow: any backticked path in the matrix must resolve. Inventing a way to parse
// "chess adapter" out of a prose cell would be a worse test than none.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _matrix = 'TEST_STRATEGY.md';

/// Repo-relative paths mentioned in backticks in the matrix's target column.
///
/// A path is anything with a `/` and a file extension, which covers `test/x_test.dart` and
/// `verify` while skipping `pubspec.yaml` — no, that has an extension too, so it is checked,
/// which is correct: `pubspec.yaml` is a real file and the matrix does claim to point at it.
Set<String> _namedPaths(String markdown) {
  final rows = <String>[];
  for (final line in markdown.split('\n')) {
    final trimmed = line.trim();
    if (!trimmed.startsWith('|')) continue;
    // Header and separator rows are not invariants.
    if (trimmed.contains('---')) continue;
    rows.add(trimmed);
  }

  final found = <String>{};
  for (final row in rows) {
    for (final match in RegExp('`([^`]+)`').allMatches(row)) {
      final candidate = match.group(1)!.trim();
      if (candidate.contains('/') || candidate == 'verify') found.add(candidate);
    }
  }
  return found;
}

void main() {
  test('every path the enforcement matrix points at exists', () {
    final file = File(_matrix);
    expect(
      file.existsSync(),
      isTrue,
      reason: 'run from the package root; $_matrix not found at ${file.path}',
    );

    final paths = _namedPaths(file.readAsStringSync());
    expect(
      paths,
      isNotEmpty,
      reason: 'the matrix stopped naming files, so it stopped being checkable',
    );

    // A target may name a directory as well as a file — "the domain layer is lib/src/domain/"
    // is a legitimate row, and checking only File would reject it while checking only
    // Directory would reject every test file.
    bool exists(String path) => File(path).existsSync() || Directory(path).existsSync();

    final missing = paths.where((p) => !exists(p)).toList()..sort();

    expect(
      missing,
      isEmpty,
      reason:
          'The enforcement matrix claims these files enforce an invariant, and they do not '
          'exist. Either the test was renamed or deleted, or the matrix is stale — and a '
          'matrix that points at a missing file is how a documented invariant ends up with '
          'no enforcement and nobody noticing.\nMissing:\n  ${missing.join('\n  ')}',
    );
  });

  test('the matrix still has a row per invariant rather than being emptied out', () {
    // A test that only validates paths passes vacuously if the matrix is trimmed to nothing
    // path-shaped. Pin a floor on the row count so gutting the document fails loudly.
    expect(
      _invariantRowCount(),
      greaterThanOrEqualTo(10),
      reason: 'the matrix had 13 invariants; ${_invariantRowCount()} rows means most were removed',
    );
  });
}

/// Invariant rows in the matrix, excluding the header and the `|---|` separator.
int _invariantRowCount() {
  final file = File(_matrix);
  if (!file.existsSync()) return 0;
  var count = 0;
  for (final line in file.readAsStringSync().split('\n')) {
    final trimmed = line.trim();
    if (!trimmed.startsWith('|')) continue;
    if (trimmed.contains('---')) continue;
    if (trimmed.startsWith('| Invariant')) continue;
    count++;
  }
  return count;
}
