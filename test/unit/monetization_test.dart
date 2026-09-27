import 'dart:convert';

import 'package:bozor/core/config/feature_flags.dart';
import 'package:bozor/core/domain/paged.dart';
import 'package:bozor/core/domain/promotion.dart';
import 'package:bozor/core/errors/app_failure.dart';
import 'package:bozor/core/utils/external_actions.dart';
import 'package:bozor/features/monetization/application/monetization_providers.dart';
import 'package:bozor/features/monetization/data/monetization_repository.dart';
import 'package:bozor/features/monetization/domain/monetization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';
import '../helpers/test_app.dart';

Map<String, Object?> price(int soum) => {'amountMinor': '${soum * 100}', 'amount': soum, 'currency': 'uzs'};

Map<String, Object?> purchaseJson({
  String id = 'p1',
  String status = 'awaitingPayment',
  Map<String, Object?>? action,
  Map<String, Object?>? activation,
}) => {
  'id': id,
  'kind': 'promotion',
  'status': status,
  'title': 'TOP',
  'productId': 'listing_top_7d',
  'planId': null,
  'target': 'listing',
  'targetId': 'l1',
  'list': price(25000),
  'discount': price(0),
  'total': price(25000),
  'creditsUsed': 0,
  'paymentStatus': 'pending',
  'provider': 'payme',
  'createdAt': '2026-09-26T10:00:00.000Z',
  'fulfilledAt': null,
  'payments': <Object>[],
  'activation': activation,
  'subscription': null,
  'action': ?action,
};

class ScriptedRepository implements MonetizationRepository {
  final List<CheckoutRequest> checkouts = [];
  final List<String> cancelled = [];
  Object? checkoutError;
  Purchase Function(CheckoutRequest request)? onCheckout;
  final List<Purchase> statuses = [];

  @override
  Future<Purchase> checkout(CheckoutRequest request) async {
    checkouts.add(request);
    if (checkoutError case final error?) {
      checkoutError = null;
      throw error;
    }
    return onCheckout!(request);
  }

  @override
  Future<Purchase> purchase(String id) async => statuses.length > 1 ? statuses.removeAt(0) : statuses.first;

  @override
  Future<Purchase> cancelPurchase(String id) async {
    cancelled.add(id);
    return Purchase.fromJson(purchaseJson(id: id, status: 'cancelled'));
  }

  @override
  Future<PromotionOffer> offer(PromotionTarget target, String targetId, {required String platform}) =>
      throw UnimplementedError();

  @override
  Future<List<Plan>> plans() async => const [];

  @override
  Future<MyEntitlements> entitlements() => throw UnimplementedError();

  @override
  Future<Quote> quote(CheckoutRequest request) => throw UnimplementedError();

  @override
  Future<PageResult<Purchase>> purchases({String? cursor}) async => const PageResult(items: [], nextCursor: null);

  @override
  Future<List<Subscription>> subscriptions() async => const [];

  @override
  Future<Subscription> cancelSubscription(String id) => throw UnimplementedError();

  @override
  Future<({int balance, List<CreditEntry> entries})> credits() async => (balance: 0, entries: const <CreditEntry>[]);
}

