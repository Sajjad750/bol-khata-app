import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../services/local_lock_service.dart';
import '../services/supabase_service.dart';
import '../services/sync_service.dart';

/// Where the auth gate should route.
enum AuthRoute {
  loading,
  onboarding,
  unlock,
  home,
}

class AuthSessionState {
  const AuthSessionState({
    required this.route,
    this.userId,
    this.message,
  });

  final AuthRoute route;
  final String? userId;
  final String? message;

  AuthSessionState copyWith({
    AuthRoute? route,
    String? userId,
    String? message,
    bool clearMessage = false,
  }) {
    return AuthSessionState(
      route: route ?? this.route,
      userId: userId ?? this.userId,
      message: clearMessage ? null : (message ?? this.message),
    );
  }
}

class AuthController extends StateNotifier<AuthSessionState> {
  AuthController(this._lock)
      : super(const AuthSessionState(route: AuthRoute.loading));

  final LocalLockService _lock;
  bool _unlocked = false;

  Future<void> bootstrap() async {
    state = const AuthSessionState(route: AuthRoute.loading);
    try {
      await SupabaseService.ensureInitialized();

      final onboarded = await _lock.isOnboarded;
      if (!onboarded) {
        _unlocked = false;
        state = const AuthSessionState(route: AuthRoute.onboarding);
        return;
      }

      final deferred = await _lock.isPhoneDeferred;
      final sessionOk = await SupabaseService.sessionLooksValid(
        allowNetworkRefresh: false,
      );

      // Local-only (phone later): unlock with PIN, no Supabase session needed.
      // Phone-linked: require a usable session, else re-verify OTP.
      if (!deferred && !sessionOk) {
        _unlocked = false;
        state = const AuthSessionState(
          route: AuthRoute.onboarding,
          message: 'Your session expired. Verify your phone once more.',
        );
        return;
      }

      _unlocked = false;
      state = AuthSessionState(
        route: AuthRoute.unlock,
        userId: await _lock.savedUserId,
      );
    } catch (_) {
      // Never crash the app on startup — fall back to onboarding.
      _unlocked = false;
      state = const AuthSessionState(route: AuthRoute.onboarding);
    }
  }

  /// After OTP + PIN (phone linked).
  ///
  /// Reuses any existing on-device ledger id so sign-out → sign-in does not
  /// open a brand-new empty database file.
  Future<void> completeOnboarding({
    required String phoneE164,
    required String userId,
  }) async {
    final existing = await _lock.savedUserId;
    final ledgerId =
        (existing != null && existing.isNotEmpty) ? existing : userId;
    await _lock.setOnboarded(
      phoneE164: phoneE164,
      userId: ledgerId,
      phoneDeferred: false,
    );
    _unlocked = true;
    state = AuthSessionState(route: AuthRoute.home, userId: ledgerId);
  }

  /// Skip phone for now — app usable offline with PIN only.
  Future<void> completeLocalOnboarding() async {
    final userId = await _lock.ensureLocalUserId();
    await _lock.setOnboarded(
      phoneE164: null,
      userId: userId,
      phoneDeferred: true,
    );
    _unlocked = true;
    state = AuthSessionState(route: AuthRoute.home, userId: userId);
  }

  /// After later phone+OTP while already using the app.
  Future<void> completePhoneLink(String phoneE164) async {
    await _lock.markPhoneLinked(phoneE164);
    final userId = await _lock.savedUserId;
    state = state.copyWith(userId: userId, clearMessage: true);
  }

  Future<void> unlockWithPin(String pin) async {
    final ok = await _lock.verifyPin(pin);
    if (!ok) {
      state = state.copyWith(message: 'Wrong PIN. Try again.');
      return;
    }
    await _finishUnlock();
  }

  Future<void> unlockWithBiometric() async {
    final enabled = await _lock.isBiometricEnabled;
    if (!enabled) {
      state = state.copyWith(message: 'Biometric unlock is not enabled.');
      return;
    }
    final ok = await _lock.authenticateBiometric();
    if (!ok) {
      state = state.copyWith(message: 'Biometric unlock failed.');
      return;
    }
    await _finishUnlock();
  }

  Future<void> _finishUnlock() async {
    final deferred = await _lock.isPhoneDeferred;
    if (!deferred) {
      final sessionOk = await SupabaseService.sessionLooksValid(
        allowNetworkRefresh: false,
      );
      if (!sessionOk) {
        _unlocked = false;
        state = const AuthSessionState(
          route: AuthRoute.onboarding,
          message: 'Your session expired. Verify your phone once more.',
        );
        return;
      }
    }
    _unlocked = true;
    state = AuthSessionState(
      route: AuthRoute.home,
      userId: await _lock.savedUserId,
      message: null,
    );
  }

  void clearMessage() {
    state = state.copyWith(clearMessage: true);
  }

  Future<void> signOutFully() async {
    await SupabaseService.signOut();
    // Keep ledger user id so Drift reopens the same khata_*.db file.
    await _lock.clearLocalLock(keepLedgerIdentity: true);
    final ledgerId = await _lock.savedUserId;
    _unlocked = false;
    state = AuthSessionState(
      route: AuthRoute.onboarding,
      userId: ledgerId,
    );
  }

  @visibleForTesting
  bool get isUnlockedForTest => _unlocked;
}

final localLockServiceProvider = Provider<LocalLockService>((ref) {
  return LocalLockService();
});

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthSessionState>((ref) {
  return AuthController(ref.watch(localLockServiceProvider));
});

/// Per-shopkeeper Drift file so account A data never mixes with account B.
///
/// Named from the stable on-device ledger id (not the live Supabase session),
/// so signing out and signing back in reopens the same file.
final databaseProvider = Provider<AppDatabase>((ref) {
  final auth = ref.watch(authControllerProvider);
  final userId = auth.userId ?? SupabaseService.userId;
  if (userId == null || userId.isEmpty) {
    return AppDatabase.memory();
  }
  final safe = userId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
  final name = 'khata_${safe.substring(0, safe.length.clamp(0, 24))}';
  final db = AppDatabase(name: name);
  ref.onDispose(db.close);
  return db;
});

final syncServiceProvider = Provider<SyncService?>((ref) {
  final route = ref.watch(authControllerProvider).route;
  if (route != AuthRoute.home) return null;
  // No cloud session yet (phone deferred) — skip starting sync.
  if (!SupabaseService.hasUsableSession) return null;
  final db = ref.watch(databaseProvider);
  final sync = SyncService(db);
  sync.start();
  ref.onDispose(sync.stop);
  return sync;
});
