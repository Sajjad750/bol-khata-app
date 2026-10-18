import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App + voice language preference.
enum AppLanguage {
  english,
  urdu,
  romanUrdu;

  String get code => switch (this) {
        AppLanguage.english => 'en',
        AppLanguage.urdu => 'ur',
        AppLanguage.romanUrdu => 'rom_ur',
      };

  /// Label shown in the picker's own language.
  String get nativeLabel => switch (this) {
        AppLanguage.english => 'English',
        AppLanguage.urdu => 'اردو',
        AppLanguage.romanUrdu => 'Roman Urdu',
      };

  String get subtitle => switch (this) {
        AppLanguage.english => 'App & voice in English',
        AppLanguage.urdu => 'ایپ اور آواز اردو میں',
        AppLanguage.romanUrdu => 'App aur awaaz Roman Urdu mein',
      };

  bool get isRtl => this == AppLanguage.urdu;

  TextDirection get textDirection =>
      isRtl ? TextDirection.rtl : TextDirection.ltr;

  /// Material / intl locale (Roman Urdu uses English glyphs).
  Locale get materialLocale => switch (this) {
        AppLanguage.english => const Locale('en'),
        AppLanguage.urdu => const Locale('ur'),
        AppLanguage.romanUrdu => const Locale('en'),
      };

  /// Whisper `language` field.
  String get whisperLanguage => switch (this) {
        AppLanguage.english => 'en',
        AppLanguage.urdu => 'ur',
        AppLanguage.romanUrdu => 'ur',
      };

  static AppLanguage? fromCode(String? code) {
    if (code == null) return null;
    for (final lang in AppLanguage.values) {
      if (lang.code == code) return lang;
    }
    return null;
  }
}

/// Persists [AppLanguage] in shared preferences (not secure storage).
class LanguagePreferenceService {
  LanguagePreferenceService(this._prefs);

  static const _key = 'bol_khata_language';
  static const _chosenKey = 'bol_khata_language_chosen';

  final SharedPreferences _prefs;

  bool get hasChosen => _prefs.getBool(_chosenKey) ?? false;

  AppLanguage get language =>
      AppLanguage.fromCode(_prefs.getString(_key)) ?? AppLanguage.romanUrdu;

  Future<void> setLanguage(AppLanguage language) async {
    await _prefs.setString(_key, language.code);
    await _prefs.setBool(_chosenKey, true);
  }
}
