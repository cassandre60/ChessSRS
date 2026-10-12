// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

/// Read-only study and chapter lookups for presentation.
///
/// `QUALITY.md` §1.1 requires `view/` to reach data through application-layer
/// providers, never through `persistence/` directly. Three screens broke that rule
/// because each needed a `Study`, a chapter list or a position tree and the nearest
/// application-layer provider did not offer one. These providers are that missing
/// layer: they are the single source of truth for these reads, so a change to the
/// `StudyRepository` contract reaches presentation through this file.
///
/// They are deliberately plain. There is no caching beyond Riverpod's own provider
/// lifetime, no invalidation and no review semantics — each is a pass-through to one
/// repository call, so moving a screen onto them changes which layer the call is made
/// from and nothing else.
library;

import 'package:chess_srs/src/domain/domain.dart';
import 'package:chess_srs/src/persistence/persistence.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Every study, for pickers and browsers.
///
/// Replaces the `_studiesProvider` that `view/analysis/analysis_hub_screen.dart`
/// declared locally over a direct repository read.
///
/// Plain [Study]s, not a wrapper carrying chapter counts: the chapters picker does not
/// display counts, and fetching one per study to decorate a list the user is about to
/// leave is work with no reader.
final studyListProvider = FutureProvider.autoDispose<List<Study>>((ref) async {
  final repo = await ref.watch(srsStudyRepositoryProvider.future);
  return await repo.getAllStudies();
});

/// A single study by id, or null when it does not exist.
///
/// Null is a real answer rather than an error: callers report "Study not found" to the
/// user, so the lookup has to be able to come back empty without throwing.
final studyByIdProvider = FutureProvider.autoDispose.family<Study?, String>((ref, studyId) async {
  final repo = await ref.watch(srsStudyRepositoryProvider.future);
  return await repo.getStudy(studyId);
});

/// The chapters of a study, in repository order.
///
/// An empty list is likewise a real answer — `openStudyExplorer` reports "Study has no
/// chapters to explore" rather than treating it as a failure.
final studyChaptersProvider = FutureProvider.autoDispose.family<List<Chapter>, String>((
  ref,
  studyId,
) async {
  final repo = await ref.watch(srsStudyRepositoryProvider.future);
  return await repo.getChaptersByStudy(studyId);
});

/// [chapter] with its position tree attached.
///
/// [Chapter.root] is a nullable cached tree, so a chapter that already carries one
/// needs no read — the caller's lookup is a single provider read either way, and the
/// second repository call happens only for a chapter that genuinely needs one.
final hydratedChapterProvider = FutureProvider.autoDispose.family<Chapter, Chapter>((
  ref,
  chapter,
) async {
  if (chapter.root != null) return chapter;
  final repo = await ref.watch(srsStudyRepositoryProvider.future);
  final root = await repo.getPositionTree(chapter.id);
  return chapter.copyWith(root: root);
});
