import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_language.dart';
import '../providers/language_providers.dart';
import '../theme/bol_khata_brand.dart';
import '../theme/khata_colors.dart';

/// First-launch (and settings) language chooser.
class LanguagePickerScreen extends ConsumerStatefulWidget {
  const LanguagePickerScreen({super.key, this.allowSkipIfChosen = false});

  /// When true (settings), picking immediately pops.
  final bool allowSkipIfChosen;

  @override
  ConsumerState<LanguagePickerScreen> createState() =>
      _LanguagePickerScreenState();
}

class _LanguagePickerScreenState extends ConsumerState<LanguagePickerScreen> {
  AppLanguage? _selected;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final state = ref.read(languageControllerProvider);
    _selected = state.hasChosen ? state.language : AppLanguage.romanUrdu;
  }

  Future<void> _continue() async {
    final lang = _selected;
    if (lang == null) return;
    setState(() => _saving = true);
    await ref.read(languageControllerProvider.notifier).setLanguage(lang);
    if (!mounted) return;
    if (widget.allowSkipIfChosen) {
      Navigator.of(context).pop(lang);
    } else {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = AppLanguage.romanUrdu; // picker chrome stays bilingual
    // Use selected language for title when possible
    final titleLang = _selected ?? preview;
    String title;
    String subtitle;
    String button;
    switch (titleLang) {
      case AppLanguage.english:
        title = 'Choose your language';
        subtitle = 'This sets the app text and how voice entries are written.';
        button = 'Continue';
      case AppLanguage.urdu:
        title = 'اپنی زبان منتخب کریں';
        subtitle = 'اس سے ایپ کا متن اور آواز کا اندراج طے ہوگا۔';
        button = 'آگے بڑھیں';
      case AppLanguage.romanUrdu:
        title = 'Apni zubaan chunein';
        subtitle = 'Is se app ka text aur awaaz ka andraj set hoga.';
        button = 'Aage badhein';
    }

    return Directionality(
      textDirection: titleLang.textDirection,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(
                  child: BolKhataLogo(
                    height: 64,
                    variant: BolKhataLogoVariant.green,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  BolKhataBrand.appName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: KhataColors.primaryGreen,
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.grey.shade700,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 28),
                for (final lang in AppLanguage.values) ...[
                  _LanguageTile(
                    language: lang,
                    selected: _selected == lang,
                    onTap: () => setState(() => _selected = lang),
                  ),
                  const SizedBox(height: 12),
                ],
                const Spacer(),
                SizedBox(
                  height: 56,
                  child: FilledButton(
                    onPressed: _saving || _selected == null ? null : _continue,
                    child: Text(_saving ? '…' : button),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({
    required this.language,
    required this.selected,
    required this.onTap,
  });

  final AppLanguage language;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? KhataColors.softGreen : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? KhataColors.primaryGreen
                  : const Color(0xFFD0D5D2),
              width: selected ? 2 : 1.2,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected
                    ? KhataColors.primaryGreen
                    : Colors.grey.shade500,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      language.nativeLabel,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      language.subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
