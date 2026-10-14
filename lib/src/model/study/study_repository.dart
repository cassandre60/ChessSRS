import 'dart:convert';

import 'package:chess_srs/src/import/pgn_exporter.dart';
import 'package:chess_srs/src/model/analysis/analysis_summary.dart';
import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chess_srs/src/model/common/id.dart';
import 'package:chess_srs/src/model/study/study.dart';
import 'package:chess_srs/src/model/study/study_filter.dart';
import 'package:chess_srs/src/model/study/study_list_paginator.dart';
import 'package:chess_srs/src/network/http.dart';
import 'package:chess_srs/src/persistence/persistence.dart';
import 'package:collection/collection.dart';
import 'package:deep_pick/deep_pick.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart';

/// A provider for [StudyRepository].
final studyRepositoryProvider = Provider<StudyRepository>((Ref ref) {
  return StudyRepository(ref, ref.watch(lichessClientProvider));
}, name: 'StudyRepositoryProvider');

class StudyRepository {
  StudyRepository(this.ref, this.client);

  final Client client;
  final Ref ref;

  Future<StudyList> getStudies({
    required StudyCategory category,
    required StudyListOrder order,
    int page = 1,
  }) {
    return _requestStudies(
      path: '${category.name}/${order.name}',
      queryParameters: {'page': page.toString()},
    );
  }

  Future<StudyList> searchStudies({
    required String query,
    required StudyListOrder order,
    int page = 1,
  }) {
    return _requestStudies(
      path: 'search',
      queryParameters: {'page': page.toString(), 'q': query, 'order': order.name},
    );
  }

  Future<StudyList> _requestStudies({
    required String path,
    required Map<String, String> queryParameters,
  }) {
    return client.readJson(
      Uri(path: '/study/$path', queryParameters: queryParameters),
      headers: {'Accept': 'application/json'},
      mapper: (Map<String, dynamic> json) {
        final paginator = pick(json, 'paginator').asMapOrThrow<String, dynamic>();

        return (
          studies: pick(
            paginator,
            'currentPageResults',
          ).asListOrThrow((pick) => StudyPageItem.fromJson(pick.asMapOrThrow())).toIList(),
          nextPage: pick(paginator, 'nextPage').asIntOrNull(),
        );
      },
    );
  }

  Future<(Study study, AnalysisSummary? analysisSummary, String pgn)> getStudy({
    required StudyId id,
    StudyChapterId? chapterId,
  }) async {
    final srsRepoAsync = ref.read(srsStudyRepositoryProvider);
    final srsRepo = srsRepoAsync.asData?.value;
    if (srsRepo != null) {
      try {
        final localStudy = await srsRepo.getStudy(id.value);
        if (localStudy != null) {
          final chapters = await srsRepo.getChaptersByStudy(localStudy.id);
          if (chapters.isNotEmpty) {
            final currentChapter = chapterId != null
                ? (chapters.firstWhereOrNull((c) => c.id == chapterId.value) ?? chapters.first)
                : chapters.first;
            final root = await srsRepo.getPositionTree(currentChapter.id);
            final fullChapter = currentChapter.copyWith(root: root);
            final pgn = chapterToPgn(fullChapter, studyTitle: localStudy.title);

            final chapterMetas = chapters
                .mapIndexed(
                  (index, ch) => StudyChapterMeta(
                    id: StudyChapterId(ch.id),
                    name: ch.title ?? 'Chapter ${index + 1}',
                    fen: ch.startingFen,
                  ),
                )
                .toIList();

            final studyChapter = StudyChapter(
              id: StudyChapterId(currentChapter.id),
              setup: StudyChapterSetup(
                id: null,
                orientation: currentChapter.orientation,
                variant: Variant.standard,
                fromFen: currentChapter.startingFen != null,
              ),
              practise: false,
              conceal: null,
              gamebook: false,
              features: (computer: true, explorer: true),
            );

            final study = Study(
              id: id,
              name: localStudy.title,
              liked: false,
              likes: 0,
              ownerId: null,
              features: (cloneable: false, sticky: false),
              topics: const IListConst([]),
              chapters: chapterMetas,
              chapter: studyChapter,
              members: const IMapConst({}),
              hints: const IListConst([]),
              deviationComments: const IListConst([]),
            );

            return (study, null, pgn);
          }
        }
      } catch (_) {
        // Fall back to network
      }
    }

    final study = await client.readJson(
      Uri(
        path: (chapterId != null) ? '/study/$id/$chapterId' : '/study/$id',
        queryParameters: {'chapters': '1'},
      ),
      headers: {'Accept': 'application/json'},
      mapper: Study.fromServerJson,
    );

    final response = await client.readResponse(
      Uri(
        path: '/api/study/$id/${chapterId ?? study.chapter.id}.pgn',
        queryParameters: {'analysisHeader': '1'},
      ),
      headers: {'Accept': 'application/x-chess-pgn'},
    );

    return (study, readAnalysisSummaryFromHeader(response), utf8.decode(response.bodyBytes));
  }

