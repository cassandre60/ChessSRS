// Copyright (C) 2024 ChessSRS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:chess_srs/src/model/auth/auth_controller.dart';
import 'package:chess_srs/src/model/common/id.dart';
import 'package:chess_srs/src/model/user/user.dart';
import 'package:chess_srs/src/view/account/account_menu.dart';
import 'package:chess_srs/src/view/settings/srs_settings_screen.dart';
import 'package:flutter_riverpod/misc.dart' show Override, ProviderOrFamily;
import 'package:flutter_test/flutter_test.dart';

import '../../binding.dart';
import '../../test_provider_scope.dart';

void main() {
  setUpAll(() {
    TestLichessBinding.ensureInitialized();
  });

  Future<void> openSettings(
    WidgetTester tester, {
    Map<ProviderOrFamily, Override> overrides = const {},
  }) async {
    final app = await makeTestProviderScopeApp(
      tester,
      home: const SrsSettingsScreen(),
      overrides: overrides,
    );
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
  }

  testWidgets('the account row is reachable and opens the account menu', (tester) async {
    await openSettings(tester);

    // Without a row here, nothing in the app can reach signing in, signing out, the profile or
    // the about page: the bottom-nav tab that used to host them was removed without a replacement.
    expect(find.text('Lichess account'), findsOneWidget);
    expect(find.text('Not signed in'), findsOneWidget);

    await tester.tap(find.text('Lichess account'));
    await tester.pumpAndSettle();

    expect(find.byType(AccountMenuScreen), findsOneWidget);
  });

  testWidgets('the account row names the signed-in account', (tester) async {
    await openSettings(
      tester,
      overrides: {authControllerProvider: authControllerProvider.overrideWith(() => _SignedIn())},
    );

    expect(find.text('Not signed in'), findsNothing);
    expect(find.text('tester'), findsOneWidget);
  });
}

/// A controller already holding a token, so the row has a name to show.
class _SignedIn extends AuthController {
  @override
  AuthUser? build() => const AuthUser(
    token: 'test-token',
    user: LightUser(id: UserId('tester'), name: 'tester'),
  );
}
