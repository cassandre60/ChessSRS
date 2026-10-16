// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:chess_srs/src/model/auth/auth_controller.dart';
import 'package:chess_srs/src/model/common/id.dart';
import 'package:chess_srs/src/model/study/study_repository.dart' as lichess_study;
import 'package:chess_srs/src/model/user/user.dart';
import 'package:chess_srs/src/view/more/import_pgn_screen.dart';
import 'package:chess_srs/src/view/review/repertoire_import_dialog.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override, ProviderOrFamily;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

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
      overrides: overrides,
    );
    await tester.pumpWidget(app);
    await tester.tap(find.text('open the import dialog'));
    await tester.pumpAndSettle();
  }

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
    await tester.tap(find.text('Pick .pgn file from disk'));
    await tester.pump();

    // Dismissed while the picker is open, the way the close affordance does it.
    Navigator.of(tester.element(find.byType(RepertoireImportDialog))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(RepertoireImportDialog), findsNothing);

    // The picker returns after the dismissal. The file read is real IO, so it needs a real
    // async window to complete; the pumps in between let the awaiting continuations run.
    await tester.runAsync(() async {
      picked.complete(_RealFilePlatformFile(pgnFile));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
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
