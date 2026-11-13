import 'dart:convert';

import 'package:chess_srs/l10n/l10n.dart';
import 'package:chess_srs/src/model/common/id.dart';
import 'package:chess_srs/src/model/game/player.dart';
import 'package:chess_srs/src/model/user/user.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAppLocalizations extends Mock implements AppLocalizations {}

void main() {
  late MockAppLocalizations l10n;

  setUp(() {
    l10n = MockAppLocalizations();
    when(() => l10n.anonymous).thenReturn('Anonymous');
    when(() => l10n.aiNameLevelAiLevel(any(), any())).thenAnswer((invocation) {
      final name = invocation.positionalArguments[0] as String;
      final level = invocation.positionalArguments[1] as String;
      return '$name level $level';
    });
  });

  group('Player', () {
    test('isAI is true when aiLevel is set', () {
      const player = Player(aiLevel: 3);
      expect(player.isAI, isTrue);
    });

    test('isAI is false when aiLevel is null', () {
      const player = Player(name: 'Human');
      expect(player.isAI, isFalse);
    });

    test('displayName prefers user name over explicit name', () {
      const player = Player(
        user: LightUser(id: UserId('u1'), name: 'Magnus'),
        name: 'Fallback',
      );
      expect(player.displayName(l10n), 'Magnus');
    });

    test('displayName falls back to explicit name', () {
      const player = Player(name: 'Fallback');
      expect(player.displayName(l10n), 'Fallback');
    });

    test('displayName falls back to AI label', () {
      const player = Player(aiLevel: 5);
      expect(player.displayName(l10n), 'Stockfish level 5');
      verify(() => l10n.aiNameLevelAiLevel('Stockfish', '5')).called(1);
    });

    test('displayName falls back to anonymous', () {
      const player = Player();
      expect(player.displayName(l10n), 'Anonymous');
      verify(() => l10n.anonymous).called(1);
    });

    test('fullName prefixes user title', () {
      const player = Player(
        user: LightUser(id: UserId('u1'), name: 'Carlsen', title: 'GM'),
      );
      expect(player.fullName(l10n), 'GM Carlsen');
    });

    test('fullName omits missing title', () {
      const player = Player(name: 'Player');
      expect(player.fullName(l10n), 'Player');
    });

    test('setOnGame marks human online and clears gone', () {
      const player = Player(name: 'Human', isGone: true);
      final updated = player.setOnGame(true);
      expect(updated.onGame, isTrue);
      expect(updated.isGone, isFalse);
    });

    test('setOnGame marks human offline but preserves gone', () {
      const player = Player(name: 'Human', onGame: true, isGone: true);
      final updated = player.setOnGame(false);
      expect(updated.onGame, isFalse);
      expect(updated.isGone, isTrue);
    });

    test('setOnGame keeps AI online and clears gone', () {
      const player = Player(aiLevel: 2, isGone: true);
      final updated = player.setOnGame(false);
      expect(updated.onGame, isTrue);
      expect(updated.isGone, isFalse);
    });

    test('setGone marks human gone and offline', () {
      const player = Player(name: 'Human', onGame: true);
      final updated = player.setGone(true);
      expect(updated.isGone, isTrue);
      expect(updated.onGame, isFalse);
    });

    test('setGone clears human gone state', () {
      const player = Player(name: 'Human', isGone: true);
      final updated = player.setGone(false);
      expect(updated.isGone, isFalse);
      expect(updated.onGame, isNull);
    });

    test('setGone never marks AI as gone or offline', () {
      const player = Player(aiLevel: 1, onGame: true);
      final updated = player.setGone(true);
      expect(updated.isGone, isFalse);
      expect(updated.onGame, isTrue);
    });

    test('JSON round-trip preserves fields', () {
      const player = Player(
        user: LightUser(id: UserId('u1'), name: 'Tester', title: 'IM'),
        name: 'fallback',
        aiLevel: null,
        rating: 2100,
        ratingDiff: -4,
        provisional: true,
        onGame: true,
        isGone: false,
        offeringDraw: true,
        offeringRematch: false,
        proposingTakeback: true,
        berserk: false,
        analysis: PlayerAnalysis(inaccuracies: 1, mistakes: 2, blunders: 3, acpl: 12, accuracy: 91),
      );

      final json = jsonDecode(jsonEncode(player.toJson())) as Map<String, dynamic>;
      final decoded = Player.fromJson(json);

      expect(decoded, player);
    });
  });

  group('PlayerAnalysis', () {
    test('JSON round-trip preserves fields', () {
      const analysis = PlayerAnalysis(
        inaccuracies: 1,
        mistakes: 2,
        blunders: 3,
        acpl: 20,
        accuracy: 88,
      );

      final json = jsonDecode(jsonEncode(analysis.toJson())) as Map<String, dynamic>;
      final decoded = PlayerAnalysis.fromJson(json);

      expect(decoded, analysis);
    });
  });
}
