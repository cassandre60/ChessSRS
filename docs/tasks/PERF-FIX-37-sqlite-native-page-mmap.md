# PERF-FIX-37 — Enable SQLite native OS page memory-mapping (`mmap_size`)

## 1. Why this is a brief at all

With the library grown to 35 MiB across 63 studies and 31,182 decisions, SQLite
reads hundreds of database pages during review screen startup, query passes, and
chapter loads.

By default on desktop and mobile platforms, SQLite reads database pages from the
filesystem via standard POSIX `read()` or `pread()` system calls. Each read
syscall transitions between user space and kernel space and copies page buffers
from the kernel file cache into SQLite's user space page cache.

SQLite has native support for memory-mapped I/O (`PRAGMA mmap_size`), introduced
in SQLite 3.7.17. When enabled:
- The OS maps the database file directly into the process's 64-bit virtual
  address space.
- Page reads bypass the `read()` syscall entirely. Reading a page becomes a
  direct pointer dereference into the OS kernel's file cache.
- Page cache evictions and page faults are handled directly by the OS virtual
  memory subsystem.
- In WAL mode, writes still append safely via the WAL journal, maintaining 100%
  ACID durability.

## 2. Read before touching anything

1. `lib/src/db/database.dart` — `openAppDatabase` and `onConfigure`.
2. Official SQLite documentation on Memory-Mapped I/O:
   https://www.sqlite.org/mmap.html
3. SPEC **INV-001** (Review writes are durable and incremental).

## 3. The Implementation Plan

In `lib/src/db/database.dart`, inside `openAppDatabase`:

```dart
onConfigure: (db) async {
  final version = await _getDatabaseVersion(db);
  _logger.info('SQLite version: $version');
  if (version != null && version >= 307000) {
    _logger.info('Enabling WAL journal mode');
    await db.rawQuery('PRAGMA journal_mode=WAL');
  }
  await db.rawQuery('PRAGMA foreign_keys = ON');

  // Memory-mapped I/O: allow SQLite to map up to 256 MiB directly into virtual memory.
  // When mmap_size is set, page reads bypass read() system calls and access the kernel
  // page cache directly. Supported since SQLite 3.7.17.
  if (version != null && version >= 3007017) {
    await db.rawQuery('PRAGMA mmap_size = 268435456'); // 256 MiB
  }

  // 64 MiB user-space page cache (negative number indicates size in kibibytes).
  await db.rawQuery('PRAGMA cache_size = -64000');
  
  // Store temporary tables and indices in memory rather than on disk.
  await db.rawQuery('PRAGMA temp_store = MEMORY');
},
```

## 4. Verification Steps

1. Verify SQLite configuration in test:
   Run existing database tests:
   ```bash
   fvm flutter test test/db/
   ```
2. Check that pragmas take effect on a running connection:
   Verify with a quick test querying `PRAGMA mmap_size` and `PRAGMA cache_size`.
3. Measure driver and query latency before and after:
   ```bash
   cp ~/.local/share/org.chesssrs.chess_srs/chess_srs.db{,-wal,-shm} /tmp/perf/
   CHESS_SRS_PERF_DB=/tmp/perf/chess_srs.db \
     fvm flutter test test/perf/driver_overhead_test.dart
   ```
4. Run gates:
   ```bash
   ./scripts/gates.sh t1
   ```

## 5. What counts as done

- `PRAGMA mmap_size`, `PRAGMA cache_size`, and `PRAGMA temp_store` enabled in `onConfigure`.
- Zero database test failures.
- No schema or model code touched.
- `./scripts/gates.sh t1` passes after commit.

## 6. What would make this brief wrong

- If `sqflite_common_ffi` or the underlying SQLite library on target platforms
  disables mmap support at compile time (`SQLITE_MAX_MMAP_SIZE=0`). (Querying
  `PRAGMA mmap_size` returns 0 if disabled at compile time).
