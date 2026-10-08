# Dependency & upgrade audit

Snapshot: branch `arena/b5e4f680-chesssrs` @ `67773588d`, 2026-10-08. Read-only: **no manifest, lockfile
or source file was modified by this audit.**

---

## 0. Method, and what these numbers are worth

`flutter pub outdated` is the right tool for this and **it could not be run here**: this environment has no
Dart/Flutter SDK, and `pub.dev` (plus `raw.githubusercontent.com`) is unreachable from it. Everything below
was reconstructed from what *is* reachable — `api.github.com`, `github.com` over git, and
`registry.npmjs.org`.

| Question | How it was answered | Confidence |
|---|---|---|
| Current version | `pubspec.lock` (exact, sha256-pinned) | **high** |
| Latest version | source repo: max *stable* of CHANGELOG.md headings and git tags (`git ls-remote`), each repo verified by re-fetching `<path>/pubspec.yaml` and checking `name:` equals the package | **high** where upstream keeps a CHANGELOG or tags releases (the large majority); **unknown** for 2 (§3.3) |
| Vulnerabilities | GitHub Advisory Database, `ecosystem=pub`, queried for all **217** non-SDK locked packages; `npm audit --package-lock-only` for the two npm projects | **high** for pub coverage found, but see caveat below |
| Maintenance | date of the last commit that touched the package's own directory, plus repo `archived` flag | high |
| Licence | `GET /repos/{o}/{r}/license` — the *repo* licence, not the published package's declared licence | medium (proxy) |
| Breaking changes | CHANGELOG text between the current and latest version, then `rg` against `lib/` and `test/` | high for API *names*, cannot see behaviour |

Two honest caveats:

- **The `pub` ecosystem has thin advisory coverage.** A pub.dev-flavoured OSV feed was not reachable; the
  GitHub Advisory DB returned 4 pub rows for our 217 packages (vs. what npm audit finds in 190 npm
  packages). "No known vulnerabilities" here means *none in the GitHub Advisory DB*, not "none exist".
- **`latest` is a source-repo reading, not a pub.dev reading.** Where upstream bumps `version:` in
  `pubspec.yaml` ahead of the release (dart-lang does this with `-wip` suffixes), those prereleases are
  excluded. Where a repo stops tagging (wakelock_plus), the HEAD pubspec is used and flagged.

---

## 1. Inventory

### 1.1 Manifests found

| Manifest | Purpose | Locked? |
|---|---|---|
| `pubspec.yaml` | the app: 65 direct main, 9 direct dev, 3 dependency overrides | `pubspec.lock` (222 packages) |
| `scripts/package.json` | dev tooling for `gen-arb.mjs` (l10n ARB generation) | `scripts/package-lock.json` (20) |
| `scripts/firebase/package.json` | Firebase Cloud Messaging demo script | `scripts/firebase/package-lock.json` (190) |
| `.fvmrc` | Flutter SDK pin | — (pin: `3.47.3`) |

No `requirements*.txt`, `pyproject.toml`, `Cargo.toml` or Dockerfile exists in the tree.

### 1.2 Composition of `pubspec.lock`

| | count |
|---|---|
| Direct main | 65 |
| Direct dev | 9 |
| Direct overridden | 3 (`multistockfish_chess`, `_light`, `_variant`) |
| Transitive | 145 |
| **Total** | **222** |
| — hosted on pub.dev | 212 |
| — git dependencies | 5 (see §4) |
| — from the Flutter SDK | 5 (`flutter`, `flutter_localizations`, `flutter_test`, `flutter_web_plugins`, `sky_engine`) |

### 1.3 Toolchain and CI pins

| Pin | Where | Current | Latest available | Gap |
|---|---|---|---|---|
| Flutter SDK | `pubspec.yaml` (`flutter: 3.47.3`), `.fvmrc`, CI reads pubspec | 3.47.3 | **3.47.6** | 3 patches |
| Dart SDK constraint | `pubspec.yaml` | `^3.12.2` | lock resolves `>=3.13.0 <4.0.0` | see §5.1 |
| Gradle | `android/gradle/wrapper/gradle-wrapper.properties` | 9.5.1 | **9.8.1** | 3 minors |
| Kotlin (AGP plugin) | `android/settings.gradle.kts` | 2.4.10 | **2.4.21** | 3 patches |
| Android Gradle Plugin | `android/settings.gradle.kts` | 9.2.0 | not verifiable (Google Maven unreachable) | — |
| iOS deployment target | `project.pbxproj` | 15.0 / 15.6 | — | — |
| Java (CI) | `release.yml`, `release-proof.yml` | Temurin 17 | — | — |
| `actions/checkout` | all workflows | v7.0.1 | v7.0.1 | up to date |
| `subosito/flutter-action` | test/release | v2.23.0 | v2.23.0 | up to date |
| `actions/setup-java` | release, release-proof | v5.0.0 | **v6.0.1** | major |
| `actions/upload-artifact` | release (×3), release-proof (×2) | v6.0.0 | **v7.0.2** | major |
| `actions/download-artifact` | release | v6.0.0 | **v8.0.2** | two majors |

