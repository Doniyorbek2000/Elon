// Renders every major screen to PNG for visual review.
//
//   flutter test tool/screenshots/screens_test.dart --update-goldens
//
// Output: tool/screenshots/out/<device>/<screen>.png. Any layout overflow
// fails the run, so this doubles as a multi-viewport layout check.
import 'package:bozor/core/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/helpers/fonts.dart';
import '../../test/helpers/test_app.dart';

class Device {
  const Device(this.name, this.size, {this.textScale = 1, this.theme = ThemeMode.light, this.language});

  final String name;
  final Size size;
  final double textScale;
  final ThemeMode theme;
  final String? language;
}

const devices = [
  Device('iphone15', Size(393, 852)),
  Device('iphone15_dark', Size(393, 852), theme: ThemeMode.dark),
  Device('iphone_se', Size(320, 568)),
  Device('android_small_text130', Size(360, 640), textScale: 1.3),
  Device('pro_max_text200', Size(430, 932), textScale: 2),
  Device('ipad', Size(820, 1180)),
  Device('iphone15_ru', Size(393, 852), language: 'ru'),
  Device('iphone_se_ru', Size(320, 568), language: 'ru'),
];

const screens = <String, String>{
  'home': '/',
  'categories': '/categories',
  'listings_cars': '/listings?category=transport',
  'listing_detail': '/listing/l_cobalt_2023',
  'create_listing': '/create',
  'jobs': '/jobs',
  'job_detail': '/job/j_oshpaz',
  'services': '/services',
  'provider': '/provider/p_rustam',
  'search_results': '/search?q=iPhone%2014',
  'chats': '/chats',
  'conversation': '/chat/c_cobalt',
  'profile': '/profile',
  'location': '/location',
  'seller': '/seller/u_azizbek',
  'notifications': '/notifications',
};

void main() {
  setUpAll(loadAppFonts);
  tearDown(() => currentLanguage = AppLanguage.uz);

  for (final device in devices) {
    group(device.name, () {
      testWidgets('onboarding', (tester) async {
        await pumpBozorApp(
          tester,
          onboarded: false,
          size: device.size,
          textScale: device.textScale,
          themeMode: device.theme,
          language: device.language,
        );
        await settle(tester, frames: 60);
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/${device.name}/00_onboarding.png'));
      });

      var index = 1;
      for (final entry in screens.entries) {
        final number = (index++).toString().padLeft(2, '0');
        testWidgets(entry.key, (tester) async {
          await pumpBozorApp(
            tester,
            location: entry.value,
            size: device.size,
            textScale: device.textScale,
            themeMode: device.theme,
            language: device.language,
          );
          await settle(tester, frames: 60);
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('out/${device.name}/${number}_${entry.key}.png'),
          );
        });
      }
    });
  }
}
