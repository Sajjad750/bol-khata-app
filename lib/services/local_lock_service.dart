import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Day-to-day unlock: 4-digit PIN and optional biometric.
///
/// Phone + OTP is optional at first launch ("Add number later"). OTP is only
/// required when linking a phone or when a linked session is revoked.
class LocalLockService {
  LocalLockService({
    FlutterSecureStorage? storage,
    LocalAuthentication? localAuth,
  }) : _storage =
           storage ??
           const FlutterSecureStorage(
             aOptions: AndroidOptions(encryptedSharedPreferences: true),
           ),
       _localAuth = localAuth ?? LocalAuthentication();

  static const _pinHashKey = 'khata_pin_hash';
  static const _pinSaltKey = 'khata_pin_salt';
  static const _biometricKey = 'khata_biometric_enabled';
  static const _phoneKey = 'khata_auth_phone';
  static const _userIdKey = 'khata_auth_user_id';
  static const _onboardedKey = 'khata_onboarded';
  static const _phoneDeferredKey = 'khata_phone_deferred';

  final FlutterSecureStorage _storage;
  final LocalAuthentication _localAuth;

  Future<bool> get hasPin async {
    try {
      return (await _storage.read(key: _pinHashKey))?.isNotEmpty == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> get isOnboarded async {
    try {
      return (await _storage.read(key: _onboardedKey)) == '1' && await hasPin;
    } catch (_) {
      return false;
    }
  }

  /// True when shopkeeper skipped phone and can use the app offline-first.
  Future<bool> get isPhoneDeferred async {
    try {
      return (await _storage.read(key: _phoneDeferredKey)) == '1';
    } catch (_) {
      return true;
    }
  }

  Future<bool> get hasLinkedPhone async {
    final phone = await savedPhone;
    return phone != null && phone.isNotEmpty && !(await isPhoneDeferred);
  }

  Future<bool> get isBiometricEnabled async =>
      (await _storage.read(key: _biometricKey)) == '1';

  Future<String?> get savedPhone async => _storage.read(key: _phoneKey);

  Future<String?> get savedUserId async => _storage.read(key: _userIdKey);

  /// Stable local ledger id for Drift (does not require Supabase).
  Future<String> ensureLocalUserId() async {
    final existing = await savedUserId;
    if (existing != null && existing.isNotEmpty) return existing;
    final id =
        'local_${DateTime.now().millisecondsSinceEpoch}_${Random.secure().nextInt(99999)}';
    await _storage.write(key: _userIdKey, value: id);
    return id;
  }

  Future<void> setOnboarded({
    String? phoneE164,
    required String userId,
    bool phoneDeferred = false,
  }) async {
    if (phoneE164 != null && phoneE164.isNotEmpty) {
      await _storage.write(key: _phoneKey, value: phoneE164);
    } else {
      await _storage.delete(key: _phoneKey);
    }
    await _storage.write(key: _userIdKey, value: userId);
    await _storage.write(key: _onboardedKey, value: '1');
    await _storage.write(
      key: _phoneDeferredKey,
      value: phoneDeferred ? '1' : '0',
    );
  }

  /// After later phone+OTP success — keep the same local ledger userId.
  Future<void> markPhoneLinked(String phoneE164) async {
    await _storage.write(key: _phoneKey, value: phoneE164);
    await _storage.write(key: _phoneDeferredKey, value: '0');
  }

  Future<void> setPin(String pin) async {
    if (!_isValidPin(pin)) {
      throw ArgumentError('PIN must be exactly 4 digits');
    }
    final salt = _randomSalt();
    final hash = _hashPin(pin, salt);
    await _storage.write(key: _pinSaltKey, value: salt);
    await _storage.write(key: _pinHashKey, value: hash);
  }

  Future<bool> verifyPin(String pin) async {
    if (!_isValidPin(pin)) return false;
    final salt = await _storage.read(key: _pinSaltKey);
    final expected = await _storage.read(key: _pinHashKey);
    if (salt == null || expected == null) return false;
    return _hashPin(pin, salt) == expected;
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    await _storage.write(key: _biometricKey, value: enabled ? '1' : '0');
  }

  Future<bool> canCheckBiometrics() async {
    try {
      return await _localAuth.canCheckBiometrics ||
          await _localAuth.isDeviceSupported();
    } on PlatformException {
      return false;
    }
  }

  Future<bool> authenticateBiometric({
    String reason = 'Unlock Bol Khata',
  }) async {
    try {
      return await _localAuth.authenticate(
        localizedReason: reason,
        biometricOnly: false,
      );
    } on PlatformException {
      return false;
    }
  }

  /// Clears PIN / phone / onboarding flags.
  ///
  /// Keeps [savedUserId] by default so the on-device Drift ledger file is reused
  /// after the shopkeeper signs in again (sign-out must not wipe khata data).
  Future<void> clearLocalLock({bool keepLedgerIdentity = true}) async {
    await _storage.delete(key: _pinHashKey);
    await _storage.delete(key: _pinSaltKey);
    await _storage.delete(key: _biometricKey);
    await _storage.delete(key: _phoneKey);
    await _storage.delete(key: _onboardedKey);
    await _storage.delete(key: _phoneDeferredKey);
    if (!keepLedgerIdentity) {
      await _storage.delete(key: _userIdKey);
    }
  }

  static bool _isValidPin(String pin) => RegExp(r'^\d{4}$').hasMatch(pin);

  static String _randomSalt() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    return base64UrlEncode(bytes);
  }

  static String _hashPin(String pin, String salt) {
    final digest = sha256.convert(utf8.encode('$salt:$pin'));
    return digest.toString();
  }
}
