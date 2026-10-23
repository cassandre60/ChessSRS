import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';
import 'test_provider_scope.dart';

/// A row whose child is 100 px wider than the test surface, so the row
/// overflows by 100 px.
Widget _overflowingRow() => MaterialApp(
  home: Row(
    children: [SizedBox(width: kTestSurfaceSize.width + 100, child: const Text('overflow'))],
  ),
);

/// Collects the lines the shared scope prints, and leaves the rest of the
/// output alone.
///
/// [restore] must run before the test body returns: the test framework checks
/// that no foundation debug variable was left changed.
class _Printer {
  _Printer() {
    _original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) {
        printed.add(message);
      }
      _original(message, wrapWidth: wrapWidth);
    };
  }

  late final void Function(String? message, {int? wrapWidth}) _original;

  /// The lines printed since this printer was installed.
  final List<String> printed = [];

  /// The lines printed about a layout overflow.
  Iterable<String> get overflowLines =>
      printed.where((line) => line.contains('SRS-LAYOUT-OVERFLOW'));

  void restore() {
    debugPrint = _original;
  }
}

void main() {
  testWidgets('the shared scope FAILS a layout overflow, and says where it happened', (
    tester,
  ) async {
    final printer = _Printer();
    try {
      final app = await makeTestProviderScope(tester, child: _overflowingRow());
      await tester.pumpWidget(app);

      // The overflow reaches the test framework, so the test fails on it: a
      // layout defect in a widget test is a red test, not a printed line.
      final error = tester.takeException();
      expect(error, isNotNull, reason: 'an overflow must fail the test');
      expect(
        error.toString(),
        contains('A RenderFlex overflowed'),
        reason: 'the failure must name the class of defect, not something else',
      );

      // ... and the marker still names the site, so it is greppable in CI.
      expect(printer.overflowLines, hasLength(1));
      expect(printer.overflowLines.single, contains('100 pixels on the right'));
      expect(printer.overflowLines.single, contains('test_provider_scope_test.dart:'));
    } finally {
      printer.restore();
    }
  });

  testWidgets('the shared scope still forwards every other error to the test framework', (
    tester,
  ) async {
    await makeTestProviderScope(tester, child: const MaterialApp(home: SizedBox()));

    FlutterError.onError!(FlutterErrorDetails(exception: StateError('not an overflow')));

    // The test framework received the error, so the test would fail on it.
    expect(tester.takeException(), isA<StateError>());
  });

  testWidgets('the shared scope reports an overflow once, however many scopes are built', (
    tester,
  ) async {
    final printer = _Printer();
    try {
      // The handler is installed on every call, so a test that builds several
      // scopes installs it several times. It must not report an overflow once
      // per install.
      await makeTestProviderScope(tester, child: const MaterialApp(home: SizedBox()));
      final app = await makeTestProviderScope(tester, child: _overflowingRow());
      await tester.pumpWidget(app);

      expect(printer.overflowLines, hasLength(1));
      // The failure reaches the framework once, not once per install.
      expect(tester.takeException(), isNotNull);
    } finally {
      printer.restore();
    }
  });
}
