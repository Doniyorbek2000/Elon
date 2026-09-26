import 'package:bozor/core/storage/key_value_store.dart';
import 'package:bozor/core/widgets/favorite_button.dart';
import 'package:bozor/features/chat/presentation/conversation_screen.dart';
import 'package:bozor/features/create_listing/presentation/create_listing_screen.dart';
import 'package:bozor/features/create_listing/presentation/steps/details_step.dart';
import 'package:bozor/features/home/presentation/home_screen.dart';
import 'package:bozor/features/listings/presentation/listing_detail_screen.dart';
import 'package:bozor/features/listings/presentation/widgets/listing_cards.dart';
import 'package:bozor/features/location/application/location_controller.dart';
import 'package:bozor/features/saved/application/saved_items_controller.dart';
import 'package:bozor/features/search/presentation/search_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

/// Scrolls the nearest scrollable containing [anchor] until [target] is built.
Future<void> scrollTo(WidgetTester tester, Finder target, {Finder? anchor, double delta = 150}) async {
  final scrollable = anchor == null
      ? find.byType(Scrollable).first
      : find.ancestor(of: anchor, matching: find.byType(Scrollable)).first;
  await tester.scrollUntilVisible(target, delta, scrollable: scrollable);
  await settle(tester);
}

Future<void> tapText(WidgetTester tester, String text, {int index = 0}) async {
  final finder = find.text(text).at(index);
  await tester.ensureVisible(finder);
  await settle(tester);
  await tester.tap(finder);
  await settle(tester);
}

