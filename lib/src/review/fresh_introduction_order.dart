// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

/// Fresh-introduction ordering policy for review sessions.
///
/// The session asks for this policy before the daily new-position allowance
/// cuts the fresh backlog. Leaving it out keeps the raw database order (as
/// tests that do not care about introductions rely on); production injects
/// [freshIntroductionOrderFor], which grows the whole library instead of its
/// head. The seam exists because the ordering is a product policy, while the
/// session that applies it lives in the pure domain.
library;

import 'package:chess_srs/src/domain/domain.dart';

/// Builds the production fresh-ordering policy from the scope's decisions and
/// their review states.
///
/// Counts how many positions of each study and chapter have ever been shown,
/// then hands the ordering function a spread that visits the least-presented
/// group first.
FreshIntroductionOrder freshIntroductionOrderFor({
  required Iterable<RepertoireDecision> decisions,
  required Map<String, ReviewState> reviewStates,
}) {
  final byStudy = <String, int>{};
  final byChapter = <String, int>{};
  for (final d in decisions) {
    if (reviewStates[d.canonicalId] == null && reviewStates[d.id] == null) continue;
    byStudy[d.studyId] = (byStudy[d.studyId] ?? 0) + 1;
    byChapter[d.chapterId] = (byChapter[d.chapterId] ?? 0) + 1;
  }
  return (fresh) => spreadFreshIntroductions(
    fresh,
    presentedByStudy: byStudy,
    presentedByChapter: byChapter,
  );
}

/// Orders [fresh] so a capped introduction grows the whole library evenly
/// instead of spending every day inside whichever study was imported first.
///
/// Two rules: groups are visited least-presented first (fewest positions from
/// that study/chapter have ever been shown), and they are interleaved one
/// position per round, so every study and chapter with material contributes
/// before any contributes twice. Order inside a chapter is preserved — the
/// author's line order — and the session re-sorts the admitted set when the
/// user asked for line order.
List<RepertoireDecision> spreadFreshIntroductions(
  List<RepertoireDecision> fresh, {
  required Map<String, int> presentedByStudy,
  required Map<String, int> presentedByChapter,
}) {
  if (fresh.length <= 2) return fresh;

  final byStudy = <String, List<RepertoireDecision>>{};
  for (final d in fresh) {
    byStudy.putIfAbsent(d.studyId, () => <RepertoireDecision>[]).add(d);
  }
  final studies = _leastPresentedFirst(byStudy, presentedByStudy);
  if (studies.length == 1) return _interleaveChapters(studies.first, presentedByChapter);
  return _interleaveStreams([
    for (final study in studies) _interleaveChapters(study, presentedByChapter),
  ]);
}

/// Round-robins one study's fresh decisions across its chapters, least-presented
/// chapter first, keeping each chapter's own order.
List<RepertoireDecision> _interleaveChapters(
  List<RepertoireDecision> decisions,
  Map<String, int> presentedByChapter,
) {
  final byChapter = <String, List<RepertoireDecision>>{};
  for (final d in decisions) {
    byChapter.putIfAbsent(d.chapterId, () => <RepertoireDecision>[]).add(d);
  }
  final chapters = _leastPresentedFirst(byChapter, presentedByChapter);
  if (chapters.length == 1) return chapters.first;
  return _interleaveStreams(chapters);
}

/// Groups ordered by how few of their positions have ever been presented, ties
/// kept in input order so an equal library stays stable across sessions.
List<List<RepertoireDecision>> _leastPresentedFirst(
  Map<String, List<RepertoireDecision>> groups,
  Map<String, int> presented,
) {
  final ordered = groups.entries.toList(growable: false);
  final rank = <String, int>{for (var i = 0; i < ordered.length; i++) ordered[i].key: i};
  final sorted = [...ordered]..sort((a, b) {
    final byCount = (presented[a.key] ?? 0).compareTo(presented[b.key] ?? 0);
    return byCount != 0 ? byCount : rank[a.key]!.compareTo(rank[b.key]!);
  });
  return [for (final entry in sorted) entry.value];
}

/// Takes one item from each stream per round until every stream is exhausted.
List<RepertoireDecision> _interleaveStreams(List<List<RepertoireDecision>> streams) {
  if (streams.length == 1) return streams.first;
  final spread = <RepertoireDecision>[];
  var index = 0;
  var added = true;
  while (added) {
    added = false;
    for (final stream in streams) {
      if (index < stream.length) {
        spread.add(stream[index]);
        added = true;
      }
    }
    index++;
  }
  return spread;
}
