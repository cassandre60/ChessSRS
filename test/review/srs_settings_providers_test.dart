// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC coverage: INV-024, INV-031.

import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/model/study/study_preferences.dart';
import 'package:chess_srs/src/review/review_service.dart';
import 'package:chess_srs/src/review/srs_settings_providers.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_container.dart';

void main() {
  group('SRS settings & scheduler providers (INV-024, INV-031)', () {
    test('studyPreferencesProvider defaults and schedulerProvider selection', () async {
      // SPEC INV-024, INV-031. Default study preferences select SimpleScheduler
      // with 0.88 targetRetention, 100 maxDailyReviews, and 10 maxNewPerDay, and
      // switching SchedulerType updates schedulerProvider deterministically.
      final container = await makeContainer();

      final initialPrefs = container.read(studyPreferencesProvider);
      expect(initialPrefs.schedulerType, SchedulerType.simple);
      expect(initialPrefs.targetRetention, 0.88);
      expect(initialPrefs.maxDailyReviews, 100);
      expect(initialPrefs.maxNewPerDay, 10);

      final initialScheduler = container.read(schedulerProvider);
      expect(initialScheduler, isA<SimpleScheduler>());

      // Switch to ChessFsrsScheduler and update target retention
      final notifier = container.read(studyPreferencesProvider.notifier);
      await notifier.setSchedulerType(SchedulerType.fsrs);
      await notifier.setTargetRetention(0.85);
      final updatedFsrs = container.read(schedulerProvider);
      expect(updatedFsrs, isA<ChessFsrsScheduler>());
      expect((updatedFsrs as ChessFsrsScheduler).targetRetention, 0.85);

      // Switch to EaseScalingScheduler and customize ease & scaling
      await notifier.setSchedulerType(SchedulerType.easeScaling);
      await notifier.setSchedulerEase(2.5);
      await notifier.setSchedulerScaling(1.8);
      final easeScheduler = container.read(schedulerProvider);
      expect(easeScheduler, isA<EaseScalingScheduler>());
      expect((easeScheduler as EaseScalingScheduler).ease, 2.5);
      expect(easeScheduler.scaling, 1.8);
    });

    test(
      'daily quota and new-position cap updates persist in studyPreferencesProvider (INV-031)',
      () async {
        // SPEC INV-031. Daily review quota and new-position allowance settings persist across updates.
        final container = await makeContainer();
        final notifier = container.read(studyPreferencesProvider.notifier);

        await notifier.setMaxDailyReviews(50);
        await notifier.setMaxNewPerDay(20);

        final updated = container.read(studyPreferencesProvider);
        expect(updated.maxDailyReviews, 50);
        expect(updated.maxNewPerDay, 20);
      },
    );

    test(
      'getDbSizeInBytesProvider is re-exported by srs_settings_providers for presentation',
      () async {
        final container = await makeContainer(
          overrides: {
            getDbSizeInBytesProvider: getDbSizeInBytesProvider.overrideWith((ref) => 4096),
          },
        );

        final size = await container.read(getDbSizeInBytesProvider.future);
        expect(size, 4096);
      },
    );
  });
}