void main() {
  group('Navigation', () {
    testWidgets('first launch shows onboarding, then location, then home', (tester) async {
      final harness = await pumpBozorApp(tester, onboarded: false);
      expect(find.text('Hududingizdagi hamma narsa\nbitta ilovada'), findsOneWidget);
      expect(find.text('E’lonlar'), findsOneWidget);

      await tapText(tester, 'Boshlash');
      expect(find.text('Hududingizni tanlang'), findsOneWidget);
      expect(harness.store.getBool(StoreKeys.onboardingCompleted), isTrue);

      await tapText(tester, 'O‘tkazib yuborish');
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('deep link opens content even on first launch', (tester) async {
      await pumpBozorApp(tester, onboarded: false, location: '/listing/l_cobalt_2023');
      expect(find.byType(ListingDetailScreen), findsOneWidget);
      expect(find.text('Cobalt 2023'), findsWidgets);
    });

    testWidgets('bottom navigation switches tabs and preserves tab state', (tester) async {
      await pumpBozorApp(tester);
      await tester.tap(find.bySemanticsLabel('Qidiruv'));
      await settle(tester);
      expect(find.byType(SearchScreen), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'santexnik');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await settle(tester);
      expect(find.text('Xizmatlar'), findsWidgets);

      await tester.tap(find.bySemanticsLabel('Bosh sahifa'));
      await settle(tester);
      expect(find.byType(HomeScreen), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Qidiruv'));
      await settle(tester);
      expect(find.widgetWithText(TextField, 'santexnik'), findsOneWidget, reason: 'search tab keeps its state');
    });

    testWidgets('center + opens the create flow', (tester) async {
      await pumpBozorApp(tester);
      await tester.tap(find.bySemanticsLabel('E’lon joylash'));
      await settle(tester);
      expect(find.byType(CreateListingScreen), findsOneWidget);
      expect(find.text('Ma’lumot'), findsOneWidget);
    });

    testWidgets('unknown links show a friendly not-found page', (tester) async {
      await pumpBozorApp(tester, location: '/nope/123');
      expect(find.text('Sahifa topilmadi'), findsOneWidget);
    });
  });

  group('Home & listings', () {
    testWidgets('home shows header, verticals, categories and nearby listings', (tester) async {
      await pumpBozorApp(tester);
      expect(find.text('Chust, Namangan'), findsOneWidget);
      expect(find.text('Bozor'), findsOneWidget);
      expect(find.text('Ish'), findsWidgets);
      expect(find.text('Xizmatlar'), findsWidgets);
      expect(find.text('Avtomobil'), findsOneWidget);
      expect(find.text('Yaqin atrofdagi e’lonlar'), findsOneWidget);
      expect(find.byType(ListingCard), findsWidgets);
    });

    testWidgets('tapping a listing opens detail with seller and contact actions', (tester) async {
      final harness = await pumpBozorApp(tester);
      await tester.tap(find.byType(ListingCard).first);
      await settle(tester);
      expect(find.byType(ListingDetailScreen), findsOneWidget);
      expect(find.text('Sotuvchi'), findsOneWidget);

      await tester.tap(find.text('Qo‘ng‘iroq'));
      await settle(tester);
      await tester.tap(find.text('Qo‘ng‘iroq qilish'));
      await settle(tester);
      expect(harness.external.calls, hasLength(1));
    });

    testWidgets('favorite toggles from the card and is persisted', (tester) async {
      final harness = await pumpBozorApp(tester);
      final firstFavorite = find.byType(FavoriteButton).first;
      await tester.ensureVisible(firstFavorite);
      await settle(tester);
      await tester.tap(firstFavorite);
      await settle(tester);
      expect(harness.container.read(savedItemsProvider), hasLength(1));
      expect(harness.store.getStringList(StoreKeys.savedItems), hasLength(1));
      expect(find.bySemanticsLabel('Saqlanganlardan olib tashlash'), findsWidgets);
    });

    testWidgets('filter sheet applies sorting', (tester) async {
      await pumpBozorApp(tester, location: '/listings?category=transport');
      expect(find.text('Avtomobil'), findsOneWidget);
      expect(find.text('Yengil avtomobillar'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Filtrlar'));
      await settle(tester);
      await tester.tap(find.text('Narxi arzon'));
      await tester.tap(find.text('Natijalarni ko‘rsatish'));
      await settle(tester);

      final titles = tester.widgetList<ListingTile>(find.byType(ListingTile)).map((t) => t.listing.title).toList();
      expect(titles.first, 'Damas 2021', reason: 'cheapest car first');
      expect(find.text('Narxi arzon'), findsOneWidget, reason: 'sort chip reflects selection');
    });

    testWidgets('share sheet sends a deep link to Telegram', (tester) async {
      final harness = await pumpBozorApp(tester, location: '/listing/l_cobalt_2023');
      await tester.tap(find.byTooltip('Ulashish'));
      await settle(tester);
      expect(find.text('bozor.uz'), findsOneWidget);
      await tester.tap(find.text('Telegram’da ulashish'));
      await settle(tester);
      expect(harness.share.shared.single.url.toString(), 'https://bozor.uz/listing/l_cobalt_2023');
    });
  });

  group('Location', () {
    testWidgets('selecting a district updates the home header', (tester) async {
      final harness = await pumpBozorApp(tester);
      await tester.tap(find.text('Chust, Namangan'));
      await settle(tester);
      expect(find.text('Manzil tanlash'), findsOneWidget);
      await tapText(tester, 'Pop tumani');
      await tapText(tester, 'Butun Pop tumani');
      expect(harness.container.read(locationProvider).districtId, 'pop');
      expect(find.text('Pop, Namangan'), findsOneWidget);
    });

    testWidgets('search finds districts by name', (tester) async {
      await pumpBozorApp(tester, location: '/location');
      await tester.enterText(find.byType(TextField), 'chilon');
      await settle(tester);
      expect(find.text('Chilonzor tumani'), findsOneWidget);
    });
  });

  group('Create listing', () {
    testWidgets('validates, walks all steps and publishes', (tester) async {
      await pumpBozorApp(tester, location: '/create');

      await tapText(tester, 'Davom etish');
      expect(find.text('Kategoriyani tanlang'), findsWidgets);

      await tapText(tester, 'Kategoriyani tanlang');
      await tapText(tester, 'Elektronika');
      await tapText(tester, 'Telefonlar');
      expect(find.text('Elektronika › Telefonlar'), findsOneWidget);

      final fields = find.descendant(of: find.byType(DetailsStep), matching: find.byType(TextField));
      await tester.enterText(fields.at(0), 'iPhone 13');
      await tester.enterText(fields.at(1), '5200000');
      await settle(tester);
      expect(find.text('5 200 000'), findsOneWidget, reason: 'price is grouped while typing');
      await tapText(tester, 'Apple');
      final description = find.byWidgetPredicate((w) => w is TextField && w.maxLength == 3000);
      await scrollTo(tester, description, anchor: fields.at(0));
      await tester.enterText(description, 'Ideal holatda, qutisi bilan.');
      await settle(tester);

      await tapText(tester, 'Davom etish');
      expect(find.text('Rasm qo‘shish'), findsOneWidget);

      await tapText(tester, 'Davom etish');
      expect(find.text('Kamida bitta rasm qo‘shing'), findsWidgets);

      await tapText(tester, 'Rasm qo‘shish');
      await tapText(tester, 'Galereyadan tanlash');
      expect(find.text('Muqova'), findsOneWidget);

      await tapText(tester, 'Davom etish');
      expect(find.text('Xaridorlar e’loningizni shunday ko‘radi'), findsOneWidget);

      await tapText(tester, 'E’lonni joylash');
      expect(find.text('E’loningiz joylandi!'), findsOneWidget);
      expect(find.text('Telegram’da ulashish'), findsOneWidget);
    });

    testWidgets('closing with content offers to keep the draft', (tester) async {
      final harness = await pumpBozorApp(tester, location: '/create');
      await tester.enterText(find.byType(TextField).first, 'Divan');
      await settle(tester);
      await tester.tap(find.byTooltip('Yopish'));
      await settle(tester);
      await tapText(tester, 'Saqlash va chiqish');
      expect(harness.store.getJson(StoreKeys.listingDraft)?['title'], 'Divan');
    });
  });

  group('Jobs', () {
    testWidgets('browse vacancies, switch intent, apply to a job', (tester) async {
      await pumpBozorApp(tester, location: '/jobs');
      expect(find.text('Oshpaz kerak'), findsOneWidget);

      await scrollTo(tester, find.text('Masofaviy'), anchor: find.text('To‘liq stavka'));
      await tapText(tester, 'Masofaviy');
      expect(find.text('Dasturchi (Frontend)'), findsOneWidget);
      expect(find.text('Oshpaz kerak'), findsNothing);

      await tapText(tester, 'Ishchi qidiraman');
      expect(find.text('Vakansiya joylash'), findsOneWidget);
      await scrollTo(tester, find.text('Barchasi'), anchor: find.text('Masofaviy'), delta: -150);
      await tapText(tester, 'Barchasi');
      expect(find.text('Haydovchi (B, C toifa)'), findsOneWidget);

      await tapText(tester, 'Ish qidiraman');
      await tapText(tester, 'Haydovchi kerak');
      expect(find.text('Talablar'), findsOneWidget);
      await tapText(tester, 'Ariza topshirish');
      await tester.tap(find.text('Yuborish'));
      await settle(tester);
      expect(find.textContaining('Ariza: Yuborildi'), findsOneWidget);
    });
  });

  group('Services', () {
    testWidgets('category → provider profile with portfolio and reviews', (tester) async {
      await pumpBozorApp(tester, location: '/services');
      expect(find.text('Tavsiya etilgan ustalar'), findsOneWidget);
      await tapText(tester, 'Santexnik');
      expect(find.text('Rustam usta'), findsOneWidget);
      await tapText(tester, 'Rustam usta');
      expect(find.text('Xizmat haqida'), findsOneWidget);
      expect(find.text('Sharhlar'), findsOneWidget);
      expect(find.text('Chat'), findsOneWidget);
    });
  });

  group('Chat', () {
    testWidgets('conversation shows listing context and sends messages', (tester) async {
      await pumpBozorApp(tester, location: '/chat/c_cobalt');
      expect(find.byType(ConversationScreen), findsOneWidget);
      expect(find.text('120 000 000 so‘m'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Ertaga kelaman');
      await settle(tester);
      await tester.tap(find.byTooltip('Yuborish'));
      await settle(tester);
      expect(find.text('Ertaga kelaman'), findsOneWidget);
    });

    testWidgets('prepayment requests trigger a safety warning', (tester) async {
      await pumpBozorApp(tester, location: '/chat/c_cobalt');
      await tester.enterText(find.byType(TextField), 'Oldindan to‘lov qilsam bo‘ladimi?');
      await settle(tester);
      await tester.tap(find.byTooltip('Yuborish'));
      await settle(tester);
      expect(find.text('Ehtiyot bo‘ling'), findsOneWidget);
    });
  });

  group('Profile & trust', () {
    testWidgets('sign out then protected actions require phone verification', (tester) async {
      await pumpBozorApp(tester, location: '/profile');
      await tapText(tester, 'Chiqish');
      await tester.tap(find.text('Chiqish').last);
      await settle(tester);
      expect(find.text('Kirish'), findsWidgets);

      await tester.tap(find.bySemanticsLabel('E’lon joylash'));
      await settle(tester);
      expect(find.text('Telefon raqamingiz'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '901234567');
      await tapText(tester, 'Kod olish');
      await tester.enterText(find.byType(TextField), '123456');
      await settle(tester);
      expect(find.byType(CreateListingScreen), findsOneWidget, reason: 'continues to the original destination');
    });

    testWidgets('report sheet submits a reason', (tester) async {
      await pumpBozorApp(tester, location: '/listing/l_cobalt_2023');
      await tapText(tester, 'E’lon ustidan shikoyat qilish');
      await tester.tap(find.text('Firibgarlik yoki aldov'));
      await settle(tester);
      await tester.tap(find.text('Yuborish'));
      await settle(tester);
      expect(find.textContaining('moderatorlarga yuborildi'), findsOneWidget);
    });
  });
}
