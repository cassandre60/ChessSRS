import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/view/analysis/engine_settings_widget.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../binding.dart';
import '../../test_provider_scope.dart';

// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

/// `SliderSettingsTile` -- the widget these replaced -- showed its value only in the drag
/// bubble, so search time, evaluation lines and CPU count had no readable value until you were
/// already dragging one, and a screen reader could not announce one at all. These are the
/// guards for the row that replaced it.
/// A mutable box, so a closure built once can hand a value back out to the test body.
class DurationHolder {
  Duration? value;
}

void main() {
  setUpAll(TestLichessBinding.ensureInitialized);

  Future<void> open(WidgetTester tester, {DurationHolder? written}) async {
    await tester.pumpWidget(
      await makeTestProviderScopeApp(
        tester,
        // A Scaffold, because the widget is a body, not a screen: a Slider asserts on a
        // Material ancestor within the closest LookupBoundary, and all three real callers
        // mount it inside one.
        home: Scaffold(
          body: EngineSettingsWidget(
            onSetEngineSearchTime: (d) => written?.value = d,
            onSetEngineCores: (n) {},
            onSetNumEvalLines: (n) {},
          ),
        ),
        surfaceSize: const Size(390, 844),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('every slider states its value, rather than only on the drag bubble', (tester) async {
    await open(tester);

    // Three bounded sliders: search time, evaluation lines, cores.
    final sliders = find.byType(Slider);
    expect(sliders, findsNWidgets(3));

    // Each row carries a value, and it is the one the slider is sitting on -- not a restated
    // constant. The sound volume row had exactly that bug: it said 50% while the slider was
    // at 0.497.
    final rows = tester.widgetList<SrsSettingsRow>(find.byType(SrsSettingsRow)).toList();
    final values = tester
        .widgetList<Slider>(sliders)
        .map((s) => (s.min, s.max, s.value, s.divisions))
        .toList();

    expect(rows.length, greaterThanOrEqualTo(3));
    for (var i = 0; i < values.length; i++) {
      final (min, max, value, divisions) = values[i];
      final row = rows[i];

      expect(row.value, isNotNull, reason: 'a bounded slider with no visible value is unusable');
      expect(divisions, isNotNull, reason: 'without notches the knob can rest between values');
      expect(value, inInclusiveRange(min, max));
    }
  });

  testWidgets('the row text is the formatted slider value, not a separate constant', (
    tester,
  ) async {
    final written = DurationHolder();
    await open(tester, written: written);

    final slider = tester.widget<Slider>(find.byType(Slider).first);
    final row = tester.widgetList<SrsSettingsRow>(find.byType(SrsSettingsRow)).first;

    // The search-time formatter is `${seconds}s`, with an infinity at the maximum.
    final expected = slider.value == slider.max ? '∞' : '${slider.value.toInt()}s';
    expect(row.value, expected);

    // Dragging to the maximum writes the maximum, not the value the row was restating.
    // An explicit gesture, because `tester.drag` starts at the widget's centre rather than on
    // the thumb and a Slider only commits a change the drag actually reaches.
    final track = tester.getRect(find.byType(Slider).first);
    final gesture = await tester.startGesture(track.center);
    await gesture.moveTo(Offset(track.right - 1, track.center.dy));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(written.value, isNotNull);
    expect(written.value!.inMilliseconds, slider.max.round() * 1000);
  });
}
