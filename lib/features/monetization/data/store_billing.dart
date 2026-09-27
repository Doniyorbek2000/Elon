import 'package:flutter_riverpod/flutter_riverpod.dart';

/// App Store / Google Play billing seam.
///
/// Apple (App Review Guideline 3.1.1 / 2.5.18-style boosts) and Google Play
/// (Payments policy) require their own billing for digital goods sold in
/// the app, such as listing boosts and subscriptions. The server decides the
/// route per platform (`checkoutRoutes`) and does not expose store products
/// until store billing is configured, so this seam stays unavailable and the
/// app never links out to an external payment page on iOS/Android.
///
/// A real implementation must: start the store purchase for
/// [productId], then send the store receipt/purchase token to the backend,
/// which verifies it with Apple/Google server APIs before activating
/// anything. The client never reports "paid" by itself.
abstract interface class StoreBilling {
  bool get available;

  /// Starts a store purchase and returns an opaque receipt for server
  /// verification.
  Future<String> purchase({required String productId, required String purchaseId});
}

class UnavailableStoreBilling implements StoreBilling {
  const UnavailableStoreBilling();

  @override
  bool get available => false;

  @override
  Future<String> purchase({required String productId, required String purchaseId}) =>
      throw UnsupportedError('Store billing is not configured');
}

final storeBillingProvider = Provider<StoreBilling>((ref) => const UnavailableStoreBilling());
