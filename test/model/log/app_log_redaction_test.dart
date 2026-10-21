// Copyright (C) 2026 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// SPEC INV-006.

import 'package:chess_srs/src/db/database.dart';
import 'package:chess_srs/src/model/log/app_log_storage.dart';
import 'package:chess_srs/src/model/log/http_log_storage.dart';
import 'package:chess_srs/src/network/http.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../binding.dart';
import '../../network/fake_http_client_factory.dart';
import '../../test_container.dart';

void main() {
  late Database db;
  late AppLogStorage storage;

  setUpAll(() {
    TestLichessBinding.ensureInitialized();
    sqfliteFfiInit();
  });

  setUp(() async {
    final previousLevel = Logger.root.level;
    Logger.root.level = Level.ALL;
    addTearDown(() => Logger.root.level = previousLevel);

    db = await databaseFactoryFfiNoIsolate.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    addTearDown(db.close);

    await db.execute('''
      CREATE TABLE app_log(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        logTime TEXT NOT NULL,
        loggerName TEXT NOT NULL,
        levelValue INTEGER NOT NULL,
        levelName TEXT NOT NULL,
        message TEXT NOT NULL,
        error TEXT,
        stackTrace TEXT,
        lastModified TEXT NOT NULL
      )
    ''');
    storage = AppLogStorage(db);
  });

  for (final useLichessClient in [true, false]) {
    final clientName = useLichessClient ? 'LichessClient' : 'DefaultClient';

    test('$clientName transport failure persists no authentication values', () async {
      const email = 'audit-transport-mail+fixture@example.invalid';
      const username = 'audit-transport-username';
      const code = 'A9C6Q2';
      final requestUri = lichessUri('/auth/mobile-code/bearer', {
        'email': email,
        'username': username,
        'code': code,
        'attempt': '2',
        'lang': 'en',
      });

      http.ClientException? injectedException;
      final sentUris = <Uri>[];
      final transport = MockClient((request) {
        sentUris.add(request.url);
        expect(request.method, 'POST');
        injectedException = http.ClientException('offline', request.url);
        throw injectedException!;
      });

      final container = await makeContainer(
        overrides: {
          databaseProvider: databaseProvider.overrideWith((ref) => db),
          httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
            (ref) => FakeHttpClientFactory(() => transport),
          ),
        },
      );
      final http.Client client = useLichessClient
          ? container.read(lichessClientProvider)
          : container.read(defaultClientProvider);

      final records = <LogRecord>[];
      final subscription = Logger.root.onRecord.listen((record) {
        if (record.loggerName == 'HttpClient') records.add(record);
      });
      addTearDown(subscription.cancel);

      await expectLater(
        client.post(requestUri, body: {'email': email, 'username': username, 'code': code}),
        throwsA(
          predicate<http.ClientException>(
            (error) => identical(error, injectedException),
            'the original ClientException injected by the HTTP transport',
          ),
        ),
      );
      await subscription.cancel();

      expect(sentUris, hasLength(1));
      expect(sentUris.single.queryParameters['email'], email);
      expect(sentUris.single.queryParameters['username'], username);
      expect(sentUris.single.queryParameters['code'], code);
      expect(injectedException!.uri, sentUris.single);
      expect(injectedException!.message, 'offline');

      expect(records.any((record) => record.level == Level.INFO), isTrue);
      final warnings = records.where((record) => record.level == Level.WARNING).toList();
      expect(warnings, hasLength(1));

      // Exercise the same conversion and real save boundary as AppLogService, whose background
      // writes are disabled under FLUTTER_TEST. Awaiting saves exposes the actual SQLite bytes.
      for (final record in records) {
        await storage.save(AppLogEntry.fromLogRecord(record));
      }

      final rows = await db.query('app_log', orderBy: 'id ASC');
      expect(rows, hasLength(records.length));
      for (var index = 0; index < rows.length; index++) {
        final row = rows[index];
        expectMetadata(
          row,
          loggerName: 'HttpClient',
          level: records[index].level,
          logTime: records[index].time,
        );
        expectNoSecrets(row, [email, username, code]);
        expectUrlDiagnostics(row['message']! as String, [requestUri]);
      }

      final warningRows = rows.where((row) => row['levelValue'] == Level.WARNING.value);
      expect(warningRows, hasLength(1));
      final warningRow = warningRows.single;
      expect(warningRow['message'], contains('failed'));
      final errorText = warningRow['error']! as String;
      expect(errorText, contains('ClientException'));
      expect(errorText, contains('offline'));
      expectUrlDiagnostics(errorText, [requestUri]);
      expect(
        warningRow['stackTrace'],
        isA<String>().having((text) => text.isNotEmpty, 'nonempty', true),
      );
    });
  }

  for (final useLogRecord in [true, false]) {
    final sourceName = useLogRecord ? 'LogRecord conversion' : 'direct AppLogEntry save';

    test('$sourceName protects every URL in message, error and stackTrace', () async {
      final fields = <String, String>{};
      final originalUris = <String, List<Uri>>{};
      final secrets = <String>[];

      for (final field in ['message', 'error', 'stackTrace']) {
        final email = 'audit-$field-mail@example.invalid';
        final username = 'audit-$field-username';
        final firstCode = 'audit-$field-code-one';
        final secondCode = 'audit-$field-code-two';
        secrets.addAll([email, username, firstCode, secondCode]);

        final uris = [
          Uri.https('lichess.org', '/auth/mobile-code/bearer', {
            'email': email,
            'username': username,
            'code': firstCode,
            'attempt': '1',
            'lang': 'en',
          }),
          Uri.https('lichess.org', '/auth/mobile-code/email', {
            'EMAIL': email,
            'Username': username,
            'Code': [firstCode, secondCode],
            'attempt': '2',
            'lang': 'fr',
          }),
        ];
        originalUris[field] = uris;
        fields[field] = '$field begins (${uris.first})\n$field ends (${uris.last})';
      }

      final error = StateError(fields['error']!);
      final stackTrace = StackTrace.fromString(fields['stackTrace']!);
      final record = LogRecord(
        Level.SEVERE,
        fields['message']!,
        'RedactionBoundary',
        error,
        stackTrace,
      );
      final fixedTime = DateTime.utc(2026, 10, 21, 12);
      final entry = useLogRecord
          ? AppLogEntry.fromLogRecord(record)
          : AppLogEntry(
              logTime: fixedTime,
              loggerName: 'RedactionBoundary',
              levelValue: Level.SEVERE.value,
              levelName: 'SEVERE',
              message: fields['message']!,
              error: error.toString(),
              stackTrace: stackTrace.toString(),
            );

      await storage.save(entry);

      final rows = await db.query('app_log');
      expect(rows, hasLength(1));
      final row = rows.single;
      expectMetadata(
        row,
        loggerName: 'RedactionBoundary',
        level: Level.SEVERE,
        logTime: useLogRecord ? record.time : fixedTime,
      );
      expectNoSecrets(row, secrets);

      for (final field in ['message', 'error', 'stackTrace']) {
        final text = row[field]! as String;
        expect(text, contains('$field begins'));
        expect(text, contains('$field ends'));
        expectUrlDiagnostics(text, originalUris[field]!);
      }
      expect(row['error'], contains('Bad state:'));
    });
  }

  test('adjacent URLs, quoted values and a repeated placeholder cannot hide credentials', () async {
    const email = 'audit-framing@example.invalid';
    const username = 'audit-framing-user';
    const code = 'audit-framing-code';
    final encodedEmail = Uri.encodeQueryComponent(email);
    const route = 'https://lichess.org/auth/mobile-code/email';
    const diagnosticQuery = 'username=$username&code=$code&attempt=2&lang=en';
    final queries = [
      '(https://lichess.org/a?lang=en),($route?email=$encodedEmail&$diagnosticQuery)',
      "ClientException: offline, uri=$route?email='$encodedEmail'&$diagnosticQuery",
      '$route?email=$encodedEmail&email=***&$diagnosticQuery',
    ];
    for (final error in queries) {
      await storage.save(
        AppLogEntry(
          logTime: DateTime.utc(2026, 10, 21, 12),
          loggerName: 'HttpClient',
          levelValue: Level.WARNING.value,
          levelName: 'WARNING',
          message: 'Request failed',
          error: error,
        ),
      );
    }
    final rows = await db.query('app_log', orderBy: 'id ASC');
    expect(rows, hasLength(queries.length));
    for (final row in rows) {
      expectNoSecrets(row, [email, username, code]);
      expect(row['error'], contains(route));
      expect(row['error'], contains('attempt=2'));
      expect(row['error'], contains('lang=en'));
    }
    expect(rows.first['error'], startsWith('(https://lichess.org/a?lang=en),('));
    final repeated = Uri.parse(rows.last['error']! as String);
    expect(repeated.queryParametersAll['email'], hasLength(2));
  });

  test('HTTP log inserts and error updates redact the stored payloads', () async {
    await db.execute('''
      CREATE TABLE http_log(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        httpLogId TEXT NOT NULL UNIQUE,
        requestDateTime TEXT NOT NULL,
        requestMethod TEXT NOT NULL,
        requestUrl TEXT NOT NULL,
        responseCode INTEGER,
        responseDateTime TEXT,
        lastModified TEXT NOT NULL,
        errorMessage TEXT
      )
    ''');
    const email = 'audit-http-mail@example.invalid';
    const username = 'audit-http-username';
    const code = 'audit-http-code';
    final uri = Uri.https('lichess.org', '/auth/mobile-code/bearer', {
      'email': email,
      'username': username,
      'code': code,
      'attempt': '2',
      'lang': 'en',
    });
    final httpStorage = HttpLogStorage(db);
    final stamp = DateTime.utc(2026, 10, 21, 12);

    await httpStorage.save(
      HttpLogEntry(
        httpLogId: 'request-1',
        requestDateTime: stamp,
        requestMethod: 'POST',
        requestUrl: uri,
        errorMessage: http.ClientException('offline', uri).toString(),
      ),
    );
    final inserted = (await db.query('http_log')).single;
    expectNoSecrets(inserted, [email, username, code]);
    expect(inserted['httpLogId'], 'request-1');
    expect(inserted['requestMethod'], 'POST');
    expect(inserted['requestDateTime'], stamp.toIso8601String());
    expectUrlDiagnostics(inserted['requestUrl']! as String, [uri]);
    expectUrlDiagnostics(inserted['errorMessage']! as String, [uri]);
    expect(inserted['errorMessage'], contains('offline'));

    const updatedCode = 'audit-http-updated-code';
    const updatedEmail = 'audit-http-updated-mail@example.invalid';
    final updatedUri = uri.replace(
      queryParameters: {...uri.queryParameters, 'email': updatedEmail, 'code': updatedCode},
    );
    await httpStorage.updateWithError(
      'request-1',
      errorMessage: http.ClientException('retry failed', updatedUri).toString(),
    );
    final updated = (await db.query('http_log')).single;
    expectNoSecrets(updated, [email, updatedEmail, username, code, updatedCode]);
    expect(updated['responseCode'], 0);
    expect(updated['requestUrl'], inserted['requestUrl']);
    expect(updated['errorMessage'], contains('retry failed'));
    expectUrlDiagnostics(updated['errorMessage']! as String, [updatedUri]);
  });

  test('ordinary diagnostics and absent optional fields survive unchanged', () async {
    const message = 'Loaded 3 chapters; next operation is review';
    const diagnosticMessage =
        'GET https://lichess.org/api/study?attempt=2&lang=en failed during refresh';
    const errorMessage = 'SQLite busy during chapter refresh';
    const stackText = '#0 refreshChapter (package:chess_srs/refresh.dart:12:3)';

    final ordinary = LogRecord(Level.INFO, message, 'StudyRepository');
    final diagnostic = LogRecord(
      Level.WARNING,
      diagnosticMessage,
      'StudyRepository',
      StateError(errorMessage),
      StackTrace.fromString(stackText),
    );

    await storage.save(AppLogEntry.fromLogRecord(ordinary));
    await storage.save(AppLogEntry.fromLogRecord(diagnostic));

    final rows = await db.query('app_log', orderBy: 'id ASC');
    expect(rows, hasLength(2));
    expectMetadata(
      rows.first,
      loggerName: 'StudyRepository',
      level: Level.INFO,
      logTime: ordinary.time,
    );
    expect(rows.first['message'], message);
    expect(rows.first['error'], isNull);
    expect(rows.first['stackTrace'], isNull);

    expectMetadata(
      rows.last,
      loggerName: 'StudyRepository',
      level: Level.WARNING,
      logTime: diagnostic.time,
    );
    expect(rows.last['message'], diagnosticMessage);
    expect(rows.last['error'], 'Bad state: $errorMessage');
    expect(rows.last['stackTrace'], stackText);
  });
}

