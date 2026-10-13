# SYSTEM-FIX-35 — Linux sound player unhandled Process.start leaks pipes and zombie processes

> **For a dumb agent**: follow this file top-to-bottom. Do exactly what it says,
> nothing more. Each section tells you where to look, what to change, and how to
> prove it — no guessing.

## 1. What is broken

In `lib/src/model/common/service/sound_service.dart:92-105`:

The Linux sound playback implementation calls:
```dart
if (_playerCmd == 'pw-play') {
  Process.start('pw-play', ['--volume=$vol', filePath]);
} else if (_playerCmd == 'paplay') {
  Process.start('paplay', ['--volume=${(volume * 65536).round()}', filePath]);
} else {
  Process.start(_playerCmd!, [filePath]);
}
```

Three critical issues:
1. `Process.start` returns `Future<Process>` which is **unhandled and unawaited**.
2. Child process OS pipes (`stdin`, `stdout`, `stderr`) are never drained or closed, leaving
   zombie processes in the Linux process table until the app exits.
3. If the audio executable fails or cannot be found, `Process.start` throws an unhandled
   asynchronous exception that escapes into the zone.

## 2. Files to read before touching anything

1. `lib/src/model/common/service/sound_service.dart:70-120` — `_LinuxSoundPlayer` implementation
2. `dart:io` documentation on `Process.run` vs `Process.start`

## 3. The fix

Replace `Process.start` with `Process.run`, wrapped in `unawaited(...)` and guarded with
`catchError`:

```dart
final args = _playerCmd == 'pw-play'
    ? ['--volume=$vol', filePath]
    : _playerCmd == 'paplay'
        ? ['--volume=${(volume * 65536).round()}', filePath]
        : [filePath];

unawaited(
  Process.run(_playerCmd!, args).then((_) {}, onError: (_) {
    // Fail-soft: audio glitch should never crash the application
  }),
);
```

`Process.run` automatically drains and closes `stdout`/`stderr`/`stdin` and waits for
the process to terminate, preventing zombie processes.

### What NOT to change

* Do not change audio player detection logic (`which` checks in `_init`).
* Do not change volume calculation math.
* Do not touch `SPEC.md`, `GATES.md`, `.gates/`, `pubspec.yaml`.

## 4. Verification

```bash
git worktree add ../chesssrs-system-fix-35 -b fix/system-fix-35-linux-sound-leak origin/main
cd ../chesssrs-system-fix-35
fvm flutter pub get && fvm dart run build_runner build --delete-conflicting-outputs
fvm flutter analyze

git add lib/src/model/common/service/sound_service.dart
git commit -m "fix(sound): use Process.run in Linux sound player to avoid pipe leaks and zombies"
./scripts/gates.sh t1
git push -u origin fix/system-fix-35-linux-sound-leak
gh pr create -R cassandre60/ChessSRS --title "fix(sound): prevent process and pipe leak in Linux sound player" --body "Closes SYSTEM-FIX-35."
```

## 5. Done when

* [ ] `_LinuxSoundPlayer` uses `Process.run` instead of `Process.start`
* [ ] Async errors are handled fail-soft without leaking
* [ ] `fvm flutter analyze` 0 issues
* [ ] `./scripts/gates.sh t1` green
* [ ] PR open against `cassandre60/ChessSRS`
