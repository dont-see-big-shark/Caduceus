import 'package:caduceus/l10n/app_localizations.dart';
import 'package:caduceus/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    localeNotifier.value = null;
  });

  testWidgets('i18n supports switching locales to zh, en, ja, zh_TW, es', (
    tester,
  ) async {
    await tester.pumpWidget(
      ValueListenableBuilder<Locale?>(
        valueListenable: localeNotifier,
        builder: (context, currentLocale, _) => MaterialApp(
          locale: currentLocale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              final l10n = AppLocalizations.of(context)!;
              return Scaffold(
                body: Column(
                  children: [
                    Text(l10n.settings, key: const Key('settings_text')),
                    Text(l10n.appearance, key: const Key('appearance_text')),
                    Text(l10n.language, key: const Key('language_text')),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Default (en fallback in test without locale)
    expect(find.text('Settings'), findsOneWidget);

    // Switch to Simplified Chinese
    await setLocale(const Locale('zh'));
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('外观'), findsOneWidget);
    expect(find.text('语言'), findsOneWidget);

    // Switch to Traditional Chinese
    await setLocale(
      const Locale.fromSubtags(
        languageCode: 'zh',
        scriptCode: 'Hant',
        countryCode: 'TW',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('設定'), findsOneWidget);
    expect(find.text('外觀'), findsOneWidget);
    expect(find.text('語言'), findsOneWidget);

    // Switch to Japanese
    await setLocale(const Locale('ja'));
    await tester.pumpAndSettle();
    expect(find.text('設定'), findsOneWidget);
    expect(find.text('外観'), findsOneWidget);
    expect(find.text('言語'), findsOneWidget);

    // Switch to Spanish
    await setLocale(const Locale('es'));
    await tester.pumpAndSettle();
    expect(find.text('Configuración'), findsOneWidget);
    expect(find.text('Apariencia'), findsOneWidget);
    expect(find.text('Idioma'), findsOneWidget);

    // Switch to English
    await setLocale(const Locale('en'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Language'), findsOneWidget);
  });
}
