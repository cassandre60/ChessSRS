import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/model/engine/engine_utils.dart';
import 'package:chess_srs/src/model/engine/evaluation_preferences.dart';
import 'package:chess_srs/src/model/engine/opponent_level.dart';
import 'package:chess_srs/src/model/engine/weights_service.dart';
import 'package:chess_srs/src/utils/l10n_context.dart';
import 'package:chess_srs/src/utils/navigation.dart';
import 'package:chess_srs/src/view/analysis/engine_settings_widget.dart';
import 'package:chess_srs/src/widgets/adaptive_choice_picker.dart';
import 'package:chess_srs/src/widgets/buttons.dart';
import 'package:chess_srs/src/widgets/shimmer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class EngineSettingsScreen extends ConsumerStatefulWidget {
  const EngineSettingsScreen({super.key});

  static Route<dynamic> buildRoute() {
    return buildScreenRoute(screen: const EngineSettingsScreen());
  }

  @override
  ConsumerState<EngineSettingsScreen> createState() => _EngineSettingsScreenState();
}

class _EngineSettingsScreenState extends ConsumerState<EngineSettingsScreen> {
  /// null = loading, true = has the file with checked integrity, false = doesn't have it
  bool? _hasVerifiedNNUEFile;

  /// Whether there are NNUE files on disk the engine cannot use: the network of a previous
  /// Stockfish version, or one that did not survive its download.
  bool _hasUnusableNNUEFiles = false;

  Future<bool>? _downloadNNUEFileFuture;

  late final ValueListenable<double> _downloadProgress;

  @override
  void initState() {
    _checkFiles();

    _downloadProgress = ref.read(stockfishNnueServiceProvider).nnueDownloadProgress;

    super.initState();
  }

  Future<void> _checkFiles() async {
    final nnueService = ref.read(stockfishNnueServiceProvider);
    // Deletes the file itself if it is corrupted, so whatever is left over afterwards is
    // either usable or from another Stockfish version.
    final good = await nnueService.checkNNUEFile();
    final leftOver = !good && await nnueService.hasNNUEFilesOnDisk();
    if (!mounted) return;
    setState(() {
      _hasVerifiedNNUEFile = good;
      _hasUnusableNNUEFiles = leftOver;
    });
  }

