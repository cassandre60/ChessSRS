import 'dart:async';
import 'dart:convert';

import 'package:chess_srs/src/model/account/account_preferences.dart';
import 'package:chess_srs/src/model/common/id.dart';
import 'package:chess_srs/src/model/user/user.dart';
import 'package:chess_srs/src/network/http.dart';
import 'package:chess_srs/src/styles/styles.dart';
import 'package:chess_srs/src/widgets/network_image.dart';
import 'package:chess_srs/src/widgets/user.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import '../network/fake_http_client_factory.dart';
import '../test_provider_scope.dart';

/// No SPEC invariant names the presentation contract of the user widget
/// (SPEC.md has no INV-xxx for the avatar, title, flair, rating, patron or
/// truncation rules), so each test below states the contract it pins instead of
/// citing an unrelated invariant id.
LightUser _user({
  String name = 'Alice',
  String? title,
  String? flair,
  int? patronColor,
  bool? isOnline,
}) => LightUser(
  id: UserId.fromUserName(name),
  name: name,
  title: title,
  flair: flair,
  patronColor: patronColor,
  isOnline: isOnline,
);

/// A one pixel transparent PNG, so a flair request can succeed.
const String _onePixelPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmM'
    'IQAAAABJRU5ErkJggg==';

/// A client that answers with a real image, so the flair loads.
http.Client _pngClient() => MockClient(
  (_) async =>
      http.Response.bytes(base64Decode(_onePixelPng), 200, headers: {'content-type': 'image/png'}),
);

