// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:io' as io;

import 'package:chess_srs/src/db/database.dart';
import 'package:chess_srs/src/import/pgn_importer.dart';
import 'package:chess_srs/src/model/auth/auth_controller.dart';
import 'package:chess_srs/src/model/common/id.dart';
import 'package:chess_srs/src/model/study/study_repository.dart' as lichess_study;
import 'package:chess_srs/src/model/user/user.dart';
import 'package:chess_srs/src/persistence/persistence.dart';
import 'package:chess_srs/src/view/more/import_pgn_screen.dart';
import 'package:chess_srs/src/view/review/repertoire_import_dialog.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override, ProviderOrFamily;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../binding.dart';
import '../../test_provider_scope.dart';

/// A picked file backed by a real file on disk, so the dialog's own read path
/// (`io.File(file.path).readAsString()`) runs for real rather than being stubbed.
final class _RealFilePlatformFile extends PlatformFile {
  _RealFilePlatformFile(this.file) : name = file.uri.pathSegments.last;

  final io.File file;

  @override
  final String name;

  @override
  Uri get uri => file.uri;

  /// [Never] is used as the return type so that no `package:cross_file` import is needed: the
  /// dialog reads by path, not through xFile.
  @override
  Never get xFile => throw UnimplementedError();

  @override
  int? lengthSync() => file.lengthSync();

  @override
  Future<int> length() async => file.lengthSync();

  @override
  Future<Uint8List> readAsBytes() => file.readAsBytes();

  @override
  Stream<Uint8List> readAsByteStream() => file.openRead().cast<Uint8List>();
}

