# Releases

Cutting a release is pushing a tag. Everything else is automatic
(`.github/workflows/release.yml`).

```bash
git tag v0.1.0 && git push origin v0.1.0
```

A tag on `main` builds every artifact and publishes a (pre-)release with
generated notes. Manual dispatch (Actions tab → Release → Run workflow)
builds the same artifacts without publishing, for proof. `main` only merges
green PRs, so a tag is already tested — the release workflow ships, it does
not re-test.

## What ships per tag

| Platform | Artifact | Shippable? |
|---|---|---|
| Linux AppImage | `chesssrs-<tag>-x86_64.AppImage` | Yes. Single-click portable executable for all distributions. |
| Linux .deb | `chesssrs_<tag>_amd64.deb` | Yes. Native graphical package for Debian/Ubuntu/Mint. |
| Linux Tarball | `chesssrs-<tag>-linux-x64.tar.gz` | Yes. Portable unpack-and-run archive. |
| Android | `chesssrs-<tag>-android.apk` / `.aab` | Yes. Signed with permanent developer release keystore from GitHub Secrets. |
| Checksums | `SHA256SUMS.txt` | Yes. Cryptographic verification for all assets. |

## Not shipped (and why)

- **Play Store**: AAB is generated and signed with the developer key; direct store upload is done via Google Play Console.
- **iOS**: no signing certificates and no Apple Developer account. Needs both
  plus a macOS-runner job, when there is a device to put it on.
- **Web**: the sqflite store and the native Stockfish engine have no web
  builds. Needs a research spike and replacements first.
- **Windows/macOS**: no platform directories exist (upstream never had them).

## Pipeline dry-run (no tag, no publish)

Validate the entire release pipeline locally without creating a tag or
publishing:

```bash
gh workflow run Release -f dry_run=true
```

This runs the Linux and Android build jobs exactly as a real release would,
but skips artifact upload and the `gh release create` step. Use it to
verify that the pipeline passes before cutting a real tag.

## Nightly proof builds

`.github/workflows/nightly.yml` runs at 03:17 UTC and builds the artifacts
from `main` **without publishing anything** — the files hang off the Release
run it dispatches. It exists so there is always something fresh to install
without cutting a tag for it.

It is not a release, and it is not "build every night". It skips, and says so
in the run summary, when:

| Skip | Why |
|---|---|
| `main` has not moved since the newest tag | There is nothing new to build. |
| Nothing shipped changed since that tag | `lib/`, `assets/`, `android/`, `linux/`, `pubspec.yaml`/`pubspec.lock` are unchanged, so the build would be identical to the last one. Test, gate and docs commits change none of them. |
| This exact commit was already built, or is building | The scheduled run and a manual one can land on the same commit. A build that **failed** or was cancelled is retried. |

This repository merges test, gate and documentation work far more often than
it merges changes to the app — 17 merges after v1.6.2 contained no shipped
change at all — so an unconditional nightly would spend most of its builds
reproducing the last tag.

The decision lives in `.github/scripts/nightly-decide.sh` and is tested by
`nightly-decide-test.sh` on every PR. Dispatch it by hand from the Actions tab
(**Actions → Nightly proof build → Run workflow**); it applies the same rules.

Whether to cut an actual **release** is a separate decision, made by the agent
under AGENTS.md §11.

## Local release builds

Never run on a dev machine (`flutter build appbundle/apk --release` OOMs,
and Gradle cannot run on new JDKs — see AGENTS.md §4). Release proof lives
in CI only.
