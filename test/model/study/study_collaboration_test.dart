// Copyright (C) 2024 ChessSRS contributors
// ignore_for_file: invalid_use_of_protected_member
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chess_srs/src/model/common/id.dart';
import 'package:chess_srs/src/model/common/socket.dart';
import 'package:chess_srs/src/model/common/uci.dart';
import 'package:chess_srs/src/model/study/study.dart';
import 'package:chess_srs/src/model/study/study_controller.dart';
import 'package:chess_srs/src/model/study/study_repository.dart';
import 'package:chess_srs/src/model/user/user.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../test_container.dart';

class MockStudyRepository extends Mock implements StudyRepository {}

const _studyId = StudyId('collab');
const _chapterOne = StudyChapterId('chapter-one');
const _chapterTwo = StudyChapterId('chapter-two');
const _pgn = '1. e4 e5 2. Nf3 *';

StudyChapter _chapter(StudyChapterId id) => StudyChapter(
  id: id,
  setup: const StudyChapterSetup(
    id: null,
    orientation: Side.white,
    variant: Variant.standard,
    fromFen: null,
  ),
  conceal: null,
  features: (computer: false, explorer: false),
  gamebook: false,
  practise: false,
);

Study _study() => Study(
  id: _studyId,
  name: 'Collaboration',
  liked: false,
  likes: 0,
  ownerId: null,
  features: (cloneable: false, sticky: false),
  topics: const IList<String>.empty(),
  chapters: IList(const [
    StudyChapterMeta(id: _chapterOne, name: 'One', fen: null),
    StudyChapterMeta(id: _chapterTwo, name: 'Two', fen: null),
  ]),
  chapter: _chapter(_chapterOne),
  members: IMap(const {
    UserId(''): StudyMember(
      user: LightUser(id: UserId(''), name: ''),
      role: '',
    ),
  }),
  hints: const IList<String?>.empty(),
  deviationComments: const IList<String?>.empty(),
);

/// A loaded controller, plus everything the server would have seen from it.
class _Peer {
  _Peer(this.controller);

  final StudyController controller;

  /// The SAN moves currently in the tree, in order.
  List<String> get sanMoves => [
    for (final branch in controller.positionTree.mainline) branch.sanMove.san,
  ];

  UciPath get currentPath => controller.state.requireValue.currentPath;

  /// Delivers a frame as though the server had broadcast it to this controller.
  void deliver(Map<String, dynamic> payload, {String topic = 'anaMove'}) {
    controller.handleSocketEvent(SocketEvent(topic: topic, data: payload));
  }
}

