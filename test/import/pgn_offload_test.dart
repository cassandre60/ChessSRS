// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/import/pgn_importer.dart';
import 'package:chess_srs/src/import/pgn_offload.dart';
import 'package:flutter_test/flutter_test.dart';

// TECH-DEBT item 8: one helper, one threshold, dart:io isolated.
void main() {
  group('shouldOffloadPgnWork', () {
    test('pins the documented 8192-byte threshold', () {
      expect(pgnOffloadThresholdBytes, 8192);
    });

    test('offloadsAt holds the at-or-above boundary exactly (POLISH-FIX-10)', () {
      // The pure decision, unguarded by the web/test sniff: 8192 itself
      // crosses ("at or above"), 8191 does not. Regression for mutation
      // round MUTATION-10 — `>=` tightened to `>` survived the mapped suite
      // because the public helper is env-guarded under flutter_test.
      expect(offloadsAt(8191), isFalse);
      expect(offloadsAt(8192), isTrue);
      expect(offloadsAt(8193), isTrue);
    });

    test('is always false in the test environment regardless of length', () {
      // FLUTTER_TEST is set under flutter_test, so the env guard dominates: even a
      // multi-megabyte input stays on this isolate. That proves the web/test sniff is
      // centralised in the helper rather than repeated at each call site.
      expect(shouldOffloadPgnWork(textLength: 81), isFalse);
      expect(shouldOffloadPgnWork(textLength: 8191), isFalse);
      expect(shouldOffloadPgnWork(textLength: 8192), isFalse);
      expect(shouldOffloadPgnWork(textLength: 65536), isFalse);
      expect(shouldOffloadPgnWork(textLength: 10 * 1024 * 1024), isFalse);
    });

    test('hash and import async helpers agree for the same input length', () async {
      // Before the fix these diverged between 8192 and 65535: the hash helper offloaded
      // at 8 KB while the tree build (and the controller branch) waited for 64 KB, so a
      // 20 KB file hashed on a worker while its parse — the expensive part — blocked the
      // UI isolate. Both now read the same helper, so both take the sync path here.
      const pgn = '''
[Event "Agreement Test"]

1. e4 e5 2. Nf3 Nc6 *
''';
      expect(await computePgnHashAsync(pgn), computePgnHash(pgn));

      final asyncResult = await importPgnAsync(pgn, studyTitle: 'Agreement');
      final syncResult = importPgn(pgn, studyTitle: 'Agreement');
      expect(asyncResult.decisions.length, syncResult.decisions.length);
    });
  });
}