  Future<String> getStudyPgn(StudyId id, {String host = 'lichess.org'}) async {
    final pgnBytes = await client.readBytes(
      Uri.https(host, '/api/study/$id.pgn'),
      headers: {'Accept': 'application/x-chess-pgn'},
    );

    return utf8.decode(pgnBytes);
  }

  /// Lists the studies of [username] through `GET /api/study/by/:username`.
  ///
  /// This is a real API route, so it accepts the app's OAuth bearer token.
  /// The website study list (`/study/mine/...`) answers 403 to the same
  /// token even with `study:read` (owner-verified 2026-10-14), so bulk import
  /// must not enumerate through it. Reads NDJSON, one `{"id","name",...}`
  /// object per study, in listing order.
  ///
  /// The body is read whole and split into lines rather than streamed:
  /// chunks do not align with lines, so decoding chunk-by-chunk breaks on
  /// any multi-study body.
  Future<List<({StudyId id, String name, DateTime updatedAt})>> getStudiesByUsername(
    String username,
  ) async {
    final url = Uri(path: '/api/study/by/$username');
    // Read with `get` and check the status here rather than through
    // `readBytes`: the app client and the base client report failures with
    // different exception types, and the controller maps on ServerException.
    final response = await client.get(url, headers: {'Accept': 'application/x-ndjson'});
    if (response.statusCode >= 400) {
      throw ServerException(
        response.statusCode,
        'Request to $url failed with status ${response.statusCode}.',
        url,
        null,
      );
    }
    final refs = <({StudyId id, String name, DateTime updatedAt})>[];
    try {
      for (final line in const LineSplitter().convert(response.body)) {
        if (line.trim().isEmpty) continue;
        final json = jsonDecode(line) as Map<String, dynamic>;
        final name = pick(json, 'name').asStringOrNull()?.trim() ?? '';
        if (name.isEmpty) continue;
        refs.add((
          id: StudyId(pick(json, 'id').asStringOrThrow()),
          name: name,
          updatedAt: DateTime.fromMillisecondsSinceEpoch(
            pick(json, 'updatedAt').asIntOrThrow(),
            isUtc: true,
          ),
        ));
      }
    } on FormatException catch (e) {
      throw ClientException('Could not read study list as NDJSON: $e', url);
    }
    return refs;
  }

  /// Creates one or more (if the PGN contains multiple games) chapters in the study with the given [studyId].
  Future<IList<StudyChapterId>> createChapter(
    StudyId studyId,
    CreateStudyChapterPayload chapter,
  ) async {
    return await client.postReadJson<IList<StudyChapterId>>(
      Uri(path: '/api/study/$studyId/import-pgn'),
      body: {
        'pgn': chapter.pgn,
        'name': chapter.name,
        'orientation': chapter.orientation.name,
        if (chapter.variant != null) 'variant': chapter.variant!.name,
      },
      mapper: (json) => pick(
        json,
        'chapters',
      ).asListOrThrow((pick) => StudyChapterId(pick.required()('id').asStringOrThrow())).lock,
    );
  }
}