void main() {
  group('Study collaboration edits', () {
    /// Loads the study — which opens on [loadedChapter] — and returns the controller with a record
    /// of everything it published.
    Future<_Peer> openPeer(StudyChapterId loadedChapter) async {
      final study = _study().copyWith(chapter: _chapter(loadedChapter));
      final container = await makeContainer(
        overrides: {
          studyRepositoryProvider: studyRepositoryProvider.overrideWith((ref) {
            final repo = MockStudyRepository();
            when(
              () => repo.getStudy(
                id: _studyId,
                chapterId: any(named: 'chapterId'),
              ),
            ).thenAnswer((_) async => (study, null, _pgn));
            return repo;
          }),
        },
      );

      const options = (id: _studyId, initialChapter: null);
      // The family is autoDispose, so a bare read would be collected straight back. Listening keeps
      // the controller — and the socket it opens — alive for the length of the test.
      final subscription = container.listen(
        studyControllerProvider(options),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      addTearDown(container.dispose);
      await container.read(studyControllerProvider(options).future);
      return _Peer(container.read(studyControllerProvider(options).notifier));
    }

    test('an edit for the chapter on screen reaches the tree', () async {
      // Two independent controllers on the same study: the observer stands in for the contributor
      // who did not make the move.
      final observer = await openPeer(_chapterOne);

      // The observer starts from the same PGN, so it does not already have the move.
      expect(observer.sanMoves.contains('e4'), isTrue, reason: 'the PGN itself starts 1.e4');

      // A move the observer has never seen, carried by the author for its own chapter.
      final before = observer.sanMoves.length;
      observer.deliver({
        'ch': _chapterOne.value,
        'orig': 'c7',
        'dest': 'c5',
        'path': UciPath.fromId(UciCharPair.fromUci('e2e4')).value,
      });

      expect(
        observer.controller.positionTree
            .nodeAt(UciPath.fromId(UciCharPair.fromUci('e2e4')))
            .children
            .map((c) => c.sanMove.san),
        contains('c5'),
        reason: "the other contributor's move is now in the tree",
      );
      expect(observer.sanMoves.length, greaterThanOrEqualTo(before));
    });

    test('an edit for a different chapter is ignored', () async {
      final observer = await openPeer(_chapterOne);
      final before = observer.sanMoves;

      observer.deliver({'ch': _chapterTwo.value, 'orig': 'c7', 'dest': 'c5', 'path': ''});

      expect(
        observer.sanMoves,
        before,
        reason: "another chapter's move must not be grafted onto this tree",
      );
    });

    test('the same move delivered twice is still one move', () async {
      final observer = await openPeer(_chapterOne);
      const payload = {'ch': null, 'orig': 'c7', 'dest': 'c5', 'path': null};
      final path = UciPath.fromId(UciCharPair.fromUci('e2e4')).value;

      observer.deliver({...payload, 'ch': _chapterOne.value, 'path': path});
      final afterFirst = observer.sanMoves;
      observer.deliver({...payload, 'ch': _chapterOne.value, 'path': path});

      expect(observer.sanMoves, afterFirst, reason: 'a replayed move is a no-op');
    });

    test('a delete already applied is not applied again', () async {
      final observer = await openPeer(_chapterOne);
      final e4 = UciPath.fromId(UciCharPair.fromUci('e2e4')).value;
      expect(observer.sanMoves, contains('e4'), reason: 'the PGN starts 1.e4');

      final payload = {'ch': _chapterOne.value, 'path': e4, 'jumpTo': ''};

      observer.deliver(payload, topic: 'deleteNode');
      final afterFirst = observer.sanMoves;
      final pathAfterFirst = observer.currentPath.value;
      expect(afterFirst, isNot(contains('e4')), reason: 'the node really was removed');

      // The same delete arriving again must find nothing to remove, and must not walk the view
      // back to `jumpTo` a second time.
      observer.deliver(payload, topic: 'deleteNode');
      expect(observer.sanMoves, afterFirst, reason: 'a replayed delete removes nothing more');
      expect(
        observer.currentPath.value,
        pathAfterFirst,
        reason: 'a replayed delete leaves the view where the first one put it',
      );
    });

    test('a frame that is not a well-formed edit is dropped', () async {
      final observer = await openPeer(_chapterOne);
      final before = observer.sanMoves;

      // Claims a move but carries none, names a role the build does not have, and a promotion
      // with no path. None of them may throw, and none may change the tree.
      observer.deliver({'ch': _chapterOne.value, 'path': ''});
      observer.deliver({'ch': _chapterOne.value, 'role': 'dragon', 'pos': 'e4', 'path': ''});
      observer.deliver({'ch': _chapterOne.value, 'toMainline': true}, topic: 'promote');
      // A payload that is not a map at all.
      observer.controller.handleSocketEvent(const SocketEvent(topic: 'anaMove', data: 'nope'));

      expect(observer.sanMoves, before);
    });
  });

  // ---------------------------------------------------------------------------
  // Chapter selection
  // ---------------------------------------------------------------------------
  group('Study chapter selection', () {
    /// Loads a study whose repository answers [onGet] for every chapter request.
    Future<StudyController> openController(
      StudyChapterId loadedChapter, {
      Future<void> Function(StudyChapterId)? onGet,
    }) async {
      final container = await makeContainer(
        overrides: {
          studyRepositoryProvider: studyRepositoryProvider.overrideWith((ref) {
            final repo = MockStudyRepository();
            when(
              () => repo.getStudy(
                id: _studyId,
                chapterId: any(named: 'chapterId'),
              ),
            ).thenAnswer((invocation) async {
              // The opening load asks for no particular chapter; later ones name one.
              final requested = invocation.namedArguments[#chapterId] as StudyChapterId?;
              if (requested != null) await onGet?.call(requested);
              return (_study().copyWith(chapter: _chapter(requested ?? loadedChapter)), null, _pgn);
            });
            return repo;
          }),
        },
      );

      const options = (id: _studyId, initialChapter: null);
      final subscription = container.listen(
        studyControllerProvider(options),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      addTearDown(container.dispose);
      await container.read(studyControllerProvider(options).future);
      final controller = container.read(studyControllerProvider(options).notifier);
      return controller;
    }

    test('navigating past the last chapter is a no-op rather than a crash', () async {
      // Opened on the final chapter: there is nothing after it.
      final controller = await openController(_chapterTwo);

      await expectLater(
        controller.nextChapter(),
        completes,
        reason: 'reading one past the end of the chapter list threw a RangeError',
      );
      expect(
        controller.state.requireValue.study.chapter.id,
        equals(_chapterTwo),
        reason: 'the chapter on screen must not change',
      );
    });

    test('the chapter you asked for last is the one you get', () async {
      // Hold the first request open so it resolves *after* the second. A study opens on
      // chapter one, so without holding it the first request would land first anyway.
      var hold = false;
      final controller = await openController(
        _chapterOne,
        onGet: (chapterId) {
          if (hold && chapterId == _chapterOne) {
            return Future<void>.delayed(const Duration(milliseconds: 150));
          }
          return Future<void>.value();
        },
      );

      hold = true;
      await Future.wait([controller.goToChapter(_chapterOne), controller.goToChapter(_chapterTwo)]);

      expect(
        controller.state.requireValue.study.chapter.id,
        equals(_chapterTwo),
        reason: 'the slower, superseded request loaded over the newer one',
      );
    });
  });
}