void main() {
  group('Server-driven models', () {
    test('money is exact minor units from the server, never computed', () {
      final p = Price.fromJson(price(25000));
      expect(p.amountMinor, '2500000');
      expect(p.money.amount, 25000);
      expect(Price.fromJson(price(0)).isZero, isTrue);
    });

    test('badges come from the server and include "Shoshilinch"', () {
      final promotion = Promotion.fromJson({
        'promotion': 'top',
        'badges': ['top', 'urgent', 'somethingNew'],
      })!;
      expect(promotion.type, PromotionType.top);
      expect(promotion.all.map((b) => b.badge), ['TOP', 'Shoshilinch']);
      expect(Promotion.fromJson({'promotion': null, 'badges': <Object>[]}), isNull);
    });

    test('flags default to off and unknown keys are ignored', () {
      const off = FeatureFlags();
      expect(off.canPromoteListings || off.canBuyPlans || off.canAdvertise, isFalse);
      final flags = FeatureFlags.fromJson({'monetization': true, 'listingTop': true, 'surprise': true});
      expect(flags.canPromoteListings, isTrue);
      expect(flags.canBuyPlans, isFalse);
      // Product flags without the master switch sell nothing.
      expect(FeatureFlags.fromJson({'listingTop': true, 'premiumJobs': true}).canPromoteListings, isFalse);
    });

    test('purchase exposes the checkout action and activation dates', () {
      final purchase = Purchase.fromJson(
        purchaseJson(
          action: {'type': 'redirect', 'url': 'https://pay.example/checkout/1'},
          activation: {'id': 'a1', 'startsAt': '2026-09-26T10:00:00Z', 'expiresAt': '2026-10-03T10:00:00Z'},
        ),
      );
      expect(purchase.action, isA<RedirectAction>());
      expect((purchase.action! as RedirectAction).url.host, 'pay.example');
      expect(purchase.activationExpiresAt!.difference(purchase.activationStartsAt!).inDays, 7);
    });

    test('checkout body carries no price, amount, status or user id', () {
      const request = CheckoutRequest(
        method: PaymentMethod.payme,
        platform: 'web',
        idempotencyKey: 'abcdefgh12345678',
        productId: 'listing_top_7d',
        targetId: 'l1',
        couponCode: '  ',
      );
      expect(
        request.toJson().keys,
        unorderedEquals(['productId', 'targetId', 'provider', 'platform', 'idempotencyKey']),
      );
      expect(request.toQuoteJson().containsKey('idempotencyKey'), isFalse);
    });

    test('idempotency keys match the server format and differ per attempt', () {
      final a = newIdempotencyKey();
      final b = newIdempotencyKey();
      expect(RegExp(r'^[A-Za-z0-9_-]{8,64}$').hasMatch(a), isTrue);
      expect(a, isNot(b));
    });

    test('platform routing: iOS/Android never get web payment routes by accident', () {
      expect(checkoutPlatform(TargetPlatform.iOS), kIsWeb ? 'web' : 'ios');
      expect(checkoutPlatform(TargetPlatform.android), kIsWeb ? 'web' : 'android');
      expect(checkoutPlatform(TargetPlatform.linux), 'web');
    });
  });

  group('API contract', () {
    test('plan limit, disabled feature and missing provider map to typed failures', () async {
      final c = buildClient();
      c.backend
        ..on('POST', '/listings', (_) => (403, error('LIMIT_REACHED', {'limit': 'activeListings', 'max': 50})))
        ..on('POST', '/businesses', (_) => (403, error('FEATURE_DISABLED')))
        ..on('POST', '/checkout', (_) => (503, error('PROVIDER_NOT_CONFIGURED')));
      await expectLater(
        c.api.post<Object?>('/listings'),
        throwsA(
          isA<LimitReachedFailure>()
              .having((f) => f.limit, 'limit', 'activeListings')
              .having((f) => f.max, 'max', 50)
              .having((f) => f.message, 'message', contains('50 ta')),
        ),
      );
      await expectLater(c.api.post<Object?>('/businesses'), throwsA(isA<FeatureDisabledFailure>()));
      await expectLater(c.api.post<Object?>('/checkout'), throwsA(isA<PaymentUnavailableFailure>()));
    });

    test('repository sends only identifiers and reads the server price', () async {
      final c = buildClient();
      Object? sent;
      c.backend
        ..on('GET', '/catalog/promotions', (options) {
          expect(options.queryParameters, {'target': 'listing', 'targetId': 'l1', 'platform': 'web'});
          return (
            200,
            {
              'data': {
                'products': [
                  {
                    'id': 'listing_top_7d',
                    'kind': 'listingTop',
                    'target': 'listing',
                    'placement': 'none',
                    'durationDays': 7,
                    'title': 'TOP',
                    'description': 'Ko‘proq odamlarga',
                    'creditCost': 1,
                    'price': price(25000),
                  },
                ],
                'eligibility': {'eligible': true, 'bumpAvailableAt': '2026-09-27T10:00:00Z'},
                'providers': ['payme', 'click', 'unknownPay'],
                'credits': {'balance': 2, 'enabled': true},
              },
            },
          );
        })
        ..on('POST', '/checkout', (options) {
          sent = options.data;
          return (
            201,
            {
              'data': purchaseJson(action: {'type': 'redirect', 'url': 'https://pay.example/x'}),
            },
          );
        });
      final repository = RemoteMonetizationRepository(c.api);
      final offer = await repository.offer(PromotionTarget.listing, 'l1', platform: 'web');
      expect(offer.products.single.price.money.amount, 25000);
      expect(offer.products.single.placement, isNull);
      expect(offer.methods, [PaymentMethod.payme, PaymentMethod.click]);
      expect(offer.bumpAvailableAt, isNotNull);

      await repository.checkout(
        const CheckoutRequest(
          method: PaymentMethod.payme,
          platform: 'web',
          idempotencyKey: 'key_12345678',
          productId: 'listing_top_7d',
          targetId: 'l1',
        ),
      );
      final body = sent is String ? jsonDecode(sent! as String) as Map<String, dynamic> : sent! as Map<String, dynamic>;
      expect(body, {
        'productId': 'listing_top_7d',
        'targetId': 'l1',
        'provider': 'payme',
        'platform': 'web',
        'idempotencyKey': 'key_12345678',
      });
    });
  });

  group('Checkout controller', () {
    late ScriptedRepository repository;
    late RecordingExternalActions external;
    late ProviderContainer container;
    late ProviderSubscription<CheckoutState> sub;

    setUp(() {
      repository = ScriptedRepository();
      external = RecordingExternalActions();
      container = ProviderContainer(
        overrides: [
          monetizationRepositoryProvider.overrideWithValue(repository),
          externalActionsProvider.overrideWithValue(external),
          checkoutPlatformProvider.overrideWithValue('web'),
          checkoutTimingProvider.overrideWithValue(
            const CheckoutTiming(pollInterval: Duration(milliseconds: 10), pollTimeout: Duration(seconds: 5)),
          ),
        ],
      );
      sub = container.listen(checkoutControllerProvider, (_, _) {});
      addTearDown(container.dispose);
    });

    CheckoutController controller() => container.read(checkoutControllerProvider.notifier);

    Future<void> waitFor(CheckoutPhase phase) async {
      for (var i = 0; i < 200 && sub.read().phase != phase; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(sub.read().phase, phase);
    }

    test('redirect → provider page → activation only after the server confirms', () async {
      repository
        ..onCheckout = ((_) =>
            Purchase.fromJson(purchaseJson(action: {'type': 'redirect', 'url': 'https://pay.example/1'})))
        ..statuses.addAll([Purchase.fromJson(purchaseJson()), Purchase.fromJson(purchaseJson(status: 'fulfilled'))]);
      await controller().start(
        controller().request(method: PaymentMethod.payme, productId: 'listing_top_7d', targetId: 'l1'),
      );
      expect(external.urls.single.toString(), 'https://pay.example/1');
      // Returning to the app does not mean "paid".
      expect(sub.read().phase, CheckoutPhase.awaitingPayment);
      await waitFor(CheckoutPhase.succeeded);
    });

    test('provider failure is shown as failed; nothing is activated', () async {
      repository
        ..onCheckout = ((_) =>
            Purchase.fromJson(purchaseJson(action: {'type': 'redirect', 'url': 'https://pay.example/2'})))
        ..statuses.add(Purchase.fromJson(purchaseJson(status: 'failed')));
      await controller().start(
        controller().request(method: PaymentMethod.payme, productId: 'listing_top_7d', targetId: 'l1'),
      );
      await waitFor(CheckoutPhase.failed);
    });

    test('a retry after a network error reuses the idempotency key (no double charge)', () async {
      repository
        ..checkoutError = const NetworkFailure()
        ..onCheckout = (_) => Purchase.fromJson(purchaseJson(status: 'fulfilled', action: {'type': 'none'}));
      final first = controller().request(method: PaymentMethod.payme, productId: 'listing_top_7d', targetId: 'l1');
      await controller().start(first);
      expect(sub.read().phase, CheckoutPhase.failed);
      await controller().start(
        controller().request(method: PaymentMethod.payme, productId: 'listing_top_7d', targetId: 'l1'),
      );
      expect(repository.checkouts.map((r) => r.idempotencyKey).toSet(), {first.idempotencyKey});
      expect(sub.read().phase, CheckoutPhase.succeeded);
    });

    test('credits settle server-side with no provider page', () async {
      repository.onCheckout = (_) => Purchase.fromJson(purchaseJson(status: 'fulfilled', action: {'type': 'none'}));
      await controller().start(
        controller().request(method: PaymentMethod.credits, productId: 'listing_top_7d', targetId: 'l1'),
      );
      expect(external.urls, isEmpty);
      expect(sub.read().phase, CheckoutPhase.succeeded);
    });

    test('store route without configured store billing is withdrawn, never linked out', () async {
      repository.onCheckout = (_) =>
          Purchase.fromJson(purchaseJson(action: {'type': 'store', 'store': 'apple', 'storeProductId': 'top7'}));
      await controller().start(
        controller().request(method: PaymentMethod.apple, productId: 'listing_top_7d', targetId: 'l1'),
      );
      expect(sub.read().phase, CheckoutPhase.unavailable);
      expect(external.urls, isEmpty);
      expect(repository.cancelled, ['p1']);
    });

    test('unavailable payment method is reported as unavailable', () async {
      repository.checkoutError = const PaymentUnavailableFailure();
      await controller().start(
        controller().request(method: PaymentMethod.payme, productId: 'listing_top_7d', targetId: 'l1'),
      );
      expect(sub.read().phase, CheckoutPhase.unavailable);
    });

    test('user cancel asks the server and shows its result', () async {
      repository
        ..onCheckout = ((_) =>
            Purchase.fromJson(purchaseJson(action: {'type': 'redirect', 'url': 'https://pay.example/3'})))
        ..statuses.add(Purchase.fromJson(purchaseJson()));
      await controller().start(
        controller().request(method: PaymentMethod.payme, productId: 'listing_top_7d', targetId: 'l1'),
      );
      await controller().cancel();
      expect(repository.cancelled, ['p1']);
      expect(sub.read().phase, CheckoutPhase.cancelled);
    });
  });
}
