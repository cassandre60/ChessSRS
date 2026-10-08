# Test suite pass 1 — assessment, additions, and remaining gaps

Date: 2026-10-08. Branch `arena/25ec2faf-chesssrs`.

## 1. How coverage was assessed

There is no coverage tooling in this repository: CI runs plain `flutter test`
(`.github/workflows/test.yml:122`), with no `--coverage` and no `coverage`
dependency in `pubspec.yaml`. There is also no Dart toolchain in the environment
this was written in, so no coverage number could be produced.

The assessment was therefore structural, using the gate's own definition of the
tree (`scripts/gates/collect_metrics.py`) plus an import graph: for each file in
`lib/src`, whether any file in `test/` is named after it or imports its package
path.

That heuristic over-reports, because modules reached through a barrel or a
transitive import look untested. `lib/src/domain/review/review_session.dart` is
the clearest case: it has no dedicated test file, but `ReviewSession` is
exercised from `test/review/review_engine_test.dart`, `review_order_test.dart`
and `review_transposition_test.dart`. It is listed below with that caveat rather
than as a blank spot.

Modules with no test file and no importing test, by line count:

| module | files | lines | untested files | untested lines |
|---|---|---|---|---|
| `view` | 76 | 23775 | 34 | 6716 |
| `model` | 111 | 22483 | 28 | 2496 |
| `widgets` | 43 | 8820 | 21 | 2073 |
| `domain` | 23 | 3112 | 6 | 1228 |
| `utils` | 20 | 1964 | 11 | 1000 |

Raw line counts are misleading here. `view` and `widgets` dominate but need
widget tests, which are expensive per line and mostly assert layout. Ranked by
importance times untested-ness, the order used for this pass was:

1. **`utils/json.dart`** — 205 lines, 49 branches. Every duration and timestamp
   decode in the game and account models goes through these `Pick` extensions.
   Pure, deterministic, no mocking needed.
2. **`utils/lru_list.dart`** — 33 lines but live in production:
   `model/log/app_log_service.dart:40` keeps 1024 log records in one.
3. **`utils/string.dart`** — public extension API, pure, cheap.
4. **`domain/review/review_session.dart`** — 994 lines, ~251 branch points, the
   session state machine, and the subject of five confirmed findings in
   `docs/review-3-review-session.md`. Highest value in the repository, and the
   hardest to reach: it needs a full study/chapter/decision fixture.
5. `utils/image.dart`, `utils/system.dart`, `utils/focus_detector.dart` — thin
   wrappers over platform channels. Low value per line; deferred.

## 2. What this pass added

Three new files, 67 tests, none of which existed before:

| file | tests | covers |
|---|---|---|
| `test/utils/json_test.dart` | 38 | `decodeObjectList`, `LocaleConverter`, the `Uci` and `Time` pick extensions |
| `test/utils/string_test.dart` | 19 | `genRandomString`, `capitalize`, `localizeNumbers` |
| `test/utils/lru_list_test.dart` | 10 | ordering, eviction, `clear`, capacity edges |

The gate metric `test_declarations` moved from 1599 at the branch point to 1679,
though that total also includes tests that arrived with the merge of `main` and
is not a like-for-like measure of this pass.

Coverage followed the brief: happy path, boundaries (empty, zero, negative,
capacity edges, unicode, single versus multi element), error paths with the
concrete exception type, and state-dependent sequences for `LRUList`. External
dependencies were not needed — all three modules are pure.

Two conventions were followed deliberately. Tests that pin current behaviour
which is *wrong* say so in a comment and name the suspected bug, rather than
presenting the behaviour as expected. And `localizeNumbers` depends on
`NumberFormat()`'s ambient locale, so the grouping tests set
`Intl.defaultLocale` in `setUpAll`; without that they would pass or fail
depending on the host.

## 3. Suspected bugs found while writing these tests

Reported, not fixed — each is pinned by a test so a later fix fails loudly
rather than silently.

