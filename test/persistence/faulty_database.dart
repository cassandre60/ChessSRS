// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Fault-injection harness for `crash_consistency_test.dart`.
//
// Source: docs/test-audit/audit-report.md blind spot #1 (T0, persistence
// crash-consistency) and docs/test-audit/redesign.md §6 (design). The
// repository's write paths are supposed to be all-or-nothing; this harness is
// how a test can prove that, instead of assuming it.

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Where a [FaultyDatabase] should fail the next write.
///
/// Both counters are one-based and count from the moment the plan is armed.
/// A plan fires **once**: after the injected failure every later call goes
/// straight through, so a retry on the same instance can prove the write
/// heals.
class FaultPlan {
  const FaultPlan({this.throwAtBatchCommit, this.throwAtStatement});

  /// Fail at the Nth `Batch.commit()` (1-based), counting batches created on
  /// the database handle and inside `transaction` callbacks alike.
  final int? throwAtBatchCommit;

  /// Fail when the Nth statement (`insert`/`update`/`delete`) is added to any
  /// batch — the "fault between the paired writes" case, before the batch is
  /// handed to SQLite.
  final int? throwAtStatement;
}

/// Shared, mutable fault state: one instance per [FaultyDatabase], so every
/// transaction and batch it hands out counts into the same sequence.
class _FaultState {
  int statements = 0;
  int commits = 0;
  bool fired = false;

  void reset() {
    statements = 0;
    commits = 0;
    fired = false;
  }
}

/// The harness's injected failure, shaped like a real driver error so the code
/// under test cannot tell it apart from one.
class InjectedFault extends DatabaseException {
  InjectedFault(super.message);

  @override
  Object? get result => null;

  @override
  int? getResultCode() => null;
}

/// A `Database` that throws [DatabaseException] at the boundary named by the
/// armed [FaultPlan]. All other calls are forwarded to [inner].
///
/// Opening a database runs migrations, which may commit batches of their own;
/// arm the plan *after* the open so the counters start where the write under
/// test starts.
class FaultyDatabase implements Database {
  FaultyDatabase(this.inner);

  final Database inner;
  final _FaultState _state = _FaultState();
  FaultPlan? _plan;

  /// Arms (or re-arms) the plan and resets the counters.
  void arm(FaultPlan plan) {
    _plan = plan;
    _state.reset();
  }

  @override
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action, {bool? exclusive}) =>
      inner.transaction((txn) => action(_FaultyTransaction(txn, this)), exclusive: exclusive);

  @override
  Batch batch() => _FaultyBatch(inner.batch(), this);

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) => inner.query(
    table,
    distinct: distinct,
    columns: columns,
    where: where,
    whereArgs: whereArgs,
    groupBy: groupBy,
    having: having,
    orderBy: orderBy,
    limit: limit,
    offset: offset,
  );

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) =>
      inner.rawQuery(sql, arguments);

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) => inner.insert(
    table,
    values,
    nullColumnHack: nullColumnHack,
    conflictAlgorithm: conflictAlgorithm,
  );

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) => inner.update(
    table,
    values,
    where: where,
    whereArgs: whereArgs,
    conflictAlgorithm: conflictAlgorithm,
  );

  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) =>
      inner.delete(table, where: where, whereArgs: whereArgs);

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) => inner.execute(sql, arguments);

  @override
  Future<void> close() => inner.close();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('FaultyDatabase does not forward ${invocation.memberName}');
}

/// Mirrors [FaultyDatabase] for the calls the repository makes inside a
/// transaction, sharing the same fault sequence.
class _FaultyTransaction implements Transaction {
  _FaultyTransaction(this.inner, this.owner);

  final Transaction inner;
  final FaultyDatabase owner;

  @override
  Batch batch() => _FaultyBatch(inner.batch(), owner);

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) => inner.insert(
    table,
    values,
    nullColumnHack: nullColumnHack,
    conflictAlgorithm: conflictAlgorithm,
  );

  @override
  Future<int> rawInsert(String sql, [List<Object?>? arguments]) => inner.rawInsert(sql, arguments);

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) => inner.query(
    table,
    distinct: distinct,
    columns: columns,
    where: where,
    whereArgs: whereArgs,
    groupBy: groupBy,
    having: having,
    orderBy: orderBy,
    limit: limit,
    offset: offset,
  );

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) =>
      inner.rawQuery(sql, arguments);

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) => inner.update(
    table,
    values,
    where: where,
    whereArgs: whereArgs,
    conflictAlgorithm: conflictAlgorithm,
  );

  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) =>
      inner.delete(table, where: where, whereArgs: whereArgs);

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) => inner.execute(sql, arguments);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('_FaultyTransaction does not forward ${invocation.memberName}');
}

/// A `Batch` that counts its statements and commits into the shared sequence,
/// throwing [DatabaseException] when the armed plan's trigger is reached.
class _FaultyBatch implements Batch {
  _FaultyBatch(this.inner, this.owner);

  final Batch inner;
  final FaultyDatabase owner;

  void _checkStatement() {
    final state = owner._state;
    state.statements++;
    if (state.fired) return;
    final trigger = owner._plan?.throwAtStatement;
    if (trigger != null && state.statements == trigger) {
      state.fired = true;
      throw InjectedFault(
        'fault injection (crash-consistency harness): statement #$trigger of a batch',
      );
    }
  }

  @override
  void insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) {
    _checkStatement();
    inner.insert(
      table,
      values,
      nullColumnHack: nullColumnHack,
      conflictAlgorithm: conflictAlgorithm,
    );
  }

  @override
  void rawInsert(String sql, [List<Object?>? arguments]) {
    _checkStatement();
    inner.rawInsert(sql, arguments);
  }

  @override
  void update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) {
    _checkStatement();
    inner.update(
      table,
      values,
      where: where,
      whereArgs: whereArgs,
      conflictAlgorithm: conflictAlgorithm,
    );
  }

  @override
  void delete(String table, {String? where, List<Object?>? whereArgs}) {
    _checkStatement();
    inner.delete(table, where: where, whereArgs: whereArgs);
  }

  @override
  Future<List<Object?>> commit({bool? exclusive, bool? noResult, bool? continueOnError}) {
    final state = owner._state;
    state.commits++;
    if (!state.fired) {
      final trigger = owner._plan?.throwAtBatchCommit;
      if (trigger != null && state.commits == trigger) {
        state.fired = true;
        throw InjectedFault('fault injection (crash-consistency harness): batch commit #$trigger');
      }
    }
    return inner.commit(exclusive: exclusive, noResult: noResult, continueOnError: continueOnError);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('_FaultyBatch does not forward ${invocation.memberName}');
}
