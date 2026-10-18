import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/phone_numbers.dart';
import '../providers/auth_providers.dart';
import '../providers/language_providers.dart';
import '../services/supabase_service.dart';
import '../theme/bol_khata_brand.dart';
import '../theme/khata_colors.dart';

/// First-launch: phone+OTP (optional) → PIN → biometric.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, this.bannerMessage});

  final String? bannerMessage;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

enum _Step { phone, otp, pin, confirmPin, biometric }

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  _Step _step = _Step.phone;
  final _phoneCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  final _pinConfirmCtrl = TextEditingController();

  String? _phoneE164;
  bool _phoneDeferred = false;
  String? _error;
  bool _busy = false;
  bool _biometricAvailable = false;
  bool _enableBiometric = true;

  @override
  void initState() {
    super.initState();
    _error = widget.bannerMessage;
    _checkBiometric();
  }

  Future<void> _checkBiometric() async {
    final lock = ref.read(localLockServiceProvider);
    final ok = await lock.canCheckBiometrics();
    if (mounted) setState(() => _biometricAvailable = ok);
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    _pinCtrl.dispose();
    _pinConfirmCtrl.dispose();
    super.dispose();
  }

  void _skipPhoneForNow() {
    setState(() {
      _phoneDeferred = true;
      _phoneE164 = null;
      _error = null;
      _step = _Step.pin;
    });
  }

  Future<void> _sendOtp() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!PhoneNumbers.isValidPakistaniMobile(_phoneCtrl.text)) {
        throw ArgumentError('Enter a valid mobile like 03XXXXXXXXX');
      }
      if (!SupabaseService.isConfigured) {
        throw AuthException(
          'Cloud backup is not set up yet. Tap “Add number later” to use Bol Khata now.',
        );
      }
      _phoneE164 = SupabaseService.toE164(_phoneCtrl.text);
      _phoneDeferred = false;
      await SupabaseService.sendOtp(_phoneE164!);
      if (!mounted) return;
      setState(() => _step = _Step.otp);
    } catch (e) {
      setState(() => _error = _friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyOtp() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final phone = _phoneE164 ?? SupabaseService.toE164(_phoneCtrl.text);
      await SupabaseService.verifyOtp(
        phoneLocalOrE164: phone,
        token: _otpCtrl.text,
      );
      if (!mounted) return;
      setState(() {
        _phoneDeferred = false;
        _step = _Step.pin;
      });
    } catch (e) {
      setState(() => _error = _friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _savePinAndContinue() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final pin = _pinCtrl.text.trim();
      if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
        throw ArgumentError('PIN must be 4 digits');
      }
      if (_step == _Step.pin) {
        setState(() {
          _step = _Step.confirmPin;
          _busy = false;
        });
        return;
      }
      if (pin != _pinConfirmCtrl.text.trim()) {
        throw ArgumentError('PINs do not match');
      }
      final lock = ref.read(localLockServiceProvider);
      await lock.setPin(pin);

      if (_biometricAvailable) {
        setState(() {
          _step = _Step.biometric;
          _busy = false;
        });
        return;
      }
      await _finish(enableBio: false);
    } catch (e) {
      setState(() {
        _error = _friendly(e);
        _busy = false;
      });
    }
  }

  Future<void> _finish({required bool enableBio}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final lock = ref.read(localLockServiceProvider);
      await lock.setBiometricEnabled(enableBio && _biometricAvailable);

      if (_phoneDeferred) {
        await ref.read(authControllerProvider.notifier).completeLocalOnboarding();
        return;
      }

      final userId = SupabaseService.userId;
      final phone = _phoneE164 ?? await lock.savedPhone;
      if (userId == null || phone == null) {
        throw AuthException('Session missing after verification.');
      }
      await ref.read(authControllerProvider.notifier).completeOnboarding(
            phoneE164: phone,
            userId: userId,
          );
    } catch (e) {
      setState(() => _error = _friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendly(Object e) {
    if (e is AuthException) return e.message;
    if (e is ArgumentError) return e.message ?? e.toString();
    final s = e.toString();
    if (s.length > 160) return '${s.substring(0, 160)}…';
    return s.replaceFirst('Exception: ', '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              const Center(
                child: BolKhataLogo(
                  height: 72,
                  variant: BolKhataLogoVariant.green,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                BolKhataBrand.appName,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.displayLarge?.copyWith(
                      color: KhataColors.primaryGreen,
                      fontSize: 36,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                _subtitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.grey.shade700,
                    ),
              ),
              const SizedBox(height: 28),
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF1F1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: KhataColors.debtRed),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Expanded(child: _buildStepBody()),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _busy ? null : _primaryAction,
                child: _busy
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_primaryLabel),
              ),
              if (_step == _Step.phone)
                TextButton(
                  onPressed: _busy ? null : _skipPhoneForNow,
                  child: Text(ref.watch(appStringsProvider).addNumberLater),
                ),
              if (_step == _Step.otp ||
                  _step == _Step.confirmPin ||
                  _step == _Step.biometric)
                TextButton(
                  onPressed: _busy
                      ? null
                      : () {
                          setState(() {
                            if (_step == _Step.otp) {
                              _step = _Step.phone;
                            } else if (_step == _Step.confirmPin) {
                              _step = _Step.pin;
                              _pinConfirmCtrl.clear();
                            } else if (_step == _Step.biometric) {
                              _finish(enableBio: false);
                            }
                            _error = null;
                          });
                        },
                  child: Text(
                    _step == _Step.biometric ? 'Skip biometric' : 'Back',
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String get _subtitle {
    final s = ref.read(appStringsProvider);
    switch (_step) {
      case _Step.phone:
        return s.phoneStepTitle;
      case _Step.otp:
        return s.otpStepTitle;
      case _Step.pin:
        return s.pinStepTitle;
      case _Step.confirmPin:
        return s.confirmPinTitle;
      case _Step.biometric:
        return s.biometricTitle;
    }
  }

  String get _primaryLabel {
    final s = ref.read(appStringsProvider);
    switch (_step) {
      case _Step.phone:
        return s.sendOtp;
      case _Step.otp:
        return s.verifyOtp;
      case _Step.pin:
        return s.continueLabel;
      case _Step.confirmPin:
        return s.save;
      case _Step.biometric:
        return _enableBiometric ? s.enableBiometric : s.skipBiometric;
    }
  }

  VoidCallback get _primaryAction {
    switch (_step) {
      case _Step.phone:
        return _sendOtp;
      case _Step.otp:
        return _verifyOtp;
      case _Step.pin:
      case _Step.confirmPin:
        return _savePinAndContinue;
      case _Step.biometric:
        return () => _finish(enableBio: _enableBiometric);
    }
  }

  Widget _buildStepBody() {
    switch (_step) {
      case _Step.phone:
        return TextField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _sendOtp(),
          decoration: const InputDecoration(
            labelText: 'Mobile number',
            hintText: '03XXXXXXXXX',
            prefixIcon: Icon(Icons.phone_android),
          ),
        );
      case _Step.otp:
        return TextField(
          controller: _otpCtrl,
          keyboardType: TextInputType.number,
          maxLength: 8,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'OTP code',
            prefixIcon: Icon(Icons.sms_outlined),
            counterText: '',
          ),
        );
      case _Step.pin:
        return TextField(
          controller: _pinCtrl,
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 4,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: '4-digit PIN',
            prefixIcon: Icon(Icons.lock_outline),
            counterText: '',
          ),
        );
      case _Step.confirmPin:
        return TextField(
          controller: _pinConfirmCtrl,
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 4,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Confirm PIN',
            prefixIcon: Icon(Icons.lock),
            counterText: '',
          ),
        );
      case _Step.biometric:
        return Column(
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Unlock with biometric'),
              subtitle: const Text('You can still use your PIN anytime.'),
              value: _enableBiometric,
              activeThumbColor: KhataColors.primaryGreen,
              onChanged: (v) => setState(() => _enableBiometric = v),
            ),
          ],
        );
    }
  }
}