---

## 2. Vulnerabilities

### 2.1 Dart / pub — nothing affects the locked versions

217 non-SDK packages queried. 4 advisory rows matched 3 of our packages; in every case the locked version is
outside the vulnerable range:

| Package | Locked | Advisory | Severity | Vulnerable range | Verdict |
|---|---|---|---|---|---|
| `archive` (transitive) | 4.2.0 | CVE-2023-39139 path traversal | high | `<= 3.3.7` | not affected (fixed in 3.3.8) |
| `archive` (transitive) | 4.2.0 | CVE-2023-39137 filename spoofing | high | `<= 3.3.7` | not affected |
| `http` (direct) | 1.6.0 | CVE-2020-35669 header injection | medium | `< 0.13.3` | not affected |
| `shared_preferences_android` (transitive) | 2.4.28 | GHSA-3hpf-ff72-j67p | low | `= 2.3.3` | not affected |

**Result: 0 packages require a security-driven upgrade.** Caveat from §0: this is the GitHub Advisory DB,
which has sparse pub coverage; an OSV feed would be a worthwhile second opinion on a machine that can reach
one.

### 2.2 npm — 5 findings, 2 of them high

`npm audit --package-lock-only` (no install, no file writes):

| Project | Package | Locked | Severity | Issue | Fix |
|---|---|---|---|---|---|
| `scripts/` | `js-yaml` | 4.3.1 | **high** | `maxTotalMergeKeys` does not limit CPU for empty merge sources (DoS) | **4.3.2** (patch) or 5.4.3 (major) |
| `scripts/` | `xml2js` | 0.4.23 | moderate | prototype pollution | **0.6.2** (major) |
| `scripts/firebase/` | `@fastify/busboy` (transitive) | 3.2.0 | **high** | DoS via oversized multipart boundary / prototype-named part header; CRLF injection via `Content-Disposition` | 3.2.2 |
| `scripts/firebase/` | `gaxios` (transitive) | 6.7.1 | moderate | via `uuid` | 8.2.0 |
| `scripts/firebase/` | `uuid` (transitive) | 9.0.1 | moderate | missing buffer bounds check in v3/v5/v6 when `buf` is provided | 14.0.2 |

Context for prioritising these: `scripts/` is dev tooling — the only npm code that actually runs is
`scripts/gen-arb.mjs`, which imports `colors` and `parseStringPromise` from `xml2js`. `scripts/firebase/` is
a self-described *demonstration* script for sending a remote message (`npm run send-message`), and
`firebase-admin` pulls in the whole `@google-cloud` tree. None of this ships in the app. The js-yaml and
@fastify/busboy highs are therefore **real but low-blast-radius** — fix them, but ahead of any app-side work
only because they are cheap, not because they are urgent.

---

## 3. Upgrade surface — Dart

### 3.1 Behind, with an upgrade available (16 hosted packages)

