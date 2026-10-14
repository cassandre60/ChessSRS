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
| Android | `chesssrs-<tag>-android.apk` / `.aab` | Yes. Signed with permanent developer release keystore from GitHub Secrets. |

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

## Local release builds

Never run on a dev machine (`flutter build appbundle/apk --release` OOMs,
and Gradle cannot run on new JDKs — see AGENTS.md §4). Release proof lives
in CI only.
