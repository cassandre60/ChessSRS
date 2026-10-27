// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/import/lichess_study_importer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('extractLichessStudyId', () {
    test('extracts ID from full HTTPS URL', () {
      expect(extractLichessStudyId('https://lichess.org/study/m1AbCd2E'), 'm1AbCd2E');
    });

    test('extracts ID from HTTPS URL with chapter ID', () {
      expect(extractLichessStudyId('https://lichess.org/study/m1AbCd2E/xYzW9876'), 'm1AbCd2E');
    });

    test('extracts ID from HTTP URL', () {
      expect(extractLichessStudyId('http://lichess.org/study/m1AbCd2E'), 'm1AbCd2E');
    });

    test('extracts ID from URL with www', () {
      expect(extractLichessStudyId('https://www.lichess.org/study/m1AbCd2E'), 'm1AbCd2E');
    });

    test('extracts ID from scheme-less URL', () {
      expect(extractLichessStudyId('lichess.org/study/m1AbCd2E'), 'm1AbCd2E');
    });

    test('extracts ID from URL with query parameters or fragments', () {
      expect(
        extractLichessStudyId('https://lichess.org/study/m1AbCd2E?tab=comments#ch1'),
        'm1AbCd2E',
      );
    });

    test('extracts ID from raw 8-character string with whitespace', () {
      expect(extractLichessStudyId('  m1AbCd2E  '), 'm1AbCd2E');
    });

    test('returns null for non-study URLs and invalid strings', () {
      expect(extractLichessStudyId('https://lichess.org/training/12345'), isNull);
      expect(extractLichessStudyId('https://lichess.org/forum'), isNull);
      expect(extractLichessStudyId('1. e4 e5 2. Nf3'), isNull);
      expect(extractLichessStudyId('shortId'), isNull);
      expect(extractLichessStudyId('toolongstudyidentifier'), isNull);
      expect(extractLichessStudyId(''), isNull);
      expect(extractLichessStudyId('   '), isNull);
    });
  });

  group('parseLichessStudyReference', () {
    test('parses full URL into id and host', () {
      final ref = parseLichessStudyReference('https://lichess.org/study/Jj55P1Sv');
      expect(ref?.id, 'Jj55P1Sv');
      expect(ref?.host, 'lichess.org');
    });

    test('parses dev URL into id and dev host', () {
      final ref = parseLichessStudyReference('https://lichess.dev/study/Jj55P1Sv');
      expect(ref?.id, 'Jj55P1Sv');
      expect(ref?.host, 'lichess.dev');
    });

    test('parses raw 8-character ID defaulting to lichess.org', () {
      final ref = parseLichessStudyReference('Jj55P1Sv');
      expect(ref?.id, 'Jj55P1Sv');
      expect(ref?.host, 'lichess.org');
    });
  });

  group('extractStudyTitleFromPgn', () {
    test('extracts title from StudyName header if present', () {
      const pgn = '''
[Event "White [Petrov]: Opening [3 knights]"]
[StudyName "White [Petrov]"]
1. e4 e5 *
''';
      expect(extractStudyTitleFromPgn(pgn), 'White [Petrov]');
    });

    test('extracts study title before colon in Event header', () {
      const pgn = '''
[Event "French Defense: Winawer Variation"]
[Site "https://lichess.org/study/m1AbCd2E"]
1. e4 e6 *
''';
      expect(extractStudyTitleFromPgn(pgn), 'French Defense');
    });

    test('prefers a non-empty StudyName header over an Event without a colon', () {
      const pgn = '''
[StudyName "My Study"]
[Event "Casual Game"]
1. e4 e5 *
''';
      expect(extractStudyTitleFromPgn(pgn), 'My Study');
    });

    test('returns null if Event has no colon or is missing', () {
      const pgnNoColon = '''
[Event "Casual Game"]
1. e4 e5 *
''';
      expect(extractStudyTitleFromPgn(pgnNoColon), isNull);

      const pgnNoEvent = '''
[Site "https://lichess.org"]
1. d4 *
''';
      expect(extractStudyTitleFromPgn(pgnNoEvent), isNull);
    });
  });
}
