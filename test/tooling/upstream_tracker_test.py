#!/usr/bin/env python3
"""Unit tests for scripts/upstream_tracker.py."""

import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from scripts.upstream_tracker import (
    classify_commit,
    extract_pr_number,
    generate_markdown_report,
    load_ledger,
    save_ledger,
)


class TestUpstreamTracker(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)
        # Create some surviving files to test against
        (self.root / "pubspec.yaml").touch()
        (self.root / "lib/src/model/study").mkdir(parents=True, exist_ok=True)
        (self.root / "lib/src/model/study/study_repository.dart").touch()
        (self.root / "lib/src/widgets").mkdir(parents=True, exist_ok=True)
        (self.root / "lib/src/widgets/pgn.dart").touch()

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_extract_pr_number(self):
        self.assertEqual(extract_pr_number("Fix login (#3746)"), 3746)
        self.assertEqual(extract_pr_number("Board editor reads position PR #3831"), 3831)
        self.assertEqual(extract_pr_number("Merge pull request #3790 from lichess"), 3790)
        self.assertIsNone(extract_pr_number("Regular commit without PR"))

    def test_classify_cut_subsystem(self):
        status, cat, files = classify_commit(
            sha="abcdef123",
            subject="Fix puzzle streak timer",
            files=["lib/src/view/puzzle/puzzle_screen.dart", "lib/src/model/puzzle/streak.dart"],
            repo_root=self.root,
        )
        self.assertEqual(status, "SKIPPED_CUT")
        self.assertEqual(cat, "cut")
        self.assertEqual(files, [])

    def test_classify_chore_subject(self):
        status, cat, files = classify_commit(
            sha="abcdef124",
            subject="Bump version to 2.1.0",
            files=["pubspec.yaml"],
            repo_root=self.root,
        )
        self.assertEqual(status, "SKIPPED_CHORE")
        self.assertEqual(cat, "chore")

    def test_classify_chore_translations(self):
        status, cat, files = classify_commit(
            sha="abcdef125",
            subject="Update Spanish and French translations",
            files=["lib/l10n/app_es.arb", "lib/l10n/app_fr.arb"],
            repo_root=self.root,
        )
        self.assertEqual(status, "SKIPPED_CHORE")
        self.assertEqual(cat, "chore")

    def test_classify_candidate_core_logic(self):
        status, cat, files = classify_commit(
            sha="abcdef126",
            subject="Fix study tree duplication bug (#3999)",
            files=["lib/src/model/study/study_repository.dart"],
            repo_root=self.root,
        )
        self.assertEqual(status, "CANDIDATE")
        self.assertEqual(cat, "core_logic")
        self.assertEqual(files, ["lib/src/model/study/study_repository.dart"])

    def test_classify_candidate_dependency(self):
        status, cat, files = classify_commit(
            sha="abcdef127",
            subject="Upgrade dartchess to 0.15.0",
            files=["pubspec.yaml"],
            repo_root=self.root,
        )
        self.assertEqual(status, "CANDIDATE")
        self.assertEqual(cat, "dependency")
        self.assertEqual(files, ["pubspec.yaml"])

    def test_classify_known_applied(self):
        status, cat, files = classify_commit(
            sha="ed3dbea51c88",
            subject="Remove unrequired abiFilters in build.gradle.kts (#3750)",
            files=["android/app/build.gradle.kts"],
            repo_root=self.root,
        )
        self.assertEqual(status, "APPLIED")
        self.assertEqual(cat, "applied")

    def test_ledger_persistence(self):
        ledger_file = self.root / "ledger.json"
        ledger = load_ledger(ledger_file)
        self.assertEqual(ledger["stats"]["total"], 0)

        ledger["commits"]["abc123456"] = {
            "sha": "abc123456789",
            "short_sha": "abc123456",
            "pr": 1234,
            "title": "A candidate",
            "status": "CANDIDATE",
            "category": "core_logic",
            "surviving_files": ["lib/src/model/study/study_repository.dart"],
        }
        ledger["commits"]["def123456"] = {
            "sha": "def123456789",
            "short_sha": "def123456",
            "pr": 1235,
            "title": "A skipped cut",
            "status": "SKIPPED_CUT",
            "category": "cut",
            "surviving_files": [],
        }

        save_ledger(ledger, ledger_file)
        reloaded = load_ledger(ledger_file)

        self.assertEqual(reloaded["stats"]["total"], 2)
        self.assertEqual(reloaded["stats"]["candidates"], 1)
        self.assertEqual(reloaded["stats"]["skipped"], 1)
        self.assertEqual(reloaded["commits"]["abc123456"]["title"], "A candidate")

    def test_generate_markdown_report(self):
        candidates = [
            {
                "sha": "abc123456789",
                "short_sha": "abc123456",
                "pr": 3812,
                "title": "Fix audio leak on Linux",
                "category": "core_logic",
                "surviving_files": ["lib/src/model/common/service/sound_service.dart"],
            }
        ]
        md = generate_markdown_report(candidates)
        self.assertIn("## Upstream Intake: Candidates for Review", md)
        self.assertIn("[#3812](https://github.com/lichess-org/mobile/pull/3812)", md)
        self.assertIn("Fix audio leak on Linux", md)
        self.assertIn("`lib/src/model/common/service/sound_service.dart`", md)


if __name__ == "__main__":
    unittest.main()
