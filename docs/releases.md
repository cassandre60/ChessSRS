# Releases

Authority: publishing mechanics, artifact support, version stamping and proof
workflows. AGENTS §11 owns the decision to release; TEST_STRATEGY owns the
local-machine budget. See docs/documentation-map.md.

Cutting a release is pushing a tag. Everything else is automatic
(`.github/workflows/release.yml`).

```bash
git tag vX.Y.Z
git push origin vX.Y.Z
```

A tag on `main` builds every artifact and publishes a (pre-)release with
generated notes. Manual dispatch (Actions tab → Release → Run workflow)
builds the same artifacts without publishing, for proof. `main` only merges
green PRs, so a tag is already tested — the release workflow ships, it does
not re-test. `AGENTS.md` §11 is the policy for *whether* to cut one.

## What ships per tag

| Platform | Artifact | Shippable? |
|---|---|---|
| Linux AppImage | `chesssrs-<tag>-x86_64.AppImage` | Yes. Single-click portable executable for all distributions. |
| Linux .deb | `chesssrs_<tag>_amd64.deb` | Yes. Native graphical package for Debian/Ubuntu/Mint. |
| Linux Tarball | `chesssrs-<tag>-linux-x64.tar.gz` | Yes. Portable unpack-and-run archive. |
| Android | `chesssrs-<tag>-android.apk` / `.aab` | Shippable only when the permanent release key is configured. release.yml falls back to a throwaway key if its secret is absent; verify signing evidence before calling an artifact shippable. |
| Checksums | `SHA256SUMS.txt` | Yes. Cryptographic verification for all assets. |

## Not shipped (and why)

- **Play Store**: AAB is generated and signed with the developer key; direct store upload is done via Google Play Console.
- **iOS**: no signing certificates and no Apple Developer account. Needs both
  plus a macOS-runner job, when there is a device to put it on.
- **Web**: the sqflite store and the native Stockfish engine have no web
  builds. Needs a research spike and replacements first.
- **Windows/macOS**: no platform directories exist (upstream never had them).

## Pipeline dry-run (no tag, no publish)

Validate the release pipeline without creating a tag or publishing: run the
workflow by hand from the Actions tab (**Actions → Release → Run workflow**)
or:

```bash
gh workflow run release.yml -R cassandre60/ChessSRS
```

This builds the Linux and Android jobs exactly as a real release would. The
publish job is gated on the run being a tag push (`refs/tags/v…`), so a manual
run stops after building — you download the artifacts from that run. The
artifacts are stamped with the version in `pubspec.yaml`, since there is no tag
to take one from.

## Throwaway Android release proof

`Release proof` (`.github/workflows/release-proof.yml`) is a **separate existing
workflow**. It always generates a temporary signing key and produces AAB/APK
for testing only, never a publishable/update-compatible release. It runs on
manual dispatch or a PR editing that workflow, not on general product PRs.
Do not confuse it with Release's manual dry-run, which builds all release
platforms and uses the permanent key when configured.

```bash
gh workflow run release-proof.yml -R cassandre60/ChessSRS
```

## The tag is the only version ledger

Each build is stamped with `--build-name`/`--build-number`, so the version the
owner sees is derived from the tag, not from `pubspec.yaml`:

| Where | What carries the version |
|---|---|
| About screen, account menu (Linux) | `data/flutter_assets/version.json`, generated from `--build-name` |
| Android | `versionName`/`versionCode`, generated from `--build-name`/`--build-number` |

Both build jobs assert that their own artifact reports the expected version, so
a stamping regression fails the release instead of shipping. `versionCode`
comes from the workflow run number, which rises on every run — Play Store
uploads require a strictly increasing `versionCode`.

The logic lives in `.github/scripts/` and is covered by
`release-version-test.sh`, which the `Tests` job runs on every PR.

`pubspec.yaml` therefore holds the **development** version and is deliberately
*not* bumped per release.

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

Follow TEST_STRATEGY §2: all release builds/proof run on GitHub runners, not
the developer's machine. The historical local OOM/JDK incident is archived in
docs/agent-history.md, not a second budget definition here.
