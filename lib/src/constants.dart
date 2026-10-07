import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

const kLichessHost = String.fromEnvironment('LICHESS_HOST', defaultValue: 'lichess.org');

const kLichessWSHost = String.fromEnvironment(
  'LICHESS_WS_HOST',
  defaultValue: 'socket.lichess.org',
);

const kLichessWSSecret = String.fromEnvironment(
  'LICHESS_WS_SECRET',
  defaultValue: 'somethingElseInProd',
);

const kLichessCDNHost = String.fromEnvironment(
  'LICHESS_CDN_HOST',
  defaultValue: 'https://lichess1.org',
);

const kLichessOpeningExplorerHost = String.fromEnvironment(
  'LICHESS_OPENING_EXPLORER_HOST',
  defaultValue: 'explorer.lichess.org',
);

const kLichessTablebaseHost = String.fromEnvironment(
  'LICHESS_TABLEBASE_HOST',
  defaultValue: 'tablebase.lichess.org',
);

const kLichessCustomUriSchemeName = 'org.chesssrs.app';

/// This app's store listings, for the "rate this app" action.
///
/// The package name is the same on Android as the application id and the iOS bundle id, so it is
/// declared once here rather than repeated — and, more to the point, so that no listing can point
/// at somebody else's app. It used to: the tile opened `org.lichess.mobileV2` and Lichess's own
/// App Store page, so rating this app sent the user to the upstream project it was forked from.
const kAppStorePackageName = kLichessCustomUriSchemeName;

/// The App Store listing's numeric id, which Apple assigns and which cannot be derived from
/// anything in the repository.
///
/// Null until the listing exists. A null here must not fall back to some other app's id: the
/// search below is a placeholder that cannot open the wrong app, and replacing it with the real
/// id is a one-line change once the app is published.
const kAppStoreListingId = null;

/// Where "rate this app" sends the user.
///
/// On Android this is the app's own Play listing, which is fully determined by the package name.
/// On iOS, until [kAppStoreListingId] is filled in, it is an App Store search for this app's name
/// rather than a hardcoded listing, because a wrong id is worse than an inexact one.
Uri appStoreListingUrl({required bool isAndroid}) {
  if (isAndroid) {
    return Uri.parse('https://play.google.com/store/apps/details?id=$kAppStorePackageName');
  }
  const listingId = kAppStoreListingId;
  return listingId != null
      ? Uri.parse('https://apps.apple.com/us/app/id$listingId')
      : Uri.parse('https://apps.apple.com/us/search?term=ChessSRS');
}

/// The deep link that opens the Play Store app on a device that has it, falling back to the web
/// listing when no store app is present.
({Uri native, Uri web}) androidAppStoreLinks() => (
  native: Uri.parse('market://details?id=$kAppStorePackageName'),
  web: appStoreListingUrl(isAndroid: true),
);

const kLichessClientId = 'chess_srs';

const kSRIStorageKey = 'socket_random_identifier';

const kFideRatingsUrl = 'https://ratings.fide.com/profile/';

// lichess
// https://github.com/lichess-org/lila/blob/4562a83cdb263c3ebf7e148c0f666f0ff92b91c7/modules/rating/src/main/Glicko.scala#L71
const kProvisionalDeviation = 110;
const kClueLessDeviation = 230;

const kMaintenanceDrawingAuthorUrl = 'https://www.pixiv.net/member.php?id=34624';
const kLichessMastodonUrl = 'https://mastodon.online/@lichess';
const kLichessBlueskyUrl = 'https://bsky.app/profile/lichess.org';
const kLichessDiscordUrl = 'https://discord.gg/lichess';

// UI
const double kCupertinoBarBlurSigma = 30.0;

const kGoldenRatio = 1.61803398875;

/// Use same box shadows as material widgets with elevation 1.
final List<BoxShadow> boardShadows = defaultTargetPlatform == TargetPlatform.iOS
    ? <BoxShadow>[]
    : kElevationToShadow[1]!;

const kMaxClockTextScaleFactor = 1.94;
const kEmptyWidget = SizedBox.shrink();
const kTabletBoardTableSidePadding = 16.0;

const kBottomBarHeight = 56.0;
const kMaterialPopupMenuMaxWidth = 500.0;

/// The threshold to detect screens with a small remaining height minus board.
const kSmallHeightMinusBoard = 200;
