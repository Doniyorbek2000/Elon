import 'package:bozor/core/config/feature_flags.dart';
import 'package:bozor/core/design/app_theme.dart';
import 'package:bozor/core/utils/clock.dart';
import 'package:bozor/core/utils/external_actions.dart';
import 'package:bozor/features/monetization/application/monetization_providers.dart';
import 'package:bozor/features/monetization/domain/monetization.dart';
import 'package:bozor/features/monetization/presentation/promote_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';
import '../unit/monetization_test.dart' show ScriptedRepository, price, purchaseJson;

class OfferRepository extends ScriptedRepository {
  OfferRepository(this.value);

  final PromotionOffer value;

  @override
  Future<PromotionOffer> offer(PromotionTarget target, String targetId, {required String platform}) async => value;
}

PromotionProduct product(String id, ProductKind kind, int soum, {int? days = 7, int? credits}) => PromotionProduct(
  id: id,
  kind: kind,
  target: PromotionTarget.listing,
  title: switch (kind) {
    ProductKind.listingBump => 'Ko‘tarish',
    ProductKind.listingVip => 'VIP',
    _ => 'TOP',
  },
  description: 'Server tavsifi',
  durationDays: days,
  creditCost: credits,
  price: Price.fromJson(price(soum)),
);

Future<(OfferRepository, RecordingExternalActions)> pumpSheet(
  WidgetTester tester, {
  required PromotionOffer offer,
  FeatureFlags flags = const FeatureFlags(monetization: true, listingTop: true, listingBump: true),
}) async {
  setDevice(tester, const Size(390, 844));
  final repository = OfferRepository(offer);
  final external = RecordingExternalActions();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        monetizationRepositoryProvider.overrideWithValue(repository),
        externalActionsProvider.overrideWithValue(external),
        featureFlagsProvider.overrideWithValue(flags),
        checkoutPlatformProvider.overrideWithValue('web'),
        clockProvider.overrideWithValue(() => testNow),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => showPromoteSheet(
                  context,
                  target: PromotionTarget.listing,
                  targetId: 'l1',
                  itemTitle: 'Cobalt 2023',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await settle(tester);
  return (repository, external);
}

void main() {
  testWidgets('shows server products and prices; bump cooldown disables bump', (tester) async {
    await pumpSheet(
      tester,
      offer: PromotionOffer(
        products: [
          product('listing_top_7d', ProductKind.listingTop, 25000),
          product('listing_bump', ProductKind.listingBump, 5000, days: null),
        ],
        eligible: true,
        methods: const [PaymentMethod.payme],
        creditBalance: 0,
        creditsEnabled: false,
        bumpAvailableAt: testNow.add(const Duration(hours: 5)),
      ),
    );
    expect(find.text('E’lonni tezroq soting'), findsOneWidget);
    expect(find.text('TOP · 7 kun'), findsOneWidget);
    expect(find.textContaining('25\u00A0000'), findsOneWidget);
    expect(find.textContaining('Keyingi ko‘tarish'), findsOneWidget);
    // Labeling and honesty copy.
    expect(find.textContaining('kafolatlanmaydi'), findsOneWidget);
    // Nothing selected yet → no pay button.
    expect(find.textContaining('Davom etish'), findsNothing);
    await tester.tap(find.text('TOP · 7 kun'));
    await settle(tester);
    expect(find.textContaining('Davom etish'), findsOneWidget);
  });

  testWidgets('no payment route on this device: explains, never links out', (tester) async {
    final (_, external) = await pumpSheet(
      tester,
      offer: PromotionOffer(
        products: [product('listing_top_7d', ProductKind.listingTop, 25000)],
        eligible: true,
        methods: const [],
        creditBalance: 0,
        creditsEnabled: false,
      ),
    );
    await tester.tap(find.text('TOP · 7 kun'));
    await settle(tester);
    expect(find.textContaining('ushbu qurilmada sotib olib bo‘lmaydi'), findsOneWidget);
    expect(find.textContaining('Davom etish'), findsNothing);
    expect(external.urls, isEmpty);
  });

  testWidgets('credits checkout ends on "TOP faollashtirildi" with the real expiry date', (tester) async {
    final (repository, external) = await pumpSheet(
      tester,
      offer: PromotionOffer(
        products: [product('listing_top_7d', ProductKind.listingTop, 25000, credits: 1)],
        eligible: true,
        methods: const [],
        creditBalance: 3,
        creditsEnabled: true,
      ),
    );
    repository.onCheckout = (request) {
      expect(request.method, PaymentMethod.credits);
      final json = purchaseJson(
        status: 'fulfilled',
        action: {'type': 'none'},
        activation: {'id': 'a1', 'startsAt': '2026-09-26T09:00:00Z', 'expiresAt': '2026-10-03T09:00:00Z'},
      )..['creditsUsed'] = 1;
      return Purchase.fromJson(json);
    };
    await tester.tap(find.text('TOP · 7 kun'));
    await settle(tester);
    await tester.tap(find.textContaining('Davom etish · 1 kredit'));
    await settle(tester);
    expect(find.text('TOP faollashtirildi'), findsOneWidget);
    expect(find.textContaining('3 oktabr gacha'), findsOneWidget);
    expect(find.textContaining('1 ta kredit ishlatildi'), findsOneWidget);
    expect(external.urls, isEmpty);
    await tester.tap(find.text('Tayyor'));
    await settle(tester);
    // Sheet closes with the activation.
    expect(find.text('E’lonni tezroq soting'), findsNothing);
  });

  testWidgets('inactive listing cannot be promoted', (tester) async {
    await pumpSheet(
      tester,
      offer: const PromotionOffer(products: [], eligible: false, methods: [], creditBalance: 0, creditsEnabled: false),
    );
    expect(find.textContaining('Faqat faol e’lonlarni'), findsOneWidget);
  });

  testWidgets('demo build sells nothing: free plan, no invented prices or plans', (tester) async {
    await pumpBozorApp(tester, location: '/account/plans');
    expect(find.text('To‘lovlar va tariflar'), findsOneWidget);
    expect(find.text('Bepul tarif'), findsOneWidget);
    expect(find.textContaining('so‘m'), findsNothing);
    expect(find.text('Biznes uchun tariflar'), findsNothing);
  });

  testWidgets('demo build shows no paid blocks on home', (tester) async {
    await pumpBozorApp(tester);
    expect(find.text('Reklama'), findsNothing);
    expect(find.text('Tavsiya etilgan'), findsNothing);
  });
}
