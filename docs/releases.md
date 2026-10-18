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
not re-test. `AGENTS.md` §11 is the policy for *whether* to cut one.

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

Validate the release pipeline without creating a tag or publishing: run the
workflow by hand from the Actions tab (**Actions → Release → Run workflow**)
or:

```bash
gh workflow run Release
```

This builds the Linux and Android jobs exactly as a real release would. The
publish job is gated on the run being a tag push (`refs/tags/v…`), so a manual
run stops after building — you download the artifacts from that run. The
artifacts are stamped with the version in `pubspec.yaml`, since there is no tag
to take one from.

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

## Local release builds

Never run on a dev machine (`flutter build appbundle/apk --release` OOMs,
and Gradle cannot run on new JDKs — see AGENTS.md §4). Release proof lives
in CI only.
