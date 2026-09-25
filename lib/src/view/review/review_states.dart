// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// The review screen's two non-data states: loading and failure.
//
// Design source: design/docs/03-components.md §12 and the demo's `loading` and `error`
// scenes. Both are extrapolation rules rather than prototype behaviour, and both are
// deliberately quiet:
//
//   Loading: the ground stays empty. If the load really is slow, one line fades in
//   (demo: 900ms; this build: SrsMotion.loadingLabelDelay). No spinner, ever.
//   Error: an idle-style column — a plain title, one sentence saying what happened, a
//   `Try again` pill, and a `Copy details` text button.
import 'dart:async';

import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/view/review/review_copy.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// The quiet label shown once the wait becomes noticeable. Demo: `#loadingLabel`.
const kSrsLoadingLabel = 'Loading…';

/// How long the ground stays empty before the label appears.
const kSrsLoadingLabelDelay = Duration(milliseconds: 250);

/// The empty ground, with a quiet label once the wait becomes noticeable.
class SrsLoadingView extends StatefulWidget {
  const SrsLoadingView({
    super.key,
    this.label = kSrsLoadingLabel,
    this.delay = kSrsLoadingLabelDelay,
  });

  final String label;
  final Duration delay;

  @override
  State<SrsLoadingView> createState() => _SrsLoadingViewState();
}

class _SrsLoadingViewState extends State<SrsLoadingView> {
  Timer? _timer;
  bool _showLabel = false;

  @override
  void initState() {
    super.initState();
    if (widget.delay > Duration.zero) {
      _timer = Timer(widget.delay, () {
        if (mounted) setState(() => _showLabel = true);
      });
    } else {
      _showLabel = true;
    }
  }

  @override
  void didUpdateWidget(SrsLoadingView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.delay == widget.delay) return;
    _timer?.cancel();
    _showLabel = widget.delay <= Duration.zero;
    if (!_showLabel) {
      _timer = Timer(widget.delay, () {
        if (mounted) setState(() => _showLabel = true);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.srs;
    return Center(
      child: ExcludeSemantics(
        // The label is decorative: the screen it replaces carries the busy state.
        child: AnimatedOpacity(
          opacity: _showLabel ? 1 : 0,
          duration: SrsMotion.resolve(context, SrsMotion.scrim),
          curve: SrsMotion.ease,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              widget.label,
              textAlign: TextAlign.center,
              style: SrsText.body(false, c.ink2),
            ),
          ),
        ),
      ),
    );
  }
}

/// The failure state: what happened, one way to retry, one way to report it.
class SrsErrorView extends StatelessWidget {
  const SrsErrorView({
    super.key,
    required this.detail,
    this.onRetry,
    this.onCopyDetails,
    this.title = kSrsErrorTitle,
  });

  /// One `ink2` sentence saying what happened, in the user's terms.
  final String detail;

  /// Title of the failure. Defaults to the design's `Something went wrong.`
  final String title;

  final VoidCallback? onRetry;
  final VoidCallback? onCopyDetails;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: SrsText.title(context.srs.ink)),
              const SizedBox(height: 12),
              Text(detail, style: SrsText.body(false, context.srs.ink2)),
              const SizedBox(height: 26),
              Wrap(
                spacing: 18,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (onRetry != null) SrsPillButton(label: kSrsRetryLabel, onPressed: onRetry),
                  if (onCopyDetails != null)
                    SrsTextButton(label: kSrsCopyDetailsLabel, onPressed: onCopyDetails),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Copies [details] to the clipboard, for the error view's `Copy details` action.
Future<void> copySrsErrorDetails(String details) => Clipboard.setData(ClipboardData(text: details));