  void _startDownload() {
    final future = ref.read(stockfishNnueServiceProvider).downloadNNUEFile(inBackground: false);
    future.then((downloaded) {
      if (mounted && downloaded) {
        setState(() {
          _hasVerifiedNNUEFile = true;
          _hasUnusableNNUEFiles = false;
        });
      }
    });
    setState(() {
      _downloadNNUEFileFuture = future;
    });
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(engineEvaluationPreferencesProvider);

    final c = context.srs;
    return Scaffold(
      backgroundColor: c.ground,
      body: SafeArea(
        child: Column(
          children: [
            SrsPageHead(label: 'Chess engine', onBack: () => Navigator.of(context).maybePop()),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                children: [
                  if (_hasVerifiedNNUEFile == null)
                    Shimmer(
                      child: ShimmerLoading(
                        isLoading: true,
                        child: Column(
                          children: [
                            for (var i = 0; i < 2; i++)
                              Container(
                                height: 56,
                                margin: const EdgeInsets.only(bottom: 8),
                                color: c.hairlineSoft,
                              ),
                          ],
                        ),
                      ),
                    )
                  else
                    SrsSettingsRow(
                      label: 'Engine',
                      value: prefs.enginePref.label,
                      onTap: () {
                        showChoicePicker(
                          context,
                          choices: ChessEnginePref.values,
                          selectedItem: prefs.enginePref,
                          labelBuilder: (ChessEnginePref t) => Text(t.label),
                          onSelectedItemChanged: (ChessEnginePref? value) {
                            ref
                                .read(engineEvaluationPreferencesProvider.notifier)
                                .setEvaluationFunction(value ?? ChessEnginePref.sfLight);
                            if (value == ChessEnginePref.sfLatest &&
                                _hasVerifiedNNUEFile == false) {
                              _startDownload();
                            }
                          },
                        );
                      },
                    ),
                  if (prefs.enginePref == ChessEnginePref.sfLatest && _hasVerifiedNNUEFile == false)
                    LoadingButtonBuilder(
                      initialFuture: _downloadNNUEFileFuture,
                      fetchData: () => ref
                          .read(stockfishNnueServiceProvider)
                          .downloadNNUEFile(inBackground: false),
                      builder: (context, isLoading, fetchData) {
                        return SrsSettingsRow(
                          control: isLoading
                              ? AnimatedBuilder(
                                  animation: _downloadProgress,
                                  builder: (_, _) {
                                    final progress = _downloadProgress.value;
                                    return SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        value: progress > 0.0 ? progress : null,
                                        strokeWidth: 2,
                                      ),
                                    );
                                  },
                                )
                              : const Icon(Icons.download, size: 20),
                          label: isLoading ? 'Downloading NNUE file' : 'Download NNUE file',
                          help: nnueDownloadSizeMB,
                          enabled: !isLoading,
                          onTap: () async {
                            final downloaded = await fetchData();
                            if (context.mounted && downloaded) {
                              setState(() {
                                _hasVerifiedNNUEFile = true;
                                _hasUnusableNNUEFiles = false;
                              });
                            }
                          },
                        );
                      },
                    )
                  else if (prefs.enginePref == ChessEnginePref.sfLatest &&
                      _hasVerifiedNNUEFile == true)
                    SrsSettingsRow(
                      control: const Icon(Icons.check, size: 20),
                      label: 'NNUE file downloaded',
                      help: '$nnueDownloadSizeMB (tap to delete)',
                      onTap: () async {
                        final isOk = await showAdaptiveDialog<bool>(
                          context: context,
                          barrierDismissible: true,
                          builder: (context) => SrsDialog(
                            body: 'Delete the NNUE file?',
                            actions: [
                              SrsTextButton(
                                label: 'Delete',
                                onPressed: () => Navigator.of(context).pop(true),
                              ),
                              SrsTextButton(
                                label: context.l10n.cancel,
                                onPressed: () => Navigator.of(context).pop(false),
                              ),
                            ],
                          ),
                        );
                        if (isOk == true) {
                          await ref.read(stockfishNnueServiceProvider).deleteNNUEFiles();
                          if (!mounted) return;
                          setState(() {
                            _hasVerifiedNNUEFile = false;
                            _hasUnusableNNUEFiles = false;
                          });
                        }
                      },
                    ),
                  if (_hasVerifiedNNUEFile == false && _hasUnusableNNUEFiles)
                    SrsSettingsRow(
                      control: const Icon(Icons.delete_outline, size: 20),
                      label: 'Delete unusable NNUE files',
                      help:
                          'Some NNUE files on this device cannot be used by the engine. Deleting '
                          'them frees up space and lets you download them again.',
                      onTap: () async {
                        await ref.read(stockfishNnueServiceProvider).deleteNNUEFiles();
                        if (!mounted) return;
                        setState(() {
                          _hasUnusableNNUEFiles = false;
                        });
                      },
                    ),
                  const _MaiaNetworksSection(),
                  EngineSettingsWidget(
                    onSetEngineSearchTime: (value) {
                      ref
                          .read(engineEvaluationPreferencesProvider.notifier)
                          .setEngineSearchTime(value);
                    },
                    onSetEngineCores: (value) {
                      ref.read(engineEvaluationPreferencesProvider.notifier).setEngineCores(value);
                    },
                    onSetNumEvalLines: (value) {
                      ref.read(engineEvaluationPreferencesProvider.notifier).setNumEvalLines(value);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The Maia networks that have been downloaded, and a way to get the space back.
///
/// Nothing is shown until there is something to delete: one network ships with the app, and the
/// rest arrive only if someone chose that rating to play against.
class _MaiaNetworksSection extends ConsumerStatefulWidget {
  const _MaiaNetworksSection();

  @override
  ConsumerState<_MaiaNetworksSection> createState() => _MaiaNetworksSectionState();
}

class _MaiaNetworksSectionState extends ConsumerState<_MaiaNetworksSection> {
  Set<MaiaRating>? _downloaded;

  /// The networks on disk that no rating can use, left behind by an older version of the app.
  ({int count, int bytes}) _unusable = (count: 0, bytes: 0);

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final service = ref.read(maiaWeightsServiceProvider);
    // Deletes the corrupted files it finds, so what [unusableWeights] reports afterwards is only
    // what nothing claims any more.
    final available = await service.availableRatings();
    final unusable = await service.unusableWeights();
    if (!mounted) return;
    setState(() {
      _downloaded = available.where((r) => !r.isBundled).toSet();
      _unusable = unusable;
    });
  }

  @override
  Widget build(BuildContext context) {
    final downloaded = _downloaded;
    if (downloaded == null) return const SizedBox.shrink();
    if (downloaded.isEmpty && _unusable.count == 0) return const SizedBox.shrink();

    final totalBytes = downloaded.fold(0, (sum, rating) => sum + rating.expectedSize);
    final ratings = (downloaded.toList()..sort((a, b) => a.rating - b.rating))
        .map((r) => r.rating.toString())
        .join(', ');

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SrsGroupHeader('Maia networks'),
        if (downloaded.isNotEmpty)
          SrsSettingsRow(
            control: const Icon(Icons.delete_outline, size: 20),
            label: ratings,
            help: '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB (tap to delete)',
            onTap: () async {
              final isOk = await showAdaptiveDialog<bool>(
                context: context,
                barrierDismissible: true,
                builder: (context) => SrsDialog(
                  body: 'Delete the downloaded Maia networks?',
                  actions: [
                    SrsTextButton(
                      label: 'Delete',
                      onPressed: () => Navigator.of(context).pop(true),
                    ),
                    SrsTextButton(
                      label: context.l10n.cancel,
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                  ],
                ),
              );
              if (isOk != true) return;
              await ref.read(maiaWeightsServiceProvider).deleteWeights();
              if (mounted) await _refresh();
            },
          ),
        if (_unusable.count > 0)
          SrsSettingsRow(
            control: const Icon(Icons.delete_outline, size: 20),
            label: 'Delete unusable Maia networks',
            help:
                '${(_unusable.bytes / (1024 * 1024)).toStringAsFixed(1)} MB of networks this '
                'version of the app cannot use (tap to delete)',
            onTap: () async {
              await ref.read(maiaWeightsServiceProvider).deleteUnusableWeights();
              if (mounted) await _refresh();
            },
          ),
      ],
    );
  }
}
