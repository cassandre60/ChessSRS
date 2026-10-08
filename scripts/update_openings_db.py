#!/usr/bin/env python3

import csv
import os
import sqlite3
import subprocess
import sys
import tempfile

if len(sys.argv) <= 1:
    print("Usage: ./update_openings_db.py <path to lichess-org/chess-openings repo>")
    sys.exit(1)

path_to_chess_openings = sys.argv[1]

if not os.path.isdir(path_to_chess_openings):
    print(f"Error: {path_to_chess_openings} is not a valid directory.")
    sys.exit(1)

subprocess.run(["make", "all"], cwd=path_to_chess_openings, check=True)

db_path = os.path.join(os.path.dirname(__file__), '../assets/chess_openings.db')

openings_sql = 'SELECT eco || " " || name || " " || pgn FROM openings ORDER BY eco, name, pgn;'

# The source is read and sanity-checked before the shipped asset is touched at all. An empty or
# truncated TSV used to delete every opening, commit that, and only then insert nothing — the
# script exited 0 and the empty database was what got built into the app.
with open(os.path.join(path_to_chess_openings, 'dist/all.tsv'), 'r') as f:
    dr = csv.DictReader(f, delimiter='\t')
    to_db = [(i['eco'], i['name'], i['pgn'], i['uci'], i['epd']) for i in dr]

if not to_db:
    print('Error: dist/all.tsv contained no openings. Leaving the database untouched.')
    sys.exit(1)

# Read what is there now, both for the diff below and for the table definition, so a rebuild
# cannot drift away from the schema that is already shipped.
conn = sqlite3.connect(db_path)
try:
    row = conn.execute("SELECT sql FROM sqlite_master WHERE name = 'openings'").fetchone()
    if row is None:
        print('Error: the existing database has no openings table. Refusing to rebuild it.')
        sys.exit(1)
    schema = row[0]
    old_openings = set(r[0] for r in conn.execute(openings_sql))
finally:
    conn.close()

# Built beside the asset so the replacement is on the same filesystem and therefore atomic. The
# shipped database is never opened for writing: a full disk, a bad row, or the process being
# killed leaves the previous one exactly as it was.
assets_dir = os.path.dirname(db_path)
fd, tmp_path = tempfile.mkstemp(dir=assets_dir, suffix='.db')
os.close(fd)

try:
    tmp = sqlite3.connect(tmp_path)
    try:
        tmp.execute(schema)
        tmp.executemany(
            'INSERT INTO openings (eco, name, pgn, uci, epd) VALUES (?, ?, ?, ?, ?);', to_db
        )
        tmp.commit()
        # The app looks up openings by exact epd on every position change
        # (see OpeningService.fetchFromFen), so keep an index on epd.
        # Built here (not read from the shipped schema) because the schema row
        # in sqlite_master holds the table only; indexes are separate rows.
        tmp.execute('CREATE INDEX IF NOT EXISTS idx_openings_epd ON openings(epd);')
        tmp.commit()
        written = tmp.execute('SELECT COUNT(*) FROM openings').fetchone()[0]
        new_openings = set(r[0] for r in tmp.execute(openings_sql))
    finally:
        tmp.close()

    if written != len(to_db):
        print(
            f'Error: wrote {written} of {len(to_db)} openings. '
            f'Leaving the database untouched.'
        )
        sys.exit(1)

    if not new_openings:
        print('Error: the rebuilt database contained no openings. Leaving it in place.')
        sys.exit(1)

    os.replace(tmp_path, db_path)
except BaseException:
    if os.path.exists(tmp_path):
        os.unlink(tmp_path)
    raise

print(f"Imported {written} openings.")
print(f"Opening changes:")
print("```diff")
[print(f"-  {o}") for o in sorted(old_openings - new_openings)]
[print(f"+  {o}") for o in sorted(new_openings - old_openings)]
print("```")