| Package | Current | Latest | Type | Vulns | Risk | Notes |
|---|---|---|---|---|---|---|
| `fast_immutable_collections` | 11.2.0 | 12.0.0 | **major** | none | **moderate** | Breaking: `IList`/`ISet`/`IMap` built with `isDeepEquals: false` now compare by identity. `rg isDeepEquals` over `lib/` + `test/` → **0 hits**, so the changed behaviour is unused; the default (`isDeepEquals: true`) is unaffected. Still: 80 files import the package, 291 `IList`/`ISet`/`IMap` tokens — needs a full `flutter test`, not a spot check |
| `material_ui` | 1.2.0 | 1.6.0 | minor (×4) | none | **moderate** | 129 files import it. Contents are fixes plus additions: Slider/RangeSlider floating-point rounding, DropdownButtonFormField underline alignment, `NavigationIndicator` repaint, `AboutDialog` no longer imports `dart:io` unconditionally (web becomes usable), new `fontFeatures`/`fontVariations` on `TextTheme.apply()`, Material 3 Expressive `IconButton`. No removals — but it is *the* visual surface, so review on a device |
| `cronet_http` | 1.9.0 | 1.10.0 | minor | none | **safe** | Adds optional DNS options to `CronetEngine.build` (`useBuiltInDnsResolver`, `enableStaleDns`, `persistHostCache`, …). The single call site (`lib/src/network/http.dart:164`) passes `cacheMode`, `cacheMaxSize`, `userAgent`, `enableHttp2` — all unchanged. Also bumps `jnigen` to 1.0.0 |
| `device_info_plus` | 13.2.0 | 13.3.0 | minor | none | **safe** | Kotlin Gradle Plugin fix, new iPhone 18 identifiers, Android build timestamp. 5 files |
| `app_links` | 7.2.1 | 7.2.2 | patch | none | **safe**, behaviour fix | Fixes change link *delivery*: all links received before the first `listen` are now sent, not just the first; iOS/macOS give each engine its own stream. 1 file touches it |
| `connectivity_plus` | 7.3.1 | 7.3.2 | patch | none | **safe** | Releases iOS multi-engine callbacks |
| `cupertino_ui` | 1.1.1 | 1.1.2 | patch | none | **safe** | Magnifier focal point, `showCupertinoSheet` now forwards `showDragHandle`. 8 files |
| `image_picker` | 1.2.3 | 1.2.4 | patch | none | **safe** | Docs + minimum SDK bump to Flutter 3.41. **0 imports** (§6) |
| `material_color_utilities` | 0.13.0 | 0.13.1 | patch | none | **safe** | 2 files |
| `package_info_plus` | 10.2.1 | 10.2.2 | patch | none | **safe** | Kotlin Gradle Plugin fix |
| `share_plus` | 13.3.0 | 13.3.1 | patch | none | **safe** | iPad popover fix; **removes the deprecated `UIApplication.keyWindow` fallback on iOS** — verify share still works on iOS 13+ |
| `shared_preferences` | 2.5.5 | 2.5.6 | patch | none | **safe** | Docs + minimum SDK bump. 2 files |
| `url_launcher` | 6.3.2 | 6.3.3 | patch | none | **safe** | `supportsCloseForLaunchMode` was reporting launch support instead of close support. 13 files |
| `wakelock_plus` | 1.8.0 | 1.8.1 | patch | none | **safe** | Linux `dbus` → `^0.8.0`. Latest read from HEAD pubspec: this repo's tags stop at 1.2.x |
| `freezed` (dev) | 4.0.1 | 4.0.2 | patch | none | **safe** | Codegen fixes (primary-constructor `copyWith`, deep copies); now requires Analyzer 14. Only affects generated output |
| `build_runner` (dev) | 2.16.1 | 2.16.2 | patch | none | **safe** | Allows `built_collection` 6.x |

### 3.2 Up to date (no action)

`async` `collection` `crypto` `logging` `path` (now `dart-lang/core`) · `intl` (`dart-lang/i18n`) · `meta`
(`dart-lang/sdk`) · `http` `cupertino_http` `web_socket_channel` (`dart-lang/http`) · `clock` `fake_async`
`stream_channel` `stream_transform` `pub_semver` (`dart-lang/tools`) · `json_annotation`
`json_serializable` · `freezed_annotation` · `flutter_riverpod` · `chessground` · `dartchess` ·
`sound_effect` · `sqflite` `sqflite_common_ffi` · `lint` · `mocktail` · `fl_chart` · `flutter_slidable` ·
`flutter_spinkit` · `flutter_secure_storage` · `flutter_native_splash` · `flutter_layout_grid` ·
`flutter_displaymode` · `flutter_appauth` · `flutter_markdown_plus` · `dynamic_system_colors` ·
`deep_pick` · `popover` · `result_extensions` · `signal_strength_indicator` · `qr_flutter` ·
`auto_size_text` · `visibility_detector` · `uuid` · `material_symbols_icons` ·
`quick_actions` · `path_provider` · `app_settings` · `file_picker` ·
`wakelock_plus_platform_interface` · `l10n_esperanto`†† · `flutter_svg`† · `cupertino_icons`†

† latest not established — see §3.3.
†† `l10n_esperanto` keeps no CHANGELOG and no tags; "up to date" here rests on its `pubspec.yaml` at HEAD
reading `3.0.0`, which matches the lock. A tag-less repo, so treat it as unverified rather than confirmed.

Several of these have unreleased work visible at HEAD (`async` 2.14.0-wip, `collection` 1.20.0-wip,
`crypto` 3.0.8-wip, `logging` 1.3.1-wip, `path` 1.9.2-wip, `http` 1.7.0-wip, `json_serializable` 6.15.0-wip,
`pub_semver` 2.2.2-wip, `stream_channel` 2.1.5-wip, `web_socket_channel` 3.0.4-wip, `build_runner`
2.16.3-wip). Being on the last *released* version is correct; nothing to do.

