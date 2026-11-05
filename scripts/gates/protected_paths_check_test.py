#!/usr/bin/env python3
"""Self-test for scripts/gates/protected_paths_check.py.

The claim under test: the ``auto=additive-ledger-rows`` lane approves only a
purely additive audit-catalog change whose added rows are complete, single
target and recorded at HEAD. An edit, a deletion, a bad hash, a bundled extra
file, a multi-target row, a non-audited status, or a pattern without the
directive must all still stop for a human.

Narrow and hermetic: throwaway git repositories, no network, no toolchain.
"""
from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "protected_paths_check.py"

PATTERNS_AUTO = "docs/LEDGER.md  auto=additive-ledger-rows\nGATES.md\n"
PATTERNS_PLAIN = "docs/LEDGER.md\nGATES.md\n"

HEADER = (
    "# Ledger\n\n"
    "| Date | Stream | Target | Hash | Status | PR | Summary | Trigger |\n"
    "|---|---|---|---|---|---|---|---|\n"
)


def row(target: str, content_hash: str, status: str = "SOUND",
        date: str = "2026-01-01", extra_targets: bool = False) -> str:
    cell = f"`{target}`, `other.dart`" if extra_targets else f"`{target}`"
    return (f"| {date} | A (Mutation) | {cell} | `{content_hash}` | {status} | — | "
            f"audited | Any modification. |\n")


class AutoLaneTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.email", "t@example.com")
        self.git("config", "user.name", "Test")
        (self.repo / "lib/src").mkdir(parents=True)
        (self.repo / "lib/src/app.dart").write_text("void main() {}\n")
        (self.repo / "GATES.md").write_text("# Gates\n")
        (self.repo / "README.md").write_text("# Readme\n")
        (self.repo / "docs").mkdir()
        (self.repo / "docs/LEDGER.md").write_text(HEADER)
        self.commit("seed")
        self.base = self.git("rev-parse", "HEAD").stdout.strip()
        self.hash9 = self.git("rev-parse", "HEAD:lib/src/app.dart").stdout.strip()[:9]

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def git(self, *args: str) -> subprocess.CompletedProcess:
        return subprocess.run(["git", *args], cwd=self.repo, capture_output=True, text=True)

    def commit(self, message: str) -> None:
        self.git("add", "-A")
        self.git("commit", "-q", "-m", message)

    def run_check(self, patterns: str, *extra: str) -> subprocess.CompletedProcess:
        patterns_file = self.root / "patterns.txt"
        patterns_file.write_text(patterns)
        return subprocess.run(
            [sys.executable, str(SCRIPT), "--base", self.base,
             "--patterns", str(patterns_file), *extra],
            cwd=self.repo, capture_output=True, text=True,
        )

    def append_ledger(self, line: str) -> None:
        path = self.repo / "docs/LEDGER.md"
        path.write_text(path.read_text() + line)
        self.commit("ledger")

    # --- the lane approves what it should ---------------------------------
    def test_additive_row_at_head_is_auto_approved(self) -> None:
        self.append_ledger(row("lib/src/app.dart", self.hash9))
        proc = self.run_check(PATTERNS_AUTO)
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertIn("auto-approved", proc.stdout)

    # --- everything else still stops --------------------------------------
    def test_wrong_hash_is_refused(self) -> None:
        self.append_ledger(row("lib/src/app.dart", "000000000"))
        proc = self.run_check(PATTERNS_AUTO)
        self.assertEqual(proc.returncode, 3, proc.stdout + proc.stderr)
        self.assertIn("but HEAD is", proc.stdout)

    def test_edited_row_is_refused(self) -> None:
        self.append_ledger(row("lib/src/app.dart", self.hash9))
        # The row must exist in the BASE for this to be an edit, not an addition.
        self.base = self.git("rev-parse", "HEAD").stdout.strip()
        path = self.repo / "docs/LEDGER.md"
        path.write_text(path.read_text().replace("audited", "audit was fine"))
        self.commit("edit")
        proc = self.run_check(PATTERNS_AUTO)
        self.assertEqual(proc.returncode, 3, proc.stdout + proc.stderr)
        self.assertIn("not purely additive", proc.stdout)

    def test_deleted_row_is_refused(self) -> None:
        self.append_ledger(row("lib/src/app.dart", self.hash9))
        self.base = self.git("rev-parse", "HEAD").stdout.strip()
        path = self.repo / "docs/LEDGER.md"
        path.write_text(HEADER)
        self.commit("delete")
        proc = self.run_check(PATTERNS_AUTO)
        self.assertEqual(proc.returncode, 3, proc.stdout + proc.stderr)
        self.assertIn("not purely additive", proc.stdout)

    def test_multi_target_row_is_refused(self) -> None:
        self.append_ledger(row("lib/src/app.dart", self.hash9, extra_targets=True))
        proc = self.run_check(PATTERNS_AUTO)
        self.assertEqual(proc.returncode, 3, proc.stdout + proc.stderr)
        self.assertIn("complete single-target audit row", proc.stdout)

    def test_non_audited_status_is_refused(self) -> None:
        self.append_ledger(row("lib/src/app.dart", self.hash9, status="IN_PROGRESS"))
        proc = self.run_check(PATTERNS_AUTO)
        self.assertEqual(proc.returncode, 3, proc.stdout + proc.stderr)

    def test_prose_line_is_refused(self) -> None:
        self.append_ledger("A stray prose paragraph, not a row.\n")
        proc = self.run_check(PATTERNS_AUTO)
        self.assertEqual(proc.returncode, 3, proc.stdout + proc.stderr)

    def test_bundled_extra_file_is_refused(self) -> None:
        self.append_ledger(row("lib/src/app.dart", self.hash9))
        (self.repo / "README.md").write_text("# Readme changed\n")
        self.commit("bundle")
        proc = self.run_check(PATTERNS_AUTO)
        self.assertEqual(proc.returncode, 3, proc.stdout + proc.stderr)
        self.assertIn("besides the catalog", proc.stdout)

    def test_other_protected_file_is_refused(self) -> None:
        self.append_ledger(row("lib/src/app.dart", self.hash9))
        (self.repo / "GATES.md").write_text("# Gates edited\n")
        self.commit("gates")
        proc = self.run_check(PATTERNS_AUTO)
        self.assertEqual(proc.returncode, 3, proc.stdout + proc.stderr)

    def test_pattern_without_the_directive_is_refused(self) -> None:
        self.append_ledger(row("lib/src/app.dart", self.hash9))
        proc = self.run_check(PATTERNS_PLAIN)
        self.assertEqual(proc.returncode, 3, proc.stdout + proc.stderr)

    # --- the human lane still works ---------------------------------------
    def test_approved_allows_an_edit(self) -> None:
        self.append_ledger(row("lib/src/app.dart", self.hash9))
        self.base = self.git("rev-parse", "HEAD").stdout.strip()
        path = self.repo / "docs/LEDGER.md"
        path.write_text(path.read_text().replace("audited", "edited by hand"))
        self.commit("edit")
        proc = self.run_check(PATTERNS_AUTO, "--approved")
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertIn("approved by a human reviewer", proc.stdout)

    def test_unprotected_change_passes_untouched(self) -> None:
        (self.repo / "README.md").write_text("# Readme changed\n")
        self.commit("readme")
        proc = self.run_check(PATTERNS_AUTO)
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertIn("no protected paths touched", proc.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
