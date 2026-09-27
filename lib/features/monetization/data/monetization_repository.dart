import '../../../core/domain/paged.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/network/api_client.dart';
import '../domain/monetization.dart';

/// Paid products, checkout and receipts. Every price, eligibility decision
/// and activation comes from the server; the client only asks and displays.
abstract interface class MonetizationRepository {
  Future<PromotionOffer> offer(PromotionTarget target, String targetId, {required String platform});

  Future<List<Plan>> plans();

  Future<MyEntitlements> entitlements();

  Future<Quote> quote(CheckoutRequest request);

  /// Creates a purchase; activation happens only after the provider's
  /// verified confirmation reaches the server.
  Future<Purchase> checkout(CheckoutRequest request);

  Future<PageResult<Purchase>> purchases({String? cursor});

  Future<Purchase> purchase(String id);

  Future<Purchase> cancelPurchase(String id);

  Future<List<Subscription>> subscriptions();

  Future<Subscription> cancelSubscription(String id);

  Future<({int balance, List<CreditEntry> entries})> credits();
}

class RemoteMonetizationRepository implements MonetizationRepository {
  RemoteMonetizationRepository(this._api);

  final ApiClient _api;

  @override
  Future<PromotionOffer> offer(PromotionTarget target, String targetId, {required String platform}) async =>
      PromotionOffer.fromJson(
        await _api.get<JsonMap>(
          '/catalog/promotions',
          query: {'target': target.name, 'targetId': targetId, 'platform': platform},
        ),
      );

  @override
  Future<List<Plan>> plans() async => [
    for (final plan in await _api.get<List<dynamic>>('/catalog/plans')) Plan.fromJson(plan as JsonMap),
  ];

  @override
  Future<MyEntitlements> entitlements() async => MyEntitlements.fromJson(await _api.get<JsonMap>('/me/entitlements'));

  @override
  Future<Quote> quote(CheckoutRequest request) async =>
      Quote.fromJson(await _api.post<JsonMap>('/checkout/quote', body: request.toQuoteJson()));

  @override
  Future<Purchase> checkout(CheckoutRequest request) async =>
      Purchase.fromJson(await _api.post<JsonMap>('/checkout', body: request.toJson()));

  @override
  Future<PageResult<Purchase>> purchases({String? cursor}) =>
      _api.getPage('/me/purchases', Purchase.fromJson, query: {'limit': 20}, cursor: cursor);

  @override
  Future<Purchase> purchase(String id) async => Purchase.fromJson(await _api.get<JsonMap>('/me/purchases/$id'));

  @override
  Future<Purchase> cancelPurchase(String id) async =>
      Purchase.fromJson(await _api.post<JsonMap>('/me/purchases/$id/cancel'));

  @override
  Future<List<Subscription>> subscriptions() async => [
    for (final s in await _api.get<List<dynamic>>('/me/subscriptions')) Subscription.fromJson(s as JsonMap),
  ];

  @override
  Future<Subscription> cancelSubscription(String id) async =>
      Subscription.fromJson(await _api.post<JsonMap>('/me/subscriptions/$id/cancel'));

  @override
  Future<({int balance, List<CreditEntry> entries})> credits() async {
    final json = await _api.get<JsonMap>('/me/credits');
    return (
      balance: (json['balance'] as num?)?.toInt() ?? 0,
      entries: [for (final e in json['entries'] as List<dynamic>? ?? const []) CreditEntry.fromJson(e as JsonMap)],
    );
  }
}

/// Demo builds: nothing is for sale and no prices are invented.
class UnavailableMonetizationRepository implements MonetizationRepository {
  const UnavailableMonetizationRepository();

  static const _off = FeatureDisabledFailure();

  @override
  Future<PromotionOffer> offer(PromotionTarget target, String targetId, {required String platform}) async =>
      const PromotionOffer(products: [], eligible: false, methods: [], creditBalance: 0, creditsEnabled: false);

  @override
  Future<List<Plan>> plans() async => const [];

  @override
  Future<MyEntitlements> entitlements() => throw _off;

  @override
  Future<Quote> quote(CheckoutRequest request) => throw _off;

  @override
  Future<Purchase> checkout(CheckoutRequest request) => throw _off;

  @override
  Future<PageResult<Purchase>> purchases({String? cursor}) async => const PageResult(items: [], nextCursor: null);

  @override
  Future<Purchase> purchase(String id) => throw const NotFoundFailure();

  @override
  Future<Purchase> cancelPurchase(String id) => throw _off;

  @override
  Future<List<Subscription>> subscriptions() async => const [];

  @override
  Future<Subscription> cancelSubscription(String id) => throw _off;

  @override
  Future<({int balance, List<CreditEntry> entries})> credits() async => (balance: 0, entries: const <CreditEntry>[]);
}
