# TEST-FIX-19 — Load-sensitive review tests flake under contention (pumpAsync fixed 80 ms)

> **For a dumb agent**: follow this file top-to-bottom. Do exactly what it says,
> nothing more. Each section tells you where to look, what to change, and how to
> prove it — no guessing.

## 1. What is broken

Several review controller tests are load-sensitive and flake in large parallel runs (`GATES.md` §42 / `AGENTS.md` Lesson 2026-09-28):

`test/view/review/review_screen_test.dart` + `test/view/review/scope_split_drawers_test.dart` use a helper:

```dart
Future<void> pumpAsync(WidgetTester tester, [int millis = 80]) async {
  await Future.delayed(Duration(milliseconds: millis));
  await tester.pump();
}
```

That waits a **fixed 80 ms of real time** for the controller's database futures, then pumps the fake clock by fixed amounts. Under CPU contention less real work fits inside the window, so the controller has not reloaded when assertions run and they fail on absent data. `flutter test` gives each file its own isolate, so this is timing, not shared state: the same four directories failed 3 tests on one run and passed all 128 on the next, unchanged (AGENTS.md Lesson, verified 30/30 isolated). Before blaming a change, re-run the file alone — but the honest fix is polling on a condition instead of sleeping a fixed interval.

Scope: only the 4 load-sensitive helpers / test groups (see §2), not every `pumpAsync` call.

## 2. Files to read before touching anything

1. `test/view/review/review_screen_test.dart:60-150` — `pumpAsync` definition + first call sites (the canonical helper)
2. `test/view/review/scope_split_drawers_test.dart:80-160` — second `pumpAsync` copy
3. `test/view/screenshot_capture_test.dart:177` — comment "same shape as the pumpAsync helper in review_screen_test.dart"
4. `GATES.md:42-50` — flake disclosure (expected behaviour, not a gate failure per se, but CI still red)
5. `AGENTS.md:420-435` — Lesson Learned 2026-09-28 ("Several review tests are load-sensitive…")
6. `docs/polish-tasks.md:111-128` — Task 6 spec (replace fixed delays with condition-based polling)
7. `lib/src/review/review_controller.dart:335-420` — `_loadState` + generation gating (what the test is actually waiting for: `reviewStateAsync` to become `AsyncData`)
8. `test/test_provider_scope.dart` — `makeTestProviderScope` helper (how tests supply `srsStudyRepositoryProvider` overrides without real DB)
9. `flutter_test` docs: `WidgetTester.pump`, `pumpAndSettle`, `runAsync` — real-time vs fake-clock distinction

## 3. The fix

Replace fixed `Future.delayed(80ms)` waits with **polling on the condition** that the controller has finished its async load.

### 3.1 Add a polling helper (preferred over sprinkling raw loops)

In `test/view/review/review_screen_test.dart` (or a new `test/view/review/test_helpers.dart`), add:

```dart
/// Pump until [condition] is true or [timeout] elapses.
///
/// Uses real time for the deadline (wall clock) but fake-clock pumps for
/// each step, so it works with `Clock` overrides and with `runAsync` futures
/// that need real time to complete.
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
  Duration step = const Duration(milliseconds: 50),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('pumpUntil timed out after $timeout waiting for condition');
    }
    await tester.pump(step);
    // Yield to real async work (DB futures, microtasks) that the tester
    // clock does not advance. Use runAsync so the fake clock doesn't stall them.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
  }
}
```

Then define the condition per test as the thing the test actually needs:

* For tests that await the controller load: `() => tester.widgetList(find.byType(SrsMemoryBar)).isNotEmpty` or `() => find.text('Nothing due.').evaluate().isNotEmpty` — whichever the test asserts next.
* For drawer tests: `() => find.byType(ReviewScopeDrawer).evaluate().isNotEmpty` or similar.
* Simplest generic: `() => providerContainer.read(reviewControllerProvider).hasValue` — but that couples to provider internals; prefer a widget finder that the user can see.

Replace call sites:

```dart
// BEFORE
await pumpAsync(tester);
expect(find.text('Nothing due.'), findsOneWidget);

// AFTER
await pumpUntil(tester, () => find.text('Nothing due.').evaluate().isNotEmpty);
expect(find.text('Nothing due.'), findsOneWidget);
// expect stays, but now it cannot race the load
```

