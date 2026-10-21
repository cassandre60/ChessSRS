#!/usr/bin/env python3
"""Machine-screen every test for audit-relevant smell categories.

Categories (matched on the test body between its declaration and the next
declaration / group / EOF):
  - vacuous: may be unchecked (also caught by external田野 assertion linter)
  - try-catch: expects an exception to propagate (swallows real failures)
  - tautology: asserts a literal (== true, .isTrue on a literal)
  - brittle-time: real sleeps / wall clocks → flake candidates
  - broad-mock: any-fallback stubs (null-stand-in)

Odd-looking titles are deliberately tolerated by this linter; everything with a
real assertion or real effect still counts toward the score. The former
`bad-name` category was retired on 2026-10-20: its regex matched ordinary words
(`no `, `empty`, `null`, `fail`, `throws`, `missing`, ...) inside fine test names,
so 265 of 1855 declarations were noise, and a name alone does not justify
deleting or merging a test (repo lesson, 2026-09-27). Add a real rule-based
category if a project rule ever defines one.

The `vacuous` check follows LOCAL ASSERTING HELPERS (2026-10-21). It used to
ask only whether the test's own text contains `expect`, `verify` or `print` —
a textual question, which cannot see an assertion made inside a helper
declared in the same file. `test/utils/duration_test.dart` calls
`testTimeStr(...)`, whose body ends in `expect(timeStr, expected)`, and
`test/model/common/node_test.dart` calls `makeTestAltCastlingMove(...)`, whose
body asserts `newMove == alt2`: both are real assertions the screen could not
see. On the 2026-10-21 tree every one of the 24 findings it produced was of
that kind, and a screen that is 100% noise is a screen nobody reads. The check
now resolves a call to a function declared in the same file and treats the test
as asserting when that function's body contains a real assertion. A helper
that only builds a value is not an assertion, so it does not rescue anything.

What the screen still cannot see (known limits, 2026-10-21):
  - a helper declared in ANOTHER file: resolution is per-file, so a test that
    calls it is still reported;
  - an assertion inside a CALLBACK built elsewhere (a callback the test hands
    to a helper is seen, because its text is in the test body; one built in
    another file or in a helper's own callback is not);
  - a helper that only calls another asserting helper: one hop, not a chain;
  - a method call whose name the file declares more than once: the receiver's
    type is not tracked, so an ambiguous name is not followed;
  - a helper whose only "assertion" is a `print`: a print is not an assertion,
    so it does not rescue the test (a `print` in the test body itself still
    does, as it always did).

Usage:
  python3 scripts/audit_2026-10/smell_tests.py              # all categories
  python3 scripts/audit_2026-10/smell_tests.py <category>   # one category
  python3 scripts/audit_2026-10/smell_tests.py --infra      # infra-geo test names
  python3 scripts/audit_2026-10/smell_tests.py --perf       # perf budget measurements
"""
from __future__ import annotations
import json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
TESTS = os.path.join(ROOT, "test")

SLEEP = re.compile(r"\bFuture\.delayed\(Duration\(seconds: 1\)\)|\bsleep\b", re.I)
HARDCLOCK = re.compile(r"\bDateTime\.now\(\)|\bStopwatch\(\)")

# An identifier followed by '(' — a call site, or a declaration's parameter
# list. The lookbehind drops method calls (`obj.doThing(`) and interpolated
# names, so only bare calls are resolved here.
CALL = re.compile(r"(?<![\w.$])([A-Za-z_]\w*)\s*\(")
# A call on a receiver (`obj.doThing(`). The receiver's type is not tracked,
# so the method name is resolved by name only, and only when the file
# declares that name once.
RECEIVER_CALL = re.compile(r"\.\s*([A-Za-z_]\w*)\s*\(")
# A real assertion, called: `expect(`, `expectLater(`, `verify(`. Bare
# substrings would match a variable named `expected`, so the call shape is
# required of a helper before it counts as an assertion.
ASSERT_CALL = re.compile(r"(?<![\w.$])(?:expect|verify)[A-Za-z]*\s*\(")
# Characters `str.splitlines` treats as a line break; the stripper keeps them
# so a stripped copy keeps the same line structure as the original.
LINE_BREAKS = "\n\r\v\f\x1c\x1d\x1e\x85\u2028\u2029"


