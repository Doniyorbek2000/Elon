// End-to-end smoke test of the real app entry point on a device or emulator
// (real plugins: secure storage, preferences, routing). Runs on demo data:
//
//   flutter test integration_test --device-id <emulator>
//   flutter drive --driver=test_driver/integration_test.dart --target=integration_test/app_test.dart
import 'dart:async';

import 'package:bozor/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> settle(WidgetTester tester, {int seconds = 6}) async {
  for (var i = 0; i < seconds * 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> tapText(WidgetTester tester, String text, {int index = 0}) async {
  final finder = find.text(text).at(index);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await settle(tester, seconds: 2);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // A clean install every time: onboarding shows, nothing is saved.
    SharedPreferences.setMockInitialValues({});
    await (await SharedPreferences.getInstance()).clear();
  });

  testWidgets('first launch → browse → search → open a listing → save it', (tester) async {
    unawaited(app.main());
    await settle(tester);

    // Onboarding and region choice.
    expect(find.text('Boshlash'), findsOneWidget);
    await tapText(tester, 'Boshlash');
    await tapText(tester, 'O‘tkazib yuborish');

    // Home shows the verticals and nearby listings.
    expect(find.text('E’lonlar'), findsWidgets);
    expect(find.text('Yaqin atrofdagi e’lonlar'), findsOneWidget);

    // Search finds a listing.
    await tapText(tester, 'Qidiruv');
    await tester.enterText(find.byType(TextField).first, 'iPhone');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await settle(tester, seconds: 3);
    expect(find.textContaining('iPhone'), findsWidgets);

    // Open it, save it from the detail page.
    await tester.tap(find.textContaining('iPhone').first);
    await settle(tester, seconds: 3);
    expect(find.text('Chat'), findsWidgets);
    final favorite = find.byTooltip('Saqlash');
    if (favorite.evaluate().isNotEmpty) {
      await tester.tap(favorite.first);
      await settle(tester, seconds: 1);
    }
  });

  testWidgets('the tab bar reaches every section without errors', (tester) async {
    unawaited(app.main());
    await settle(tester);
    if (find.text('Boshlash').evaluate().isNotEmpty) {
      await tapText(tester, 'Boshlash');
      await tapText(tester, 'O‘tkazib yuborish');
    }
    for (final tab in ['Qidiruv', 'Chat', 'Profil', 'Bosh sahifa']) {
      await tapText(tester, tab);
      expect(tester.takeException(), isNull, reason: 'opening $tab');
    }
  });
}
