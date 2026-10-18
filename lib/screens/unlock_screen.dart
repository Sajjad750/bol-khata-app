import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_providers.dart';
import '../providers/language_providers.dart';
import '../theme/bol_khata_brand.dart';
import '../theme/khata_colors.dart';

/// Fast unlock with PIN / biometric — no OTP on normal opens.
class UnlockScreen extends ConsumerStatefulWidget {
  const UnlockScreen({super.key});

  @override
  ConsumerState<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends ConsumerState<UnlockScreen> {
  String _pin = '';
  bool _bioAvailable = false;
  bool _bioEnabled = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    final lock = ref.read(localLockServiceProvider);
    final can = await lock.canCheckBiometrics();
    final enabled = await lock.isBiometricEnabled;
    if (!mounted) return;
    setState(() {
      _bioAvailable = can;
      _bioEnabled = enabled;
    });
    if (can && enabled) {
      // Auto-prompt biometric once — still no network / OTP.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (mounted) await _tryBiometric();
    }
  }

  Future<void> _tryBiometric() async {
    if (_busy) return;
    setState(() => _busy = true);
    ref.read(authControllerProvider.notifier).clearMessage();
    await ref.read(authControllerProvider.notifier).unlockWithBiometric();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _onDigit(String d) async {
    if (_pin.length >= 4 || _busy) return;
    setState(() => _pin = '$_pin$d');
    if (_pin.length == 4) {
      setState(() => _busy = true);
      ref.read(authControllerProvider.notifier).clearMessage();
      await ref.read(authControllerProvider.notifier).unlockWithPin(_pin);
      if (!mounted) return;
      final route = ref.read(authControllerProvider).route;
      if (route != AuthRoute.home) {
        setState(() {
          _pin = '';
          _busy = false;
        });
      }
    }
  }

  void _backspace() {
    if (_pin.isEmpty || _busy) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final message = auth.message;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            children: [
              const SizedBox(height: 40),
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
                ref.watch(appStringsProvider).enterPinToUnlock,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.grey.shade700,
                    ),
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (i) {
                  final filled = i < _pin.length;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: filled
                          ? KhataColors.primaryGreen
                          : Colors.grey.shade300,
                    ),
                  );
                }),
              ),
              if (message != null) ...[
                const SizedBox(height: 16),
                Text(
                  message,
                  style: const TextStyle(color: KhataColors.debtRed),
                  textAlign: TextAlign.center,
                ),
              ],
              const Spacer(),
              if (_bioAvailable && _bioEnabled)
                IconButton(
                  onPressed: _busy ? null : _tryBiometric,
                  iconSize: 36,
                  icon: const Icon(
                    Icons.fingerprint,
                    color: KhataColors.primaryGreen,
                  ),
                ),
              const SizedBox(height: 8),
              _PinPad(onDigit: _onDigit, onBackspace: _backspace),
              TextButton(
                onPressed: _busy
                    ? null
                    : () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Verify phone again?'),
                            content: const Text(
                              'Only needed if you forgot your PIN or changed phones. '
                              'This will ask for SMS OTP once.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Continue'),
                              ),
                            ],
                          ),
                        );
                        if (ok == true) {
                          await ref
                              .read(authControllerProvider.notifier)
                              .signOutFully();
                        }
                      },
                child: const Text('Forgot PIN? Verify phone again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PinPad extends StatelessWidget {
  const _PinPad({required this.onDigit, required this.onBackspace});

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    final keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', '⌫'],
    ];
    return Column(
      children: [
        for (final row in keys)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final key in row)
                SizedBox(
                  width: 88,
                  height: 64,
                  child: key.isEmpty
                      ? const SizedBox.shrink()
                      : TextButton(
                          onPressed: () {
                            HapticFeedback.selectionClick();
                            if (key == '⌫') {
                              onBackspace();
                            } else {
                              onDigit(key);
                            }
                          },
                          child: Text(
                            key,
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                ),
            ],
          ),
      ],
    );
  }
}