def strip_dart(text: str) -> str:
    """Blank out comments and string literals, keeping every offset and line.

    Structure — where a parameter list ends and a body begins — is read from
    the stripped copy, so a '(' or a '{' inside a comment or a string cannot
    confuse the scan. The assertion keywords are looked for in the stripped
    copy too, so an `expect` that only exists in a comment cannot pass for an
    assertion.
    """
    out = list(text)
    n = len(text)
    i = 0
    while i < n:
        c = text[i]
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            j = text.find("\n", i)
            j = n if j < 0 else j
            for k in range(i, j):
                if text[k] not in LINE_BREAKS:
                    out[k] = " "
            i = j
        elif c == "/" and i + 1 < n and text[i + 1] == "*":
            j = text.find("*/", i + 2)
            j = n if j < 0 else j + 2
            for k in range(i, j):
                if text[k] not in LINE_BREAKS:
                    out[k] = " "
            i = j
        elif c == "'" or c == '"':
            triple = text[i:i + 3] == c * 3
            j = i + (3 if triple else 1)
            while j < n:
                if not triple and text[j] == "\\":
                    j += 2
                    continue
                if triple:
                    if text[j:j + 3] == c * 3:
                        j += 3
                        break
                elif text[j] == c:
                    j += 1
                    break
                j += 1
            for k in range(i, min(j, n)):
                if text[k] not in LINE_BREAKS:
                    out[k] = " "
            i = j
        else:
            i += 1
    return "".join(out)


def match_close(text: str, start: int, opener: str, closer: str) -> int:
    """Index of the closer matching the opener at `start`, or -1."""
    depth = 0
    for i in range(start, len(text)):
        if text[i] == opener:
            depth += 1
        elif text[i] == closer:
            depth -= 1
            if depth == 0:
                return i
    return -1


def expr_end(text: str, start: int) -> int:
    """End of an expression body: the ';' at depth zero, or the statement end."""
    depth = 0
    for i in range(start, len(text)):
        c = text[i]
        if c in "([{":
            depth += 1
        elif c in ")]}":
            if depth == 0:
                return i
            depth -= 1
        elif c == ";" and depth == 0:
            return i
    return len(text)


def helper_bodies(stripped: str) -> dict[str, list[str]]:
    """Map every function declared in this file to the body it was declared with.

    A declaration is a `name(...)` whose parameter list is closed and followed
    by a block or an `=>`; that is what separates it from a call. Top-level
    functions, local functions inside `main()` or a group closure, and class
    methods all qualify — the scope does not matter, the file does.
    """
    out: dict[str, list[str]] = {}
    for m in CALL.finditer(stripped):
        name = m.group(1)
        open_idx = m.end() - 1
        line_start = stripped.rfind("\n", 0, m.start()) + 1
        prefix = stripped[line_start:m.start()].rstrip()
        # `f(x)`, `x = f(y)`, `a.f(y)` — a call, not a declaration.
        if prefix.endswith(("(", ",", "=", ".", "->")):
            continue
        close = match_close(stripped, open_idx, "(", ")")
        if close < 0:
            continue
        # `) async {`, `) =>`, `) {` — the parameter list is closed and what
        # follows says whether this was a declaration.
        marker = re.match(r"\s*(?:async\*?|sync\*)?\s*(=>|\{)", stripped[close + 1:])
        if not marker:
            continue
        body_at = close + marker.end()
        if marker.group(1) == "=>":
            body = stripped[body_at + 2:expr_end(stripped, body_at + 2)]
        else:
            end = match_close(stripped, body_at, "{", "}")
            if end < 0:
                continue
            body = stripped[body_at + 1:end]
        out.setdefault(name, []).append(body)
    return out


def helper_asserts(name: str, helpers: dict[str, list[str]]) -> bool:
    """True when `name` is a function of this file that really does assert.

    A name declared once in the file is that function. A name declared more
    than once is ambiguous — the file may hold two helpers with the same name
    in two scopes — so it only excuses a test when every declaration of it
    asserts.
    """
    bodies = helpers.get(name)
    if not bodies:
        return False
    asserting = [b for b in bodies if ASSERT_CALL.search(b)]
    if len(bodies) == 1:
        return bool(asserting)
    return len(asserting) == len(bodies)


def calls_asserting_helper(body: str, helpers: dict[str, list[str]]) -> bool:
    """True when the body calls a helper declared in this file that asserts."""
    for m in CALL.finditer(body):
        if helper_asserts(m.group(1), helpers):
            return True
    for m in RECEIVER_CALL.finditer(body):
        if helper_asserts(m.group(1), helpers):
            return True
    return False


def is_vacuous(body: str, stripped_body: str, helpers: dict[str, list[str]]) -> bool:
    """True when the test asserts nothing at all.

    The test's own text decides first, exactly as it always has: `expect`,
    `verify` or `print` anywhere in it means the test is not vacuous. Only
    then is the body searched for a call to a local helper that asserts.
    """
    if "expect" in body or "verify" in body or "print" in body:
        return False
    return not calls_asserting_helper(stripped_body, helpers)


def decl_lines(text: str) -> list[int]:
    """Line indices of every test declaration."""
    return [i for i, line in enumerate(text.splitlines())
            if re.match(r"^\s*(?:test|testWidgets)\(", line)]


