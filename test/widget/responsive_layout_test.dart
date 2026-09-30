import 'package:bozor/core/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

/// Renders every major screen across phone/tablet sizes, dark mode and
/// large text. The test font's glyphs are wider than Inter, so passing here
/// leaves headroom for real devices. Any RenderFlex overflow is reported by the framework and fails the test.
void main() {
  const viewports = <String, (Size, double, ThemeMode)>{
    'iPhone SE 1st gen': (Size(320, 568), 1.0, ThemeMode.light),
    'small Android @130% text': (Size(360, 640), 1.3, ThemeMode.dark),
    'Pro Max @200% text': (Size(430, 932), 2.0, ThemeMode.light),
    'iPad landscape': (Size(1180, 820), 1.0, ThemeMode.dark),
  };

  const screens = [
    '/',
    '/search',
    '/search?q=iPhone',
    '/chats',
    '/profile',
    '/categories',
    '/listings?category=transport',
    '/listing/l_cobalt_2023',
    '/listing/l_apartment_3r',
    '/create',
    '/jobs',
    '/jobs?mode=hire',
    '/job/j_frontend',
    '/candidate/cv_jasur',
    '/services',
    '/services/category/plumber',
    '/provider/p_rustam',
    '/seller/u_bekzod',
    '/chat/c_cobalt',
    '/location',
    '/notifications',
    '/account/listings',
    '/account/saved',
    '/account/applications',
    '/account/settings',
    '/account/help',
    '/account/business',
    '/account/edit',
    '/verify-phone',
  ];

  // Russian strings are longer than Uzbek ones: check the tightest layouts in both languages.
  const languages = {'uz': null, 'ru': 'ru'};
  const russianViewports = {'iPhone SE 1st gen', 'Pro Max @200% text'};

  for (final MapEntry(key: name, value: (size, textScale, theme)) in viewports.entries) {
    for (final MapEntry(key: languageName, value: language) in languages.entries) {
      if (language != null && !russianViewports.contains(name)) continue;
      final label = language == null ? name : '$name [$languageName]';
      testWidgets('$label: onboarding lays out without overflow', (tester) async {
        addTearDown(() => currentLanguage = AppLanguage.uz);
        await pumpBozorApp(
          tester,
          onboarded: false,
          size: size,
          textScale: textScale,
          themeMode: theme,
          language: language,
        );
      });

      for (final location in screens) {
        testWidgets('$label: $location lays out without overflow', (tester) async {
          addTearDown(() => currentLanguage = AppLanguage.uz);
          await pumpBozorApp(
            tester,
            location: location,
            size: size,
            textScale: textScale,
            themeMode: theme,
            language: language,
          );
          expect(find.byType(ErrorWidget), findsNothing);
        });
      }
    }
  }
}
