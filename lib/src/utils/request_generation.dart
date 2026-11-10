import 'package:meta/meta.dart';

/// The version counter that fences concurrent requests: only the newest claim
/// is current, so a request that was already running when the world moved on
/// can tell it is stale and drop out instead of publishing over the newer one.
///
/// The pattern is claim, then check, then act: a long-running request claims a
/// generation with [claim] before its first await, and every continuation after
/// that await re-checks [isCurrent] before touching shared state. Any new claim
/// — including a bare supersede that promises nothing of its own — moves the
/// counter on, which is what makes every older claim's check false.
///
/// Several controllers in the repository carry this counter alongside extra
/// protocol of their own — a null-return load protocol, an ownership tag for
/// an in-flight acquisition, an in-flight dedup map — and keep their bespoke
/// counters; this type serves the plain cases.
@internal
class RequestGeneration {
  int _counter = 0;

  /// Stamps a request with the newest generation. The value is held by the
  /// request and re-presented to [isCurrent] after every await.
  int claim() => ++_counter;

  /// Whether [generation] is still the newest claim.
  bool isCurrent(int generation) => generation == _counter;
}
