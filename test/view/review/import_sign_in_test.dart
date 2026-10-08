// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/model/auth/auth_controller.dart';
import 'package:chess_srs/src/model/common/id.dart';
import 'package:chess_srs/src/model/study/study_repository.dart' as lichess_study;
import 'package:chess_srs/src/model/user/user.dart';
import 'package:chess_srs/src/review/review_controller.dart';
import 'package:chess_srs/src/view/review/repertoire_import_dialog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override, ProviderOrFamily;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

import '../../binding.dart';
import '../../test_provider_scope.dart';

/// Studies are private by default here: Lichess answers 404 for anything it will not show the
/// current requester, and it does not distinguish private from non-existent.
MockClient privateStudyClient() => MockClient((_) async => http.Response('Not Found', 404));

void main() {
  setUpAll(() {
    TestLichessBinding.ensureInitialized();
  });

  Future<void> openImportDialog(
    WidgetTester tester, {
    Map<ProviderOrFamily, Override> overrides = const {},
  }) async {
    final app = await makeTestProviderScopeApp(
      tester,
      home: const RepertoireImportDialog(),
      overrides: overrides,
    );
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
  }

  Map<ProviderOrFamily, Override> withPrivateStudies() => {
    lichess_study.studyRepositoryProvider: lichess_study.studyRepositoryProvider.overrideWith(
      (ref) => lichess_study.StudyRepository(ref, privateStudyClient()),
    ),
  };

  Map<ProviderOrFamily, Override> signedIn() => {
    isLoggedInProvider: isLoggedInProvider.overrideWith((ref) => true),
  };

  group('sign-in affordance in the import scene', () {
    testWidgets('a 404 on a private study offers sign-in instead of blaming the study', (
      tester,
    ) async {
      await openImportDialog(tester, overrides: withPrivateStudies());

      expect(
        find.text('Importing a private study? Sign in'),
        findsOneWidget,
        reason: 'the quiet hint is present before anything has failed',
      );

      await tester.enterText(find.byType(TextField).first, 'm1AbCd2E');
      await tester.tap(find.text('Fetch & Import from Lichess'));
      await tester.pumpAndSettle();

      // The old toast told the user to "ensure the study is public or unlisted", which is
      // exactly what may be untrue. Asserting its absence is the point of the change, so this
      // fails on the pre-fix dialog.
      expect(find.textContaining('Ensure the study is public or unlisted'), findsNothing);

      expect(
        find.textContaining('the same for a private study as for one that does not exist'),
        findsOneWidget,
        reason: 'the 404 is explained without claiming to know why it happened',
      );
      expect(find.text('Sign in and retry'), findsOneWidget);
      expect(find.text('Importing a private study? Sign in'), findsNothing);
    });

    testWidgets('a signed-in 404 still blames the study, because sign-in cannot help', (
      tester,
    ) async {
      await openImportDialog(tester, overrides: {...withPrivateStudies(), ...signedIn()});

      await tester.enterText(find.byType(TextField).first, 'm1AbCd2E');
      await tester.tap(find.text('Fetch & Import from Lichess'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Ensure the study is public or unlisted'), findsOneWidget);
      expect(find.text('Sign in and retry'), findsNothing);
    });

    testWidgets('a signed-in user is not nagged about private studies at all', (tester) async {
      await openImportDialog(tester, overrides: signedIn());

      expect(find.text('Importing a private study? Sign in'), findsNothing);
      expect(find.text('Sign in and retry'), findsNothing);
    });

    testWidgets('signing in after a 404 retries the import without retyping the id', (
      tester,
    ) async {
      var firstCallFails = true;
      final client = MockClient((_) async {
        if (firstCallFails) {
          firstCallFails = false;
          return http.Response('Not Found', 404);
        }
        return http.Response('[Event "Study"]\n[Site "?"]\n[Result "*"]\n\n1. e4 e5 *', 200);
      });

      await openImportDialog(
        tester,
        overrides: {
          lichess_study.studyRepositoryProvider: lichess_study.studyRepositoryProvider.overrideWith(
            (ref) => lichess_study.StudyRepository(ref, client),
          ),
        },
      );

      await tester.enterText(find.byType(TextField).first, 'm1AbCd2E');
      await tester.tap(find.text('Fetch & Import from Lichess'));
      await tester.pumpAndSettle();
      expect(find.text('Sign in and retry'), findsOneWidget);

      // Stand in for the OAuth round trip completing. The dialog watches the auth controller and
      // reacts to it becoming non-null, so the token itself is what has to change here.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(RepertoireImportDialog)),
      );
      container.read(authControllerProvider.notifier).state = const AuthUser(
        token: 'test-token',
        user: LightUser(id: UserId('tester'), name: 'tester'),
      );
      await tester.pumpAndSettle();

      // The retry consumed the prompt, which only happens if the second fetch ran and no longer
      // 404'd — the first call consumed the 404 and the id was never retyped.
      expect(find.text('Sign in and retry'), findsNothing);
      expect(find.text('Importing a private study? Sign in'), findsNothing);
    });
  });

  group('StudyNotFoundException', () {
    test('is still a FormatException, so existing callers keep catching it', () {
      expect(const StudyNotFoundException('nope'), isA<FormatException>());
      expect(const StudyNotFoundException('nope').message, 'nope');
    });
  });

  group('the failure notice is reachable from where the user is', () {
    // Found by looking at a landscape capture, not by an assertion: the dialog body is taller
    // than a landscape phone, the user presses Fetch at the bottom of the form, and a notice
    // pinned near the top then opened above the viewport. A failure with a known cause and a
    // known fix read as a failure with neither. Fails without the scroll-to-top on failure.
    testWidgets('is on screen after a 404 on a surface shorter than the form', (tester) async {
      const landscape = Size(844, 390);
      final app = await makeTestProviderScopeApp(
        tester,
        home: const RepertoireImportDialog(),
        surfaceSize: landscape,
        overrides: {
          lichess_study.studyRepositoryProvider: lichess_study.studyRepositoryProvider.overrideWith(
            (ref) => lichess_study.StudyRepository(ref, privateStudyClient()),
          ),
        },
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'm1AbCd2E');
      await tester.ensureVisible(find.text('Fetch & Import from Lichess'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fetch & Import from Lichess'));
      await tester.pumpAndSettle();

      final notice = find.textContaining('Lichess answers the same');
      expect(notice, findsOneWidget, reason: 'the 404 notice should be rendered');

      final noticeRect = tester.getRect(notice);
      expect(
        noticeRect.bottom,
        lessThanOrEqualTo(landscape.height),
        reason: 'the notice must be inside the viewport, not scrolled above it',
      );
      expect(
        noticeRect.top,
        greaterThanOrEqualTo(0),
        reason: 'the notice must not be clipped off the top of the screen',
      );

      // And the recovery action has to be reachable, not just visible.
      final retry = find.text('Sign in and retry');
      expect(retry, findsOneWidget);
      expect(tester.getRect(retry).bottom, lessThanOrEqualTo(landscape.height));
    });
  });
}