### 3.3 Two packages whose latest version could not be established

| Package | Locked | What was found | Why it matters |
|---|---|---|---|
| `flutter_svg` | 2.3.0 | The only public repo for it (`dnfield/flutter_svg`) has master at **2.0.10+1** and was last pushed **2024-11-01**. No reachable repo accounts for 2.3.0 | Probably just my reachability limits — but I could not verify 2.3.0's provenance or what changed since 2.0.x. Worth one `flutter pub outdated` on a networked machine. 1 file imports it |
| `cupertino_icons` | 1.0.9 | No reachable repo publishes it (the 2018-era `devoncarew/cupertino_icons` is at 0.1.1) | Same caveat; **and it is unused** (§6), so the cheapest resolution is deletion |

Neither is a security finding. Both are gaps in this audit, not evidence of a problem.

---

## 4. Git dependencies — both pins are behind

These are pinned to commits, so there is no "latest version" — what matters is how far the pin sits behind
the default branch.

| Package | Pinned | Pinned date | Branch head | Behind | What moved since |
|---|---|---|---|---|---|
| `multistockfish` (+ `_chess`, `_light`, `_variant`, all one ref) | `896c3884` | 2026-09-09 | `fd8dcea4` | **4 commits** | **Merge PR #16: Stockfish 19**, remove commented code, update description, bump version (0.6.0 → 0.6.1) |
| `lc0` | `04284fa8` | 2026-09-07 | `a8410e96` | **3 commits** | **Merge PR #2: private I/O and handle API**, readme tweak, rename folder to `tool` |

The second one deserves attention: `pubspec.yaml` pins lc0 to a git ref with the comment *"the branch that
gave lc0 private I/O and a handle API is not merged nor published yet"*. That branch **has since been
merged** — the pin predates the merge by 3 commits. Whoever owns `engine_refactor.md §13` should look at
whether the pin can now move (or, better, return to a published version).

Bumping the multistockfish pin pulls in **Stockfish 19** — a new engine, i.e. new native binaries and
possibly new evaluation behaviour. That is a product decision, not a dependency bump.

---

## 5. Maintenance status

No dependency is archived. Five have had no commit touching the package in over two years:

| Package | Last commit to the package | Note |
|---|---|---|
| `cupertino_icons` | 2018-01-05 (repo, not the real upstream — §3.3) | unused; delete rather than track |
| `auto_size_text` | 2023-06-30 | current version is the latest |
| `flutter_svg` | 2024-02-20 | latest unverifiable (§3.3) |
| `qr_flutter` | 2024-05-16 | current is latest; unused (§6) |
| `deep_pick` | 2024-08-30 | current is latest; 3 files |

Everything else has moved in the last 12 months, most within the last 6 weeks.

### 5.1 One configuration smell

`pubspec.yaml` declares `sdk: ^3.12.2`, but the resolved tree requires `dart: ">=3.13.0 <4.0.0"` (the lock's
`sdks:` block says so). Someone on Dart 3.12.x would get a resolution failure the pubspec did not warn them
about. Tightening the constraint to `^3.13.0` would make the declaration honest — a one-line change, but it
raises the floor for contributors, so it is your call, not mine.

Also note `flutter: 3.47.3` is an **exact** pin, not a caret. Every Flutter patch bump therefore needs edits
in two places (`pubspec.yaml` + `.fvmrc`) before CI sees it, which is why the branch is 3 patches behind
(3.47.6 exists) despite the comment right above it saying it should track every stable release.

---

## 6. Direct dependencies with no references anywhere

`rg` over `lib/` and `test/` for `package:<name>` returned **zero** hits for 7 declared direct dependencies
(each then re-checked with a plain case-insensitive search for the name — still zero):

`app_settings` · `cupertino_icons` · `flutter_layout_grid` · `flutter_markdown_plus` · `image_picker` ·
`qr_flutter` · `stream_transform`

Three more "unused" hits are false positives of this method and were excluded: `build_runner` and
`json_serializable` are invoked by `dart run build_runner build`, and `lint` is consumed by
`analysis_options.yaml`, not by an import.

Removing a dependency changes `pubspec.lock` and the `direct_dependencies` ratchet in `scripts/gates.sh`, and
two of these (`cupertino_icons`, `qr_flutter`) are the ones whose provenance I could not verify — so if you
want them gone, do it as its own change with a build. Same story in `scripts/package.json`, where
`@octokit/request`, `js-yaml` and `node-fetch` are declared but never imported (only `colors` and `xml2js`
are used, by `gen-arb.mjs`).

---