void main() {
  group('ConnectedIcon', () {
    testWidgets('shows the wifi icon and the Online tooltip when connected', (
      WidgetTester tester,
    ) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: const Scaffold(body: ConnectedIcon(isConnected: true)),
      );
      await tester.pumpWidget(app);

      expect(find.byIcon(Symbols.wifi), findsOneWidget);
      expect(find.byIcon(Symbols.wifi_off), findsNothing);
      expect(tester.widget<Tooltip>(find.byType(Tooltip)).message, 'Online');
    });

    testWidgets('shows the offline icon and the Offline tooltip when disconnected', (
      WidgetTester tester,
    ) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: const Scaffold(body: ConnectedIcon(isConnected: false)),
      );
      await tester.pumpWidget(app);

      expect(find.byIcon(Symbols.wifi_off), findsOneWidget);
      expect(find.byIcon(Symbols.wifi), findsNothing);
      expect(tester.widget<Tooltip>(find.byType(Tooltip)).message, 'Offline');
    });

    testWidgets('uses the in-game labels when asked for them', (WidgetTester tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: const Scaffold(
          body: Column(
            children: [
              ConnectedIcon(isConnected: true, shouldShowIsOnGameLabels: true),
              ConnectedIcon(isConnected: false, shouldShowIsOnGameLabels: true),
            ],
          ),
        ),
      );
      await tester.pumpWidget(app);

      final tooltips = tester.widgetList<Tooltip>(find.byType(Tooltip)).toList();
      expect(tooltips.map((t) => t.message), ['Joined the game', 'Left the game']);
    });

    testWidgets('sizes the icon to the requested size', (WidgetTester tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: const Scaffold(body: ConnectedIcon(isConnected: true, size: 24)),
      );
      await tester.pumpWidget(app);

      expect(tester.getSize(find.byType(Icon)), const Size(24, 24));
    });

    testWidgets('leaves the icon size to the theme when none is given', (
      WidgetTester tester,
    ) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: const Scaffold(body: ConnectedIcon(isConnected: true)),
      );
      await tester.pumpWidget(app);

      expect(tester.widget<Icon>(find.byType(Icon)).size, isNull);
      expect(tester.getSize(find.byType(Icon)), const Size(24, 24));
    });

    testWidgets('dims the offline icon and leaves the online one to the theme', (
      WidgetTester tester,
    ) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: const Scaffold(
          body: Column(
            children: [ConnectedIcon(isConnected: true), ConnectedIcon(isConnected: false)],
          ),
        ),
      );
      await tester.pumpWidget(app);

      final icons = tester.widgetList<Icon>(find.byType(Icon)).toList();
      expect(icons[0].color, isNull);

      final context = tester.element(find.byType(ConnectedIcon).first);
      final ambient = DefaultTextStyle.of(context).style.color;
      expect(ambient, isNotNull);
      expect(icons[1].color, ambient!.withValues(alpha: 0.3));
      expect(icons[1].color!.a, closeTo(0.3, 0.01));
    });
  });

  group('UserAppBarTitleWidget', () {
    testWidgets('shows the online subtitle for an online user', (WidgetTester tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: Scaffold(
          body: UserAppBarTitleWidget(user: _user(name: 'Alice'), isOnline: true),
        ),
      );
      await tester.pumpWidget(app);

      expect(find.text('online'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
    });

    testWidgets('shows the last-seen subtitle for an offline user with a seenAt', (
      WidgetTester tester,
    ) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: Scaffold(
          body: UserAppBarTitleWidget(
            user: _user(name: 'Alice'),
            isOnline: false,
            seenAt: DateTime.now().subtract(const Duration(hours: 2)),
          ),
        ),
      );
      await tester.pumpWidget(app);

      expect(find.text('Active 2 hours ago'), findsOneWidget);
      expect(find.text('offline'), findsNothing);
    });

    testWidgets('shows the offline subtitle for an offline user without a seenAt', (
      WidgetTester tester,
    ) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: Scaffold(
          body: UserAppBarTitleWidget(user: _user(name: 'Alice'), isOnline: false),
        ),
      );
      await tester.pumpWidget(app);

      expect(find.text('offline'), findsOneWidget);
    });

    testWidgets('hides the flair from the app bar title', (WidgetTester tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: Scaffold(
          body: UserAppBarTitleWidget(
            user: _user(name: 'Alice', flair: 'henny'),
            isOnline: true,
          ),
        ),
      );
      await tester.pumpWidget(app);

      expect(find.byType(HttpNetworkImageWidget), findsNothing);
    });

    testWidgets('renders the avatar at the app bar radius', (WidgetTester tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: Scaffold(
          body: UserAppBarTitleWidget(user: _user(name: 'Alice'), isOnline: true),
        ),
      );
      await tester.pumpWidget(app);

      expect(tester.getSize(find.byType(CircleAvatar)), const Size(32, 32));
    });

    testWidgets('separates the avatar from the name by the title gap', (WidgetTester tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: Scaffold(
          body: UserAppBarTitleWidget(user: _user(name: 'Alice'), isOnline: true),
        ),
      );
      await tester.pumpWidget(app);

      final gap =
          tester.getTopLeft(find.text('Alice')).dx -
          tester.getTopRight(find.byType(CircleAvatar)).dx;
      expect(gap, closeTo(8, 0.01));
    });
  });

  group('PatronIcon', () {
    testWidgets('uses the light patron palette in light mode', (WidgetTester tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: const Scaffold(body: PatronIcon(color: 1)),
      );
      await tester.pumpWidget(app);

      expect(tester.widget<Icon>(find.byType(Icon)).color, PatronIcon.patronColorsLight[0]);
    });

    testWidgets('uses the dark patron palette in dark mode', (WidgetTester tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: Scaffold(
          body: Theme(data: ThemeData.dark(), child: const PatronIcon(color: 1)),
        ),
      );
      await tester.pumpWidget(app);

      expect(tester.widget<Icon>(find.byType(Icon)).color, PatronIcon.patronColorsDark[0]);
    });

    testWidgets('leaves the icon uncoloured when the patron picked no colour', (
      WidgetTester tester,
    ) async {
      final app = await makeTestProviderScopeApp(tester, home: const Scaffold(body: PatronIcon()));
      await tester.pumpWidget(app);

      expect(tester.widget<Icon>(find.byType(Icon)).color, isNull);
    });

    testWidgets('maps patron colour N to the palette entry N-1', (WidgetTester tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: const Scaffold(
          body: Column(
            children: [PatronIcon(color: 1), PatronIcon(color: 2), PatronIcon(color: 3)],
          ),
        ),
      );
      await tester.pumpWidget(app);

      final colors = tester.widgetList<Icon>(find.byType(Icon)).map((i) => i.color).toList();
      expect(colors, [
        PatronIcon.patronColorsLight[0],
        PatronIcon.patronColorsLight[1],
        PatronIcon.patronColorsLight[2],
      ]);
    });

    testWidgets('sizes the icon from the ambient text style when no size is given', (
      WidgetTester tester,
    ) async {
      final app = await makeTestProviderScopeApp(tester, home: const Scaffold(body: PatronIcon()));
      await tester.pumpWidget(app);

      final context = tester.element(find.byType(PatronIcon));
      final ambientSize = DefaultTextStyle.of(context).style.fontSize;
      expect(ambientSize, isNotNull);
      expect(tester.widget<Icon>(find.byType(Icon)).size, ambientSize);
    });

    testWidgets('labels the patron icon for screen readers', (WidgetTester tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: const Scaffold(body: PatronIcon(color: 1)),
      );
      await tester.pumpWidget(app);

      expect(tester.widget<Icon>(find.byType(Icon)).semanticLabel, 'Lichess Patron');
    });
  });

  group('UserFullNameWidget', () {
    testWidgets('displays fallback name when user is null', (WidgetTester tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: const Scaffold(
          body: UserFullNameWidget.player(user: null, name: 'Kasparov, Garry', aiLevel: null),
        ),
      );
      await tester.pumpWidget(app);

      expect(find.text('Kasparov, Garry'), findsOneWidget);
    });

    testWidgets('displays Anonymous when neither user nor name is available', (
      WidgetTester tester,
    ) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: const Scaffold(
          body: UserFullNameWidget.player(user: null, name: null, aiLevel: null),
        ),
      );
      await tester.pumpWidget(app);

      expect(find.text('Anonymous'), findsOneWidget);
    });

    testWidgets('prefers the user name over the given name', (WidgetTester tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: Scaffold(
          body: UserFullNameWidget(
            user: _user(name: 'Alice'),
            name: 'Bob',
          ),
        ),
      );
      await tester.pumpWidget(app);

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsNothing);
    });

    testWidgets('falls back to the AI name when there is an AI level', (WidgetTester tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: const Scaffold(body: UserFullNameWidget.player(user: null, name: null, aiLevel: 3)),
      );
      await tester.pumpWidget(app);

      expect(find.text('Stockfish level 3'), findsOneWidget);
    });

    testWidgets('shows the title before the name of a titled user', (WidgetTester tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: Scaffold(
          body: UserFullNameWidget(
            user: _user(name: 'Alice', title: 'GM'),
          ),
        ),
      );
      await tester.pumpWidget(app);

      expect(find.text('GM'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('GM')).dx,
        lessThan(tester.getTopLeft(find.text('Alice')).dx),
      );
    });

    testWidgets('reserves no room for a title when the user has none', (WidgetTester tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: Scaffold(
          body: UserFullNameWidget(user: _user(name: 'Alice'), rating: 1500),
        ),
      );
      await tester.pumpWidget(app);

      final widgetLeft = tester.getTopLeft(find.byType(UserFullNameWidget)).dx;
      expect(tester.getTopLeft(find.text('Alice')).dx, widgetLeft);
      expect(tester.getTopLeft(find.text('1500')).dx, greaterThan(widgetLeft));
    });

    testWidgets('separates the title from the name by the title gap', (WidgetTester tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: Scaffold(
          body: UserFullNameWidget(
            user: _user(name: 'Alice', title: 'GM'),
          ),
        ),
      );
      await tester.pumpWidget(app);

      final gap = tester.getTopLeft(find.text('Alice')).dx - tester.getTopRight(find.text('GM')).dx;
      expect(gap, closeTo(5, 0.01));
    });

    testWidgets('styles a BOT title differently from a human title', (WidgetTester tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: Scaffold(
          body: Column(
            children: [
              UserFullNameWidget(
                user: _user(name: 'Alice', title: 'GM'),
              ),
              UserFullNameWidget(
                user: _user(name: 'Bot', title: 'BOT'),
              ),
            ],
          ),
        ),
      );
      await tester.pumpWidget(app);

      final context = tester.element(find.byType(UserFullNameWidget).first);
      final colors = context.lichessColors;

      final human = tester.widget<Text>(find.text('GM'));
      expect(human.style?.color, colors.brag);
      expect(human.style?.fontWeight, FontWeight.bold);

      final bot = tester.widget<Text>(find.text('BOT'));
      expect(bot.style?.color, colors.fancy);
      expect(bot.style?.fontWeight, isNull);
    });

    testWidgets('shows the rating of a rated user', (WidgetTester tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: Scaffold(
          body: UserFullNameWidget(user: _user(name: 'Alice'), rating: 1500),
        ),
      );
      await tester.pumpWidget(app);

      expect(find.text('1500'), findsOneWidget);
    });

    testWidgets('shows the rating while the rating preference is still loading', (
      WidgetTester tester,
    ) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: Scaffold(
          body: UserFullNameWidget(user: _user(name: 'Alice'), rating: 1500),
        ),
        overrides: {
          showRatingsPrefProvider: showRatingsPrefProvider.overrideWith(
            (ref) => Completer<ShowRatings>().future,
          ),
        },
      );
      await tester.pumpWidget(app);

      expect(find.text('1500'), findsOneWidget);
    });

    testWidgets('marks a provisional rating with a question mark', (WidgetTester tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: Scaffold(
          body: UserFullNameWidget(user: _user(name: 'Alice'), rating: 1500, provisional: true),
        ),
      );
      await tester.pumpWidget(app);

      expect(find.text('1500?'), findsOneWidget);
    });

    testWidgets('shows no question mark on a settled rating', (WidgetTester tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: Scaffold(
          body: UserFullNameWidget(user: _user(name: 'Alice'), rating: 1500, provisional: false),
        ),
      );
      await tester.pumpWidget(app);

      expect(find.text('1500'), findsOneWidget);
      expect(find.text('1500?'), findsNothing);
    });

    testWidgets('shows no rating when the user has none', (WidgetTester tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: Scaffold(
          body: UserFullNameWidget(user: _user(name: 'Alice')),
        ),
      );
      await tester.pumpWidget(app);

      expect(
        tester.getSize(find.byType(UserFullNameWidget)).width,
        tester.getSize(find.text('Alice')).width,
      );
    });

    testWidgets('hides the rating when the preference says no', (WidgetTester tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: Scaffold(
          body: UserFullNameWidget(user: _user(name: 'Alice'), rating: 1500, ratingDiff: 12),
        ),
        overrides: {
          showRatingsPrefProvider: showRatingsPrefProvider.overrideWith((ref) => ShowRatings.no),
        },
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('1500'), findsNothing);
      expect(find.text('+12'), findsNothing);
    });

    testWidgets('shows the rating difference with its sign and colour', (
      WidgetTester tester,
    ) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: Scaffold(
          body: Column(
            children: [
              UserFullNameWidget(user: _user(name: 'A'), ratingDiff: 12),
              UserFullNameWidget(user: _user(name: 'B'), ratingDiff: -5),
              UserFullNameWidget(user: _user(name: 'C'), ratingDiff: 0),
            ],
          ),
        ),
      );
      await tester.pumpWidget(app);

      expect(find.text('+12'), findsOneWidget);
      expect(find.text('-5'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);

      final context = tester.element(find.byType(UserFullNameWidget).first);
      final colors = context.lichessColors;
      expect(tester.widget<Text>(find.text('+12')).style?.color, colors.good);
      expect(tester.widget<Text>(find.text('0')).style?.color, colors.brag);
      expect(tester.widget<Text>(find.text('-5')).style?.color, colors.error);
    });

    testWidgets('shows the flair of a user who has one', (WidgetTester tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: Scaffold(
          body: UserFullNameWidget(
            user: _user(name: 'Alice', flair: 'henny'),
          ),
        ),
      );
      await tester.pumpWidget(app);

      expect(find.byType(HttpNetworkImageWidget), findsOneWidget);
    });

    testWidgets('shows no flair for a user who has none', (WidgetTester tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: Scaffold(
          body: UserFullNameWidget(user: _user(name: 'Alice')),
        ),
      );
      await tester.pumpWidget(app);

      expect(find.byType(HttpNetworkImageWidget), findsNothing);
    });

    testWidgets('shows no flair when the caller hides it', (WidgetTester tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: Scaffold(
          body: UserFullNameWidget(
            user: _user(name: 'Alice', flair: 'henny'),
            showFlair: false,
          ),
        ),
      );
      await tester.pumpWidget(app);

      expect(find.byType(HttpNetworkImageWidget), findsNothing);
    });

    testWidgets('shows the connected icon only when the caller asks for it', (
      WidgetTester tester,
    ) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: Scaffold(
          body: Column(
            children: [
              UserFullNameWidget(user: _user(name: 'Alice', isOnline: true)),
              UserFullNameWidget(user: _user(name: 'Bob', isOnline: true), shouldShowOnline: true),
            ],
          ),
        ),
      );
      await tester.pumpWidget(app);

      final names = find.byType(UserFullNameWidget);
      expect(find.descendant(of: names.at(0), matching: find.byType(ConnectedIcon)), findsNothing);
      expect(
        find.descendant(of: names.at(1), matching: find.byType(ConnectedIcon)),
        findsOneWidget,
      );
      expect(find.byType(ConnectedIcon), findsOneWidget);
    });

    testWidgets('shows no connected icon for a name without a user', (WidgetTester tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: const Scaffold(
          body: UserFullNameWidget.player(
            user: null,
            name: 'Bob',
            aiLevel: null,
            shouldShowOnline: true,
          ),
        ),
      );
      await tester.pumpWidget(app);

      expect(find.byType(ConnectedIcon), findsNothing);
    });

    testWidgets('shows the offline icon for an offline user', (WidgetTester tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: Scaffold(
          body: UserFullNameWidget(
            user: _user(name: 'Alice', isOnline: false),
            shouldShowOnline: true,
          ),
        ),
      );
      await tester.pumpWidget(app);

      expect(find.byIcon(Symbols.wifi_off), findsOneWidget);
      expect(find.byIcon(Symbols.wifi), findsNothing);
    });

    testWidgets('shows the patron icon only for a patron', (WidgetTester tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: Scaffold(
          body: Column(
            children: [
              UserFullNameWidget(user: _user(name: 'Alice')),
              UserFullNameWidget(user: _user(name: 'Bob', patronColor: 3)),
            ],
          ),
        ),
      );
      await tester.pumpWidget(app);

      final names = find.byType(UserFullNameWidget);
      expect(find.descendant(of: names.at(0), matching: find.byType(PatronIcon)), findsNothing);
      expect(find.descendant(of: names.at(1), matching: find.byType(PatronIcon)), findsOneWidget);
      expect(find.byType(PatronIcon), findsOneWidget);
    });

    testWidgets('shows no patron icon when the caller hides it', (WidgetTester tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: Scaffold(
          body: UserFullNameWidget(user: _user(name: 'Bob', patronColor: 3), showPatron: false),
        ),
      );
      await tester.pumpWidget(app);

      expect(find.byType(PatronIcon), findsNothing);
    });

    testWidgets('calls onTap when the name is tapped', (WidgetTester tester) async {
      var taps = 0;
      final app = await makeTestProviderScopeApp(
        tester,
        home: Scaffold(
          body: UserFullNameWidget(
            user: _user(name: 'Alice'),
            onTap: () => taps++,
          ),
        ),
      );
      await tester.pumpWidget(app);

      await tester.tap(find.text('Alice'));
      await tester.pump();

      expect(taps, 1);
    });

    testWidgets('truncates a long name on one line', (WidgetTester tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: Scaffold(
          body: SizedBox(
            width: 120,
            child: UserFullNameWidget(user: _user(name: 'AveryLongUserNameThatCannotFit')),
          ),
        ),
      );
      await tester.pumpWidget(app);

      final text = tester.widget<Text>(find.text('AveryLongUserNameThatCannotFit'));
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);

      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: find.byType(UserFullNameWidget),
          matching: find.text('AveryLongUserNameThatCannotFit'),
        ),
      );
      expect(paragraph.didExceedMaxLines, isTrue);
    });

    testWidgets('sizes the flair to the text style font size', (WidgetTester tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: Scaffold(
          body: UserFullNameWidget(
            user: _user(name: 'Alice', flair: 'henny'),
            style: const TextStyle(fontSize: 22),
          ),
        ),
      );
      await tester.pumpWidget(app);

      final flair = tester.widget<HttpNetworkImageWidget>(find.byType(HttpNetworkImageWidget));
      expect(flair.width, 22);
      expect(flair.height, 22);
    });

    testWidgets('falls back to the default sizes when the style has no font size', (
      WidgetTester tester,
    ) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: Scaffold(
          body: DefaultTextStyle(
            style: const TextStyle(),
            child: UserFullNameWidget(
              user: _user(name: 'Alice', flair: 'henny'),
              rating: 1500,
            ),
          ),
        ),
      );
      await tester.pumpWidget(app);

      final flair = tester.widget<HttpNetworkImageWidget>(find.byType(HttpNetworkImageWidget));
      expect(flair.width, 16.0);
      expect(flair.height, 16.0);
      expect(tester.widget<Text>(find.text('1500')).style?.fontSize, 13);
    });

    testWidgets('renders the rating three points smaller than the name', (
      WidgetTester tester,
    ) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: Scaffold(
          body: UserFullNameWidget(
            user: _user(name: 'Alice'),
            rating: 1500,
            ratingDiff: 12,
            style: const TextStyle(fontSize: 20),
          ),
        ),
      );
      await tester.pumpWidget(app);

      expect(tester.widget<Text>(find.text('1500')).style?.fontSize, 17);
      expect(tester.widget<Text>(find.text('+12')).style?.fontSize, 17);
      expect(tester.widget<Text>(find.text('Alice')).style?.fontSize, 20);
      expect(tester.widget<Text>(find.text('1500')).style?.fontWeight, FontWeight.w400);
    });

    testWidgets('keeps the online icon flush with the start of the row', (
      WidgetTester tester,
    ) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: Scaffold(
          body: UserFullNameWidget(
            user: _user(name: 'Alice', isOnline: true),
            shouldShowOnline: true,
          ),
        ),
      );
      await tester.pumpWidget(app);

      final widgetLeft = tester.getTopLeft(find.byType(UserFullNameWidget)).dx;
      expect(tester.getTopLeft(find.byIcon(Symbols.wifi)).dx - widgetLeft, 0);
    });
  });

  group('UserFullNameWidget.player', () {
    testWidgets('shows no connected icon by default', (WidgetTester tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: Scaffold(
          body: UserFullNameWidget.player(
            user: _user(name: 'Alice', isOnline: true),
            aiLevel: null,
          ),
        ),
      );
      await tester.pumpWidget(app);

      expect(find.byType(ConnectedIcon), findsNothing);
    });

    testWidgets('shows the flair by default', (WidgetTester tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: Scaffold(
          body: UserFullNameWidget.player(
            user: _user(name: 'Alice', flair: 'henny'),
            aiLevel: null,
          ),
        ),
      );
      await tester.pumpWidget(app);

      expect(find.byType(HttpNetworkImageWidget), findsOneWidget);
    });

    testWidgets('shows the patron icon by default', (WidgetTester tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: Scaffold(
          body: UserFullNameWidget.player(
            user: _user(name: 'Alice', patronColor: 3),
            aiLevel: null,
          ),
        ),
      );
      await tester.pumpWidget(app);

      expect(find.byType(PatronIcon), findsOneWidget);
    });
  });

  group('UserAvatar', () {
    testWidgets('renders the avatar at the given radius', (WidgetTester tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: Scaffold(
          body: Column(
            children: [
              UserAvatar(_user(name: 'alice')),
              UserAvatar(_user(name: 'bob'), radius: 16),
            ],
          ),
        ),
      );
      await tester.pumpWidget(app);

      final avatars = tester.widgetList<CircleAvatar>(find.byType(CircleAvatar)).toList();
      expect(avatars[0].radius, 20);
      expect(avatars[1].radius, 16);
      expect(tester.getSize(find.byType(CircleAvatar).first), const Size(40, 40));
      expect(tester.getSize(find.byType(CircleAvatar).last), const Size(32, 32));
    });

    testWidgets('shows the initial of a user without a flair', (WidgetTester tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: Scaffold(body: UserAvatar(_user(name: 'alice'))),
      );
      await tester.pumpWidget(app);

      expect(find.text('A'), findsOneWidget);
      final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      expect(avatar.foregroundImage, isNull);
      expect(avatar.child, isNotNull);
    });

    testWidgets('uses the flair as the foreground image of a user who has one', (
      WidgetTester tester,
    ) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: Scaffold(
          body: UserAvatar(_user(name: 'alice', flair: 'henny')),
        ),
        overrides: {
          httpClientFactoryProvider: httpClientFactoryProvider.overrideWith(
            (ref) => const FakeHttpClientFactory(_pngClient),
          ),
        },
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      expect(avatar.foregroundImage, isNotNull);
      expect(avatar.child, isNull);
      expect(find.text('A'), findsNothing);
    });

    testWidgets('reacts to a flair that fails to load', (WidgetTester tester) async {
      // The avatar must stop showing a flair it cannot load: the error
      // handler drops the foreground image and rebuilds around the initial.
      //
      // That rebuild must not raise: CircleAvatar asserts
      // `foregroundImage != null || onForegroundImageError == null`, so the
      // error handler has to go with the image it belonged to
      // (lib/src/widgets/user.dart:331). The avatar falls back to the
      // initial instead.
      //
      // The flair name differs from the one the loading test uses, so the
      // image cache cannot hand this test the image that test loaded.
      final app = await makeTestProviderScopeApp(
        tester,
        home: Scaffold(
          body: UserAvatar(_user(name: 'alice', flair: 'broken')),
        ),
      );
      await tester.pumpWidget(app);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      expect(avatar.foregroundImage, isNull);
      expect(avatar.onForegroundImageError, isNull);
      expect(find.text('A'), findsOneWidget);
    });

    testWidgets('colours the initial from its letter in light mode', (WidgetTester tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: Scaffold(
          body: Theme(
            data: ThemeData.light(),
            child: UserAvatar(_user(name: 'nancy')),
          ),
        ),
      );
      await tester.pumpWidget(app);

      final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      expect(avatar.backgroundColor, Colors.red.shade800);
    });

    testWidgets('colours the initial from its letter in dark mode', (WidgetTester tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: Scaffold(
          body: Theme(
            data: ThemeData.dark(),
            child: UserAvatar(_user(name: 'nancy')),
          ),
        ),
      );
      await tester.pumpWidget(app);

      final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      expect(avatar.backgroundColor, Colors.red.shade700);
    });

    testWidgets('gives every letter its own colour', (WidgetTester tester) async {
      final app = await makeTestProviderScopeApp(
        tester,
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                for (final code in 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.codeUnits)
                  UserAvatar(_user(name: String.fromCharCode(code))),
              ],
            ),
          ),
        ),
      );
      await tester.pumpWidget(app);

      final colors = tester
          .widgetList<CircleAvatar>(find.byType(CircleAvatar))
          .map((a) => a.backgroundColor)
          .toList();
      expect(colors.length, 26);
      expect(colors.toSet().length, 26);
    });
  });
}
