import 'package:chess_srs/l10n/l10n.dart';
import 'package:chess_srs/src/utils/l10n.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('l10nWithWidget', () {
    const widget = Text('I am a widget');
    test('placeholder in the middle', () {
      final text = l10nWithWidget((_) => 'foo %s bar', widget);
      final children = (text.textSpan as TextSpan?)?.children;
      expect(children!.length, 3);
      expect((children[0] as TextSpan).text, 'foo ');
      expect((children[1] as WidgetSpan).child, widget);
      expect((children[2] as TextSpan).text, ' bar');
    });

    test('no placeholder', () {
      final text = l10nWithWidget((_) => 'foo bar', widget);
      expect(text.data, 'foo bar');
    });

    test('placeholder at the beginning', () {
      final text = l10nWithWidget((_) => '%s foo bar', widget);
      final children = (text.textSpan as TextSpan?)?.children;
      expect(children!.length, 2);
      expect((children[0] as WidgetSpan).child, widget);
      expect((children[1] as TextSpan).text, ' foo bar');
    });

    test('placeholder at the end', () {
      final text = l10nWithWidget((_) => 'foo bar %s', widget);
      final children = (text.textSpan as TextSpan?)?.children;
      expect(children!.length, 2);
      expect((children[0] as TextSpan).text, 'foo bar ');
      expect((children[1] as WidgetSpan).child, widget);
    });

    test('passes textStyle', () {
      final text = l10nWithWidget(
        (_) => 'foo %s bar',
        widget,
        textStyle: const TextStyle(fontWeight: FontWeight.bold),
      );
      final children = (text.textSpan as TextSpan?)?.children;
      expect(children!.length, 3);
      expect((children[0] as TextSpan).style?.fontWeight, FontWeight.bold);
      expect((children[1] as WidgetSpan).child, widget);
      expect((children[2] as TextSpan).style?.fontWeight, FontWeight.bold);
    });
  });

  group('formatPgnDate', () {
    test('full date', () {
      expect(formatPgnDate('1972.08.31'), 'Aug 31, 1972');
      expect(formatPgnDate('1972.08.31', shortDate: false), 'August 31, 1972');
    });

    test('unknown day falls back to the month', () {
      expect(formatPgnDate('1972.08.??'), 'Aug 1972');
      expect(formatPgnDate('1972.08'), 'Aug 1972');
      expect(formatPgnDate('1972.08.??', shortDate: false), 'August 1972');
      // out of range days are not rolled over to the next month
      expect(formatPgnDate('1972.02.31'), 'Feb 1972');
    });

    test('unknown month falls back to the year', () {
      expect(formatPgnDate('1972.??.??'), '1972');
      expect(formatPgnDate('1972'), '1972');
      expect(formatPgnDate('1972.13.01'), '1972');
    });

    test('unknown date', () {
      expect(formatPgnDate('????.??.??'), '????');
      expect(formatPgnDate(''), '????');
    });
  });

  group('mobile review keys fall back to English until translated', () {
    // Round 7 moved the review surfaces onto pipeline-owned mobile* keys so a
    // template regen can no longer drop them. Until Crowdin translates them, every
    // locale must render the English text — including through parameters.
    final locales = [
      lookupAppLocalizations(const Locale('de')),
      lookupAppLocalizations(const Locale('fr')),
      lookupAppLocalizations(const Locale('ja')),
      lookupAppLocalizations(const Locale('ar')),
    ];
    for (final strings in locales) {
      test('${strings.localeName} renders the English fallback', () {
        expect(strings.mobileReviewContinue, 'Continue');
        expect(strings.mobileReviewSkip, 'Skip');
        expect(strings.mobileReviewNothingDueTitle, 'Nothing due.');
        expect(strings.mobileReviewDueWord, 'due');
        expect(
          strings.mobileReviewDuplicateStudy('Sicilian'),
          'Study "Sicilian" is already imported and up to date',
        );
        expect(
          strings.mobileReviewDailyProgress('6', '100'),
          'You reviewed 6 of 100 positions today. White and Black combined.',
        );
        expect(strings.mobileReviewCrossSideButton('White', '5'), 'Review White — 5 due');
        expect(strings.mobileReviewPositionsCount('3'), '3 positions');
        expect(
          strings.mobileReviewDeleteStudyConfirm('T', '9'),
          'Delete “T” and its 9 positions? This cannot be undone.',
        );
        expect(strings.mobileReviewNothingMatches('q'), 'Nothing matches “q”.');
        expect(strings.mobileReviewVerdictCorrectMove('Nf3'), 'Correct. Nf3.');
        expect(strings.mobileReviewVerdictWrongMove('e4'), 'Not this move. The study move is e4.');
      });
    }
  });

  group('localesSortedByLocalizedName', () {
    test('sorts by native name, grouping scripts together', () {
      const locales = [
        Locale('ru'), // русский язык (Cyrillic)
        Locale('en'), // English (Latin)
        Locale('ko'), // 한국어 (Hangul)
        Locale('fr'), // Français (Latin)
        Locale('ar'), // العربية (Arabic)
      ];

      final sorted = localesSortedByLocalizedName(locales);

      // Unicode ordering: Latin, then Cyrillic (U+04xx), Arabic (U+06xx), Hangul.
      expect(sorted.map(localeToLocalizedName).toList(), [
        'English',
        'Français',
        'русский язык',
        'العربية',
        '한국어',
      ]);
    });

    test('does not mutate the input list', () {
      const locales = [Locale('ru'), Locale('en')];
      localesSortedByLocalizedName(locales);
      expect(locales, const [Locale('ru'), Locale('en')]);
    });

    test('all supported locales are sorted by their localized name', () {
      final sorted = localesSortedByLocalizedName(AppLocalizations.supportedLocales);
      final names = sorted.map(localeToLocalizedName).toList();
      final expected = [...names]..sort();
      expect(names, expected);
      expect(sorted.length, AppLocalizations.supportedLocales.length);
    });
  });
}
