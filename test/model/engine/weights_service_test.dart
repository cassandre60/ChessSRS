import 'dart:async';
import 'dart:io';

import 'package:chess_srs/src/model/common/preloaded_data.dart';
import 'package:chess_srs/src/model/engine/opponent_level.dart';
import 'package:chess_srs/src/model/engine/weights_service.dart';
import 'package:chess_srs/src/network/connectivity.dart';
import 'package:chess_srs/src/network/http.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../network/fake_http_client_factory.dart';

/// The bundled network's own bytes, which is the only content with a matching checksum.
Future<List<int>> bundledWeightsBytes() =>
    File('assets/maia/${MaiaRating.defaultRating.fileName}').readAsBytes();

/// A connectivity plugin that always reports the same thing.
class _FakeConnectivity implements Connectivity {
  _FakeConnectivity([this.result = ConnectivityResult.wifi]);

  final ConnectivityResult result;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() => Future.value([result]);

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => Stream.value([result]);
}

ProviderContainer makeWeightsContainer({
  required Directory? appSupportDirectory,
  MockClient? mockClient,
  Connectivity? connectivity,
}) {
  final container = ProviderContainer(
    overrides: [
      preloadedDataProvider.overrideWith((ref) {
        return (
          sri: 'test-sri',
          packageInfo: PackageInfo(
            appName: 'lichess_mobile_test',
            version: '0.0.0',
            buildNumber: '0',
            packageName: 'lichess_mobile_test',
          ),
          deviceInfo: BaseDeviceInfo({'name': 'test'}),
          authUser: null,
          engineMaxMemoryInMb: 256,
          appDocumentsDirectory: null,
          appSupportDirectory: appSupportDirectory,
        );
      }),
      if (mockClient != null)
        httpClientFactoryProvider.overrideWith((ref) {
          return FakeHttpClientFactory(() => mockClient);
        }),
      if (connectivity != null) connectivityPluginProvider.overrideWith((_) => connectivity),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<Directory> makeTempDir() async {
  final dir = await Directory.systemTemp.createTemp('maia_weights_test_');
  addTearDown(() => dir.delete(recursive: true));
  return dir;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MaiaWeightsService', () {
    test('the bundled networks are available before anything has been downloaded', () async {
      final container = makeWeightsContainer(appSupportDirectory: await makeTempDir());
      final service = container.read(maiaWeightsServiceProvider);

      expect(await service.isAvailable(MaiaRating.defaultRating), isTrue);
      expect(await service.isAvailable(MaiaRating.maia1700), isFalse);
      expect(await service.availableRatings(), MaiaRating.bundledRatings);
    });

    test('writes the bundled network out of the asset bundle, once', () async {
      final dir = await makeTempDir();
      final container = makeWeightsContainer(appSupportDirectory: dir);
      final service = container.read(maiaWeightsServiceProvider);

      final (:rating, :path) = await service.ensureWeights(MaiaRating.defaultRating);

      // LC0 reads its network from a path, so even the bundled one has to reach the disk.
      expect(rating, MaiaRating.defaultRating);
      expect(path, '${dir.path}/maia/${MaiaRating.defaultRating.fileName}');
      expect(await File(path).length(), MaiaRating.defaultRating.expectedSize);

      // The second call is served from the file that is already there.
      final again = await service.ensureWeights(MaiaRating.defaultRating);
      expect(again.path, path);
    });

    // test('writes a bundled network that is not the default one, without the network', () async {
    //   final dir = await makeTempDir();
    //   final container = makeWeightsContainer(
    //     appSupportDirectory: dir,
    //     mockClient: MockClient((_) async => http.Response('', 404)),
    //   );
    //   final service = container.read(maiaWeightsServiceProvider);

    //   final (:rating, :path) = await service.ensureWeights(MaiaRating.maia1900);

    //   expect(rating, MaiaRating.maia1900);
    //   expect(path, '${dir.path}/maia/maia-1900.pb.gz');
    //   expect(await File(path).length(), MaiaRating.maia1900.expectedSize);
    // });

    test('downloads a network that is not there, and checks what it got', () async {
      final dir = await makeTempDir();
      final bytes = await bundledWeightsBytes();
      final requested = <Uri>[];
      final container = makeWeightsContainer(
        appSupportDirectory: dir,
        mockClient: MockClient((request) async {
          requested.add(request.url);
          return http.Response.bytes(bytes, 200);
        }),
      );
      final service = container.read(maiaWeightsServiceProvider);

      // The bytes served are the 1500 network's, so this is the only rating whose checksum can
      // match what the fake server hands back.
      final path = await service.download(MaiaRating.defaultRating);

      expect(path, '${dir.path}/maia/${MaiaRating.defaultRating.fileName}');
      expect(requested.single.path, endsWith('/maia-1500.pb.gz'));
    });

    test('a download whose checksum does not match is thrown away', () async {
      final dir = await makeTempDir();
      final container = makeWeightsContainer(
        appSupportDirectory: dir,
        mockClient: MockClient((_) async => http.Response('not a network', 200)),
      );
      final service = container.read(maiaWeightsServiceProvider);

      expect(await service.download(MaiaRating.maia1700), isNull);
      expect(await service.isAvailable(MaiaRating.maia1700), isFalse);
      expect(await File('${dir.path}/maia/maia-1700.pb.gz').exists(), isFalse);
    });

    test('a rating that cannot be downloaded falls back to the bundled network', () async {
      final dir = await makeTempDir();
      final container = makeWeightsContainer(
        appSupportDirectory: dir,
        mockClient: MockClient((_) async => http.Response('', 404)),
      );
      final service = container.read(maiaWeightsServiceProvider);

      final (:rating, :path) = await service.ensureWeights(MaiaRating.maia1700);

      // An opponent that cannot move because a download did not work is a dead end.
      expect(rating, MaiaRating.defaultRating);
      expect(path, endsWith('/maia-1500.pb.gz'));
    });

    test('two callers asking at once share one download', () async {
      final dir = await makeTempDir();
      final bytes = await bundledWeightsBytes();
      var requests = 0;
      final container = makeWeightsContainer(
        appSupportDirectory: dir,
        mockClient: MockClient((_) async {
          requests++;
          return http.Response.bytes(bytes, 200);
        }),
      );
      final service = container.read(maiaWeightsServiceProvider);

      await Future.wait([
        service.download(MaiaRating.defaultRating),
        service.download(MaiaRating.defaultRating),
      ]);

      expect(requests, 1);
    });

    test('deleting the downloaded networks leaves the bundled one obtainable', () async {
      final dir = await makeTempDir();
      final container = makeWeightsContainer(appSupportDirectory: dir);
      final service = container.read(maiaWeightsServiceProvider);

      final (:path, rating: _) = await service.ensureWeights(MaiaRating.defaultRating);
      await service.deleteWeights();
      expect(await File(path).exists(), isFalse);

      expect(await service.isAvailable(MaiaRating.defaultRating), isTrue);
      expect((await service.ensureWeights(MaiaRating.defaultRating)).path, path);
    });

    test('a network on disk that fails its checksum is deleted', () async {
      final dir = await makeTempDir();
      final container = makeWeightsContainer(appSupportDirectory: dir);
      final service = container.read(maiaWeightsServiceProvider);

      final file = File('${dir.path}/maia/maia-1700.pb.gz');
      await file.parent.create(recursive: true);
      await file.writeAsString('not a network');

      expect(await service.isAvailable(MaiaRating.maia1700), isFalse);
      expect(await file.exists(), isFalse);
    });

    test('isAvailable returns false and does not delete file during in-flight download', () async {
      final dir = await makeTempDir();
      final downloadCompleter = Completer<void>();
      final fileWrittenCompleter = Completer<void>();

      final container = makeWeightsContainer(
        appSupportDirectory: dir,
        mockClient: MockClient((_) async {
          final file = File('${dir.path}/maia/maia-1700.pb.gz');
          await file.parent.create(recursive: true);
          await file.writeAsBytes([1, 2, 3, 4, 5]);

          if (!fileWrittenCompleter.isCompleted) {
            fileWrittenCompleter.complete();
          }

          await downloadCompleter.future;
          return http.Response('test content', 200);
        }),
      );
      final service = container.read(maiaWeightsServiceProvider);

      final downloadFuture = service.download(MaiaRating.maia1700);

      await fileWrittenCompleter.future;

      final file = service.weightsFile(MaiaRating.maia1700);
      expect(await file.exists(), isTrue);
      expect(await service.isAvailable(MaiaRating.maia1700), isFalse);
      expect(await file.exists(), isTrue);

      downloadCompleter.complete();
      await downloadFuture;
    });

    test('a corrupted bundled network is replaced by the one in the asset bundle', () async {
      final dir = await makeTempDir();
      final container = makeWeightsContainer(appSupportDirectory: dir);
      final service = container.read(maiaWeightsServiceProvider);

      final file = File('${dir.path}/maia/${MaiaRating.defaultRating.fileName}');
      await file.parent.create(recursive: true);
      await file.writeAsString('not a network');

      final (:rating, :path) = await service.ensureWeights(MaiaRating.defaultRating);

      expect(rating, MaiaRating.defaultRating);
      expect(path, file.path);
      expect(await file.length(), MaiaRating.defaultRating.expectedSize);
    });

    test('a download that fails leaves nothing behind', () async {
      final dir = await makeTempDir();
      final container = makeWeightsContainer(
        appSupportDirectory: dir,
        mockClient: MockClient((_) async => http.Response('nope', 404)),
      );
      final service = container.read(maiaWeightsServiceProvider);

      expect(await service.download(MaiaRating.maia1700), isNull);
      expect(await File('${dir.path}/maia/maia-1700.pb.gz').exists(), isFalse);
    });

    test('networks no rating claims can be reported and deleted on their own', () async {
      final dir = await makeTempDir();
      final container = makeWeightsContainer(appSupportDirectory: dir);
      final service = container.read(maiaWeightsServiceProvider);

      // The bundled network, written out, is claimed and must survive.
      final (:path, rating: _) = await service.ensureWeights(MaiaRating.defaultRating);
      final stray = File('${dir.path}/maia/maia-4200.pb.gz');
      await stray.writeAsString('a network from another era');

      expect(await service.unusableWeights(), (count: 1, bytes: await stray.length()));

      await service.deleteUnusableWeights();

      expect(await stray.exists(), isFalse);
      expect(await File(path).exists(), isTrue);
      expect(await service.unusableWeights(), (count: 0, bytes: 0));
    });

    test('unusableWeights does not report in-flight download as unusable', () async {
      final dir = await makeTempDir();
      final downloadCompleter = Completer<void>();
      final fileWrittenCompleter = Completer<void>();

      final container = makeWeightsContainer(
        appSupportDirectory: dir,
        mockClient: MockClient((_) async {
          final file = File('${dir.path}/maia/maia-1700.pb.gz');
          await file.parent.create(recursive: true);
          await file.writeAsBytes([1, 2, 3, 4, 5]);

          if (!fileWrittenCompleter.isCompleted) {
            fileWrittenCompleter.complete();
          }

          await downloadCompleter.future;
          return http.Response('test content', 200);
        }),
      );
      final service = container.read(maiaWeightsServiceProvider);

      final downloadFuture = service.download(MaiaRating.maia1700);

      await fileWrittenCompleter.future;

      expect(await service.unusableWeights(), (count: 0, bytes: 0));

      downloadCompleter.complete();
      await downloadFuture;
    });

    test('reports rather than throws when there is nowhere to put a network', () async {
      final container = makeWeightsContainer(appSupportDirectory: null);
      final service = container.read(maiaWeightsServiceProvider);

      expect(await service.isAvailable(MaiaRating.maia1700), isFalse);
      expect(await service.download(MaiaRating.maia1700), isNull);
    });

    // SPEC INV-020. No invariant names the weights service itself; INV-020 is the
    // nearest one: the engine is given the network it is meant to play with.
    test('the unusable networks are reported as none when there is nowhere to put one', () async {
      final container = makeWeightsContainer(appSupportDirectory: null);
      final service = container.read(maiaWeightsServiceProvider);

      // The settings screen asks this question every time it opens, so it has to have an answer
      // even when there is nowhere to put a network: "nothing to clean up" is an answer, and an
      // exception is not one.
      expect(await service.unusableWeights(), (count: 0, bytes: 0));
    });

    // SPEC INV-020. No invariant names the weights service itself; INV-020 is the
    // nearest one: the engine is given the network it is meant to play with.
    test('deleting the unusable networks does nothing when there is nowhere to put one', () async {
      final container = makeWeightsContainer(appSupportDirectory: null);
      final service = container.read(maiaWeightsServiceProvider);

      // There is nothing to delete, and the caller's request has been carried out: the same
      // answer [deleteWeights] gives when there is nowhere to put a network.
      await expectLater(service.deleteUnusableWeights(), completes);
    });

    // SPEC INV-020.
    test('each rating has a file of its own', () async {
      final dir = await makeTempDir();
      final container = makeWeightsContainer(appSupportDirectory: dir);
      final service = container.read(maiaWeightsServiceProvider);

      final bundled = service.weightsFile(MaiaRating.defaultRating);
      final other = service.weightsFile(MaiaRating.maia1700);

      // Two ratings that share a file would overwrite each other: one of them would be played
      // with the other's network.
      expect(bundled.path, '${dir.path}/maia/${MaiaRating.defaultRating.fileName}');
      expect(other.path, '${dir.path}/maia/${MaiaRating.maia1700.fileName}');
      expect(other.path, isNot(bundled.path));
    });

    // SPEC INV-020.
    test('the download asks for the network of the rating that was asked for', () async {
      final dir = await makeTempDir();
      final requested = <Uri>[];
      final container = makeWeightsContainer(
        appSupportDirectory: dir,
        mockClient: MockClient((request) async {
          requested.add(request.url);
          return http.Response('not a network', 200);
        }),
      );
      final service = container.read(maiaWeightsServiceProvider);

      await service.download(MaiaRating.maia1700);

      expect(requested.single.path, endsWith('/maia-1700.pb.gz'));
    });

    // SPEC INV-020.
    test('a network is checked against the checksum of its own rating', () async {
      final dir = await makeTempDir();
      final container = makeWeightsContainer(appSupportDirectory: dir);
      final service = container.read(maiaWeightsServiceProvider);

      // The bundled network's bytes, stored under another rating's name: a valid network, but
      // not this rating's network.
      final file = service.weightsFile(MaiaRating.maia1700);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(await bundledWeightsBytes());

      expect(await service.isAvailable(MaiaRating.maia1700), isFalse);
      expect(await file.exists(), isFalse);
    });

    // SPEC INV-020.
    test('a network downloaded over a verified one is checked again', () async {
      final dir = await makeTempDir();
      final container = makeWeightsContainer(
        appSupportDirectory: dir,
        mockClient: MockClient((_) async => http.Response('not a network', 200)),
      );
      final service = container.read(maiaWeightsServiceProvider);

      // The bundled network is written out and verified in this session.
      final (:path, rating: _) = await service.ensureWeights(MaiaRating.defaultRating);
      expect(await File(path).exists(), isTrue);

      // A download that does not check out is thrown away, even though the network was
      // verified a moment ago: what landed on disk is what has to be checked.
      expect(await service.download(MaiaRating.defaultRating), isNull);
      expect(await File(path).exists(), isFalse);
    });

    // SPEC INV-020.
    test('a download can be started again once the first one has finished', () async {
      final dir = await makeTempDir();
      final bytes = await bundledWeightsBytes();
      var requests = 0;
      final container = makeWeightsContainer(
        appSupportDirectory: dir,
        mockClient: MockClient((_) async {
          requests++;
          return http.Response.bytes(bytes, 200);
        }),
      );
      final service = container.read(maiaWeightsServiceProvider);

      await service.download(MaiaRating.defaultRating);
      await service.download(MaiaRating.defaultRating);

      // The second download is a new one, not the finished first one handed out again.
      expect(requests, 2);
      expect(service.downloading, isNull);
    });

    // SPEC INV-020.
    test('the download reports its progress and resets it when it ends', () async {
      final dir = await makeTempDir();
      final bytes = await bundledWeightsBytes();
      final container = makeWeightsContainer(
        appSupportDirectory: dir,
        mockClient: MockClient((_) async => http.Response.bytes(bytes, 200)),
      );
      final service = container.read(maiaWeightsServiceProvider);

      final progress = <double>[];
      service.downloadProgress.addListener(() {
        progress.add(service.downloadProgress.value);
      });

      await service.download(MaiaRating.defaultRating);

      expect(progress, isNotEmpty);
      expect(progress.any((value) => value > 0.0), isTrue);
      // The download is over: the progress is back to zero, not left at a hundred per cent.
      expect(service.downloadProgress.value, 0.0);
    });

    // SPEC INV-020.
    test('a file that is not a network is not reported as an unusable one', () async {
      final dir = await makeTempDir();
      final container = makeWeightsContainer(appSupportDirectory: dir);
      final service = container.read(maiaWeightsServiceProvider);

      final (:path, rating: _) = await service.ensureWeights(MaiaRating.defaultRating);
      final stray = File('${dir.path}/maia/notes.txt');
      await stray.writeAsString('not a network');

      expect(await service.unusableWeights(), (count: 0, bytes: 0));
      expect(await File(path).exists(), isTrue);
    });

    // SPEC INV-020.
    test('a directory named like a network does not hide the ones to clean up', () async {
      final dir = await makeTempDir();
      final container = makeWeightsContainer(appSupportDirectory: dir);
      final service = container.read(maiaWeightsServiceProvider);

      final stray = File('${dir.path}/maia/maia-4200.pb.gz');
      await stray.parent.create(recursive: true);
      await stray.writeAsString('a network from another era');
      await Directory('${dir.path}/maia/maia-4300.pb.gz').create();

      // The directory is not a network, and it must not stop the network that is one from
      // being reported: a stray network nothing claims is space the app can give back.
      expect(await service.unusableWeights(), (count: 1, bytes: await stray.length()));
    });

    // SPEC INV-020.
    test('the bundled network is written out again after the networks are deleted', () async {
      final dir = await makeTempDir();
      final container = makeWeightsContainer(appSupportDirectory: dir);
      final service = container.read(maiaWeightsServiceProvider);

      final (:path, rating: _) = await service.ensureWeights(MaiaRating.defaultRating);
      await service.deleteWeights();
      expect(await File(path).exists(), isFalse);

      await service.ensureWeights(MaiaRating.defaultRating);

      // The network was deleted, so it has to be written out again: a path to a file that is
      // not there is a path LC0 cannot read.
      expect(await File(path).exists(), isTrue);
    });

    // SPEC INV-020. No invariant names the weights service itself; INV-020 is the
    // nearest one: the engine is given the network it is meant to play with.
    test('the bundled network is produced from the asset bundle, not from the network', () async {
      final dir = await makeTempDir();
      final bytes = await bundledWeightsBytes();
      var requests = 0;
      final container = makeWeightsContainer(
        appSupportDirectory: dir,
        mockClient: MockClient((_) async {
          requests++;
          return http.Response.bytes(bytes, 200);
        }),
      );
      final service = container.read(maiaWeightsServiceProvider);

      final (:rating, :path) = await service.ensureWeights(MaiaRating.defaultRating);

      expect(rating, MaiaRating.defaultRating);
      // The bundled network is in the app already: fetching it would cost the user data for a
      // file the app already carries, and would leave the opponent unplayable offline.
      expect(requests, 0);
      // What landed on disk is the whole bundled network.
      expect(await File(path).length(), MaiaRating.defaultRating.expectedSize);
    });

    // SPEC INV-020. No invariant names the weights service itself; INV-020 is the
    // nearest one: the engine is given the network it is meant to play with.
    test('the rating being downloaded is reported while the download is in flight', () async {
      final dir = await makeTempDir();
      final gate = Completer<void>();
      final container = makeWeightsContainer(
        appSupportDirectory: dir,
        mockClient: MockClient((_) async {
          await gate.future;
          return http.Response('not a network', 200);
        }),
      );
      final service = container.read(maiaWeightsServiceProvider);

      final download = service.download(MaiaRating.maia1700);

      // The download is in flight, and the rating it is for is reported.
      expect(service.downloading, MaiaRating.maia1700);

      gate.complete();
      await download;

      // Nothing is in flight any more.
      expect(service.downloading, isNull);
    });

    // SPEC INV-020. No invariant names the weights service itself; INV-020 is the
    // nearest one: the engine is given the network it is meant to play with.
    test('a network outside the weights directory is not one of ours to delete', () async {
      final dir = await makeTempDir();
      final container = makeWeightsContainer(appSupportDirectory: dir);
      final service = container.read(maiaWeightsServiceProvider);

      // A network file in the app support directory itself, not in the weights directory.
      final stray = File('${dir.path}/maia-4200.pb.gz');
      await stray.writeAsString('a network from another era');

      expect(await service.unusableWeights(), (count: 0, bytes: 0));

      await service.deleteUnusableWeights();

      // Nothing outside the weights directory is ours to report, or to delete.
      expect(await stray.exists(), isTrue);
    });

    // SPEC INV-020. No invariant names the weights service itself; INV-020 is the
    // nearest one: the engine is given the network it is meant to play with.
    test('a link to a network is not a network to clean up', () async {
      final dir = await makeTempDir();
      final elsewhere = await makeTempDir();
      final target = File('${elsewhere.path}/precious.txt');
      await target.writeAsString('not ours to delete');
      // A link that looks like a network, pointing at a file that is not the app's.
      final link = Link('${dir.path}/maia/linked.pb.gz');
      await link.parent.create(recursive: true);
      await link.create(target.path);

      final container = makeWeightsContainer(appSupportDirectory: dir);
      final service = container.read(maiaWeightsServiceProvider);

      // The app did not write that file, so it is not space the app can give back.
      expect(await service.unusableWeights(), (count: 0, bytes: 0));

      await service.deleteUnusableWeights();

      expect(await link.exists(), isTrue);
      expect(await target.exists(), isTrue);
    });

    // SPEC INV-020. No invariant names the weights service itself; INV-020 is the
    // nearest one: the engine is given the network it is meant to play with.
    test('a bundled network that cannot be written is an error, not a fallback', () async {
      final dir = await makeTempDir();
      // The weights directory cannot be a file, so the bundled network cannot be written out.
      await File('${dir.path}/maia').writeAsString('not a directory');
      final container = makeWeightsContainer(appSupportDirectory: dir);
      final service = container.read(maiaWeightsServiceProvider);

      // There is no network to fall back to either, and that is an error the caller has to see.
      await expectLater(service.ensureWeights(MaiaRating.defaultRating), throwsA(isA<Exception>()));
    });
  });

  group('StockfishNnueService', () {
    // SPEC INV-020.
    test('an app support directory with no net in it holds no outdated net', () async {
      final dir = await makeTempDir();
      final container = makeWeightsContainer(appSupportDirectory: dir);
      final service = container.read(stockfishNnueServiceProvider);

      expect(await service.hasOutdatedNNUEFiles(), isFalse);
    });

    // SPEC INV-020.
    test('a file that is not a net is not an outdated net', () async {
      final dir = await makeTempDir();
      await File('${dir.path}/notes.txt').writeAsString('hello');
      final container = makeWeightsContainer(appSupportDirectory: dir);
      final service = container.read(stockfishNnueServiceProvider);

      expect(await service.hasOutdatedNNUEFiles(), isFalse);
    });

    // SPEC INV-020.
    test('the net on disk is reported', () async {
      final dir = await makeTempDir();
      await File('${dir.path}/some.net.nnue').writeAsString('a net');
      final container = makeWeightsContainer(appSupportDirectory: dir);
      final service = container.read(stockfishNnueServiceProvider);

      expect(await service.hasNNUEFilesOnDisk(), isTrue);
    });

    // SPEC INV-020.
    test('an app support directory with no net in it holds no net', () async {
      final dir = await makeTempDir();
      await File('${dir.path}/notes.txt').writeAsString('hello');
      final container = makeWeightsContainer(appSupportDirectory: dir);
      final service = container.read(stockfishNnueServiceProvider);

      expect(await service.hasNNUEFilesOnDisk(), isFalse);
    });

    // SPEC INV-020.
    test('no net on disk is reported as none when there is nowhere to put one', () async {
      final container = makeWeightsContainer(appSupportDirectory: null);
      final service = container.read(stockfishNnueServiceProvider);

      expect(await service.hasNNUEFilesOnDisk(), isFalse);
    });

    // SPEC INV-020.
    test('deleting the nets leaves a directory that looks like one alone', () async {
      final dir = await makeTempDir();
      final lookalike = Directory('${dir.path}/old-net.nnue');
      await lookalike.create();
      final net = File('${dir.path}/real.nnue');
      await net.writeAsString('a net');

      final container = makeWeightsContainer(appSupportDirectory: dir);
      final service = container.read(stockfishNnueServiceProvider);

      await service.deleteNNUEFiles();

      // Only files are nets: a directory that is named like one is not one, and deleting the
      // nets does not delete it.
      expect(await lookalike.exists(), isTrue);
      expect(await net.exists(), isFalse);
    });

    // SPEC INV-020.
    test('a download that cannot ask for confirmation is refused', () async {
      final dir = await makeTempDir();
      var requests = 0;
      final container = makeWeightsContainer(
        appSupportDirectory: dir,
        mockClient: MockClient((_) async {
          requests++;
          return http.Response('', 404);
        }),
        connectivity: _FakeConnectivity(ConnectivityResult.mobile),
      );
      final service = container.read(stockfishNnueServiceProvider);

      // There is no navigator in a test, so the confirmation the user has to give cannot be
      // asked for, and a download that cannot ask is not a download that happened.
      expect(await service.downloadNNUEFile(inBackground: false), isFalse);
      expect(requests, 0);
    });

    // SPEC INV-020.
    test('a net that cannot be read is not a net that checks out', () async {
      final dir = await makeTempDir();
      final container = makeWeightsContainer(appSupportDirectory: dir);
      final service = container.read(stockfishNnueServiceProvider);

      final file = service.nnueFile;
      await file.writeAsString('a net');
      // Take the read permission away, so that reading the net fails instead of returning
      // bytes. (A no-op where the platform has no such permission: the test then checks the
      // readable case, which is the same contract.)
      await Process.run('chmod', ['000', file.path]);

      // A net that cannot be read is not a net that checks out: the failure to read it must
      // not be read as "the net is fine".
      expect(await service.checkNNUEFile(), isFalse);
    });

    // SPEC INV-020.
    test('the download is not in progress once every byte has arrived', () async {
      final dir = await makeTempDir();
      final container = makeWeightsContainer(
        appSupportDirectory: dir,
        mockClient: MockClient((_) async => http.Response('not a net', 200)),
        connectivity: _FakeConnectivity(),
      );
      final service = container.read(stockfishNnueServiceProvider);

      final seen = <bool>[];
      service.nnueDownloadProgress.addListener(() {
        if (service.nnueDownloadProgress.value == 1.0) {
          seen.add(service.isDownloadingNNUEFile);
        }
      });

      await service.downloadNNUEFile(inBackground: true);

      // Every byte has arrived, so the download is no longer in progress.
      expect(seen, isNotEmpty);
      expect(seen, everyElement(isFalse));
    });

    // SPEC INV-020. No invariant names the weights service itself; INV-020 is the
    // nearest one: the engine is given the network it is meant to play with.
    test('the download progress is back to zero when the download ends', () async {
      final dir = await makeTempDir();
      final container = makeWeightsContainer(
        appSupportDirectory: dir,
        mockClient: MockClient((_) async => http.Response('not a net', 200)),
        connectivity: _FakeConnectivity(),
      );
      final service = container.read(stockfishNnueServiceProvider);

      final seen = <double>[];
      service.nnueDownloadProgress.addListener(() {
        seen.add(service.nnueDownloadProgress.value);
      });

      await service.downloadNNUEFile(inBackground: true);

      // The bytes arrived, so the progress was reported...
      expect(seen, isNotEmpty);
      expect(seen.any((value) => value > 0.0), isTrue);
      // ...and the download is over: the progress is back to zero, not left at a hundred
      // per cent.
      expect(service.nnueDownloadProgress.value, 0.0);
    });

    // SPEC INV-020. No invariant names the weights service itself; INV-020 is the
    // nearest one: the engine is given the network it is meant to play with.
    test('a download asked for in the background is refused on mobile data', () async {
      final dir = await makeTempDir();
      var requests = 0;
      final container = makeWeightsContainer(
        appSupportDirectory: dir,
        mockClient: MockClient((_) async {
          requests++;
          return http.Response('', 404);
        }),
        connectivity: _FakeConnectivity(ConnectivityResult.mobile),
      );
      final service = container.read(stockfishNnueServiceProvider);

      // A download nobody was asked about is not one to make on mobile data.
      await expectLater(service.downloadNNUEFile(), throwsA(isA<Exception>()));
      expect(requests, 0);
    });

    // SPEC INV-020. No invariant names the weights service itself; INV-020 is the
    // nearest one: the engine is given the network it is meant to play with.
    test('a link to a net is not a net the app manages', () async {
      final dir = await makeTempDir();
      final elsewhere = await makeTempDir();
      final target = File('${elsewhere.path}/precious.txt');
      await target.writeAsString('not ours to delete');
      // A link that looks like a net, pointing at a file that is not the app's.
      final link = Link('${dir.path}/linked.nnue');
      await link.create(target.path);

      final container = makeWeightsContainer(appSupportDirectory: dir);
      final service = container.read(stockfishNnueServiceProvider);

      // The app did not write that file, so it is not a net of ours to count, or to delete.
      expect(await service.hasNNUEFilesOnDisk(), isFalse);
      expect(await service.hasOutdatedNNUEFiles(), isFalse);

      await service.deleteNNUEFiles();

      expect(await link.exists(), isTrue);
      expect(await target.exists(), isTrue);
    });
  });
}
