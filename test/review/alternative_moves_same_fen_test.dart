import 'package:chess_srs/src/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('repertoire with alternative moves at 1. e4 d5 prompts the same position twice', () {
    const startFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
    const startKey = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -';
    const e4d5Fen = 'rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2';
    const e4d5Key = 'rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq -';
    const exd5Fen = 'rnbqkbnr/ppp1pppp/8/3P4/8/8/PPPP1PPP/RNBQKBNR b KQkq - 0 2';
    const exd5Key = 'rnbqkbnr/ppp1pppp/8/3P4/8/8/PPPP1PPP/RNBQKBNR b KQkq -';
    const e5Fen = 'rnbqkbnr/ppp1pppp/8/3pP3/8/8/PPPP1PPP/RNBQKBNR b KQkq - 0 2';
    const e5Key = 'rnbqkbnr/ppp1pppp/8/3pP3/8/8/PPPP1PPP/RNBQKBNR b KQkq -';

    // Study 1 (Scandinavian): 1. e4 d5 2. exd5
    const root1 = RepertoireNode(
      id: 'root-1',
      fen: startFen,
      fenKey: startKey,
      children: [
        RepertoireNode(
          id: 'scandi-d5',
          fen: e4d5Fen,
          fenKey: e4d5Key,
          incomingMove: RepertoireMove(from: 'e2', to: 'e4', san: 'e4'),
          children: [
            RepertoireNode(
              id: 'scandi-exd5',
              fen: exd5Fen,
              fenKey: exd5Key,
              incomingMove: RepertoireMove(from: 'e4', to: 'd5', san: 'exd5'),
            ),
          ],
        ),
      ],
    );

    // Study 2 (French): 1. e4 d5 2. e5
    const root2 = RepertoireNode(
      id: 'root-2',
      fen: startFen,
      fenKey: startKey,
      children: [
        RepertoireNode(
          id: 'french-d5',
          fen: e4d5Fen,
          fenKey: e4d5Key,
          incomingMove: RepertoireMove(from: 'e2', to: 'e4', san: 'e4'),
          children: [
            RepertoireNode(
              id: 'french-e5',
              fen: e5Fen,
              fenKey: e5Key,
              incomingMove: RepertoireMove(from: 'e4', to: 'e5', san: 'e5'),
            ),
          ],
        ),
      ],
    );

    const study1 = Study(id: 's1', title: 'Scandinavian');
    const study2 = Study(id: 's2', title: 'French');
    final ch1 = Chapter(id: 'c1', studyId: 's1', sourceOrder: 0, root: root1);
    final ch2 = Chapter(id: 'c2', studyId: 's2', sourceOrder: 0, root: root2);

    final decExd5 = RepertoireDecision.create(
      studyId: 's1',
      chapterId: 'c1',
      nodeId: 'scandi-d5',
      fenKey: e4d5Key,
      expectedMoves: const [RepertoireMove(from: 'e4', to: 'd5', san: 'exd5')],
    );
    final decE5 = RepertoireDecision.create(
      studyId: 's2',
      chapterId: 'c2',
      nodeId: 'french-d5',
      fenKey: e4d5Key,
      expectedMoves: const [RepertoireMove(from: 'e4', to: 'e5', san: 'e5')],
    );

    final clock = FixedClock(DateTime.utc(2026, 11, 9, 12));
    final now = clock.now();
    final states = {
      decExd5.canonicalId: ReviewState(
        decisionId: decExd5.canonicalId,
        nextDueAt: now.subtract(const Duration(days: 1)),
        repetitionCount: 1,
      ),
      decE5.canonicalId: ReviewState(
        decisionId: decE5.canonicalId,
        nextDueAt: now.subtract(const Duration(days: 1)),
        repetitionCount: 1,
      ),
    };

    final session = ReviewEngine(clock: clock).createSession(
      studies: const [study1, study2],
      chapters: [ch1, ch2],
      decisions: [decExd5, decE5],
      reviewStates: states,
      transposeScope: TransposeScope.inScope,
    );

    // Initial queue has 2 decisions! Both at 1. e4 d5!
    expect(session.initialQueueCount, 2);

    // First prompt is at 1. e4 d5
    expect(session.currentPrompt?.fenKey, e4d5Key);

    // User plays e5 (an alternative valid move in scope via transposition)!
    final r1 = session.submitMove(from: 'e4', to: 'e5');
    expect(r1.isCorrect, isTrue);

    // Because e5 was played via transposition, the decE5 decision is dequeued,
    // the prompt is answered, and the user is NOT asked the same position again.
    expect(session.currentPrompt, isNull);
    expect(session.isComplete, isTrue);
  });
}
