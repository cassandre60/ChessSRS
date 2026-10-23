# CLAUDE.md

Authority: Dart/Riverpod/code-generation and test-helper conventions for all
agents contributing to ChessSRS. AGENTS owns safe execution/isolation;
TEST_STRATEGY owns verification budgets; ARCHITECTURE owns module arrangement;
design/docs owns visual rules. See docs/documentation-map.md.

## Project Overview

ChessSRS is a local-first trainer forked from Lichess Mobile. The app uses:
- **Flutter**: Cross-platform UI framework; toolchain pins in .fvmrc/pubspec.yaml
- **Riverpod**: State management with providers
- **Freezed**: Immutable data classes
- **Code generation**: For data classes, JSON serialization, and localization
- **Stockfish**: Chess engine integration via `multistockfish` package

## Development Setup

### Initial Setup
```bash
# Install dependencies
fvm flutter pub get

# Generate code (required before first run)
fvm dart run build_runner build
```

### Running the App
```bash
# Launch one bounded runtime-validation target (production host is lichess.org)
fvm flutter run -d linux

# Run with custom server
fvm flutter run \
  --dart-define=LICHESS_HOST=localhost:8080 \
  --dart-define=LICHESS_WS_HOST=localhost:8080
```

**Note**: Do not include scheme (https:// or ws://) in host values.

### For Android with local lila-docker
```bash
# Map ports
adb reverse tcp:8080 tcp:8080

# Run app
fvm flutter run --dart-define=LICHESS_HOST=localhost:8080 --dart-define=LICHESS_WS_HOST=localhost:8080
```

## Testing & Quality

### Run Tests
```bash
# Single test file
fvm flutter test <affected test file> --concurrency=1

# Specific test
fvm flutter test <affected test file> --plain-name 'test name' --concurrency=1
```

### Testing Strategy: Prefer HTTP Mocking Over Provider Overrides

**Always mock at the HTTP layer** (override `httpClientFactoryProvider`) rather than overriding Riverpod providers directly. Reasons:

1. **`autoDispose` + `ref.read` interaction**: Many providers are `FutureProvider.autoDispose` and use `ref.withClientCacheFor` which calls `keepAlive()` to prevent premature disposal. Overriding the provider directly bypasses `keepAlive()`, so the provider can be disposed before its future resolves — causing silent test failures where navigation never happens.

2. **Tests provider logic, not mocks**: Most providers contain real logic (caching, fallback, data transformation) that should be exercised in tests. Replacing a provider with `(_) async => fakeValue` skips all that logic.

**Pattern to use:**
```dart
overrides: [
  httpClientFactoryProvider.overrideWith((ref) {
    return FakeHttpClientFactory(
      () => MockClient((request) async {
        if (request.url.path == '/api/study/abcdefgh.pgn') {
          return http.Response(studyPgn, 200);
        }
        return http.Response('', 404);
      }),
    );
  }),
],
```

Direct provider overrides are acceptable for **non-network providers** (repositories backed by mocks, services with no HTTP, etc.) where the provider has no `keepAlive` dependency and the override doesn't skip meaningful logic.

### Chessboard Testing Patterns

Since chessground v10, pieces and highlights are rendered by `CustomPainter`s, not as individual widgets. **Do not use `find.byKey(Key('e2-whitepawn'))` or `find.byKey(ValueKey('${sq}-highlight'))` — those keys no longer exist.**

Use the helpers in `test/test_helpers.dart` instead:

```dart
// Check pieces on any Chessboard (interactive or Chessboard.fixed)
getBoardPieces(tester)                             // Map<Square, Piece>
boardHasPiece(tester, Square.f3, Piece.whiteKnight) // bool

// Check premove highlight
boardHasPremove(tester, move)                      // bool

// Tap/move at a board square
squareOffset(square, tester.getRect(find.byType(Chessboard)))
```

For `ChessboardEditor` (board editor screen), read pieces directly from the widget:
```dart
tester.widget<ChessboardEditor>(find.byType(ChessboardEditor)).pieces
```

### Analysis Rules (CRITICAL)

Analysis timing/scope is owned by TEST_STRATEGY §2 (once, after the last edit,
all touched Dart files including tests).

Two rules the analyzer enforces that are easy to miss:

- **`const` constructors**: use `const` (not `final`) when constructing a const-capable class. The analyzer will flag `prefer_const_constructors`. This applies everywhere, including test files. When the enclosing expression is not `const` (e.g. a non-const record or class), constructor calls inside it still need their own explicit `const` — e.g. `(time: const Duration(minutes: 3), increment: const Duration(seconds: 2))`.
- **No leading underscores for local identifiers**: local variables and functions must not start with `_`. Reserve `_` for library-private top-level or class members.

### Code Quality Checks
```bash
# Format/check only the touched hand-written Dart files (full checks run in CI)
fvm dart format <touched Dart files>
fvm flutter analyze <touched Dart paths>
```

### Formatting Rules (CRITICAL)

Format touched hand-written Dart per TEST_STRATEGY. Generated output follows
the policy below, especially l10n (never manually formatted).

```bash
fvm dart format path/to/file.dart
```

The formatter is configured via `analysis_options.yaml` (`formatter: page_width: 100`) and `dart format` picks this up automatically. Key rules enforced by the formatter:

- **Page width: 100 characters** — lines exceeding 100 chars will be reflowed
- **Trailing commas drive formatting**: a trailing comma after the last argument/parameter forces the formatter to expand the list to one-item-per-line; omitting it allows the formatter to keep items on one line if they fit within 100 chars
- **Do not manually wrap lines** — let the formatter decide based on trailing commas and line length; hand-wrapping without trailing commas will be reformatted by the tool
- The formatter may reformat code you didn't touch in the same expression if you change surrounding structure

**Comments are the exception: the formatter never reflows them, so they are yours to wrap.**
Wrap comments and doc comments (`//` and `///`) to the same 100 character page width, not to
80. `dart format` leaves prose untouched, so a comment wrapped at 80 will simply stay that way
and look inconsistent with the code around it. Fill each line before wrapping to the next.

## Translations (i18n)

**CRITICAL**: Never manually edit `lib/l10n/app_*.arb` files - they are generated.

### Adding New Translations
1. Edit `translation/source/mobile.xml` for mobile-specific strings
2. Regenerate everything:
```bash
./scripts/gen-translations.sh
```

Inspect scripts/gen-translations.sh for the current pipeline; native home-screen
widgets were removed, so the inherited WidgetKit-string stage is not current.

Mobile-specific translations get a `mobile` prefix (e.g., "foo" becomes `mobileFoo` in Dart).

## Architecture

### Directory Structure

The module map is owned by ARCHITECTURE §3. The abbreviated surviving foundation:
```
lib/src/
├── model/          # Business logic, state management (Riverpod providers)
│   ├── account/
│   ├── analysis/
│   ├── auth/
│   ├── common/     # Shared models and utilities
│   ├── engine/     # Stockfish integration
│   ├── game/
│   ├── settings/
│   └── ...
├── view/           # UI screens and pages
│   ├── account/
│   ├── analysis/
│   ├── game/
│   ├── settings/
│   └── ...
├── widgets/        # Reusable UI components
├── network/        # HTTP client, WebSocket, connectivity
├── utils/          # Helper functions and utilities
├── styles/         # Theme, colors, icons
├── db/             # Local database (sqflite)
├── app.dart        # Main app widget
├── binding.dart    # Plugin/API abstraction layer
└── constants.dart  # App-wide constants
```

### Key Architectural Patterns

**State Management**: Riverpod providers throughout `lib/src/model/`. Controllers, repositories, and services are implemented as providers. State is immutable and managed with Freezed data classes.

**Riverpod version: 3.x — API differences from 2.x (CRITICAL)**

This project uses `flutter_riverpod 3.x` / `riverpod 3.x`. Several APIs changed from 2.x:

- **`AsyncValue.value`** (not `valueOrNull`): In 3.x, `AsyncValue<T>.value` returns `T?` (null while loading/error). `valueOrNull` no longer exists.
- **`ProviderListenable` is not exported**: Do not use `ProviderListenable<T>` as a type annotation — it is an internal interface. The return type of `.select()` is also internal (`_ProviderSelector`). `ProviderListenableSelect` is exported but is an *extension* on `ProviderListenable`, not a class — it cannot be used as a type.
  - When you need to pass a provider or select result to `ref.watch`/`ref.read`/`ref.listenManual`, just pass it directly without naming the type. If a return type annotation is required (e.g. an abstract method), use two concrete methods (`readCurrentState()` + `listenToStateChanges()`) instead of trying to name the provider type.
- **`ref.listenManual` type inference**: When the selected type is nullable (e.g. `provider.select((v) => v.value)` → `T?`), Dart cannot infer `StateT` because the callback signature is `void Function(StateT?, StateT)`. Always add an explicit type: `ref.listenManual<T?>(provider.select(...), listener)`.
- **`listenManual` in `ConsumerState`**: Subscriptions set up in `initState()` via `ref.listenManual` are automatically cancelled when the widget is disposed. No need to store or cancel manually.

**Binding Layer**: `LichessBinding` (in `binding.dart`) provides a testable abstraction for plugins and external APIs:
- SharedPreferences
- Stockfish factory

Use `AppLichessBinding.ensureInitialized()` in production, `TestLichessBinding` in tests.

**Network Layer**:
- HTTP: `lib/src/network/http.dart` - Platform-specific clients (Cronet for Android, Cupertino for iOS) with authentication, caching, and retry logic
- WebSocket: `lib/src/network/socket.dart` - Handles ping/pong, message acks, auto-reconnection, event versioning
- Helper: `lichessUri(path, queryParams)` for HTTP, `lichessWSUri(path, queryParams)` for WebSocket

**Services**: inspect app.dart for actual startup providers. Notification,
message, challenge and correspondence services were removed with the product cuts.

**Navigation**: Uses Flutter's Navigator with custom route resolution via `app_links.dart` for deep linking.

## Dart Event Loop Execution Model

Understanding Dart's event loop is critical for this codebase due to heavy async operations (network requests, WebSocket communication, Stockfish engine interaction).

### Event Loop Basics

Dart is single-threaded and uses an event loop with two queues:

1. **Microtask Queue** (higher priority)
   - Executed before the event queue
   - Scheduled with `scheduleMicrotask()` or via `Future` completions
   - Used internally by `Future.then()`, `async`/`await`

2. **Event Queue** (lower priority)
   - I/O events, timers, user interactions
   - Scheduled with `Future()`, `Timer`, `Stream` events
   - UI rendering happens between event queue items

**Execution order**:
```
1. Execute current synchronous code
2. Process ALL microtasks (until microtask queue is empty)
3. Process ONE event from event queue
4. Repeat from step 2
```

### Async/Await Behavior

```dart
// This does NOT block the event loop
Future<void> fetchData() async {
  final response = await http.get(uri);  // Yields to event loop
  // Resumes here when response completes
  processData(response);
}
```

When `await` is encountered:
1. Current function execution pauses
2. Control returns to event loop
3. Function resumes as a microtask when Future completes

### Common Patterns in This Codebase

**Riverpod AsyncNotifier**: State updates are async but don't block UI:
```dart
class MyController extends AsyncNotifier<Data> {
  @override
  Future<Data> build() async {
    // Fetches async, UI shows loading state
    return await repository.getData();
  }
}
```

**WebSocket Message Handling** (see `lib/src/network/socket.dart`):
- Messages arrive as events
- Processed in event queue
- Microtasks schedule state updates

**Stockfish Engine Communication**:
- Engine runs in isolate (separate event loop)
- Communication via `SendPort`/`ReceivePort` (event queue)

### Important Gotchas

**Microtask Queue Starvation**: Never create infinite microtask loops - they block the event queue and freeze the UI:
```dart
// BAD - Starves event queue
void badLoop() {
  scheduleMicrotask(() {
    doWork();
    badLoop();  // Immediately schedules another microtask
  });
}

// GOOD - Allows event queue processing
void goodLoop() {
  Future(() {  // Uses event queue
    doWork();
    goodLoop();
  });
}
```

**Future vs Future.microtask**:
- `Future(callback)` → event queue
- `Future.microtask(callback)` → microtask queue
- Prefer event queue for non-critical work

**Stream Subscriptions**: Always cancel to prevent memory leaks:
```dart
// In StatefulWidget or Riverpod
final subscription = stream.listen(onData);

@override
void dispose() {
  subscription.cancel();  // Critical!
  super.dispose();
}
```

**Testing with fake_async**: Use `FakeAsync` for tests involving timers and microtasks to control time progression.

## Coding Standards

### Immutability (Required)
All data structures must be immutable (all fields `final` or `late final`):
- Use **Freezed** for data classes
- Use **fast_immutable_collections** for collections in public APIs
- Standard Dart collections (`List`, `Map`) are forbidden in public APIs but allowed in local scopes

### Strong Typing
Prefer strong types over primitives (e.g., `Duration` instead of `int`).

### Dot Shorthand Syntax (Dart 3.10+)
Use dot shorthand syntax (`.foo`) to write more concise code when the type can be inferred from context. This is especially useful for enums, named constructors, and static members.

```dart
// Enums - use shorthand
Status current = .running;           // Good
Status current = Status.running;     // Verbose

// Switch statements
switch (status) {
  case .running: ...
  case .stopped: ...
}

// Named constructors
Point p = .origin();                 // Good
Point p = Point.origin();            // Verbose

// Widget properties
MainAxisAlignment: .center,          // Good
MainAxisAlignment: MainAxisAlignment.center,  // Verbose

// Equality checks (shorthand on right side)
if (color == .red) ...               // Good
if (.red == color) ...               // Won't work
```

**Note**: Shorthand requires clear context type inference and cannot start expression statements.

### Functional Style
Prefer functional constructs over imperative:
```dart
// Good
return [
  if (check) Text('conditional'),
  for (el in items) Text(el.name),
];

// Bad
final widgets = <Widget>[];
if (check) widgets.add(Text('conditional'));
for (el in items) widgets.add(Text(el.name));
```

### Widget Guidelines
- Avoid functions returning widgets (use `StatelessWidget` for reusables)
- Don't create private widgets used only once - inline them
- Write reusable widgets as classes even if single-screen scope

### Analysis
- Strict mode enabled: `strict-casts`, `strict-inference`, `strict-raw-types`
- Use single quotes for strings
- Always use package imports (no relative imports)
- Page width: 100 characters
- Generated files (`*.g.dart`, `*.freezed.dart`) are excluded from analysis

## Code Generation

Run `fvm dart run build_runner build` after:
- Modifying Freezed classes
- Adding JSON serialization
- Changing models with code generation annotations

Freezed/JSON `*.freezed.dart` and `*.g.dart` are gitignored and per-worktree.
Generated **l10n Dart and ARB are committed**. With l10n.yaml `format: false`,
commit raw pinned-generator output when regeneration is intended; do not run
dart format over lib/l10n or resurrect the obsolete formatting workaround.
Run pub get before formatting so analyzer includes/page-width configuration
resolve correctly. Inspect unexpected generator changes before staging them.

## Common Gotchas

- **Don't edit generated files**: Anything ending in `.g.dart`, `.freezed.dart`, or in `lib/l10n/`
- **Translations**: Start with hardcoded English text for new features. Add translations after the feature is stable and in use
- **Error messages**: Don't translate non-critical error messages (e.g., "could not load XY")
- **Brand names**: Don't translate names like "Puzzle Storm" or "Puzzle Streak"
- **FVM users**: Remember to prefix commands with `fvm` (e.g., `fvm flutter test`)

## Removed native integrations

Firebase/FCM and Android/iOS home-screen widgets were removed. CUT_PROPOSALS
owns the cut record; do not restore them from inherited contributor guidance.

## Debugging

```bash
# Start DevTools for logging
fvm dart devtools

# Then run app and follow printed link
fvm flutter run -d linux
```
