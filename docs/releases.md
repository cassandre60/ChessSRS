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
| Linux x64 | `chesssrs-<tag>-linux-x64.tar.gz` | Yes. Needs system GTK/SQLite libs (standard Flutter Linux prerequisites). |
| Android | `chesssrs-<tag>-android-testing.apk` / `.aab` | Testing only: throwaway-signed. Installs and runs; cannot update to/from a store build. |

## Not shipped (and why)

- **Play Store**: needs the permanent upload keystore, which lives with the
  owner and must never enter this repo. When it exists: add keystore +
  `key.properties` as action secrets and extend the Android job to use them.
- **iOS**: no signing certificates and no Apple Developer account. Needs both
  plus a macOS-runner job, when there is a device to put it on.
- **Web**: the sqflite store and the native Stockfish engine have no web
  builds. Needs a research spike and replacements first.
- **Windows/macOS**: no platform directories exist (upstream never had them).

## Local release builds

Never run on a dev machine (`flutter build appbundle/apk --release` OOMs,
and Gradle cannot run on new JDKs — see AGENTS.md §4). Release proof lives
in CI only.
