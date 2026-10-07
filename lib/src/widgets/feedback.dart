import 'package:chess_srs/src/design/design.dart';
import 'package:chess_srs/src/network/connectivity.dart';
import 'package:chess_srs/src/network/socket.dart';
import 'package:chess_srs/src/styles/styles.dart';
import 'package:chess_srs/src/utils/l10n_context.dart';
import 'package:chess_srs/src/widgets/buttons.dart';
import 'package:chess_srs/src/widgets/popover.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:material_ui/material_ui.dart';
import 'package:signal_strength_indicator/signal_strength_indicator.dart';
import 'package:url_launcher/url_launcher.dart';

/// A icon that shows the lag rating of the current socket connection.
///
/// If [socketUri] is provided, it will be used to get the lag rating from that socket route only,
/// otherwise it will use the default socket route.
class SocketPingRatingIcon extends ConsumerWidget {
  const SocketPingRatingIcon({this.socketUri, super.key});

  final Uri? socketUri;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ping = ref.watch(socketPingProvider(socketUri));

    return SemanticIconButton(
      semanticsLabel: 'PING: ${ping.averageLag.inMilliseconds}ms',
      icon: LagIndicator(lagRating: ping.rating, isActive: ping.isActive, size: 24.0),
      onPressed: () {
        showPopover(
          context: context,
          bodyBuilder: (_) {
            return Consumer(
              builder: (_, ref, _) {
                final p = ref.watch(socketPingProvider(socketUri));
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Text.rich(
                    TextSpan(
                      text: 'PING: ',
                      children: [
                        TextSpan(
                          text: p.averageLag > Duration.zero
                              ? '${p.averageLag.inMilliseconds}'
                              : '?',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        TextSpan(
                          text: ' ms',
                          style: TextStyle(color: ColorScheme.of(context).onSurface),
                        ),
                      ],
                    ),
                    style: TextStyle(color: ColorScheme.of(context).onSurface),
                  ),
                );
              },
            );
          },
          backgroundColor:
              DialogTheme.of(context).backgroundColor ??
              ColorScheme.of(context).surfaceContainerHigh,
          transitionDuration: Duration.zero,
          popoverTransitionBuilder: (_, child) => child,
        );
      },
    );
  }
}

class SocketPingRatingListTile extends ConsumerWidget {
  const SocketPingRatingListTile({this.socketUri, super.key});

  final Uri? socketUri;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ping = ref.watch(socketPingProvider(socketUri));

    return ListTile(
      leading: LagIndicator(lagRating: ping.rating, isActive: ping.isActive),
      title: ping.averageLag > Duration.zero
          ? Text.rich(
              TextSpan(
                text: 'PING ',
                children: [
                  TextSpan(
                    text: '${ping.averageLag.inMilliseconds}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: ColorScheme.of(context).onSurface,
                    ),
                  ),
                  const TextSpan(text: ' ms'),
                ],
              ),
              style: TextStyle(color: ColorScheme.of(context).onSurface.withValues(alpha: 0.7)),
            )
          : Text(
              context.l10n.noNetwork,
              style: TextStyle(color: ColorScheme.of(context).onSurface.withValues(alpha: 0.7)),
            ),
      enabled: ping.averageLag > Duration.zero,
      onTap: () {
        launchUrl(Uri.parse('https://lichess.org/lag'));
      },
    );
  }
}

/// An indicator that shows the lag rating of the connection.
class LagIndicator extends StatelessWidget {
  const LagIndicator({required this.lagRating, this.isActive = true, this.size = 20.0, super.key})
    : assert(lagRating >= 0 && lagRating <= 4);

  /// The lag rating from 0 to 4.
  final int lagRating;

  /// Whether the connection is active (connected or trying to reconnect).
  ///
  /// When the lag rating is 0 and the connection is active, a loading animation
  /// is shown to indicate a reconnection attempt. When inactive, no animation is
  /// shown.
  final bool isActive;

