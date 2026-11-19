import 'package:chess_srs/src/domain/repertoire_decision.dart';
import 'package:chess_srs/src/domain/repertoire_move.dart';
import 'package:chess_srs/src/domain/repertoire_node.dart';
import 'package:chess_srs/src/domain/review/review_prompt.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  RepertoireMove move(String from, String to, {String? san}) =>
      RepertoireMove(from: from, to: to, san: san);

  RepertoireDecision decision({
    String id = 'dec-1',
    String studyId = 'study-1',
    String chapterId = 'chapter-1',
    String nodeId = 'node-1',
    String? canonicalStateId,
    String? fenKey,
    List<RepertoireMove>? expectedMoves,
  }) {
    return RepertoireDecision(
      id: id,
      studyId: studyId,
      chapterId: chapterId,
      nodeId: nodeId,
      expectedMoves: expectedMoves ?? [move('e2', 'e4', san: 'e4')],
      canonicalStateId: canonicalStateId,
      fenKey: fenKey,
    );
  }

  ReviewPrompt prompt({
    RepertoireDecision? promptDecision,
    String studyId = 'study-1',
    String chapterId = 'chapter-1',
    String nodeId = 'node-1',
    String fen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
    String fenKey = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -',
    Side sideToMove = Side.white,
    List<RepertoireMove>? expectedMoves,
    RepertoireNode? currentNode,
    String? comment,
    String? studyTitle,
    String? chapterTitle,
    String? parentFen,
    RepertoireMove? incomingMove,
    List<String> moveHistory = const [],
  }) {
    final expected = expectedMoves ?? [move('e2', 'e4', san: 'e4')];
    return ReviewPrompt(
      decision: promptDecision ?? decision(expectedMoves: expected),
      studyId: studyId,
      chapterId: chapterId,
      nodeId: nodeId,
      fen: fen,
      fenKey: fenKey,
      sideToMove: sideToMove,
      expectedMoves: expected,
      currentNode: currentNode,
      comment: comment,
      studyTitle: studyTitle,
      chapterTitle: chapterTitle,
      parentFen: parentFen,
      incomingMove: incomingMove,
      moveHistory: moveHistory,
    );
  }

  group('ReviewPrompt', () {
    test('stores required and optional fields', () {
      final expected = [move('e2', 'e4', san: 'e4'), move('d2', 'd4', san: 'd4')];
      final node = RepertoireNode.root(
        fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
        fenKey: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -',
        comment: 'start',
      );
      final incoming = move('e7', 'e5', san: 'e5');
      final p = prompt(
        studyId: 's',
        chapterId: 'c',
        nodeId: 'n',
        fen: 'fen',
        fenKey: 'fen-key',
        sideToMove: Side.black,
        expectedMoves: expected,
        currentNode: node,
        comment: 'comment',
        studyTitle: 'Study',
        chapterTitle: 'Chapter',
        parentFen: 'parent-fen',
        incomingMove: incoming,
        moveHistory: const ['e4', 'e5'],
      );

      expect(p.studyId, 's');
      expect(p.chapterId, 'c');
      expect(p.nodeId, 'n');
      expect(p.fen, 'fen');
      expect(p.fenKey, 'fen-key');
      expect(p.sideToMove, Side.black);
      expect(p.expectedMoves, expected);
      expect(p.currentNode, same(node));
      expect(p.comment, 'comment');
      expect(p.studyTitle, 'Study');
      expect(p.chapterTitle, 'Chapter');
      expect(p.parentFen, 'parent-fen');
      expect(p.incomingMove, same(incoming));
      expect(p.moveHistory, const ['e4', 'e5']);
    });

    test('defaults moveHistory to empty list', () {
      final p = prompt();
      expect(p.moveHistory, isEmpty);
    });

    test('equality and hashCode are based on decision id, nodeId, and fenKey', () {
      final base = prompt(
        promptDecision: decision(id: 'dec-a'),
        nodeId: 'node-a',
        fenKey: 'key-a',
        studyTitle: 'ignored',
      );
      final sameIdentity = prompt(
        promptDecision: decision(id: 'dec-a', studyId: 'other-study'),
        nodeId: 'node-a',
        fenKey: 'key-a',
        studyTitle: 'different',
        chapterId: 'different-chapter',
      );
      final differentDecision = prompt(
        promptDecision: decision(id: 'dec-b'),
        nodeId: 'node-a',
        fenKey: 'key-a',
      );
      final differentNode = prompt(
        promptDecision: decision(id: 'dec-a'),
        nodeId: 'node-b',
        fenKey: 'key-a',
      );
      final differentFenKey = prompt(
        promptDecision: decision(id: 'dec-a'),
        nodeId: 'node-a',
        fenKey: 'key-b',
      );

      expect(base, equals(sameIdentity));
      expect(base.hashCode, sameIdentity.hashCode);
      expect(base, isNot(equals(differentDecision)));
      expect(base, isNot(equals(differentNode)));
      expect(base, isNot(equals(differentFenKey)));
    });

    test('toString includes decision id, fen key, and expected move count', () {
      final p = prompt(
        promptDecision: decision(id: 'dec-42'),
        fenKey: 'start-key',
        expectedMoves: [move('e2', 'e4'), move('d2', 'd4')],
      );

      expect(p.toString(), 'ReviewPrompt(decision: dec-42, fen: start-key, moves: 2)');
    });
  });

  group('AutoPlayedMove', () {
    test('stores fields and toString uses SAN when present', () {
      final played = AutoPlayedMove(
        move: move('g1', 'f3', san: 'Nf3'),
        fenBefore: 'before',
        fenAfter: 'after',
        isUserMove: true,
        comment: 'develop',
      );

      expect(played.move.uci, 'g1f3');
      expect(played.fenBefore, 'before');
      expect(played.fenAfter, 'after');
      expect(played.isUserMove, isTrue);
      expect(played.comment, 'develop');
      expect(played.toString(), 'AutoPlayedMove(Nf3, user: true)');
    });

    test('toString falls back to UCI when SAN is absent', () {
      final played = AutoPlayedMove(
        move: move('e2', 'e4'),
        fenBefore: 'before',
        fenAfter: 'after',
        isUserMove: false,
      );

      expect(played.toString(), 'AutoPlayedMove(e2e4, user: false)');
    });

    test('equality and hashCode include move, positions, and side flag', () {
      final a = AutoPlayedMove(
        move: move('e2', 'e4', san: 'e4'),
        fenBefore: 'a',
        fenAfter: 'b',
        isUserMove: true,
      );
      final same = AutoPlayedMove(
        move: move('e2', 'e4', san: 'different-san'),
        fenBefore: 'a',
        fenAfter: 'b',
        isUserMove: true,
        comment: 'ignored by equality',
      );
      final differentMove = AutoPlayedMove(
        move: move('d2', 'd4'),
        fenBefore: 'a',
        fenAfter: 'b',
        isUserMove: true,
      );
      final differentBefore = AutoPlayedMove(
        move: move('e2', 'e4'),
        fenBefore: 'other',
        fenAfter: 'b',
        isUserMove: true,
      );
      final differentAfter = AutoPlayedMove(
        move: move('e2', 'e4'),
        fenBefore: 'a',
        fenAfter: 'other',
        isUserMove: true,
      );
      final differentSide = AutoPlayedMove(
        move: move('e2', 'e4'),
        fenBefore: 'a',
        fenAfter: 'b',
        isUserMove: false,
      );

      expect(a, equals(same));
      expect(a.hashCode, same.hashCode);
      expect(a, isNot(equals(differentMove)));
      expect(a, isNot(equals(differentBefore)));
      expect(a, isNot(equals(differentAfter)));
      expect(a, isNot(equals(differentSide)));
    });
  });
}
