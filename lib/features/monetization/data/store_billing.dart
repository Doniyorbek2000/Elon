import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../../core/config/app_config.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/l10n/l10n.dart';

/// App Store / Google Play billing seam.
///
/// Apple (App Review Guideline 3.1.1 / 2.5.18-style boosts) and Google Play
/// (Payments policy) require their own billing for digital goods sold in the
/// app, such as listing boosts and plan periods. The server decides the route
/// per platform (`checkoutRoutes`) and names the store product; the app buys
/// it, then sends the store receipt to the backend, which verifies it with
/// Apple/Google server APIs before activating anything. The client never
/// reports "paid" by itself.
abstract interface class StoreBilling {
  /// True when the device can make store purchases right now.
  Future<bool> isAvailable();

  /// Buys [productId]. [accountToken] (the server's payment id) is attached to
  /// the store transaction so the receipt can only be claimed by that payment.
  Future<StoreReceipt> purchase({required String productId, required String accountToken});

  /// Finished-in-the-store purchases that nobody is waiting for (the app was closed
  /// after paying, the receipt call failed, …). The store re-delivers them until completed.
  Stream<UnclaimedPurchase> unclaimed();
}

/// A store purchase found without a checkout in progress.
class UnclaimedPurchase {
  const UnclaimedPurchase({
    required this.store,
    required this.productId,
    required this.receipt,
    required this.complete,
  });

  /// `apple` or `google`.
  final String store;
  final String productId;
  final String receipt;
  final Future<void> Function() complete;
}

/// Proof of a store purchase to hand to the server. Call [complete] only after
/// the server accepted the receipt: it finishes (iOS) / consumes (Android) the
/// transaction so the store stops re-delivering it.
class StoreReceipt {
  const StoreReceipt({required this.receipt, required this.complete});

  /// App Store transaction id or Google Play purchase token.
  final String receipt;
  final Future<void> Function() complete;
}

class UnavailableStoreBilling implements StoreBilling {
  const UnavailableStoreBilling();

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<StoreReceipt> purchase({required String productId, required String accountToken}) =>
      throw UnsupportedError('Store billing is not available');

  @override
  Stream<UnclaimedPurchase> unclaimed() => const Stream.empty();
}

/// The part of `in_app_purchase` we use, so the flow is testable without a store.
abstract interface class StorePlatform {
  Future<bool> isAvailable();
  Future<ProductDetails?> product(String productId);
  Stream<List<PurchaseDetails>> get purchases;
  Future<bool> buyConsumable(ProductDetails product, {required String accountToken});
  Future<void> complete(PurchaseDetails purchase);
}

class InAppPurchasePlatform implements StorePlatform {
  InAppPurchasePlatform([InAppPurchase? iap]) : _iap = iap ?? InAppPurchase.instance;

  final InAppPurchase _iap;

  @override
  Future<bool> isAvailable() => _iap.isAvailable();

  @override
  Future<ProductDetails?> product(String productId) async {
    final response = await _iap.queryProductDetails({productId});
    return response.productDetails.where((p) => p.id == productId).firstOrNull;
  }

  @override
  Stream<List<PurchaseDetails>> get purchases => _iap.purchaseStream;

  @override
  Future<bool> buyConsumable(ProductDetails product, {required String accountToken}) => _iap.buyConsumable(
    purchaseParam: PurchaseParam(productDetails: product, applicationUserName: accountToken),
    autoConsume: false,
  );

  @override
  Future<void> complete(PurchaseDetails purchase) => _iap.completePurchase(purchase);
}

class PlatformStoreBilling implements StoreBilling {
  PlatformStoreBilling(this._platform, {this.timeout = const Duration(minutes: 10)});

  final StorePlatform _platform;

  /// Upper bound for the store sheet (Face ID, parental approval, …).
  final Duration timeout;

  /// Number of purchases currently waiting for their own store result; events are theirs, not recovery's.
  int _inFlight = 0;

  @override
  Future<bool> isAvailable() => _platform.isAvailable();

  @override
  Stream<UnclaimedPurchase> unclaimed() => _platform.purchases.expand((updates) {
    if (_inFlight > 0) return const <UnclaimedPurchase>[];
    return [
      for (final purchase in updates)
        if (purchase.status == PurchaseStatus.purchased || purchase.status == PurchaseStatus.restored)
          UnclaimedPurchase(
            store: purchase.verificationData.source == 'google_play' ? 'google' : 'apple',
            productId: purchase.productID,
            receipt: receiptOf(purchase),
            complete: () => _platform.complete(purchase),
          ),
    ];
  });

  @override
  Future<StoreReceipt> purchase({required String productId, required String accountToken}) async {
    _inFlight++;
    try {
      return await _purchase(productId, accountToken);
    } finally {
      _inFlight--;
    }
  }

  Future<StoreReceipt> _purchase(String productId, String accountToken) async {
    final product = await _platform.product(productId);
    if (product == null) {
      throw PaymentUnavailableFailure(tr('Bu xizmatni hozircha ushbu qurilmada sotib olib bo‘lmaydi.'));
    }

    final outcome = Completer<PurchaseDetails>();
    final subscription = _platform.purchases.listen((updates) {
      for (final purchase in updates.where((p) => p.productID == productId)) {
        switch (purchase.status) {
          case PurchaseStatus.purchased || PurchaseStatus.restored:
            if (!outcome.isCompleted) {
              outcome.complete(purchase);
            }
          case PurchaseStatus.canceled:
            if (!outcome.isCompleted) {
              outcome.completeError(const UnknownFailure('cancelled'));
            }
          case PurchaseStatus.error:
            if (!outcome.isCompleted) {
              outcome.completeError(const UnknownFailure('store_error'));
            }
          case PurchaseStatus.pending:
            break;
        }
      }
    });
    try {
      final started = await _platform.buyConsumable(product, accountToken: accountToken);
      if (!started) throw const UnknownFailure('store_not_started');
      final purchase = await outcome.future.timeout(timeout);
      return StoreReceipt(receipt: receiptOf(purchase), complete: () => _platform.complete(purchase));
    } finally {
      await subscription.cancel();
    }
  }

  /// App Store: the StoreKit transaction id. Google Play: the purchase token.
  static String receiptOf(PurchaseDetails purchase) {
    final source = purchase.verificationData.source;
    if (source == 'google_play') return purchase.verificationData.serverVerificationData;
    return purchase.purchaseID ?? purchase.verificationData.serverVerificationData;
  }
}

final storeBillingProvider = Provider<StoreBilling>((ref) {
  if (ref.watch(appConfigProvider).useDemoData) return const UnavailableStoreBilling();
  if (!(Platform.isAndroid || Platform.isIOS)) return const UnavailableStoreBilling();
  return PlatformStoreBilling(InAppPurchasePlatform());
});