void expectMetadata(
  Map<String, Object?> row, {
  required String loggerName,
  required Level level,
  required DateTime logTime,
}) {
  expect(row['id'], isA<int>());
  expect(row['loggerName'], loggerName);
  expect(row['levelValue'], level.value);
  expect(row['levelName'], level.name);
  expect(row['logTime'], logTime.toIso8601String());
  expect(row['lastModified'], isA<String>());
}

void expectNoSecrets(Map<String, Object?> row, Iterable<String> secrets) {
  final persistedText = row.values.whereType<String>().join('\n').toLowerCase();
  for (final secret in secrets) {
    for (final representation in {
      secret,
      Uri.encodeComponent(secret),
      Uri.encodeQueryComponent(secret),
      if (secret.contains('@')) secret.split('@').first,
    }) {
      expect(
        persistedText,
        isNot(contains(representation.toLowerCase())),
        reason: 'raw SQLite row must not contain authentication value $representation',
      );
    }
  }
}

void expectUrlDiagnostics(String text, List<Uri> originalUris) {
  // Parse independently of the production redaction helper; blanking everything must fail.
  final persistedUris = RegExp(
    r'https?://[^\s)]+',
  ).allMatches(text).map((match) => Uri.parse(match.group(0)!)).toList();

  expect(persistedUris, hasLength(originalUris.length));
  for (var index = 0; index < originalUris.length; index++) {
    final persisted = persistedUris[index];
    final original = originalUris[index];
    expect(persisted.scheme, original.scheme);
    expect(persisted.host, original.host);
    expect(persisted.path, original.path);
    for (final parameter in ['attempt', 'lang']) {
      expect(persisted.queryParameters[parameter], original.queryParameters[parameter]);
    }
  }
}
