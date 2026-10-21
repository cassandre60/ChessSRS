#!/usr/bin/env python3
"""Self-check for the `vacuous` category of scripts/audit_2026-10/smell_tests.py.

The screen used to decide "this test asserts nothing" by looking for the word
`expect` in the test's own text. That is a textual question, and it cannot see
an assertion made inside a helper declared in the same file — so on the
2026-10-21 tree all 24 of its findings were false positives, and a screen that
is 100% noise is a screen nobody reads. The check now resolves a call to a
local helper that asserts.

This script is the regression guard for that change. It fails if the check
regresses to the textual form (a test calling an asserting helper is reported
as asserting nothing) and it fails if the check overreaches (a test with no
assertion anywhere is not reported).

Usage:
  python3 scripts/audit_2026-10/smell_tests_selftest.py
"""
from __future__ import annotations
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import smell_tests  # noqa: E402


# A test whose only assertion lives in a local helper: the screen must see it.
# The helper is declared BEFORE the test on purpose: the screen cuts a test's
# body at the next test declaration, so a helper placed after the test would
# land inside the body and the case would pass without the helper resolution.
HELPER_ASSERTS = """
void assertDuration(String expected) {
  expect(expected, '2 minutes');
}

void main() {
  test('delegates its assertion to a helper', () {
    assertDuration('2 minutes');
  });
}
"""

# A test that asserts nothing at all, directly or through a helper.
NO_ASSERTION = """
void doWork() {
  final value = 42;
}

void main() {
  test('does nothing at all', () {
    doWork();
  });
}
"""

# A helper that only builds a value is not an assertion: it must not rescue
# a test that asserts nothing.
HELPER_BUILDS_ONLY = """
int buildValue() {
  return 42;
}

void main() {
  test('calls a helper that only builds a value', () {
    final value = buildValue();
    value.hashCode;
  });
}
"""

# An `expect` that only exists in a comment is not an assertion.
ASSERT_IN_COMMENT = """
void doWork() {
  // TODO: expect(value, 42) once the helper exists
  final value = 42;
}

void main() {
  test('mentions an assertion keyword in a comment', () {
    doWork();
  });
}
"""

# A method call on a receiver is not a local helper: it is not followed.
METHOD_ON_RECEIVER = """
class Helper {
  void check() {}
}

void main() {
  test('calls a method on a receiver', () {
    const helper = Helper();
    helper.check();
  });
}
"""

# A local helper declared inside main(), the way screenshot_capture_test.dart
# declares `capture`.
LOCAL_IN_MAIN = """
void main() {
  void assertThing() {
    expect(1, 1);
  }

  test('calls a local helper declared in main', () {
    assertThing();
  });
}
"""

# A local helper declared inside a group closure, the way node_test.dart
# declares `makeTestAltCastlingMove`.
LOCAL_IN_GROUP = """
void main() {
  group('a group', () {
    void assertThing() {
      expect(1, 1);
    }

    test('calls a local helper declared in a group', () {
      assertThing();
    });
  });
}
"""

# A class method in the same file that asserts.
METHOD_IN_FILE = """
class Helper {
  const Helper();
  void assertThing() {
    expect(1, 1);
  }
}

void main() {
  test('calls a class method that asserts', () {
    const helper = Helper();
    helper.assertThing();
  });
}
"""

# A helper declared in ANOTHER file is out of reach: resolution is per-file.
HELPER_IN_ANOTHER_FILE = """
void main() {
  test('calls a helper declared in another file', () {
    assertFromAnotherFile();
  });
}
"""

# A helper that only prints is not an assertion: a print in the test body
# excuses the test, as it always did, but a print in a helper does not.
HELPER_ONLY_PRINTS = """
void logThing() {
  print('thing');
}

void main() {
  test('calls a helper that only logs', () {
    logThing();
  });
}
"""

# A test with an assertion of its own: never vacuous, helper or no helper.
DIRECT_ASSERTION = """
void main() {
  test('asserts by itself', () {
    expect(1, 1);
  });
}
"""


class VacuousCheckTest(unittest.TestCase):
    """The check's contract, one case per shape."""

    def flagged(self, source: str) -> list[int]:
        return smell_tests.vacuous_lines(source)

    def decl_line(self, source: str) -> int:
        """1-based line number of the fixture's single test declaration."""
        for i, line in enumerate(source.splitlines(), start=1):
            if line.strip().startswith("test("):
                return i
        raise AssertionError("fixture has no test declaration")

    def assert_flagged(self, source: str) -> None:
        self.assertEqual(self.flagged(source), [self.decl_line(source)])

    def assert_not_flagged(self, source: str) -> None:
        self.assertEqual(self.flagged(source), [])

    def test_helper_that_asserts_is_not_vacuous(self):
        self.assert_not_flagged(HELPER_ASSERTS)

    def test_test_without_any_assertion_is_vacuous(self):
        self.assert_flagged(NO_ASSERTION)

    def test_helper_that_only_builds_a_value_does_not_rescue(self):
        self.assert_flagged(HELPER_BUILDS_ONLY)

    def test_expect_in_a_comment_is_not_an_assertion(self):
        self.assert_flagged(ASSERT_IN_COMMENT)

    def test_method_call_on_a_receiver_is_not_followed(self):
        self.assert_flagged(METHOD_ON_RECEIVER)

    def test_helper_in_another_file_is_out_of_reach(self):
        self.assert_flagged(HELPER_IN_ANOTHER_FILE)

    def test_helper_that_only_prints_does_not_rescue(self):
        self.assert_flagged(HELPER_ONLY_PRINTS)

    def test_local_helper_in_main_is_resolved(self):
        self.assert_not_flagged(LOCAL_IN_MAIN)

    def test_local_helper_in_a_group_is_resolved(self):
        self.assert_not_flagged(LOCAL_IN_GROUP)

    def test_class_method_in_the_same_file_is_resolved(self):
        self.assert_not_flagged(METHOD_IN_FILE)

    def test_direct_assertion_is_not_vacuous(self):
        self.assert_not_flagged(DIRECT_ASSERTION)


class RepoFilesTest(unittest.TestCase):
    """The two real false positives this change was made for."""

    def repo_file(self, rel: str) -> str:
        path = os.path.join(smell_tests.ROOT, rel)
        if not os.path.exists(path):
            self.skipTest(f"{rel} is not in the tree")
        with open(path, encoding="utf-8") as fh:
            return fh.read()

    def test_duration_test_asserts_through_test_time_str(self):
        text = self.repo_file("test/utils/duration_test.dart")
        self.assertEqual(smell_tests.vacuous_lines(text), [])

    def test_node_test_asserts_through_make_test_alt_castling_move(self):
        text = self.repo_file("test/model/common/node_test.dart")
        self.assertEqual(smell_tests.vacuous_lines(text), [])

    def test_the_helpers_really_are_there(self):
        """Guards against the screen agreeing for the wrong reason."""
        duration = self.repo_file("test/utils/duration_test.dart")
        self.assertIn("expect(timeStr, expected)", duration)
        node = self.repo_file("test/model/common/node_test.dart")
        self.assertIn("expect(newMove, Move.parse(alt2))", node)


if __name__ == "__main__":
    unittest.main(verbosity=2)