## 7. Licences

Project licence: **GPL-3.0**. Across the resolved direct dependencies:

| Licence | Packages |
|---|---|
| BSD-3-Clause | 34 |
| MIT | 17 |
| GPL-3.0 | 8 — all Lichess: `chessground`, `dartchess`, `lc0`, `multistockfish{,_chess,_light,_variant}`, `sound_effect` |
| Apache-2.0 | 6 |
| BSD-2-Clause | 3 |
| not determined | 6 (`fake_async`, `flutter_appauth`, `freezed`, `freezed_annotation`, `path`, `result_extensions` — monorepo subdirectories where the repo-licence endpoint returned nothing) |

**No incompatible licence and no drift found.** Permissive deps (BSD/MIT/Apache-2.0) are fine inside a
GPL-3.0 project; the Lichess packages are GPL-3.0 like the project itself. Nothing is GPL-2.0-only (which
would *not* combine with GPL-3.0), nothing AGPL, nothing non-commercial.

Two limits: this is the *repository* licence, not the licence string in the published package (pub.dev would
be authoritative), and "not determined" means the API gave nothing — not that the licence is missing.

---

## 8. Prioritised upgrade plan

Nothing has been upgraded. Proposed order, cheapest-and-safest first; each batch stops for a full
`dart format` / `flutter analyze` / `flutter test` run.

**Batch 0 — the two npm highs (10 min, no app impact).**
`js-yaml` 4.3.1 → **4.3.2** in `scripts/` (patch, closes the only high-severity issue reachable here), and
`@fastify/busboy` → 3.2.2 in `scripts/firebase/` (transitive; `npm audit fix` or an override). Leave
`xml2js` 0.4.23 → 0.6.2 for its own change: it is a major bump and `gen-arb.mjs` calls `parseStringPromise`
directly, so the ARB generation must be run and diffed. `uuid`/`gaxios` are transitive inside the
firebase demo tree — take them only if you bump `firebase-admin` 14.4.0 → 14.5.0 anyway.

**Batch 1 — twelve safe Dart patches, one commit.**
`app_links` · `connectivity_plus` · `cupertino_ui` · `image_picker` · `material_color_utilities` ·
`package_info_plus` · `share_plus` · `shared_preferences` · `url_launcher` · `wakelock_plus` · `freezed` ·
`build_runner`. All patch-level, all with a reviewed changelog. Two to verify by hand afterwards: iOS
sharing (share_plus dropped the `keyWindow` fallback) and deep-link delivery (app_links changed which links
get delivered).

**Batch 2 — minors.**
`cronet_http` 1.10.0 (additive), `device_info_plus` 13.3.0 (additive). Then `material_ui` 1.2.0 → 1.6.0 on
its own: four minors at once across 129 files, and the changes are visual — it wants a device pass, not just
a green CI.

**Batch 3 — the one major.**
`fast_immutable_collections` 11.2.0 → **12.0.0**, alone, with the full suite. The breaking change is scoped
to identity-comparing collections, of which this codebase has none, so I expect it to pass — but 80 files
and 291 collection type references is not something to bundle with anything else.

**Batch 4 — toolchain (separate from app deps; touches release workflows).**
Flutter 3.47.3 → 3.47.6 (`pubspec.yaml` **and** `.fvmrc`), Gradle 9.5.1 → 9.8.1, Kotlin 2.4.10 → 2.4.21,
and the three behind-major CI actions (`setup-java` v5→v6, `upload-artifact` v6→v7, `download-artifact`
v6→v8). The artifact actions are used by `release.yml`, so do this when a release is not imminent, and
verify one full release-proof run afterwards.

**Decide, don't just bump.**
- The two git pins (§4): `lc0` can probably move now that the branch it was waiting for has merged;
  `multistockfish` moving means **Stockfish 19** — a product call.
- The 7 unused Dart dependencies and 3 unused npm dependencies (§6).
- `sdk: ^3.12.2` vs the tree's real `>=3.13.0` floor (§5.1).
- `flutter_svg` and `cupertino_icons`: get a real `flutter pub outdated` reading on a networked machine.

---

## 9. What this audit changed

Nothing. No manifest, lockfile or source file was touched; the working tree is exactly as it was. The only
files added are this report and the scratch data under `/home/user/.audit/` (outside the repo).

**Waiting on direction for which batches to run.** When you pick one, I will do it as you asked: small
batches, full lint/type-check/test after each, and a report of what broke and how it was fixed — with the
standing caveat that `flutter analyze` and `flutter test` cannot run in this environment, so verification
will be `scripts/gates.sh t1` here plus CI (`test.yml`) on the pushed branch.
