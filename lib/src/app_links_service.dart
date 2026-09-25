import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:chess_srs/src/constants.dart';
import 'package:chess_srs/src/model/analysis/analysis_controller.dart';
import 'package:chess_srs/src/model/common/chess.dart';
import 'package:chess_srs/src/model/common/id.dart';
import 'package:chess_srs/src/model/game/game_repository.dart';
import 'package:chess_srs/src/model/user/user.dart';
import 'package:chess_srs/src/model/user/user_repository.dart';
import 'package:chess_srs/src/navigation.dart';
import 'package:chess_srs/src/utils/navigation.dart';
import 'package:chess_srs/src/view/analysis/analysis_screen.dart';
import 'package:chess_srs/src/view/board_editor/board_editor_screen.dart';
import 'package:chess_srs/src/view/study/study_screen.dart';
import 'package:chess_srs/src/view/user/user_or_profile_screen.dart';
import 'package:chess_srs/src/widgets/feedback.dart';
import 'package:chess_srs/src/widgets/rich_link_text.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:url_launcher/url_launcher.dart';

final _logger = Logger('AppLinks');

final appLinksServiceProvider = Provider<AppLinksService>((ref) {
  final service = AppLinksService(ref);
  ref.onDispose(() => service.dispose());
  return service;
});

class AppLinksService {
  /// Creates the service. [appLinks] is injectable so tests can supply a fake
  /// in place of the real (singleton, platform-channel backed) [AppLinks].
  AppLinksService(this.ref, {AppLinks? appLinks}) : _appLinks = appLinks ?? AppLinks();

  final Ref ref;