Keep `pumpAsync` as a thin delegator for tests that truly want a fixed delay (e.g. 700ms opponent animation wait) — do not touch those sleeps; only the 80ms "wait for DB reload" sleeps are flakes. A pragmatic rule: if the delay precedes an assertion on `hasValue` / `findsOneWidget` of a value the DB load produces, it needs `pumpUntil`; if it precedes a `find.byType(SrsMoveArrow)` timing check, leave it.

### 3.2 Optional — extract shared helper

If multiple files define their own `pumpAsync`, extract one `test/view/review/test_helpers.dart` with `pumpAsync` + `pumpUntil` and have the two test files import it. This matches `polish-tasks.md` Task 6 ("`test/test_helpers.dart`") but keep the file next to the review tests to avoid cross-feature imports.

### 3.3 What NOT to change

* Do not change `ReviewService.getDueSummary` or `ReviewController._loadState` timing — flake is in the test, not the product.
* Do not add `testWidgets` `skip: true` / `timeout` overrides or `expect` tolerances — G08 rejects test weakening.
* Do not run wide `flutter test` locally beyond the 2 touched files — CI is the authority for the full suite (AGENTS.md §3.1).
* Do not touch `SPEC.md`, `GATES.md`, `.gates/`, `pubspec.yaml`. This is a test-only change (`Class: test-only`).

## 4. How to make the work verifiable (no guessing)

### 4.1 Worktree setup — required

```bash
git worktree add ../chesssrs-test-fix-19 -b fix/test-fix-19-pumpasync-flake origin/main
cd ../chesssrs-test-fix-19
fvm flutter pub get
fvm dart run build_runner build --delete-conflicting-outputs
fvm flutter analyze
```

Branch name is `fix/test-fix-19-pumpasync-flake`.

### 4.2 Failing-or-proving test — reproduce the flake, then harden

**Baseline (before fix):** Run the review dir in parallel — the flake is load-sensitive, so run it 3 times or with high concurrency if available:

```bash
fvm flutter test test/view/review/ --concurrency 4 2>&1 | rg -n "FAILED|failed|pump"
# Before fix: ~3 failures across review_screen_test.dart + scope_split_drawers_test.dart (timing)
```

Also run each file alone — should pass:

```bash
fvm flutter test test/view/review/review_screen_test.dart 2>&1 | tail -5
# Should pass 30/30 or similar in isolation
```

**After fix:** Same parallel run must be green, and isolated runs remain green. The proof is that the same test that flaked under `concurrency 4` now passes there — the condition poll, not the wall clock, decides completion.

Include this comparison in the PR description (before/after `concurrency 4` snippet).

### 4.3 Implement the fix — GREEN

Edit only `test/view/review/review_screen_test.dart`, `test/view/review/scope_split_drawers_test.dart` (and new `test/view/review/test_helpers.dart` if extracted).

### 4.4 Verify

```bash
fvm flutter test test/view/review/review_screen_test.dart
fvm flutter test test/view/review/scope_split_drawers_test.dart
fvm flutter analyze

git add test/view/review/review_screen_test.dart test/view/review/scope_split_drawers_test.dart test/view/review/test_helpers.dart
git commit -m "test(review): replace fixed 80ms pumpAsync with pumpUntil condition polling"
./scripts/gates.sh t1
```

Gates read committed diff — run after committing. Expect G08 to stay green (no skips/ignores/xfails) and G10 to stay green (ratchets are not touched). The fix must not weaken assertions — it makes the existing assertions deterministic, which is what `polish-tasks.md` Task 6 asks for.

### 4.5 Push & PR

```bash
git push -u origin fix/test-fix-19-pumpasync-flake
gh pr create -R cassandre60/ChessSRS --title "test(review): replace fixed 80ms pumpAsync with pumpUntil condition polling" --body "Closes TEST-FIX-19. See docs/tasks/TEST-FIX-19-pumpAsync-flake.md."
```

## 5. Done when

* [ ] `pumpUntil` helper exists and the 80ms "wait for DB reload" waits are replaced by condition polls (widget finder or provider `hasValue`)
* [ ] Fixed-duration 700ms/600ms animation sleeps are untouched (they are not the flake)
* [ ] `fvm flutter test test/view/review/` passes at `--concurrency 4` (flake gone) and in isolation
* [ ] `fvm flutter analyze` 0 issues
* [ ] `./scripts/gates.sh t1` green on committed branch (no test weakening)
* [ ] PR open against `cassandre60/ChessSRS`
