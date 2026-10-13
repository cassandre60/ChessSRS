# DOMAIN-FIX-36 — Division-by-zero in lapse contagion and unrecoverable stability collapse

> **For a dumb agent**: follow this file top-to-bottom. Do exactly what it says,
> nothing more. Each section tells you where to look, what to change, and how to
> prove it — no guessing.

## 1. What is broken

In `lib/src/domain/graph_aware_review_coordinator.dart:227-232` and `lib/src/domain/chess_fsrs_scheduler.dart:166,239`:

### 1a. Division-by-zero / NaN in lapse contagion
In `_propagateLapseContagion`:
```dart
final decay = params.contagionBase * math.exp(-(depth - 1) / params.contagionTau);
```
If `contagionTau <= 0` (e.g. invalid parameter configuration), at `depth = 1`:
`-(1 - 1) / 0 = 0 / 0 = NaN`.
`math.exp(NaN)` produces `NaN`. Then in `_pullDueForward`:
```dart
final newRemainingMs = (remaining.inMilliseconds * (1 - decay)).round();
```
Calling `(NaN).round()` throws `UnsupportedError: NaN` when converting to integer, crashing the review session!

### 1b. Near-zero stability collapse in FSRS
In `_propagateLapseContagion`:
```dart
final shrunkStability = childState.stability * (1 - decay).clamp(0.0, 1.0);
```
Repeated stability haircuts can shrink `stability` to sub-millisecond positive values (e.g. `0.0001` ms).
In `ChessFsrsScheduler`:
```dart
final prevStabilityDays = previous.stability <= 0
    ? params.minStabilityDays
    : previous.stability / _dayMs;
```
Because `previous.stability > 0`, it is **not** floored to `minStabilityDays` (0.02 days).
In `fsrsNextStabilityLapse`:
```dart
final safeS = s <= 0 ? p.minStabilityDays : s;
```
Because `safeS` is only floored when `<= 0`, an item with near-zero stability evaluates
`(1e-12 + 1)^w13 - 1 ≈ w13 * 1e-12`, trapping the item's stability in an unrecoverable near-zero cycle
where future review gains scale off `1e-12`.

## 2. Files to read before touching anything

1. `lib/src/domain/graph_aware_review_coordinator.dart:50-85, 220-270`
2. `lib/src/domain/chess_fsrs_scheduler.dart:150-190, 230-250`
3. `test/domain/chess_fsrs_scheduler_test.dart` and `test/review/`

## 3. The fix

### 3a. Guard contagion decay math
In `GraphAwareParams`:
Add constructor asserts:
```dart
assert(contagionTau > 0, 'contagionTau must be positive');
assert(contagionBase >= 0, 'contagionBase must be non-negative');
```
In `_propagateLapseContagion`:
```dart
final rawDecay = params.contagionTau > 0
    ? params.contagionBase * math.exp(-(depth - 1) / params.contagionTau)
    : 0.0;
final decay = rawDecay.isFinite ? rawDecay.clamp(0.0, 1.0) : 0.0;
```

### 3b. Floor stability against collapse
In `_propagateLapseContagion`:
```dart
final minStabilityMs = 60000.0; // 1 minute floor
final shrunkStability = math.max(
  childState.stability * (1 - decay).clamp(0.0, 1.0),
  minStabilityMs,
);
```

In `ChessFsrsScheduler.schedule`:
```dart
final prevStabilityDays = math.max(
  previous.stability / _dayMs,
  params.minStabilityDays,
);
```
In `fsrsNextStabilityLapse`:
```dart
final safeS = math.max(s, p.minStabilityDays);
```

### What NOT to change

* Do not change FSRS weight parameters ($w_0$ through $w_{16}$).
* Do not change formula exponents.
* Do not touch `SPEC.md`, `GATES.md`, `.gates/`, `pubspec.yaml`.

## 4. Verification

```bash
git worktree add ../chesssrs-domain-fix-36 -b fix/domain-fix-36-stability-guards origin/main
cd ../chesssrs-domain-fix-36
fvm flutter pub get && fvm dart run build_runner build --delete-conflicting-outputs
fvm flutter test test/domain/chess_fsrs_scheduler_test.dart
fvm flutter analyze

git add lib/src/domain/graph_aware_review_coordinator.dart lib/src/domain/chess_fsrs_scheduler.dart
git commit -m "fix(domain): guard against NaN decay and floor FSRS stability to prevent collapse"
./scripts/gates.sh t1
git push -u origin fix/domain-fix-36-stability-guards
gh pr create -R cassandre60/ChessSRS --title "fix(domain): guard against NaN decay and stability collapse" --body "Closes DOMAIN-FIX-36."
```

## 5. Done when

* [ ] `contagionTau <= 0` cannot produce `NaN` or crash `.round()`
* [ ] FSRS stability does not collapse into unrecoverable sub-millisecond cycles
* [ ] Existing scheduler and review coordinator tests pass
* [ ] `fvm flutter analyze` 0 issues
* [ ] `./scripts/gates.sh t1` green
* [ ] PR open against `cassandre60/ChessSRS`
