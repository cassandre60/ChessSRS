// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:sqflite/sqflite.dart';

const kTableSrsStudy = 'srs_study';
const kTableSrsChapter = 'srs_chapter';
const kTableSrsDecision = 'srs_decision';
const kTableSrsReviewState = 'srs_review_state';
const kTableSrsReviewEvent = 'srs_review_event';
const kTablePositionKnowledgeState = 'position_knowledge_state';
const kTableSrsStudyRemote = 'srs_study_remote';
const kTableSrsUnlockedDecision = 'srs_unlocked_decision';

void createSrsTables(Batch batch) {
  batch.execute('''
    CREATE TABLE IF NOT EXISTS $kTableSrsStudy (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      createdAt TEXT NOT NULL,
      updatedAt TEXT NOT NULL,
      isActive INTEGER NOT NULL DEFAULT 1,
      pgnHash TEXT
    );
  ''');
  batch.execute('''
    CREATE INDEX IF NOT EXISTS idx_srs_study_pgnHash
    ON $kTableSrsStudy(pgnHash);
  ''');

  // Bulk-import linkage lives beside the study, not on the domain entity:
  // it is sync metadata (which remote study, how fresh), not repertoire
  // content, and a side table needs no ALTER hazard on upgrade.
  batch.execute('''
    CREATE TABLE IF NOT EXISTS $kTableSrsStudyRemote (
      studyId TEXT PRIMARY KEY,
      remoteStudyId TEXT NOT NULL,
      remoteUpdatedAt TEXT NOT NULL,
      FOREIGN KEY (studyId) REFERENCES $kTableSrsStudy(id) ON DELETE CASCADE
    );
  ''');
  batch.execute('''
    CREATE INDEX IF NOT EXISTS idx_srs_study_remote_remoteStudyId
    ON $kTableSrsStudyRemote(remoteStudyId);
  ''');

  batch.execute('''
    CREATE TABLE IF NOT EXISTS $kTableSrsChapter (
      id TEXT PRIMARY KEY,
      studyId TEXT NOT NULL,
      sourceOrder INTEGER NOT NULL,
      title TEXT,
      startingFen TEXT,
      createdAt TEXT NOT NULL,
      treeJson TEXT,
      opening TEXT,
      orientation TEXT NOT NULL DEFAULT 'white',
      FOREIGN KEY (studyId) REFERENCES $kTableSrsStudy(id) ON DELETE CASCADE
    );
  ''');
  batch.execute('''
    CREATE INDEX IF NOT EXISTS idx_srs_chapter_studyId
    ON $kTableSrsChapter(studyId);
  ''');

  batch.execute('''
    CREATE TABLE IF NOT EXISTS $kTableSrsDecision (
      id TEXT PRIMARY KEY,
      studyId TEXT NOT NULL,
      chapterId TEXT NOT NULL,
      nodeId TEXT NOT NULL,
      expectedMoves TEXT NOT NULL,
      canonicalStateId TEXT,
      FOREIGN KEY (studyId) REFERENCES $kTableSrsStudy(id) ON DELETE CASCADE,
      FOREIGN KEY (chapterId) REFERENCES $kTableSrsChapter(id) ON DELETE CASCADE
    );
  ''');
  batch.execute('''
    CREATE INDEX IF NOT EXISTS idx_srs_decision_studyId
    ON $kTableSrsDecision(studyId);
  ''');
  batch.execute('''
    CREATE INDEX IF NOT EXISTS idx_srs_decision_chapterId
    ON $kTableSrsDecision(chapterId);
  ''');
  batch.execute('''
    CREATE INDEX IF NOT EXISTS idx_srs_decision_canonicalStateId
    ON $kTableSrsDecision(canonicalStateId);
  ''');

  batch.execute('''
    CREATE TABLE IF NOT EXISTS $kTablePositionKnowledgeState (
      canonicalId TEXT PRIMARY KEY,
      firstReviewedAt TEXT,
      lastReviewedAt TEXT,
      nextDueAt TEXT,
      repetitionCount INTEGER NOT NULL DEFAULT 0,
      lapseCount INTEGER NOT NULL DEFAULT 0,
      stability REAL NOT NULL DEFAULT 0.0,
      difficulty REAL NOT NULL DEFAULT 0.0,
      latencyEmaMs REAL,
      latencySampleCount INTEGER NOT NULL DEFAULT 0,
      lastExposedAt TEXT
    );
  ''');
  batch.execute('''
    CREATE INDEX IF NOT EXISTS idx_position_knowledge_state_nextDueAt
    ON $kTablePositionKnowledgeState(nextDueAt);
  ''');

  batch.execute('''
    CREATE TABLE IF NOT EXISTS $kTableSrsReviewState (
      decisionId TEXT PRIMARY KEY,
      firstReviewedAt TEXT,
      lastReviewedAt TEXT,
      nextDueAt TEXT,
      repetitionCount INTEGER NOT NULL DEFAULT 0,
      lapseCount INTEGER NOT NULL DEFAULT 0,
      stability REAL NOT NULL DEFAULT 0.0,
      difficulty REAL NOT NULL DEFAULT 5.0
    );
  ''');
  batch.execute('''
    CREATE INDEX IF NOT EXISTS idx_srs_review_state_nextDueAt
    ON $kTableSrsReviewState(nextDueAt);
  ''');

  batch.execute('''
    CREATE TABLE IF NOT EXISTS $kTableSrsReviewEvent (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      decisionId TEXT NOT NULL,
      whenTimestamp TEXT NOT NULL,
      result TEXT NOT NULL,
      oldStateJson TEXT NOT NULL,
      newStateJson TEXT NOT NULL
    );
  ''');
  batch.execute('''
    CREATE INDEX IF NOT EXISTS idx_srs_review_event_decisionId
    ON $kTableSrsReviewEvent(decisionId);
  ''');
  batch.execute('''
    CREATE INDEX IF NOT EXISTS idx_srs_review_event_whenTimestamp
    ON $kTableSrsReviewEvent(whenTimestamp);
  ''');

  batch.execute('''
    CREATE TABLE IF NOT EXISTS $kTableSrsUnlockedDecision (
      decisionId TEXT PRIMARY KEY,
      unlockedAt TEXT NOT NULL,
      FOREIGN KEY (decisionId) REFERENCES $kTableSrsDecision(id) ON DELETE CASCADE
    );
  ''');
  batch.execute('''
    CREATE INDEX IF NOT EXISTS idx_srs_unlocked_decision_decisionId
    ON $kTableSrsUnlockedDecision(decisionId);
  ''');
}