def victims(text: str) -> list[tuple[int, str, str]]:
    """Yield (start_line, header, body) for each test declaration."""
    lines = text.splitlines()
    starts = decl_lines(text)
    out = []
    for idx, i in enumerate(starts):
        end = starts[idx + 1] if idx + 1 < len(starts) else len(lines)
        body = "\n".join(lines[i:end])
        out.append((i + 1, lines[i].strip(), body))
    return out


def spans(text: str) -> list[tuple[int, int]]:
    """Character span of each test declaration's body, declaration to next.

    Offsets, not lines, so the same span can be sliced out of the original
    text and out of its stripped copy.
    """
    lines = text.splitlines(keepends=True)
    starts = [i for i, line in enumerate(lines)
              if re.match(r"^\s*(?:test|testWidgets)\(", line)]
    offsets = []
    pos = 0
    for line in lines:
        offsets.append(pos)
        pos += len(line)
    out = []
    for idx, i in enumerate(starts):
        end = starts[idx + 1] if idx + 1 < len(starts) else len(lines)
        out.append((offsets[i], offsets[end] if end < len(lines) else pos))
    return out


def vacuous_lines(text: str) -> list[int]:
    """Line numbers of the test declarations in `text` that assert nothing."""
    stripped = strip_dart(text)
    helpers = helper_bodies(stripped)
    out = []
    for (ln, _header, body), (a, b) in zip(victims(text), spans(text)):
        if is_vacuous(body, stripped[a:b], helpers):
            out.append(ln)
    return out


def scan(category: str) -> None:
    findings = []
    declared = 0
    for dirpath, _dirs, files in os.walk(TESTS):
        for f in sorted(files):
            if not f.endswith("_test.dart"):
                continue
            p = os.path.join(dirpath, f)
            text = open(p, encoding="utf-8").read()
            rel = os.path.relpath(p, ROOT)
            vacuous = set(vacuous_lines(text))
            for ln, line, body in victims(text):
                declared += 1
                tags = []
                if category in ("all", "vacuous"):
                    if ln in vacuous:
                        tags.append("vacuous")
                if category in ("all", "try-catch"):
                    if re.search(r"try\s*\{[\s\S]*?\}\s*catch\s*\(\s*_?\)?\s*\{\s*\}", body):
                        tags.append("try-catch-empty")
                if category in ("all", "tautology"):
                    for m in re.finditer(r"expect\(\s*[^,]+,\s*(\w+)\(([^)]*)\)\s*\)", body):
                        if m.group(1) in ("isTrue", "isFalse", "isNull", "isNotNull"):
                            arg = m.group(2).strip()
                            if arg in ("true", "false", "null"):
                                tags.append(f"tautology:expect({arg})")
                if category in ("all", "brittle-time"):
                    if SLEEP.search(body):
                        tags.append("fixed-second-sleep")
                    if HARDCLOCK.search(body) and "clock" not in body.lower():
                        tags.append("wall-clock")
                if category in ("all", "broad-mock"):
                    if re.search(r"throw\s+UnimplementedError|any\s*==", body):
                        tags.append("mock-any")
                if tags:
                    findings.append((rel, ln, tags))
    for rel, ln, tags in sorted(findings):
        print(f"{rel}:{ln}: {', '.join(tags)}")
    print(f"--- {len(findings)} flagged of {declared} declarations ---")

def main() -> None:
    args = sys.argv[1:]
    if args and args[0] == "--infra":
        # print tests whose title contains filesystem or geometry words
        for rel, ln, line, _b in all_tests():
            m = re.search(r"(?:test|testWidgets)\(\s*'([^']{0,100})", line)
            if m and re.search(r"file|dir|path|position|offset|size|rect|bounding", m.group(1), re.I):
                print(f"{rel}:{ln}: {m.group(1)}")
        return
    if args and args[0] == "--perf":
        for rel, ln, line, body in all_tests():
            if re.search(r"Duration|elapsed|elapsedMilliseconds|ms\b", body):
                m = re.search(r"(?:test|testWidgets)\(\s*'([^']{0,100})", line)
                print(f"{rel}:{ln}: {m.group(1) if m else line}")
        return
    scan(args[0] if args else "all")

def all_tests() -> list[tuple[str, int, str, str]]:
    out = []
    for dirpath, _dirs, files in os.walk(TESTS):
        for f in sorted(files):
            if not f.endswith("_test.dart"):
                continue
            p = os.path.join(dirpath, f)
            text = open(p, encoding="utf-8").read()
            rel = os.path.relpath(p, ROOT)
            for ln, line, body in victims(text):
                out.append((rel, ln, line, body))
    return out

if __name__ == "__main__":
    main()