void main() {
  setUpAll(() {
    TestLichessBinding.ensureInitialized();
    sqfliteFfiInit();
  });

  /// The local store the import writes into.
  ///
  /// Opened here, outside the widget test's fake-async zone, because the app's own
  /// `databaseProvider` opens the database inside that zone and never finishes opening it.
  /// `test/view/review/export_pgn_dialog_test.dart` does the same for the same reason.
  late Database db;
  late SqliteStudyRepository repo;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    final batch = db.batch();
    createSrsTables(batch);
    await batch.commit();
    repo = SqliteStudyRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  /// Opens the dialog the way the app does — pushed over a home screen — so dismissing it is
  /// an ordinary route pop rather than replacing the whole tree.
  Future<void> openImportDialog(
    WidgetTester tester, {
    ImportSource source = ImportSource.lichess,
    Map<ProviderOrFamily, Override> overrides = const {},
  }) async {
    final app = await makeTestProviderScopeApp(
      tester,
      home: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => RepertoireImportDialog.show(context, initialSource: source),
            child: const Text('open the import dialog'),
          ),
        ),
      ),
      overrides: {
        databaseProvider: databaseProvider.overrideWith((ref) => db),
        srsStudyRepositoryProvider: srsStudyRepositoryProvider.overrideWith((ref) => repo),
        ...overrides,
      },
    );
    await tester.pumpWidget(app);
    await tester.tap(find.text('open the import dialog'));
    await tester.pumpAndSettle();
  }

  /// A field of the dialog, found by the label of its decoration.
  ///
  /// The dialog reuses the same label for the title field on both tabs, but only one tab is
  /// ever built at a time, so the label is unambiguous.
  Finder fieldLabelled(String label) => find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  );

  /// A Lichess study repository whose HTTP client answers every request with [answer].
  ///
  /// Recording the paths is how a test tells "the dialog asked Lichess for the study" apart
  /// from "the dialog decided not to fetch anything", which is the difference between an
  /// input that was accepted and an input that was refused.
  Override lichessRepositoryAnswering(
    Future<http.Response> Function(String path) answer, {
    void Function(String path)? record,
  }) {
    return lichess_study.studyRepositoryProvider.overrideWith(
      (ref) => lichess_study.StudyRepository(
        ref,
        MockClient((request) {
          record?.call(request.url.toString());
          return answer(request.url.toString());
        }),
      ),
    );
  }

  testWidgets('an empty Lichess URL is refused before anything is fetched', (tester) async {
    // SPEC INV-011.
    final requested = <String>[];
    await openImportDialog(
      tester,
      overrides: {
        lichess_study.studyRepositoryProvider: lichessRepositoryAnswering(
          (path) async => http.Response('', 404),
          record: requested.add,
        ),
      },
    );

    await tester.ensureVisible(find.text('Fetch & Import from Lichess'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fetch & Import from Lichess'));
    await tester.pump();

    expect(
      find.text('Please enter a Lichess study URL or study ID'),
      findsOneWidget,
      reason: 'an empty URL must be refused as an empty input, not as an invalid one',
    );
    expect(requested, isEmpty, reason: 'nothing may be fetched for an empty URL');
  });

  testWidgets('a URL that is not a Lichess study is refused before anything is fetched', (
    tester,
  ) async {
    // SPEC INV-011.
    final requested = <String>[];
    await openImportDialog(
      tester,
      overrides: {
        lichess_study.studyRepositoryProvider: lichessRepositoryAnswering(
          (path) async => http.Response('', 404),
          record: requested.add,
        ),
      },
    );

    await tester.ensureVisible(find.text('Fetch & Import from Lichess'));
    await tester.pumpAndSettle();
    await tester.enterText(
      fieldLabelled('Lichess Study URL or ID'),
      'https://example.com/not-a-study',
    );
    await tester.pump();
    await tester.tap(find.text('Fetch & Import from Lichess'));
    await tester.pump();

    expect(
      find.text('Invalid Lichess study URL or ID. Example: https://lichess.org/study/xxxxxx'),
      findsOneWidget,
      reason: 'a URL without a study id must be refused as an invalid one',
    );
    expect(requested, isEmpty, reason: 'nothing may be fetched for a URL without a study id');
  });

  testWidgets('an empty PGN box is refused before an import is attempted', (tester) async {
    // SPEC INV-011: empty or non-PGN input is refused outright.
    await openImportDialog(tester, source: ImportSource.file);

    await tester.ensureVisible(find.text('Import and Start Review'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import and Start Review'));
    await tester.pump();

    expect(
      find.text('Please enter or select PGN content'),
      findsOneWidget,
      reason: 'an empty PGN box must be refused as an empty input',
    );
  });

  testWidgets('the private-study notice appears only after a signed-out 404', (tester) async {
    // SPEC INV-011: a failed import must be explained, and the explanation must not claim
    // more than it knows. Before anything is attempted the dialog knows nothing about the
    // study, so it must not claim the study may be private; and once it does claim it, the
    // quiet "sign in if this is private" hint has nothing left to add.
    const notice =
        'Lichess answers the same for a private study as for one that does not exist. '
        'Sign in to tell the two apart.';
    const hint = 'Importing a private study? Sign in';

    final gate = Completer<http.Response>();
    await openImportDialog(
      tester,
      overrides: {
        lichess_study.studyRepositoryProvider: lichessRepositoryAnswering((path) => gate.future),
      },
    );

    expect(
      find.text(notice),
      findsNothing,
      reason: 'nothing has been attempted yet, so nothing may be claimed about the study',
    );
    expect(find.text(hint), findsOneWidget, reason: 'the quiet sign-in hint is the resting state');

    await tester.ensureVisible(find.text('Fetch & Import from Lichess'));
    await tester.pumpAndSettle();
    await tester.enterText(
      fieldLabelled('Lichess Study URL or ID'),
      'https://lichess.org/study/abcd1234',
    );
    await tester.pump();
    await tester.tap(find.text('Fetch & Import from Lichess'));
    await tester.pump();

    expect(
      find.text(notice),
      findsNothing,
      reason: 'a fetch that is still running has not failed yet, so it may not claim it has',
    );

    gate.complete(http.Response('', 404));
    await tester.pumpAndSettle();

    expect(
      find.text(notice),
      findsOneWidget,
      reason: 'a signed-out 404 is the one case the notice exists for',
    );
    expect(
      find.text(hint),
      findsNothing,
      reason: 'the notice replaces the hint, it does not stack with it',
    );
  });

  testWidgets('the Fetch button is dead while a Lichess fetch is in flight', (tester) async {
    // A fetch that has not come back yet must not be startable a second time.
    final gate = Completer<http.Response>();
    await openImportDialog(
      tester,
      overrides: {
        lichess_study.studyRepositoryProvider: lichessRepositoryAnswering((path) => gate.future),
      },
    );

    await tester.ensureVisible(find.text('Fetch & Import from Lichess'));
    await tester.pumpAndSettle();
    await tester.enterText(
      fieldLabelled('Lichess Study URL or ID'),
      'https://lichess.org/study/abcd1234',
    );
    await tester.pump();
    await tester.tap(find.text('Fetch & Import from Lichess'));
    await tester.pump();

    expect(
      find.text('Fetching from Lichess...'),
      findsOneWidget,
      reason: 'the button must say that it is working',
    );
    final fetch = tester.widget<ButtonStyleButton>(
      find
          .ancestor(
            of: find.text('Fetching from Lichess...'),
            matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
          )
          .first,
    );
    expect(fetch.onPressed, isNull, reason: 'the Fetch button must be dead while it fetches');

    gate.complete(http.Response('', 404));
    await tester.pumpAndSettle();
  });

  testWidgets('the Fetch button comes back after a failed fetch', (tester) async {
    // SPEC INV-011: a failed import leaves the dialog usable.
    await openImportDialog(
      tester,
      overrides: {
        isLoggedInProvider: isLoggedInProvider.overrideWith((ref) => true),
        lichess_study.studyRepositoryProvider: lichessRepositoryAnswering(
          (path) async => http.Response('', 404),
        ),
      },
    );

    await tester.ensureVisible(find.text('Fetch & Import from Lichess'));
    await tester.pumpAndSettle();
    await tester.enterText(
      fieldLabelled('Lichess Study URL or ID'),
      'https://lichess.org/study/abcd1234',
    );
    await tester.pump();
    await tester.tap(find.text('Fetch & Import from Lichess'));
    // Bounded, not pumpAndSettle: a fetch that never finishes leaves the button's
    // spinner animating forever, and waiting for that to settle would wait forever.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(
      find.text('Fetch & Import from Lichess'),
      findsOneWidget,
      reason: 'the Fetch button must be back to its resting label once the import is over',
    );
    final fetch = tester.widget<ButtonStyleButton>(
      find
          .ancestor(
            of: find.text('Fetch & Import from Lichess'),
            matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
          )
          .first,
    );
    expect(
      fetch.onPressed,
      isNotNull,
      reason: 'the Fetch button must be usable again once the failed import is over',
    );
  });

  testWidgets('a PGN with a bad move reports what it skipped', (tester) async {
    // SPEC INV-011: an illegal move yields a typed error naming the chapter, and the
    // player is told about it — a partial import must not look like a complete one.
    await openImportDialog(tester, source: ImportSource.file);

    await tester.ensureVisible(find.text('Import and Start Review'));
    await tester.pumpAndSettle();
    await tester.enterText(fieldLabelled('PGN text'), '1. e4 e5 2. Nf3 Qxh8 *');
    await tester.pump();
    await tester.tap(find.text('Import and Start Review'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('problem(s) in 1 chapter(s)'),
      findsOneWidget,
      reason: 'a skipped position must be counted and named in the report',
    );
  });

  testWidgets('the title the player typed is the title of the imported repertoire', (tester) async {
    // SPEC INV-014: a re-imported repertoire keeps the names the player gave it.
    await openImportDialog(tester, source: ImportSource.file);

    await tester.ensureVisible(find.text('Import and Start Review'));
    await tester.pumpAndSettle();
    await tester.enterText(fieldLabelled('Study Title (optional)'), 'My French Defense');
    await tester.enterText(fieldLabelled('PGN text'), '1. e4 e5 2. Nf3 Nc6 *');
    await tester.pump();
    await tester.tap(find.text('Import and Start Review'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('My French Defense'),
      findsOneWidget,
      reason: 'the title the player typed must reach the imported repertoire',
    );
  });

  /// A Lichess study repository that serves a study listing and per-study PGN bodies.
  ///
  /// The listing is NDJSON, one study per line, exactly as the studies API answers it.
  Override lichessRepositoryServing({
    required String listing,
    Map<String, String> pgns = const {},
    Future<http.Response> Function(String id)? studyAnswer,
  }) {
    return lichess_study.studyRepositoryProvider.overrideWith(
      (ref) => lichess_study.StudyRepository(
        ref,
        MockClient((request) {
          final path = request.url.path;
          if (path.startsWith('/api/study/by/')) {
            return Future.value(http.Response(listing, 200));
          }
          final id = path.replaceFirst('/api/study/', '').replaceFirst('.pgn', '');
          if (studyAnswer != null) return studyAnswer(id);
          return Future.value(http.Response(pgns[id] ?? '', 200));
        }),
      ),
    );
  }

  /// Signs the test account in, which is what makes the bulk-import controls appear.
  Future<void> signIn(WidgetTester tester) async {
    ProviderScope.containerOf(
      tester.element(find.byType(RepertoireImportDialog)),
    ).read(authControllerProvider.notifier).state = const AuthUser(
      token: 'test-token',
      user: LightUser(id: UserId('tester'), name: 'tester'),
    );
    await tester.pumpAndSettle();
  }

  /// The button carrying [label], whether or not it is the one currently shown.
  ButtonStyleButton buttonWithText(WidgetTester tester, String label) =>
      tester.widget<ButtonStyleButton>(
        find
            .ancestor(
              of: find.text(label),
              matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
            )
            .first,
      );

  testWidgets('the bulk button is dead and says it is listing while the study list loads', (
    tester,
  ) async {
    final gate = Completer<http.Response>();
    await openImportDialog(
      tester,
      overrides: {
        isLoggedInProvider: isLoggedInProvider.overrideWith((ref) => true),
        lichess_study.studyRepositoryProvider: lichessRepositoryAnswering((path) => gate.future),
      },
    );
    await signIn(tester);

    await tester.ensureVisible(find.text('Import all my studies'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import all my studies'));
    await tester.pump();

    expect(
      find.text('Listing your studies…'),
      findsOneWidget,
      reason: 'the button must say that it is still listing the account',
    );
    expect(
      buttonWithText(tester, 'Listing your studies…').onPressed,
      isNull,
      reason: 'the bulk button must be dead while the bulk import runs',
    );

    gate.complete(http.Response('', 200));
    await tester.pumpAndSettle();
  });

  testWidgets('the bulk button is dead while a single import runs', (tester) async {
    // A bulk import on top of a single import would fetch and store the same material twice.
    final gate = Completer<http.Response>();
    await openImportDialog(
      tester,
      overrides: {
        isLoggedInProvider: isLoggedInProvider.overrideWith((ref) => true),
        lichess_study.studyRepositoryProvider: lichessRepositoryAnswering((path) => gate.future),
      },
    );
    await signIn(tester);

    await tester.ensureVisible(find.text('Fetch & Import from Lichess'));
    await tester.pumpAndSettle();
    await tester.enterText(
      fieldLabelled('Lichess Study URL or ID'),
      'https://lichess.org/study/abcd1234',
    );
    await tester.pump();
    await tester.tap(find.text('Fetch & Import from Lichess'));
    await tester.pump();

    expect(
      buttonWithText(tester, 'Import all my studies').onPressed,
      isNull,
      reason: 'the bulk button must be dead while a single import runs',
    );

    gate.complete(http.Response('', 404));
    await tester.pumpAndSettle();
  });

  testWidgets('a bulk import that finds nothing says so and leaves the button usable', (
    tester,
  ) async {
    await openImportDialog(
      tester,
      overrides: {
        isLoggedInProvider: isLoggedInProvider.overrideWith((ref) => true),
        lichess_study.studyRepositoryProvider: lichessRepositoryServing(listing: ''),
      },
    );
    await signIn(tester);

    await tester.ensureVisible(find.text('Import all my studies'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import all my studies'));
    // Bounded, not pumpAndSettle: a bulk import that never finishes leaves the button's
    // spinner animating forever, and waiting for that to settle would wait forever.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(
      find.textContaining('No studies found on your Lichess account'),
      findsWidgets,
      reason: 'an account with no studies must be reported as such, not as an empty import',
    );
    expect(
      find.text('Import all my studies'),
      findsOneWidget,
      reason: 'the bulk button must be back to its resting label once the import is over',
    );
    expect(
      buttonWithText(tester, 'Import all my studies').onPressed,
      isNotNull,
      reason: 'the bulk button must be usable again once the bulk import is over',
    );
  });

  testWidgets('a bulk import that imports one study reports one import and no duplicates', (
    tester,
  ) async {
    await openImportDialog(
      tester,
      overrides: {
        isLoggedInProvider: isLoggedInProvider.overrideWith((ref) => true),
        lichess_study.studyRepositoryProvider: lichessRepositoryServing(
          listing: '{"id":"aaaaaaaa","name":"Only","updatedAt":1000}',
          pgns: {'aaaaaaaa': '1. e4 e5 2. Nf3 Nc6 *'},
        ),
      },
    );
    await signIn(tester);

    await tester.ensureVisible(find.text('Import all my studies'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import all my studies'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('1 imported'),
      findsWidgets,
      reason: 'the summary must count what was imported',
    );
    expect(
      find.textContaining('already here'),
      findsNothing,
      reason: 'nothing was already here, so nothing may be reported as already here',
    );
  });

  testWidgets('a bulk import reports the studies it skipped and the ones it could not read', (
    tester,
  ) async {
    // SPEC INV-011: what was skipped has to be named, and the counts must be right.
    final seeded = importPgn('1. e4 e5 2. Nf3 Nc6 *', studyTitle: 'Seeded');
    await repo.saveImportResult(seeded);

    const duplicatePgn = '1. e4 e5 2. Nf3 Nc6 *';
    final listing = [
      '{"id":"dup11111","name":"Dup one","updatedAt":1000}',
      '{"id":"dup22222","name":"Dup two","updatedAt":1000}',
      '{"id":"dup33333","name":"Dup three","updatedAt":1000}',
      '{"id":"bad11111","name":"Bad one","updatedAt":1000}',
      '{"id":"bad22222","name":"Bad two","updatedAt":1000}',
      '{"id":"bad33333","name":"Bad three","updatedAt":1000}',
    ].join('\n');

    await openImportDialog(
      tester,
      overrides: {
        isLoggedInProvider: isLoggedInProvider.overrideWith((ref) => true),
        lichess_study.studyRepositoryProvider: lichessRepositoryServing(
          listing: listing,
          pgns: {'dup11111': duplicatePgn, 'dup22222': duplicatePgn, 'dup33333': duplicatePgn},
        ),
      },
    );
    await signIn(tester);

    await tester.ensureVisible(find.text('Import all my studies'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import all my studies'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('3 already here (Seeded, Seeded, Seeded)'),
      findsWidgets,
      reason: 'the studies that were already stored must be counted and named',
    );
    expect(
      find.textContaining('3 failed (Bad one, Bad two, Bad three)'),
      findsWidgets,
      reason: 'the studies that could not be read must be counted and named',
    );
    expect(
      find.textContaining('and 0 more'),
      findsNothing,
      reason: 'three names fit in the summary, so no overflow may be announced',
    );
  });

  testWidgets('a Lichess URL typed in the PGN box is fetched from Lichess', (tester) async {
    final requested = <String>[];
    await openImportDialog(
      tester,
      source: ImportSource.file,
      overrides: {
        lichess_study.studyRepositoryProvider: lichessRepositoryAnswering(
          (path) async => http.Response('1. e4 e5 2. Nf3 Nc6 *', 200),
          record: requested.add,
        ),
      },
    );

    await tester.ensureVisible(find.text('Import and Start Review'));
    await tester.pumpAndSettle();
    await tester.enterText(fieldLabelled('PGN text'), 'https://lichess.org/study/abcd1234');
    await tester.pump();
    await tester.tap(find.text('Import and Start Review'));
    await tester.pumpAndSettle();

    expect(
      requested.any((path) => path.contains('/api/study/abcd1234.pgn')),
      isTrue,
      reason: 'a study id in the PGN box is a request for that study',
    );
  });

  testWidgets('a PGN that mentions a study URL is still imported as PGN', (tester) async {
    // The PGN box holds PGN. A URL inside it is a comment, not an instruction.
    final requested = <String>[];
    await openImportDialog(
      tester,
      source: ImportSource.file,
      overrides: {
        lichess_study.studyRepositoryProvider: lichessRepositoryAnswering(
          (path) async => http.Response('1. e4 e5 2. Nf3 Nc6 *', 200),
          record: requested.add,
        ),
      },
    );

    await tester.ensureVisible(find.text('Import and Start Review'));
    await tester.pumpAndSettle();
    await tester.enterText(
      fieldLabelled('PGN text'),
      '1. e4 e5 2. Nf3 Nc6 * { see https://lichess.org/study/abcd1234 }',
    );
    await tester.pump();
    await tester.tap(find.text('Import and Start Review'));
    await tester.pumpAndSettle();

    expect(
      requested.any((path) => path.contains('/api/study/abcd1234.pgn')),
      isFalse,
      reason: 'a PGN with moves is a PGN, whatever it mentions',
    );
    expect(
      find.textContaining('Imported'),
      findsWidgets,
      reason: 'the PGN must be imported rather than fetched',
    );
  });

  testWidgets('the picked file supplies the PGN and the title', (tester) async {
    // SPEC INV-014: the file the player picked is the repertoire, and its name is the
    // title until they type one of their own.
    final dir = io.Directory.systemTemp.createTempSync('repertoire_import_pick');
    addTearDown(() => dir.deleteSync(recursive: true));
    final pgnFile = io.File('${dir.path}/BOOK.PGN')
      ..writeAsStringSync('[Event "Book"]\n\n1. e4 e5 *');

    await openImportDialog(
      tester,
      source: ImportSource.file,
      overrides: {
        pickPgnFileProvider: pickPgnFileProvider.overrideWithValue(
          () async => _RealFilePlatformFile(pgnFile),
        ),
      },
    );

    await tester.ensureVisible(find.text('Pick .pgn file from disk'));
    await tester.pumpAndSettle();

    final pgnField = tester.widget<TextField>(fieldLabelled('PGN text'));
    final titleField = tester.widget<TextField>(fieldLabelled('Study Title (optional)'));

    // The dialog reads the file for real, and a real read completes on the real event
    // loop, which the fake-async zone the widget test runs in never sees. Polled rather
    // than slept on, so the test waits for the read instead of for a guess.
    await tester.runAsync(() async {
      await tester.tap(find.text('Pick .pgn file from disk'));
      for (var i = 0; i < 200 && pgnField.controller!.text.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });
    await tester.pumpAndSettle();

    expect(
      pgnField.controller!.text,
      '[Event "Book"]\n\n1. e4 e5 *',
      reason: 'the picked file supplies the PGN',
    );
    expect(
      titleField.controller!.text,
      'BOOK',
      reason: 'the picked file supplies the title, and its extension is not part of it',
    );
  });

  testWidgets('a title typed for a Lichess study is the title it is stored under', (tester) async {
    // SPEC INV-014: the name the player gave the repertoire survives the import.
    await openImportDialog(
      tester,
      overrides: {
        lichess_study.studyRepositoryProvider: lichessRepositoryAnswering(
          (path) async =>
              http.Response('[StudyName "French Defence"]\n\n1. e4 e5 2. Nf3 Nc6 *', 200),
        ),
      },
    );

    await tester.ensureVisible(find.text('Fetch & Import from Lichess'));
    await tester.pumpAndSettle();
    await tester.enterText(fieldLabelled('Study Title (optional)'), 'My Own Name');
    await tester.enterText(
      fieldLabelled('Lichess Study URL or ID'),
      'https://lichess.org/study/abcd1234',
    );
    await tester.pump();
    await tester.tap(find.text('Fetch & Import from Lichess'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('My Own Name'),
      findsWidgets,
      reason: 'the title the player typed must win over the one in the study header',
    );
  });

  testWidgets('a Lichess study with a bad move reports what it skipped', (tester) async {
    // SPEC INV-011: the same contract as the PGN path — a skipped position is reported.
    await openImportDialog(
      tester,
      overrides: {
        lichess_study.studyRepositoryProvider: lichessRepositoryAnswering(
          (path) async => http.Response('1. e4 e5 2. Nf3 Qxh8 *', 200),
        ),
      },
    );

    await tester.ensureVisible(find.text('Fetch & Import from Lichess'));
    await tester.pumpAndSettle();
    await tester.enterText(
      fieldLabelled('Lichess Study URL or ID'),
      'https://lichess.org/study/abcd1234',
    );
    await tester.pump();
    await tester.tap(find.text('Fetch & Import from Lichess'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('problem(s) in 1 chapter(s)'),
      findsWidgets,
      reason: 'a skipped position must be counted and named in the report',
    );
  });

  testWidgets('the paste button fills the Lichess URL field', (tester) async {
    await openImportDialog(tester);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
      call,
    ) async {
      if (call.method == 'Clipboard.getData') {
        return <String, dynamic>{'text': 'https://lichess.org/study/abcd1234'};
      }
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.ensureVisible(find.text('Fetch & Import from Lichess'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Paste from clipboard'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(fieldLabelled('Lichess Study URL or ID')).controller!.text,
      'https://lichess.org/study/abcd1234',
      reason: 'the paste button must put the clipboard into the URL field',
    );
  });

  testWidgets('signing in does not fetch a study that was never asked for', (tester) async {
    // The dialog resumes an import after a sign-in only when a signed-out 404 asked for
    // one. Signing in for any other reason must not start a fetch.
    final requested = <String>[];
    await openImportDialog(
      tester,
      overrides: {
        lichess_study.studyRepositoryProvider: lichessRepositoryAnswering(
          (path) async => http.Response('', 404),
          record: requested.add,
        ),
      },
    );

    await tester.ensureVisible(find.text('Fetch & Import from Lichess'));
    await tester.pumpAndSettle();
    await tester.enterText(
      fieldLabelled('Lichess Study URL or ID'),
      'https://lichess.org/study/abcd1234',
    );
    await tester.pump();

    ProviderScope.containerOf(
      tester.element(find.byType(RepertoireImportDialog)),
    ).read(authControllerProvider.notifier).state = const AuthUser(
      token: 'test-token',
      user: LightUser(id: UserId('tester'), name: 'tester'),
    );
    await tester.pumpAndSettle();

    expect(requested, isEmpty, reason: 'signing in on its own must not fetch a study');
  });

  testWidgets('the bulk import names the study it is on and drops the name when it is done', (
    tester,
  ) async {
    final gate = Completer<http.Response>();
    await openImportDialog(
      tester,
      overrides: {
        isLoggedInProvider: isLoggedInProvider.overrideWith((ref) => true),
        lichess_study.studyRepositoryProvider: lichessRepositoryServing(
          listing: '{"id":"aaaaaaaa","name":"Stalled","updatedAt":1000}',
          studyAnswer: (id) => gate.future,
        ),
      },
    );
    await signIn(tester);

    await tester.ensureVisible(find.text('Import all my studies'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import all my studies'));
    // No pumpAndSettle here: the bulk button's progress spinner animates forever while
    // the study fetch is outstanding.
    await tester.pump();
    await tester.pump();

    // The listing is answered, the study fetch is not: the dialog sits on that study.
    expect(
      find.text('Stalled'),
      findsOneWidget,
      reason: 'the bulk import must say which study it is working on',
    );

    gate.complete(http.Response('1. e4 e5 2. Nf3 Nc6 *', 200));
    await tester.pumpAndSettle();

    expect(
      find.text('Stalled'),
      findsNothing,
      reason: 'the name of the last study must not stay on screen after the import',
    );
  });

  testWidgets('the PGN import button comes back after a failed import', (tester) async {
    // SPEC INV-011: a failed import leaves the dialog usable.
    await openImportDialog(tester, source: ImportSource.file);

    await tester.ensureVisible(find.text('Import and Start Review'));
    await tester.pumpAndSettle();
    await tester.enterText(fieldLabelled('PGN text'), 'this is not a pgn');
    await tester.pump();
    await tester.tap(find.text('Import and Start Review'));
    // Bounded, not pumpAndSettle: an import that never finishes leaves the button's
    // spinner animating forever, and waiting for that to settle would wait forever.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(
      find.text('Import and Start Review'),
      findsOneWidget,
      reason: 'the import button must be back to its resting label once the import is over',
    );
    expect(
      buttonWithText(tester, 'Import and Start Review').onPressed,
      isNotNull,
      reason: 'the import button must be usable again once the failed import is over',
    );
  });

  testWidgets('a clipboard read that answers after the dismissal does not crash the dialog', (
    tester,
  ) async {
    // The same hazard as the file picker: the clipboard read can land after the dialog
    // is gone, and the continuation must not touch the disposed State.
    final gate = Completer<String?>();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
      call,
    ) async {
      if (call.method == 'Clipboard.getData') {
        return <String, dynamic>{'text': await gate.future};
      }
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await openImportDialog(tester);
    await tester.ensureVisible(find.text('Fetch & Import from Lichess'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Paste from clipboard'));
    await tester.pump();

    Navigator.of(tester.element(find.byType(RepertoireImportDialog))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(RepertoireImportDialog), findsNothing);

    gate.complete('https://lichess.org/study/abcd1234');
    await tester.pump();
    await tester.pump();

    expect(
      tester.takeException(),
      isNull,
      reason:
          'a clipboard read that lands after the dismissal must not setState on a disposed State',
    );
  });

  testWidgets('signing in resumes the import a private study asked for', (tester) async {
    // The dialog's reason for offering sign-in at all: a signed-out 404 may be a private
    // study, and signing in is how the two are told apart — so the import continues.
    final requested = <String>[];
    await openImportDialog(
      tester,
      overrides: {
        lichess_study.studyRepositoryProvider: lichessRepositoryAnswering(
          (path) async => http.Response('', 404),
          record: requested.add,
        ),
      },
    );

    await tester.ensureVisible(find.text('Fetch & Import from Lichess'));
    await tester.pumpAndSettle();
    await tester.enterText(
      fieldLabelled('Lichess Study URL or ID'),
      'https://lichess.org/study/abcd1234',
    );
    await tester.pump();
    await tester.tap(find.text('Fetch & Import from Lichess'));
    await tester.pumpAndSettle();

    expect(requested.length, 1, reason: 'the first fetch happened and was refused');

    ProviderScope.containerOf(
      tester.element(find.byType(RepertoireImportDialog)),
    ).read(authControllerProvider.notifier).state = const AuthUser(
      token: 'test-token',
      user: LightUser(id: UserId('tester'), name: 'tester'),
    );
    await tester.pumpAndSettle();

    expect(
      requested.length,
      2,
      reason: 'signing in must resume the import the private study asked for',
    );
  });

  testWidgets('a file picked after the dialog is dismissed does not crash the disposed dialog', (
    tester,
  ) async {
    // The native picker can outlive the dialog: the user closes the dialog while the picker is
    // still open, and the picker still returns a file afterwards. The continuation then ran on
    // a disposed State — it read the file and called setState, which threw "setState() called
    // after dispose()". The picker is held open until after the dismissal so the ordering is
    // deterministic instead of a race.
    final dir = io.Directory.systemTemp.createTempSync('repertoire_import_guard');
    addTearDown(() => dir.deleteSync(recursive: true));
    final pgnFile = io.File('${dir.path}/book.pgn')
      ..writeAsStringSync('[Event "Book"]\n\n1. e4 e5 *');

    final picked = Completer<PlatformFile?>();
    await openImportDialog(
      tester,
      source: ImportSource.file,
      overrides: {pickPgnFileProvider: pickPgnFileProvider.overrideWithValue(() => picked.future)},
    );

    await tester.ensureVisible(find.text('Pick .pgn file from disk'));
    await tester.pumpAndSettle();
    // Tapped inside a real async window for a mechanical reason, not a stylistic one: this
    // registers `_pickPgnFile`'s awaits in real async time. The continuation reaches a real
    // file read, and a read started from the fake-async zone never completes — which is how
    // this test first passed against the unfixed code. Do not "simplify" the runAsync away.
    await tester.runAsync(() async {
      await tester.tap(find.text('Pick .pgn file from disk'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });

    // Dismissed while the picker is open, the way the close affordance does it.
    Navigator.of(tester.element(find.byType(RepertoireImportDialog))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(RepertoireImportDialog), findsNothing);

    // The picker returns after the dismissal. Unfixed, the continuation reads the file and
    // calls setState on the disposed State: "setState() called after dispose()". With the
    // guard it returns before either.
    await tester.runAsync(() async {
      picked.complete(_RealFilePlatformFile(pgnFile));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();

    expect(
      tester.takeException(),
      isNull,
      reason: 'a picked file arriving after dismissal must not setState on a disposed State',
    );
  });

  testWidgets('the single-import controls are inert while a bulk import is running', (
    tester,
  ) async {
    // A bulk import can run for minutes. Pressing a single-import control mid-run used to
    // start a second import on top of it.
    final stalled = Completer<http.Response>();
    await openImportDialog(
      tester,
      overrides: {
        isLoggedInProvider: isLoggedInProvider.overrideWith((ref) => true),
        lichess_study.studyRepositoryProvider: lichess_study.studyRepositoryProvider.overrideWith(
          (ref) => lichess_study.StudyRepository(ref, MockClient((_) => stalled.future)),
        ),
      },
    );

    // Bulk import lists /api/study/by/<username>: the login flag alone is not enough, the
    // account itself must be present.
    ProviderScope.containerOf(
      tester.element(find.byType(RepertoireImportDialog)),
    ).read(authControllerProvider.notifier).state = const AuthUser(
      token: 'test-token',
      user: LightUser(id: UserId('tester'), name: 'tester'),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Import all my studies'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import all my studies'));
    // The listing never answers, so the bulk state stays set. No pumpAndSettle here: the bulk
    // button's progress spinner animates forever while it waits.
    await tester.pump();

    ButtonStyleButton buttonLabelled(String label) => tester.widget<ButtonStyleButton>(
      find
          .ancestor(
            of: find.text(label),
            matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
          )
          .first,
    );

    expect(
      buttonLabelled('Fetch & Import from Lichess').onPressed,
      isNull,
      reason: 'the Fetch button must be dead while the bulk import runs',
    );

    await tester.tap(find.text('PGN Text / File'));
    await tester.pump();

    expect(
      buttonLabelled('Import and Start Review').onPressed,
      isNull,
      reason: 'the PGN import button must be dead while the bulk import runs',
    );
    expect(
      buttonLabelled('Pick .pgn file from disk').onPressed,
      isNull,
      reason: 'the file picker must be dead while the bulk import runs',
    );
  });
}
