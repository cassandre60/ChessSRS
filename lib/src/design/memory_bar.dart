// Three-state memory bar. Encoded by SHAPE, never by colour alone:
//   retained = solid ink, learning = ink hatch, new = empty with 1px outline.
// Adapted from design/flutter/memory_bar.dart.
import 'package:chess_srs/src/design/hatch.dart';
import 'package:chess_srs/src/design/tokens.dart';
import 'package:flutter/widgets.dart';

class SrsMemoryBar extends StatelessWidget {
  const SrsMemoryBar({
    super.key,
    required this.retained,
    required this.learning,
    required this.fresh,
    this.height = 5,
    this.gap = 2,
    this.radius = 1,
    this.width,
  });
  final int retained;
  final int learning;
  final int fresh;
  final double height;
  final double gap;
  final double radius;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final c = context.srs;
    final r = BorderRadius.circular(radius);

    // A bar with nothing in it (no positions at all) would otherwise render as a
    // 5px-tall empty gap, which reads as a rendering fault rather than as "no
    // material on this side yet". The outline keeps the slot legible without
    // implying progress, and it is what `fresh` segments already look like.
    if (retained == 0 && learning == 0 && fresh == 0) {
      return Semantics(
        label: 'no positions',
        child: SizedBox(
          height: height,
          width: width,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: r,
              border: Border.all(color: c.hairlineSoft, width: 1),
            ),
          ),
        ),
      );
    }

    final segs = <Widget>[
      if (retained > 0)
        Expanded(
          flex: retained,
          child: DecoratedBox(
            decoration: BoxDecoration(color: c.ink, borderRadius: r),
          ),
        ),
      if (learning > 0)
        Expanded(
          flex: learning,
          child: ClipRRect(
            borderRadius: r,
            child: CustomPaint(
              painter: HatchPainter(color: c.ink, gap: 3.2, width: 1.2),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      if (fresh > 0)
        Expanded(
          flex: fresh,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: r,
              border: Border.all(color: c.ink3, width: 1),
            ),
          ),
        ),
    ];
    final withGaps = <Widget>[];
    for (var i = 0; i < segs.length; i++) {
      if (i > 0) withGaps.add(SizedBox(width: gap));
      withGaps.add(segs[i]);
    }
    return Semantics(
      label: '$retained retained, $learning learning, $fresh new',
      child: SizedBox(
        height: height,
        width: width,
        child: Row(children: withGaps),
      ),
    );
  }
}
