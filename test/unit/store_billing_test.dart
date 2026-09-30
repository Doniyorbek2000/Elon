import 'dart:async';

import 'package:bozor/core/errors/app_failure.dart';
import 'package:bozor/features/monetization/data/store_billing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

class FakeStorePlatform implements StorePlatform {
  final controller = StreamController<List<PurchaseDetails>>.broadcast();
  ProductDetails? known = ProductDetails(
    id: 'uz.bozor.top7',
    title: 'TOP',
    description: 'TOP 7 kun',
    price: '25 000 so‘m',
    rawPrice: 25000,
    currencyCode: 'UZS',
  );
  bool starts = true;
  final bought = <({String id, String accountToken})>[];
  final completedPurchases = <PurchaseDetails>[];
  void Function()? onBuy;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<ProductDetails?> product(String productId) async => known;

  @override
  Stream<List<PurchaseDetails>> get purchases => controller.stream;

  @override
  Future<bool> buyConsumable(ProductDetails product, {required String accountToken}) async {
    bought.add((id: product.id, accountToken: accountToken));
    scheduleMicrotask(() => onBuy?.call());
    return starts;
  }

  @override
  Future<void> complete(PurchaseDetails purchase) async => completedPurchases.add(purchase);
}

PurchaseDetails details({
  String product = 'uz.bozor.top7',
  PurchaseStatus status = PurchaseStatus.purchased,
  String source = 'app_store',
  String? purchaseId = '2000000123',
  String server = 'server-data',
}) => PurchaseDetails(
  purchaseID: purchaseId,
  productID: product,
  verificationData: PurchaseVerificationData(
    localVerificationData: 'local',
    serverVerificationData: server,
    source: source,
  ),
  transactionDate: '1790000000000',
  status: status,
);

void main() {
  late FakeStorePlatform platform;
  late PlatformStoreBilling billing;

  setUp(() {
    platform = FakeStorePlatform();
    billing = PlatformStoreBilling(platform, timeout: const Duration(milliseconds: 300));
  });

  test('App Store: the receipt is the transaction id and the account token is attached', () async {
    platform.onBuy = () => platform.controller.add([details()]);
    final receipt = await billing.purchase(productId: 'uz.bozor.top7', accountToken: 'pay-1');
    expect(receipt.receipt, '2000000123');
    expect(platform.bought, [(id: 'uz.bozor.top7', accountToken: 'pay-1')]);
    expect(platform.completedPurchases, isEmpty, reason: 'finishing waits for the server');
    await receipt.complete();
    expect(platform.completedPurchases, hasLength(1));
  });

  test('Google Play: the receipt is the purchase token', () async {
    platform.onBuy = () =>
        platform.controller.add([details(source: 'google_play', purchaseId: 'GPA.1', server: 'the-token')]);
    final receipt = await billing.purchase(productId: 'uz.bozor.top7', accountToken: 'pay-1');
    expect(receipt.receipt, 'the-token');
  });

  test('pending then purchased waits for the final state; other products are ignored', () async {
    platform.onBuy = () {
      platform.controller.add([details(product: 'other', purchaseId: '999')]);
      platform.controller.add([details(status: PurchaseStatus.pending)]);
      Timer(const Duration(milliseconds: 20), () => platform.controller.add([details()]));
    };
    expect((await billing.purchase(productId: 'uz.bozor.top7', accountToken: 'p')).receipt, '2000000123');
  });

  test('dismissing the store sheet is reported as cancelled', () async {
    platform.onBuy = () => platform.controller.add([details(status: PurchaseStatus.canceled)]);
    await expectLater(
      billing.purchase(productId: 'uz.bozor.top7', accountToken: 'p'),
      throwsA(isA<UnknownFailure>().having((e) => e.message, 'message', 'cancelled')),
    );
  });

  test('store errors, unknown products and hangs surface as failures', () async {
    platform.onBuy = () => platform.controller.add([details(status: PurchaseStatus.error)]);
    await expectLater(billing.purchase(productId: 'uz.bozor.top7', accountToken: 'p'), throwsA(isA<UnknownFailure>()));

    platform.known = null;
    await expectLater(
      billing.purchase(productId: 'uz.bozor.top7', accountToken: 'p'),
      throwsA(isA<PaymentUnavailableFailure>()),
    );

    platform
      ..known = ProductDetails(
        id: 'uz.bozor.top7',
        title: 't',
        description: 'd',
        price: '1',
        rawPrice: 1,
        currencyCode: 'UZS',
      )
      ..onBuy = null;
    await expectLater(
      billing.purchase(productId: 'uz.bozor.top7', accountToken: 'p'),
      throwsA(isA<TimeoutException>()),
    );

    platform
      ..starts = false
      ..onBuy = null;
    await expectLater(billing.purchase(productId: 'uz.bozor.top7', accountToken: 'p'), throwsA(isA<UnknownFailure>()));
  });

  group('unclaimed purchases (recovery)', () {
    test('purchases nobody is waiting for are surfaced with their store and receipt', () async {
      final found = <UnclaimedPurchase>[];
      final subscription = billing.unclaimed().listen(found.add);
      addTearDown(subscription.cancel);
      platform.controller.add([
        details(purchaseId: '111'),
        details(source: 'google_play', server: 'play-token'),
        details(status: PurchaseStatus.pending),
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(found.map((p) => (p.store, p.receipt)), [('apple', '111'), ('google', 'play-token')]);
      await found.first.complete();
      expect(platform.completedPurchases, hasLength(1));
    });

    test('while a checkout is waiting for the store, its events are not treated as unclaimed', () async {
      final found = <UnclaimedPurchase>[];
      final subscription = billing.unclaimed().listen(found.add);
      addTearDown(subscription.cancel);
      platform.onBuy = () => platform.controller.add([details()]);
      final receipt = await billing.purchase(productId: 'uz.bozor.top7', accountToken: 'p');
      expect(receipt.receipt, '2000000123');
      await Future<void>.delayed(Duration.zero);
      expect(found, isEmpty);
    });
  });
}
