import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_providers.dart';
import '../providers/language_providers.dart';
import '../theme/khata_colors.dart';
import 'home_screen.dart';
import 'language_picker_screen.dart';
import 'onboarding_screen.dart';
import 'unlock_screen.dart';

/// Routes language pick → OTP onboarding / PIN unlock / home.
class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(authControllerProvider.notifier).bootstrap();
    });
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(languageControllerProvider);
    if (!lang.hasChosen) {
      return const LanguagePickerScreen();
    }

    final auth = ref.watch(authControllerProvider);

    switch (auth.route) {
      case AuthRoute.loading:
        return const Scaffold(
          body: Center(
            child: CircularProgressIndicator(color: KhataColors.primaryGreen),
          ),
        );
      case AuthRoute.onboarding:
        return OnboardingScreen(bannerMessage: auth.message);
      case AuthRoute.unlock:
        return const UnlockScreen();
      case AuthRoute.home:
        return const HomeScreen();
    }
  }
}
