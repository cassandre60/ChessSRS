// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC coverage: INV-050, INV-065.

import 'dart:io';

import 'package:chess_srs/src/db/database.dart';
import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/persistence/persistence.dart';
import 'package:chess_srs/src/review/review_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Counts flat FEN→node index loads through the session-start path.
///
/// The index serves transposition acceptance alone (INV-065): every lookup
/// returns early when transposition is off, so a session that can never consult
/// it must not map every node of its scope to build it (INV-050). The owner's
/// library is 71k node rows, ~0.4 s of session start, for a setting that never
/// reads a single entry.
class _NodeIndexCountingRepository extends SqliteStudyRepository {
  _NodeIndexCountingRepository(super.db);

  int nodeIndexLoads = 0;

  @override
  Future<Map<String, List<NodeRef>>> getNodeIndex(List<String> chapterIds) {
    nodeIndexLoads++;
    return super.getNodeIndex(chapterIds);
  }
}

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory tempDir;
  late String dbPath;
  final now = DateTime.utc(2026, 11, 5, 12);

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('chess_srs_node_index_load_');
    dbPath = p.join(tempDir.path, 'node_index_load.db');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// One study, one due chapter. Due so the position is queued and the session
  /// has a prompt, which is the state whose build the index load belongs to.
  Future<_NodeIndexCountingRepository> seed() async {
    final db = await openAppDatabase(databaseFactoryFfi, dbPath);
    final repo = _NodeIndexCountingRepository(db);
    final study = Study(id: 's1', title: 'S', createdAt: now, updatedAt: now);
    const root = RepertoireNode(id: 'n1', fen: 'startfen', fenKey: 'startkey');
    final chapter = Chapter(id: 'c1', studyId: 's1', sourceOrder: 0, root: root, createdAt: now);
    final decision = RepertoireDecision.create(
      studyId: 's1',
      chapterId: 'c1',
      nodeId: 'n1',
      fenKey: 'startkey',
      expectedMoves: const [RepertoireMove(from: 'e2', to: 'e4', san: 'e4')],
    );
    await repo.saveStudy(study);
    await repo.saveChapter(chapter);
    await repo.saveDecision(decision);
    await repo.saveReviewState(
      ReviewState(
        decisionId: decision.canonicalId,
        firstReviewedAt: now.subtract(const Duration(days: 2)),
        nextDueAt: now.subtract(const Duration(days: 1)),
        repetitionCount: 1,
      ),
    );
    return repo;
  }

  test('with transposition off the session loads no node index', () async {
    final repo = await seed();
    final service = ReviewService(
      repository: repo,
      clock: FixedClock(now),
      transposeScope: TransposeScope.off,
    );

    final session = await service.startSession();

    expect(session.currentPrompt, isNotNull, reason: 'the due position is queued');
    expect(
      repo.nodeIndexLoads,
      0,
      reason: 'no lookup can consult the index with transposition off, so loading it is waste',
    );
  });

  test('with transposition in scope the session loads the node index', () async {
    final repo = await seed();
    final service = ReviewService(
      repository: repo,
      clock: FixedClock(now),
      transposeScope: TransposeScope.inScope,
    );

    final session = await service.startSession();

    expect(session.currentPrompt, isNotNull);
    expect(
      repo.nodeIndexLoads,
      greaterThanOrEqualTo(1),
      reason: 'transposition acceptance needs the flat index to find the target chapter',
    );
  });
}
