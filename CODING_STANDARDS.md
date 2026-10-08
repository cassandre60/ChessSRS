# Coding Standards

This document defines coding standards for the ChessSRS project. These standards are enforced during code review.

## Domain Layer Documentation Requirements

The domain layer (`lib/src/domain/`) is the core business logic of the application. All public APIs in this layer must be documented.

### Requirements

1. **All public classes** must have a documentation comment explaining their purpose and key behaviors.
2. **All public methods** must have documentation comments explaining:
   - What the method does
   - Parameters and their constraints
   - Return value and its meaning
   - Any side effects or exceptions thrown
3. **All public properties/fields** must have documentation comments explaining their purpose and valid values.
4. **Enums** must have documentation for each value explaining its meaning.

### Enforcement

The domain layer documentation coverage is checked by CI. Run locally with:

```bash
fvm dart doc lib/src/domain --dry-run
```

The domain layer must maintain **100% public API documentation coverage**.

### Example

```dart
/// A chess move in UCI notation stored in the domain layer.
///
/// This is a *domain* value — a thin named container for UCI coordinates.
/// It is not a dartchess [Move]; the import pipeline converts dartchess moves
/// into these after legal-move validation. The Review engine similarly converts
/// user input to this type before matching against [RepertoireDecision.expectedMoves].
///
/// Position identity is by [from]/[to]/[promotion] only (no FEN context stored
/// here). FEN context is on the parent [RepertoireNode].
class RepertoireMove {
  /// Origin square, e.g. `'e2'`.
  final String from;

  /// Target square, e.g. `'e4'`.
  final String to;

  /// Promotion piece character (`'q'`, `'r'`, `'b'`, `'n'`) or null.
  final String? promotion;

  /// Standard Algebraic Notation label for display, e.g. `'e4'`, `'Nf6'`.
  final String? san;
  // ...
}
```

## General Dart Style

- Follow the lint rules in `analysis_options.yaml` (extends `package:lint/strict.yaml`)
- Format with `dart format` (page width 100)
- Prefer `const` constructors where possible
- Use `final` for immutable fields
- Prefer `const` constructors for immutable classes

## Naming Conventions

- Classes, enums, typedefs, extensions: `UpperCamelCase`
- Methods, variables, parameters, fields: `lowerCamelCase`
- Constants: `lowerCamelCase` (not SCREAMING_SNAKE_CASE)
- Private members: prefix with `_`

## Error Handling

- Prefer explicit error types over `dynamic`
- Use `Result<T, E>` or similar for recoverable errors
- Never swallow exceptions silently
- Log errors with context at the boundary where they're handled

## Testing

- Unit tests for all domain logic
- Test file naming: `<file>_test.dart`
- Test naming: `test('description of behavior', () { ... })`
- Use `setUp`/`tearDown` for shared fixtures
- Prefer `fakeAsync` for time-dependent tests
