import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khata_app/providers/auth_providers.dart';
import 'package:khata_app/services/local_lock_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('PIN set / verify works; wrong PIN fails', () async {
    final lock = LocalLockService();
    expect(await lock.hasPin, isFalse);

    await lock.setPin('1234');
    expect(await lock.hasPin, isTrue);
    expect(await lock.verifyPin('1234'), isTrue);
    expect(await lock.verifyPin('9999'), isFalse);
  });

  test('onboarding flags + clear require OTP path again', () async {
    final lock = LocalLockService();
    await lock.setPin('4321');
    await lock.setOnboarded(phoneE164: '+923001234567', userId: 'user-a');
    expect(await lock.isOnboarded, isTrue);
    expect(await lock.savedPhone, '+923001234567');
    expect(await lock.savedUserId, 'user-a');

    await lock.clearLocalLock();
    expect(await lock.isOnboarded, isFalse);
    expect(await lock.hasPin, isFalse);
  });

  test('AuthController goes home after completeOnboarding', () async {
    final lock = LocalLockService();
    await lock.setPin('1111');
    final controller = AuthController(lock);

    expect(controller.state.route, AuthRoute.loading);
    await controller.completeOnboarding(
      phoneE164: '+923001111111',
      userId: 'uid-1',
    );
    expect(controller.state.route, AuthRoute.home);
    expect(controller.state.userId, 'uid-1');
  });

  test('unlockWithPin rejects wrong PIN without opening home', () async {
    final lock = LocalLockService();
    await lock.setPin('2222');
    await lock.setOnboarded(phoneE164: '+923002222222', userId: 'uid-2');

    final controller = AuthController(lock);
    // Simulate unlock screen state without real Supabase session.
    // unlockWithPin will fail session check and send to onboarding — OR
    // fail PIN first. Wrong PIN should keep us from home.
    await controller.unlockWithPin('0000');
    expect(controller.state.route, isNot(AuthRoute.home));
    expect(controller.state.message, contains('Wrong PIN'));
  });

  test('local onboarding (phone later) reaches home without Supabase', () async {
    final lock = LocalLockService();
    await lock.setPin('5555');
    final controller = AuthController(lock);
    await controller.completeLocalOnboarding();
    expect(controller.state.route, AuthRoute.home);
    expect(controller.state.userId, startsWith('local_'));
    expect(await lock.isPhoneDeferred, isTrue);
    expect(await lock.hasLinkedPhone, isFalse);
  });

  test('deferred phone unlock does not require session', () async {
    final lock = LocalLockService();
    await lock.setPin('6666');
    await lock.setOnboarded(
      userId: 'local_test_user',
      phoneDeferred: true,
    );
    final controller = AuthController(lock);
    await controller.unlockWithPin('6666');
    expect(controller.state.route, AuthRoute.home);
  });
}
