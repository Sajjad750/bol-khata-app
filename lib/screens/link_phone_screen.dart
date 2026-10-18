import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/phone_numbers.dart';
import '../providers/auth_providers.dart';
import '../services/supabase_service.dart';
import '../theme/khata_colors.dart';

/// Link phone later for cloud backup (keeps existing PIN + local ledger).
class LinkPhoneScreen extends ConsumerStatefulWidget {
  const LinkPhoneScreen({super.key});

  @override
  ConsumerState<LinkPhoneScreen> createState() => _LinkPhoneScreenState();
}

class _LinkPhoneScreenState extends ConsumerState<LinkPhoneScreen> {
  final _phoneCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  bool _otpSent = false;
  String? _phoneE164;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
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
          'Add SUPABASE_URL and SUPABASE_ANON_KEY to .env, then rebuild.',
        );
      }
      _phoneE164 = SupabaseService.toE164(_phoneCtrl.text);
      await SupabaseService.sendOtp(_phoneE164!);
      if (!mounted) return;
      setState(() => _otpSent = true);
    } catch (e) {
      setState(() => _error = _friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
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
      await ref.read(authControllerProvider.notifier).completePhoneLink(phone);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Phone linked. Cloud backup enabled.')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = _friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendly(Object e) {
    if (e is AuthException) return e.message;
    if (e is ArgumentError) return e.message ?? e.toString();
    return e.toString().replaceFirst('Exception: ', '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add phone number')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Link your shop phone once for cloud backup. Daily unlock stays PIN / biometric.',
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: Colors.grey.shade700),
              ),
              const SizedBox(height: 20),
              if (_error != null) ...[
                Text(
                  _error!,
                  style: const TextStyle(color: KhataColors.debtRed),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _phoneCtrl,
                enabled: !_otpSent,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Mobile number',
                  hintText: '03XXXXXXXXX',
                ),
              ),
              if (_otpSent) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _otpCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 8,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'OTP code',
                    counterText: '',
                  ),
                ),
              ],
              const Spacer(),
              FilledButton(
                onPressed: _busy ? null : (_otpSent ? _verify : _send),
                child: _busy
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_otpSent ? 'Verify & link' : 'Send code'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
