import 'package:chess_srs/src/model/account/account_repository.dart';
import 'package:chess_srs/src/model/account/account_service.dart';
import 'package:chess_srs/src/model/auth/auth_controller.dart';
import 'package:chess_srs/src/model/common/id.dart';
import 'package:chess_srs/src/model/user/user.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockAccountRepository extends Mock implements AccountRepository {}

class _SignedIn extends AuthController {
  @override
  AuthUser? build() => const AuthUser(
    token: 't',
    user: LightUser(id: UserId('u'), name: 'u'),
  );
}

class _SignedOut extends AuthController {
  @override
  AuthUser? build() => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockAccountRepository repo;
  late ProviderContainer container;

  setUp(() {
    repo = _MockAccountRepository();
    when(() => repo.bookmark(any(), bookmark: any(named: 'bookmark'))).thenAnswer((_) async {});
    container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(_SignedIn.new),
        accountRepositoryProvider.overrideWithValue(repo),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  test('setGameBookmark calls repository and emits change when signed in', () async {
    final service = container.read(accountServiceProvider);
    final events = <(GameId, bool)>[];
    final sub = service.bookmarkChanges.listen(events.add);

    const id = GameId('12345678');
    await service.setGameBookmark(id, bookmark: true);
    await Future<void>.delayed(Duration.zero);

    verify(() => repo.bookmark(id, bookmark: true)).called(1);
    expect(events, [(id, true)]);

    await sub.cancel();
  });

  test('setGameBookmark with bookmark false emits false', () async {
    final service = container.read(accountServiceProvider);
    final events = <(GameId, bool)>[];
    final sub = service.bookmarkChanges.listen(events.add);

    const id = GameId('12345678');
    await service.setGameBookmark(id, bookmark: false);
    await Future<void>.delayed(Duration.zero);

    verify(() => repo.bookmark(id, bookmark: false)).called(1);
    expect(events, [(id, false)]);

    await sub.cancel();
  });

  test('setGameBookmark does nothing when signed out', () async {
    final signedOut = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(_SignedOut.new),
        accountRepositoryProvider.overrideWithValue(repo),
      ],
    );
    final service = signedOut.read(accountServiceProvider);
    final events = <(GameId, bool)>[];
    final sub = service.bookmarkChanges.listen(events.add);

    const id = GameId('12345678');
    await service.setGameBookmark(id, bookmark: true);

    verifyNever(() => repo.bookmark(any(), bookmark: any(named: 'bookmark')));
    expect(events, isEmpty);

    await sub.cancel();
    signedOut.dispose();
  });
}