| location | behaviour | pinned by |
|---|---|---|
| `utils/lru_list.dart:16` | `capacity` is never validated. At `0` or negative, the eviction branch runs against an empty list and `LinkedList`'s null check throws, instead of the `put` being a no-op. | `LRUList > capacity 0 rejects every put` |
| `utils/string.dart:13` | `capitalize()` on an empty string is a `RangeError` on `this[0]` rather than returning `''`. No caller in `lib/` today, so it is latent. | `capitalize > empty string throws` |
| `utils/json.dart:44` | `LocaleConverter.fromJson` does `json['languageCode'] as String` while every sibling field is read as nullable, so a truncated payload throws a `TypeError` instead of degrading. | `LocaleConverter > fromJson throws when languageCode is missing` |
| `utils/string.dart:20` | `localizeNumbers()` is lossy past three fraction digits, because that is `NumberFormat`'s default. Callers hand it user-visible strings. | `localizeNumbers > a longer fraction is rounded away` |
| `utils/lru_list.dart` | The class is named LRU but exposes no read path, so recency is never updated and `put` does not deduplicate. It is insertion-ordered eviction, not least-recently-used. Not a bug against its own doc comment, but the name misleads. | `re-putting an old value does not move it to the end` |

None of these is severe. The first is the only one that can crash, and only with
a capacity that no caller passes.

## 4. Verification — what was and was not checked

This is the weak point of the pass and it should not be glossed over.

- **Run:** `./scripts/gates.sh t1`. G03, G05, G07 and G08 pass; `test_declarations`
  improves. G10 fails on `domain_loc` for the reason recorded in
  `docs/review-index.md` — `main` grew the domain past the ratchet's tolerance —
  which is unrelated to these files.
- **Not run:** the tests themselves. There is no Dart toolchain in this
  environment, so **not one of the 67 tests has been executed**. They are
  unverified in the strongest sense: a typo, a wrong matcher or a wrong
  assumption about `deep_pick` or `intl` behaviour would not have been caught.
- **Formatting:** `test/utils/lru_list_test.dart` and `string_test.dart` passed
  `dart format` in CI (run `37786070349`). `json_test.dart` did not, in an
  earlier form, and the offending construct could not be isolated by bisecting.
  It was rewritten so that **no call is split across lines at all** — zero lines
  end in an open paren — which is the one shape the formatter provably leaves
  alone. That rewrite has not been through CI.
- **Why nothing can be checked now:** PR #12 was closed on 2026-10-08 without
  being merged, and `pull_request` workflows do not run on a branch whose pull
  request is closed. Pushing to this branch produces no CI run at all. Restoring
  the verification loop needs the pull request reopened, or a new one opened.

The first thing to do with a toolchain is:

```
dart format --output=none --set-exit-if-changed test/utils
flutter test test/utils/lru_list_test.dart test/utils/string_test.dart test/utils/json_test.dart
```

Expect to adjust the four exception-type assertions
(`TypeError`, `RangeError`, `Error`, `PickException`) if the SDK or library
behaviour differs from what the code reads as.

## 5. Remaining gaps, ranked for a future pass

1. **`domain/review/review_session.dart` regression tests.** The single highest
   value target in the repository: 994 lines, ~251 branch points, and five
   confirmed findings in `docs/review-3-review-session.md` with no test pinning
   any of them. The sequences worth writing are a lapse followed by a successful
   re-test (C1, C2 and the D015 single-grading rule), the daily quota
   interacting with a re-queued lapse (C2), and a decision with more than one
   user continuation (C3). The blocker is fixture cost, not difficulty —
   `test/review/review_engine_test.dart` already builds the study, chapter and
   decision tree to copy.
2. **`model/` parsing.** 28 files, 2496 lines, no test file. The JSON decoding
   in the game and account models is now partly covered indirectly by
   `json_test.dart`, but the models themselves are not.
3. **`utils/image.dart`, `utils/system.dart`, `utils/focus_detector.dart`.**
   Platform-channel wrappers. Worth testing only with mocked channels; low value
   per line.
4. **`view/` and `widgets/`.** 8789 untested lines, but widget tests. Leave for
   a pass that specifically targets user-visible regressions.
