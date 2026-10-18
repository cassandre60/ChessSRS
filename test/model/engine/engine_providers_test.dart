import 'package:chess_srs/src/model/engine/engine.dart';
import 'package:chess_srs/src/model/engine/engine_providers.dart';
import 'package:chess_srs/src/model/engine/engine_spec.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_container.dart';
import 'fake_engine.dart';

// The provider drives everything through Timers (`Timer(kEngineDisposeDelay, …)`)
// and the fake engine through `Future.delayed`, so every test advances the fake
// schedule with async.elapse instead of sleeping in real time: assertions land
// on exact schedule boundaries (a dispose or start that fires one millisecond
// early or late is caught, which the old `+50 ms` pads could not see), and the
// suite cannot flake under CPU load.
void main() {
  group('engineProvider', () {
    test('disposes an engine whose last watcher left while it was still starting', () async {
      // Long enough that the subscription can be closed while the engine is still starting, which
      // is the whole scenario: leaving the analysis screen before the engine has answered.
      fakeEngine = FakeEngine(startDelay: const Duration(milliseconds: 50));
      final container = await makeContainer();
      addTearDown(container.dispose);

      fakeAsync((async) {
        final subscription = container.listen<AsyncValue<Engine>>(
          engineProvider(const StockfishSpec.light()),
          (_, _) {},
        );

        // Nobody is waiting any more, and the engine has not started yet.
        subscription.close();
        async.elapse(Duration.zero);
        expect(fakeEngine.startCount, 1, reason: 'the create was already in flight');
        expect(fakeEngine.isRunning, isFalse);

        async.elapse(const Duration(milliseconds: 49));
        expect(fakeEngine.isRunning, isFalse, reason: '49 ms into a 50 ms start');
        expect(fakeEngine.quitCount, 0, reason: 'the in-flight start cannot be disposed early');

        async.elapse(const Duration(milliseconds: 1));
        async.elapse(Duration.zero);

        // The engine did start — the create was already in flight and nothing cancels it — so it
        // must have been quit. An engine left running here holds its native slot for the rest of
        // the process's life, and every later engine of that flavour is refused.
        expect(fakeEngine.startCount, 1);
        expect(fakeEngine.quitCount, 1);
        expect(fakeEngine.isRunning, isFalse);
      });
    });

    test('keeps the engine alive for the dispose window, then disposes it', () async {
      fakeEngine = FakeEngine();
      final container = await makeContainer();
      addTearDown(container.dispose);

      fakeAsync((async) {
        final subscription = container.listen<AsyncValue<Engine>>(
          engineProvider(const StockfishSpec.light()),
          (_, _) {},
        );
        async.elapse(Duration.zero);
        expect(fakeEngine.startCount, 1);

        subscription.close();
        async.elapse(Duration.zero);
        expect(fakeEngine.isRunning, isTrue, reason: 'the dispose window has not passed yet');

        // An early fire is a defect: the engine would be torn down while the screen could still
        // come back for it.
        async.elapse(kEngineDisposeDelay - const Duration(milliseconds: 1));
        expect(fakeEngine.quitCount, 0, reason: '1 ms inside the dispose window');

        async.elapse(const Duration(milliseconds: 1));
        expect(fakeEngine.quitCount, 1);
        async.elapse(Duration.zero);
        expect(fakeEngine.isRunning, isFalse);
      });
    });

    test('the dispose window is idle time, not a lifetime', () async {
      fakeEngine = FakeEngine();
      final container = await makeContainer();
      addTearDown(container.dispose);

      fakeAsync((async) {
        final subscription = container.listen<AsyncValue<Engine>>(
          engineProvider(const StockfishSpec.light()),
          (_, _) {},
        );
        async.elapse(Duration.zero);
        expect(fakeEngine.startCount, 1);

        // Watched for longer than the window: a timer started when the engine was built would have
        // fired by now, and the engine would be quit the moment its last watcher went away.
        async.elapse(kEngineDisposeDelay + const Duration(milliseconds: 50));
        expect(fakeEngine.startCount, 1);
        expect(fakeEngine.quitCount, 0, reason: 'the engine is watched, so nothing disposes it');

        subscription.close();
        async.elapse(Duration.zero);
        expect(
          fakeEngine.isRunning,
          isTrue,
          reason: 'the window starts when the last watcher leaves',
        );

        async.elapse(kEngineDisposeDelay - const Duration(milliseconds: 1));
        expect(fakeEngine.quitCount, 0, reason: '1 ms inside the dispose window');

        async.elapse(const Duration(milliseconds: 1));
        expect(fakeEngine.quitCount, 1);
        async.elapse(Duration.zero);
        expect(fakeEngine.isRunning, isFalse);
      });
    });

    test('an engine on another slot starts without waiting for an unwatched one to exit', () async {
      fakeEngine = FakeEngine();
      final container = await makeContainer();
      addTearDown(container.dispose);

      fakeAsync((async) {
        final subscription = container.listen<AsyncValue<Engine>>(
          engineProvider(const StockfishSpec.light()),
          (_, _) {},
        );
        async.elapse(Duration.zero);
        expect(fakeEngine.startCount, 1);

        subscription.close();
        async.elapse(Duration.zero);
        expect(fakeEngine.isRunning, isTrue, reason: 'still inside its dispose window');

        final other = container.listen<AsyncValue<Engine>>(
          engineProvider(const StockfishSpec.fairy()),
          (_, _) {},
        );
        addTearDown(other.close);
        async.elapse(Duration.zero);
        expect(fakeEngine.sessions.map((session) => session.spec), {
          const StockfishSpec.light(),
          const StockfishSpec.fairy(),
        }, reason: 'the new engine did not wait on the unwatched one');

        // The budget sizes a table for each of `kMaxResidentEngines`, so an engine waiting out its
        // window is left to it: it is one table more than that for as long as the window lasts, and
        // nothing about the new engine waits on it.
        expect(fakeEngine.quitCount, 0);
        expect(fakeEngine.sessions.length, 2);

        // It still goes when its own window ends.
        async.elapse(kEngineDisposeDelay - const Duration(milliseconds: 1));
        expect(fakeEngine.quitCount, 0, reason: '1 ms inside the dispose window');

        async.elapse(const Duration(milliseconds: 1));
        expect(fakeEngine.quitCount, 1);
        expect(fakeEngine.sessions.single.spec, const StockfishSpec.fairy());
      });
    });
  });
}
