import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:khata_app/main.dart';
import 'package:khata_app/providers/language_providers.dart';
import 'package:khata_app/theme/bol_khata_brand.dart';

void main() {
  testWidgets('App loads with Bol Khata brand', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'bol_khata_language': 'rom_ur',
      'bol_khata_language_chosen': true,
    });
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: const KhataApp(),
      ),
    );
    await tester.pump();
    expect(find.text(BolKhataBrand.appName), findsWidgets);
  });
}
