import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/phone_numbers.dart';
import 'secure_supabase_storage.dart';

/// Supabase client + phone OTP auth (no anonymous sign-in).
class SupabaseService {
  SupabaseService._();

  static bool _initialized = false;

  static SupabaseClient get client => Supabase.instance.client;

  static bool get isConfigured {
    final url = dotenv.env['SUPABASE_URL']?.trim() ?? '';
    final key = dotenv.env['SUPABASE_ANON_KEY']?.trim() ?? '';
    return url.isNotEmpty &&
        key.isNotEmpty &&
        !url.contains('your-project') &&
        !key.contains('your-anon');
  }

  static bool get isInitialized => _initialized;

  static bool get isReady => _initialized && isConfigured && hasUsableSession;

  static String? get userId => client.auth.currentUser?.id;

  /// True when a session (access + refresh) is restored locally.
  /// Does not require a network call.
  static bool get hasUsableSession {
    if (!_initialized || !isConfigured) return false;
    final session = client.auth.currentSession;
    return session != null && session.refreshToken != null;
  }

  /// Initialize client and restore secure session. Never signs in anonymously.
  static Future<bool> ensureInitialized() async {
    if (!isConfigured) return false;

    try {
      if (!_initialized) {
        final url = dotenv.env['SUPABASE_URL']!.trim();
        final key = dotenv.env['SUPABASE_ANON_KEY']!.trim();
        await Supabase.initialize(
          url: url,
          publishableKey: key,
          authOptions: FlutterAuthClientOptions(
            localStorage: SecureSupabaseLocalStorage(),
            autoRefreshToken: true,
          ),
        );
        _initialized = true;
      }
      return hasUsableSession;
    } catch (_) {
      return false;
    }
  }

  /// Pakistani local `03…` → E.164 `+92…` for Supabase Auth.
  static String toE164(String input) {
    final local = PhoneNumbers.normalize(input);
    if (!PhoneNumbers.isValidPakistaniMobile(local)) {
      throw ArgumentError('Enter a valid Pakistani mobile (03XXXXXXXXX)');
    }
    return '+92${local.substring(1)}';
  }

  static Future<void> sendOtp(String phoneLocalOrE164) async {
    await ensureInitialized();
    if (!isConfigured || !_initialized) {
      throw AuthException(
        'Supabase is not configured. Add SUPABASE_URL and SUPABASE_ANON_KEY.',
      );
    }
    final phone = phoneLocalOrE164.startsWith('+')
        ? phoneLocalOrE164
        : toE164(phoneLocalOrE164);
    await client.auth.signInWithOtp(phone: phone);
  }

  static Future<AuthResponse> verifyOtp({
    required String phoneLocalOrE164,
    required String token,
  }) async {
    await ensureInitialized();
    if (!isConfigured || !_initialized) {
      throw AuthException(
        'Supabase is not configured. Add SUPABASE_URL and SUPABASE_ANON_KEY.',
      );
    }
    final phone = phoneLocalOrE164.startsWith('+')
        ? phoneLocalOrE164
        : toE164(phoneLocalOrE164);
    final response = await client.auth.verifyOTP(
      phone: phone,
      token: token.trim(),
      type: OtpType.sms,
    );
    if (response.session == null) {
      throw AuthException('Verification failed. Check the code and try again.');
    }
    return response;
  }

  /// Soft check: session present locally. Refresh only if clearly expired.
  /// Unlock path should call this without blocking the user on network.
  static Future<bool> sessionLooksValid({
    bool allowNetworkRefresh = false,
  }) async {
    await ensureInitialized();
    if (!hasUsableSession) return false;

    final session = client.auth.currentSession!;
    final expiresAt = session.expiresAt;
    if (expiresAt == null) return true;

    final expired = DateTime.fromMillisecondsSinceEpoch(
      expiresAt * 1000,
    ).isBefore(DateTime.now());
    if (!expired) return true;

    if (!allowNetworkRefresh) {
      // Refresh token still present — unlock offline; sync can refresh later.
      return session.refreshToken != null;
    }

    try {
      final refreshed = await client.auth.refreshSession();
      return refreshed.session != null;
    } catch (_) {
      return false;
    }
  }

  static Future<void> signOut() async {
    if (!_initialized) return;
    try {
      await client.auth.signOut();
    } catch (_) {}
  }
}
