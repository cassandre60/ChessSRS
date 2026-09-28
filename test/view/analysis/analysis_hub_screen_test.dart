// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/domain/chapter.dart';
import 'package:chess_srs/src/domain/study.dart';
import 'package:chess_srs/src/persistence/persistence.dart';
import 'package:chess_srs/src/view/analysis/analysis_hub_screen.dart';
import 'package:chess_srs/src/view/review/study_chapters_screen.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../test_provider_scope.dart';

/// The Explore hub, reachable from Library.
///
/// This exists because of a decision, not a design: `00-agent-brief.md` open decision 1 asked
/// whether Analysis, Explorer and Board editor should be kept, folded into an "Explore" area, or
/// cut. Owner decision 2026-09-28: fold them into one screen called Analysis, alongside an entry
/// for a study's chapters. Chapters stay owned by the scope drawer for *choosing* what to review;
/// this entry is for *browsing* them.
void main() {
  group('Analysis hub', () {
    testWidgets('offers the three tools and a chapters entry', (tester) async {
      final app = await makeTestProviderScopeApp(tester, home: const AnalysisHubScreen());
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      // The three labels are the design's own, verbatim from 03-components.md §7 -- so this fails
      // if a rename happens in one place and not the other.
      expect(find.text('Analysis board'), findsOneWidget);
      expect(find.text('Opening explorer'), findsOneWidget);
      expect(find.text('Board editor'), findsOneWidget);
      expect(find.text('Chapters of a study'), findsOneWidget);
    });

    testWidgets('says so plainly when there is nothing to browse', (tester) async {
      final app = await makeTestProviderScopeApp(tester, home: const AnalysisHubScreen());
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      // Tapping with nothing imported must *say* so. A row that opens an empty sheet, or silently
      // does nothing, both read as a broken hub rather than as "you have no repertoires yet".
      await tester.tap(find.text('Chapters of a study'));
      await tester.pumpAndSettle();

      expect(find.text('Import a repertoire first.'), findsOneWidget);
      expect(find.byType(StudyChaptersScreen), findsNothing);
    });

    testWidgets('reaches the chapters screen for a study that has chapters', (tester) async {
      final repo = _FakeStudyRepository.withChapters('Sicilian: Najdorf');
      final app = await makeTestProviderScopeApp(
        tester,
        home: const AnalysisHubScreen(),
        overrides: {srsStudyRepositoryProvider: repo.providerOverride},
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      // The study list is NOT on the hub: it lives one level in, in a picker. An inline list would
      // put a second set of repertoire rows beside the scope drawer, which already owns that.
      expect(find.text('Sicilian Defense'), findsNothing);

      await tester.tap(find.text('Chapters of a study'));
      await tester.pumpAndSettle();

      expect(find.text('Sicilian Defense'), findsOneWidget);

      await tester.tap(find.text('Sicilian Defense'));
      await tester.pumpAndSettle();

      // The existing screen, not a new one: this hub routes, it does not reimplement.
      expect(find.byType(StudyChaptersScreen), findsOneWidget);
      expect(find.text('Sicilian: Najdorf'), findsOneWidget);
    });
  });
}

/// Stand-in for the study repository, holding just enough to drive the picker.
///
/// The real one opens a SQLite database; a widget test cannot, and the hub's only use of it is
/// `getAllStudies` plus `getChaptersByStudy`.
class _FakeStudyRepository extends Fake implements StudyRepository {
  _FakeStudyRepository(this._studies, this._chaptersByStudy);

  factory _FakeStudyRepository.withChapters(String chapterTitle) {
    final study = Study.create(title: 'Sicilian Defense');
    return _FakeStudyRepository(
      [study],
      {
        study.id: [Chapter.create(studyId: study.id, sourceOrder: 0, title: chapterTitle)],
      },
    );
  }

  final List<Study> _studies;
  final Map<String, List<Chapter>> _chaptersByStudy;

  /// The provider override, in the shape `makeTestProviderScopeApp` expects.
  ///
  /// Not named `override`: that would shadow the `@override` annotation in this class body, and
  /// every `@override` below then fails to compile as a non-constant expression.
  Override get providerOverride =>
      srsStudyRepositoryProvider.overrideWith((ref) => Future.value(this));

  @override
  Future<List<Study>> getAllStudies() => Future.value(_studies);

  @override
  Future<List<Chapter>> getChaptersByStudy(String studyId) async =>
      _chaptersByStudy[studyId] ?? <Chapter>[];
}