  final AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  Future<void> start() async {
    // app_links' uriLinkStream emits the link that cold-started the app as its
    // first event, followed by any links received while the app is running, so a
    // single subscription covers both. (Also calling getInitialLink() would
    // deliver the cold-start link a second time, running its side effects twice.)
    var isColdStart = true;
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      if (isColdStart) {
        isColdStart = false;
        // The cold-start link can arrive before the first frame, so defer until
        // the navigator is ready. Push without a transition — the user launched
        // the app via this link so the target screen should just be there.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(_handleUriLogged(uri, animated: false));
        });
      } else {
        // Links received while the app is already running get a normal transition.
        unawaited(_handleUriLogged(uri, animated: true));
      }
    });
  }

  Future<void> _handleUriLogged(Uri uri, {required bool animated}) async {
    try {
      await _handleUri(uri, animated: animated);
    } catch (e, st) {
      _logger.severe('Error handling app link:', e, st);
    }
  }

  Future<void> _handleUri(Uri uri, {required bool animated}) async {
    // File links are handled by the sharing intent logic, so we can ignore them here.
    if (uri.scheme == 'file' || uri.scheme == 'content') {
      return;
    }
    // Shared PGN deeplinks (from the iOS Share Extension) are handled natively by
    // SharePlugin, which reads the PGN from the shared App Group container.
    if (uri.scheme == kLichessCustomUriSchemeName && uri.host == 'shared-pgn') {
      return;
    }
    if (uri.scheme == kLichessCustomUriSchemeName && uri.host == 'open-web') {
      _handleOpenWebLink(uri);
      return;
    }
    final context = ref.read(rootNavigatorKeyProvider).currentContext;
    if (context != null && context.mounted) {
      // For app deep links, we don't want to allow falling back to the browser as it might trigger an infinite loop if the app isn't properly handling the link
      await handleAppLink(context, uri, animated: animated, allowBrowserFallback: false);
    }
  }

  void dispose() {
    _linkSubscription?.cancel();
  }

  /// Resolves an app link [Uri] to one or more corresponding [Route]s.
  Future<List<Route<dynamic>>?> resolveAppLinkUri(BuildContext context, Uri appLinkUri) async {
    if (appLinkUri.pathSegments.isEmpty) return null;
    _logger.info('Resolving app link: $appLinkUri');
    switch (appLinkUri.pathSegments[0]) {
      case 'study':
        // A link can name the route and nothing else. Reading the id unconditionally threw a
        // RangeError, which the caller logged and dropped, so a truncated link did nothing at all
        // with nothing shown — indistinguishable from a link that simply had not loaded yet.
        final id = appLinkUri.pathSegments.getOrNull(1);
        if (id == null || id.isEmpty) {
          _logger.warning('Ignoring app link with no study id: $appLinkUri');
          return null;
        }
        final chapter = appLinkUri.pathSegments.getOrNull(2);
        return [
          StudyScreen.buildRoute((
            id: StudyId(id),
            initialChapter: chapter != null ? StudyChapterId(chapter) : null,
          )),
        ];
      case 'editor':
        final orientation = appLinkUri.queryParameters['color'] == 'black'
            ? Side.black
            : Side.white;
        final fen = appLinkUri.pathSegments.sublist(1).join('/').replaceAll('_', ' ').trim();
        String? initialFen;
        if (fen.isNotEmpty) {
          try {
            Setup.parseFen(fen);
            initialFen = fen;
          } catch (_) {
            if (context.mounted) {
              showSnackBar(context, 'Invalid FEN: $fen', type: SnackBarType.error);
            }
          }
        }
        return [
          BoardEditorScreen.buildRoute((
            initialVariant: Variant.standard,
            initialFen: initialFen,
            initialOrientation: orientation,
          )),
        ];
      case '@':
        if (appLinkUri.pathSegments.length > 2) {
          return null;
        }
        final userName = appLinkUri.pathSegments.getOrNull(1);
        if (userName == null || userName.isEmpty) {
          _logger.warning('Ignoring app link with no user name: $appLinkUri');
          return null;
        }
        try {
          final user = await ref
              .read(userRepositoryProvider)
              .getUser(UserId.fromUserName(userName));
          if (!context.mounted) return null;

          return [UserOrProfileScreen.buildRoute(user.lightUser)];
        } catch (e) {
          if (!context.mounted) return null;
          showSnackBar(context, 'Cannot find user $userName', type: SnackBarType.error);
          return [];
        }
      case _:
        final gameRoutes = await _tryResolveGameLink(context, appLinkUri);
        if (gameRoutes != null) return gameRoutes;
    }

    return null;
  }

  /// Handles an `org.chesssrs.app://open-web?url=...` link (e.g. from the platform widget)
  /// by opening the encoded URL in the platform in-app browser.
  ///
  /// Only web URLs are opened. The link can be delivered by anything able to hand the app a URL,
  /// and `launchUrl` hands any scheme it is given to the platform — a `url` naming `tel:`,
  /// `file:` or `intent:` would have the app open it on the user's behalf. That is not what this
  /// link is for, so anything else is refused here.
  ///
  /// url_launcher refuses these too, throwing rather than launching, so this is not closing a
  /// hole that is open today. It keeps the refusal ours and deliberate, and it survives the one
  /// change that would remove url_launcher's own guard: switching the launch mode to
  /// `externalApplication`, whose precondition is not scheme-checked.
  void _handleOpenWebLink(Uri uri) {
    final target = uri.queryParameters['url'];
    if (target == null) return;
    final targetUri = Uri.tryParse(target);
    if (targetUri == null) {
      _logger.warning('Refusing open-web link with an unparseable url: $target');
      return;
    }
    if (targetUri.scheme != 'http' && targetUri.scheme != 'https') {
      _logger.warning('Refusing open-web link for a non-web url: $targetUri');
      return;
    }
    launchUrl(targetUri, mode: LaunchMode.inAppBrowserView);
  }

  Future<List<Route<dynamic>>?> _tryResolveGameLink(BuildContext context, Uri appLinkUri) async {
    try {
      final gameId = GameId(appLinkUri.pathSegments[0]);
      if (!gameId.isValid) return null;

      final game = await ref.read(gameRepositoryProvider).getGame(gameId);
      final orientation = appLinkUri.pathSegments.getOrNull(1) == 'black' ? Side.black : Side.white;
      final int ply = int.tryParse(appLinkUri.fragment) ?? 0;

      if (!context.mounted) return null;

      if (game.finished || game.source == .import) {
        return [
          AnalysisScreen.buildRoute(
            AnalysisOptions.archivedGame(
              orientation: orientation,
              gameId: gameId,
              initialMoveCursor: ply,
            ),
          ),
        ];
      }
    } catch (e, st) {
      _logger.info('Not a game link:', e, st);
    }

    return null;
  }

  /// Handles an app link [Uri] by navigating to the corresponding screen(s).
  Future<void> handleAppLink(
    BuildContext context,
    Uri uri, {
    bool animated = true,
    bool allowBrowserFallback = true,
  }) async {
    final routes = await resolveAppLinkUri(context, uri);
    if (!context.mounted) return;

    if (routes != null) {
      final navigator = Navigator.of(context, rootNavigator: true);
      for (final route in routes) {
        _pushDeepLinkRoute(navigator, route, animated: animated);
      }
    } else {
      if (allowBrowserFallback) {
        launchUrl(uri);
      } else {
        _logger.warning('Could not resolve app link $uri');
      }
    }
  }

  /// Pushes [route] onto [navigator], replacing the top route instead of
  /// stacking when the top is already the same screen type — preventing
  /// duplicates when the user taps a deep link while already on that screen.
  /// Also applies [_withNoTransition] when [animated] is `false`.
  static Future<void> _pushDeepLinkRoute(
    NavigatorState navigator,
    Route<dynamic> route, {
    required bool animated,
  }) {
    final pushed = animated ? route : _withNoTransition(route);
    Route<dynamic>? top;
    navigator.popUntil((r) {
      top = r;
      return true;
    });
    final topRoute = top;
    if (topRoute is ScreenRoute &&
        pushed is ScreenRoute &&
        topRoute.screen.runtimeType == pushed.screen.runtimeType) {
      return navigator.pushReplacement(pushed);
    }
    return navigator.push(pushed);
  }

  /// Returns a copy of [route] with [Duration.zero] transition so the screen
  /// appears instantly — used when the app is opened via a deep link and a
  /// transition would be jarring.
  static Route<dynamic> _withNoTransition(Route<dynamic> route) {
    if (route is ScreenRoute) {
      return MaterialScreenRoute(
        screen: route.screen,
        settings: route.settings,
        fullscreenDialog: route.fullscreenDialog,
        maintainState: route.maintainState,
        allowSnapshotting: route.allowSnapshotting,
        overrideTransitionDuration: Duration.zero,
      );
    }
    return route;
  }

  static const kLichessLinkifiers = [UrlLinkifier(), EmailLinkifier(), UserTagLinkifier()];

  /// Handles link clicks in RichLinkText widgets throughout the app.
  Future<void> onLinkifyOpen(BuildContext context, LinkableElement link) async {
    if (link is UrlElement && link.url.startsWith(RegExp('https?:\\/\\/$kLichessHost'))) {
      // Handle Lichess links specifically
      final appLinkUri = Uri.parse(link.url);
      await handleAppLink(context, appLinkUri);
    } else if (link.originText.startsWith('@')) {
      final username = link.originText.substring(1);
      Navigator.of(context).push(
        UserOrProfileScreen.buildRoute(
          LightUser(id: UserId.fromUserName(username), name: username),
        ),
      );
    } else {
      launchUrl(Uri.parse(link.url));
    }
  }
}
