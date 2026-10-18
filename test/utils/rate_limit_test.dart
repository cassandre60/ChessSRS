// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:chess_srs/src/utils/rate_limit.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

// All timing uses fakeAsync: every delay is advanced with async.elapse, so no
// test sleeps in real wall-clock time and each assertion lands on an exact
// schedule boundary. Under CPU load this cannot flake, and a timer that fires
// one millisecond late (or early) is caught instead of hidden inside a
// generous sleep margin.
void main() {
  group('debounce', () {
    test('should call the callback after the delay', () {
      fakeAsync((async) {
        final debouncer = Debouncer(const Duration(milliseconds: 100));
        var called = false;
        debouncer(() {
          called = true;
        });
        async.elapse(const Duration(milliseconds: 99));
        expect(called, isFalse, reason: '99 ms into a 100 ms debounce it must not have run');
        async.elapse(const Duration(milliseconds: 1));
        expect(called, isTrue);
      });
    });

    test('should not execute callback more than once if called multiple times', () {
      fakeAsync((async) {
        final debouncer = Debouncer(const Duration(milliseconds: 100));
        var called = 0;
        debouncer(() {
          called++;
        });
        debouncer(() {
          called++;
        });
        debouncer(() {
          called++;
        });
        async.elapse(const Duration(milliseconds: 150));
        expect(called, 1);
      });
    });

    test('should cancel the previous callback', () {
      fakeAsync((async) {
        final debouncer = Debouncer(const Duration(milliseconds: 100));
        var called = false;
        debouncer(() {
          called = true;
        });
        debouncer(() {
          called = false;
        });
        async.elapse(const Duration(milliseconds: 150));
        expect(called, isFalse);
      });
    });

    test('cancel should cancel the callback', () {
      fakeAsync((async) {
        final debouncer = Debouncer(const Duration(milliseconds: 100));
        var called = false;
        debouncer(() {
          called = true;
        });
        async.elapse(const Duration(milliseconds: 20));
        debouncer.cancel();
        async.elapse(const Duration(milliseconds: 150));
        expect(called, isFalse);
      });
    });
  });

  group('throttle', () {
    test('should call the callback immediately', () {
      final throttler = Throttler(const Duration(milliseconds: 100));
      var called = false;
      throttler(() {
        called = true;
      });
      expect(called, true);
    });

    test('should call the callback only once within delay', () {
      fakeAsync((async) {
        final throttler = Throttler(const Duration(milliseconds: 100));
        var called = 0;
        throttler(() {
          called++;
        });
        throttler(() {
          called++;
        });
        throttler(() {
          called++;
        });
        async.elapse(const Duration(milliseconds: 150));
        expect(called, 1);
      });
    });

    test('drops a call made within the delay when not trailing', () {
      fakeAsync((async) {
        final throttler = Throttler(const Duration(milliseconds: 100));
        var called = 0;
        throttler(() => called++);
        async.elapse(const Duration(milliseconds: 99));
        throttler(() => called++); // 99 ms into a 100 ms window: dropped
        async.elapse(const Duration(milliseconds: 1));
        throttler(() => called++); // the window expired at exactly 100 ms
        expect(called, 2, reason: 'a call at exactly the window expiry must not be swallowed');
      });
    });

    test('runs a trailing call once the delay expires', () {
      fakeAsync((async) {
        final throttler = Throttler(const Duration(milliseconds: 100), trailing: true);
        var called = 0;
        throttler(() => called++);
        async.elapse(const Duration(milliseconds: 50));
        throttler(() => called++);
        expect(called, 1, reason: 'the second call waits for the delay to expire');
        async.elapse(const Duration(milliseconds: 150));
        expect(called, 2);
      });
    });

    test('coalesces the calls made within the delay into a single trailing run', () {
      fakeAsync((async) {
        final throttler = Throttler(const Duration(milliseconds: 100), trailing: true);
        final calls = <String>[];
        throttler(() => calls.add('first'));
        throttler(() => calls.add('second'));
        throttler(() => calls.add('third'));
        async.elapse(const Duration(milliseconds: 300));
        expect(calls, ['first', 'third'], reason: 'the last action of the window wins');
      });
    });

    test('a trailing run opens a new delay of its own', () {
      fakeAsync((async) {
        final throttler = Throttler(const Duration(milliseconds: 100), trailing: true);
        var called = 0;
        throttler(() => called++);
        throttler(() => called++);
        async.elapse(const Duration(milliseconds: 150));
        expect(called, 2);
        throttler(() => called++);
        expect(called, 2, reason: 'the trailing run throttles what follows it');
        async.elapse(const Duration(milliseconds: 150));
        expect(called, 3);
      });
    });

    test('cancel drops a pending trailing call', () {
      fakeAsync((async) {
        final throttler = Throttler(const Duration(milliseconds: 100), trailing: true);
        var called = 0;
        throttler(() => called++);
        throttler(() => called++);
        throttler.cancel();
        async.elapse(const Duration(milliseconds: 150));
        expect(called, 1);
      });
    });

    test('should call the callback multiple times if delay is passed', () {
      fakeAsync((async) {
        final throttler = Throttler(const Duration(milliseconds: 100));
        var called = 0;
        throttler(() {
          called++;
        });
        throttler(() {
          called++;
        });
        async.elapse(const Duration(milliseconds: 150));
        throttler(() {
          called++;
        });
        async.elapse(const Duration(milliseconds: 150));
        throttler(() {
          called++;
        });
        async.elapse(const Duration(milliseconds: 150));
        expect(called, 3);
      });
    });
  });
}
