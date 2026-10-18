import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_language.dart';
import '../l10n/app_strings.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPreferencesProvider must be overridden in main');
});

final languagePreferenceServiceProvider =
    Provider<LanguagePreferenceService>((ref) {
  return LanguagePreferenceService(ref.watch(sharedPreferencesProvider));
});

class LanguageState {
  const LanguageState({
    required this.language,
    required this.hasChosen,
  });

  final AppLanguage language;
  final bool hasChosen;

  AppStrings get strings => AppStrings(language);
}

class LanguageController extends StateNotifier<LanguageState> {
  LanguageController(this._service)
      : super(
          LanguageState(
            language: _service.language,
            hasChosen: _service.hasChosen,
          ),
        );

  final LanguagePreferenceService _service;

  Future<void> setLanguage(AppLanguage language) async {
    await _service.setLanguage(language);
    state = LanguageState(language: language, hasChosen: true);
  }
}

final languageControllerProvider =
    StateNotifierProvider<LanguageController, LanguageState>((ref) {
  return LanguageController(ref.watch(languagePreferenceServiceProvider));
});

final appStringsProvider = Provider<AppStrings>((ref) {
  return ref.watch(languageControllerProvider).strings;
});