  /// Visual size of the indicator.
  final double size;

  static const inactiveColor = Color(0x339E9E9E);

  static const materialLevels = {
    0: inactiveColor,
    1: Colors.red,
    2: Colors.yellow,
    3: Colors.green,
    4: Colors.green,
  };

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: Stack(
        children: [
          SignalStrengthIndicator.bars(
            barCount: 4,
            minValue: 0,
            maxValue: 4,
            value: lagRating,
            size: size,
            inactiveColor: inactiveColor,
            levels: materialLevels,
          ),
          if (lagRating == 0 && isActive)
            Center(
              child: SpinKitThreeBounce(color: Colors.grey, size: size / 2),
            ),
        ],
      ),
    );
  }
}

class OfflineBanner extends ConsumerWidget {
  const OfflineBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    if (ref.watch(isDeviceOnlineProvider)) {
      return const SizedBox.shrink();
    }
    return Material(
      child: Container(
        height: 40,
        color: theme.colorScheme.tertiaryContainer,
        child: Padding(
          padding: Styles.horizontalBodyPadding,
          child: Row(
            children: [
              Icon(Icons.report_outlined, color: theme.colorScheme.onTertiaryContainer),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  'Network connectivity unavailable.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: theme.colorScheme.onTertiaryContainer),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A adaptive circular progress indicator which size is constrained so it can fit
/// in buttons.
class ButtonLoadingIndicator extends StatelessWidget {
  const ButtonLoadingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 20,
      width: 20,
      child: CircularProgressIndicator.adaptive(strokeWidth: 2),
    );
  }
}

/// A centered circular progress indicator
class CenterLoadingIndicator extends StatelessWidget {
  const CenterLoadingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator.adaptive());
  }
}

/// A screen with an error message and a retry button.
///
/// This widget is intended to be used when a request fails and the user can
/// retry it.
class FullScreenRetryRequest extends StatelessWidget {
  const FullScreenRetryRequest({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(context.l10n.mobileSomethingWentWrong, style: Styles.sectionTitle),
          const SizedBox(height: 10),
          FilledButton.tonal(onPressed: onRetry, child: Text(context.l10n.retry)),
        ],
      ),
    );
  }
}

enum SnackBarType { error, info, success }

class FeedbackTile extends StatelessWidget {
  const FeedbackTile({this.leading, required this.title, this.subtitle, super.key});

  final Widget? leading;
  final Widget title;
  final Widget? subtitle;

  @override
  Widget build(BuildContext context) {
    final defaultFontSize = DefaultTextStyle.of(context).style.fontSize;

    return Row(
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: 16.0)],
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              DefaultTextStyle.merge(
                style: TextStyle(
                  fontSize: defaultFontSize != null ? defaultFontSize * 1.2 : null,
                  fontWeight: FontWeight.bold,
                ),
                child: title,
              ),
              ?subtitle,
            ],
          ),
        ),
      ],
    );
  }
}

/// Shows a toast with the given message.
///
/// The name is the inherited one and stays, because 53 call sites across 29 files use it and
/// renaming would be a diff with no user-visible effect. What it draws is the Diagram toast
/// (`design/docs/03-components.md` §12) rather than a Material `SnackBar`.
///
/// [type] is accepted and deliberately not rendered: the design specifies one toast
/// appearance, and gives errors a screen state instead. See [SrsToastTone].
void showSnackBar(BuildContext context, String message, {SnackBarType type = SnackBarType.info}) {
  // Kept inside a try, as before: this is called from async gaps and from error paths where
  // the context may already be defunct, and a toast must never be the thing that throws.
  try {
    showSrsToast(
      context,
      message,
      tone: switch (type) {
        SnackBarType.error => SrsToastTone.error,
        SnackBarType.success => SrsToastTone.success,
        SnackBarType.info => SrsToastTone.info,
      },
    );
  } catch (_) {}
}
