### Test gap: surviving mutant in `lib/src/domain/review/review_session.dart:616`

#### Mutation

Swap logical AND (&&) to OR (||)

```diff
--- lib/src/domain/review/review_session.dart (line 616)
+++ mutated
-   bool get isComplete => _currentPrompt == null && _dueQueue.isEmpty && _unbufferedQueue.isEmpty;
+   bool get isComplete => _currentPrompt == null && _dueQueue.isEmpty || _unbufferedQueue.isEmpty;
```

The targeted test command passed with this mutant applied:

```bash
fvm flutter test test/review/review_session_test.dart --concurrency=1
```

#### Required proof (fail-to-pass)

1. Triage first: confirm this is not an equivalent mutant, string/comment
   noise, or a regex false positive. Close the issue if it is.
2. Add a test that is **red with this mutant applied** and **green on clean
   source**. The test does not need to be red on `origin/main` — the defect
   here is the mutant, not a bug in the repository.
3. Run the targeted test once with the mutant and once without it; paste both
   results into the PR body.
4. Keep the PR to the source-adjacent test file plus any fixture it needs.
