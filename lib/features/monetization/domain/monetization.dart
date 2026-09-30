import 'package:flutter/foundation.dart';

import '../../../core/config/feature_flags.dart';
import '../../../core/domain/money.dart';
import '../../../core/l10n/l10n.dart';

typedef Json = Map<String, dynamic>;

DateTime? _date(Object? value) => value is String ? DateTime.tryParse(value)?.toLocal() : null;

/// Server price. [amountMinor] is the exact integer (tiyin) as a string;
/// [money] holds whole so‘m for display. The client never computes prices.
@immutable
class Price {
  const Price({required this.amountMinor, required this.money});

  factory Price.fromJson(Json json) => Price(
    amountMinor: json['amountMinor'] as String? ?? '0',
    money: Money((json['amount'] as num? ?? 0).toInt(), Currency.parse(json['currency'])),
  );

  final String amountMinor;
  final Money money;

  bool get isZero => BigInt.tryParse(amountMinor) == BigInt.zero;

  @override
  bool operator ==(Object other) => other is Price && other.amountMinor == amountMinor && other.money == money;

  @override
  int get hashCode => Object.hash(amountMinor, money);
}

/// What is being promoted. API values: `listing`, `job`, `provider`, `business`.
enum PromotionTarget {
  listing,
  job,
  provider,
  business;

  static PromotionTarget parse(Object? value) =>
      PromotionTarget.values.where((t) => t.name == value).firstOrNull ?? PromotionTarget.listing;
}

enum ProductKind {
  listingTop,
  listingVip,
  listingBump,
  listingFeatured,
  jobTop,
  jobFeatured,
  jobUrgent,
  providerTop,
  providerFeatured,
  adCampaign,
  unknown;

  static ProductKind parse(Object? value) =>
      ProductKind.values.where((k) => k.name == value).firstOrNull ?? ProductKind.unknown;

  bool get isBump => this == ProductKind.listingBump;

  /// Success headline after activation, e.g. "TOP faollashtirildi".
  String get activatedTitle => switch (this) {
    ProductKind.listingTop || ProductKind.jobTop || ProductKind.providerTop => tr('TOP faollashtirildi'),
    ProductKind.listingVip => tr('VIP faollashtirildi'),
    ProductKind.listingBump => tr('E’lon yuqoriga ko‘tarildi'),
    ProductKind.listingFeatured ||
    ProductKind.jobFeatured ||
    ProductKind.providerFeatured => tr('Tavsiya faollashtirildi'),
    ProductKind.jobUrgent => tr('«Shoshilinch» belgisi qo‘shildi'),
    ProductKind.adCampaign => tr('Reklama tekshiruvga yuborildi'),
    ProductKind.unknown => tr('Xizmat faollashtirildi'),
  };
}

/// A paid promotion product from `GET /catalog/promotions`.
@immutable
class PromotionProduct {
  const PromotionProduct({
    required this.id,
    required this.kind,
    required this.target,
    required this.title,
    required this.description,
    required this.price,
    this.placement,
    this.durationDays,
    this.creditCost,
  });

  factory PromotionProduct.fromJson(Json json) => PromotionProduct(
    id: json['id'] as String,
    kind: ProductKind.parse(json['kind']),
    target: PromotionTarget.parse(json['target']),
    placement: json['placement'] == 'none' ? null : json['placement'] as String?,
    durationDays: (json['durationDays'] as num?)?.toInt(),
    title: json['title'] as String? ?? '',
    description: json['description'] as String? ?? '',
    creditCost: (json['creditCost'] as num?)?.toInt(),
    price: Price.fromJson(json['price'] as Json),
  );

  final String id;
  final ProductKind kind;
  final PromotionTarget target;
  final String? placement;
  final int? durationDays;
  final String title;
  final String description;
  final int? creditCost;
  final Price price;
}

/// Checkout methods the server allows for this platform.
enum PaymentMethod {
  dev,
  payme,
  click,
  apple,
  google,
  credits,
  free;

  static PaymentMethod? parse(Object? value) => PaymentMethod.values.where((m) => m.name == value).firstOrNull;

  String get label => switch (this) {
    PaymentMethod.dev => tr('Test to‘lov'),
    PaymentMethod.payme => 'Payme',
    PaymentMethod.click => 'Click',
    PaymentMethod.apple => tr('App Store'),
    PaymentMethod.google => tr('Google Play'),
    PaymentMethod.credits => tr('Reklama krediti'),
    PaymentMethod.free => tr('Bepul'),
  };

  bool get isStore => this == PaymentMethod.apple || this == PaymentMethod.google;
}

@immutable
class PromotionOffer {
  const PromotionOffer({
    required this.products,
    required this.eligible,
    required this.methods,
    required this.creditBalance,
    required this.creditsEnabled,
    this.ineligibleReason,
    this.bumpAvailableAt,
  });

  factory PromotionOffer.fromJson(Json json) {
    final eligibility = json['eligibility'] as Json? ?? const {};
    final credits = json['credits'] as Json? ?? const {};
    return PromotionOffer(
      products: [for (final p in json['products'] as List<dynamic>? ?? const []) PromotionProduct.fromJson(p as Json)],
      eligible: eligibility['eligible'] as bool? ?? true,
      ineligibleReason: eligibility['reason'] as String?,
      bumpAvailableAt: _date(eligibility['bumpAvailableAt']),
      methods: [for (final m in json['providers'] as List<dynamic>? ?? const []) ?PaymentMethod.parse(m)],
      creditBalance: (credits['balance'] as num?)?.toInt() ?? 0,
      creditsEnabled: credits['enabled'] as bool? ?? false,
    );
  }

  final List<PromotionProduct> products;
  final bool eligible;
  final String? ineligibleReason;

  /// Next time a bump is allowed (server cooldown), if in the future.
  final DateTime? bumpAvailableAt;
  final List<PaymentMethod> methods;
  final int creditBalance;
  final bool creditsEnabled;
}

@immutable
class PlanEntitlements {
  const PlanEntitlements({
    required this.photoLimit,
    required this.storefront,
    required this.businessBadge,
    required this.advancedAnalytics,
    required this.maxManagers,
    required this.monthlyPromotionCredits,
    required this.prioritySupport,
    this.activeListingLimit,
    this.monthlyListingLimit,
    this.activeJobLimit,
  });

  factory PlanEntitlements.fromJson(Json json) => PlanEntitlements(
    activeListingLimit: (json['activeListingLimit'] as num?)?.toInt(),
    monthlyListingLimit: (json['monthlyListingLimit'] as num?)?.toInt(),
    photoLimit: (json['photoLimit'] as num?)?.toInt() ?? 0,
    activeJobLimit: (json['activeJobLimit'] as num?)?.toInt(),
    storefront: json['storefront'] as bool? ?? false,
    businessBadge: json['businessBadge'] as bool? ?? false,
    advancedAnalytics: json['analytics'] == 'advanced',
    maxManagers: (json['maxManagers'] as num?)?.toInt() ?? 0,
    monthlyPromotionCredits: (json['monthlyPromotionCredits'] as num?)?.toInt() ?? 0,
    prioritySupport: json['prioritySupport'] as bool? ?? false,
  );

  final int? activeListingLimit;
  final int? monthlyListingLimit;
  final int photoLimit;
  final int? activeJobLimit;
  final bool storefront;
  final bool businessBadge;
  final bool advancedAnalytics;
  final int maxManagers;
  final int monthlyPromotionCredits;
  final bool prioritySupport;
}

@immutable
class PlanPrice {
  const PlanPrice({required this.id, required this.period, required this.price});

  factory PlanPrice.fromJson(Json json) =>
      PlanPrice(id: json['id'] as String, period: json['period'] as String? ?? 'month', price: Price.fromJson(json));

  final String id;

  /// `month` or `year`.
  final String period;
  final Price price;

  String get periodLabel => period == 'year' ? 'yil' : 'oy';
}

@immutable
class Plan {
  const Plan({
    required this.id,
    required this.title,
    required this.description,
    required this.entitlements,
    required this.prices,
  });

  factory Plan.fromJson(Json json) => Plan(
    id: json['id'] as String,
    title: json['title'] as String? ?? '',
    description: json['description'] as String? ?? '',
    entitlements: PlanEntitlements.fromJson(json['entitlements'] as Json? ?? const {}),
    prices: [for (final p in json['prices'] as List<dynamic>? ?? const []) PlanPrice.fromJson(p as Json)],
  );

  final String id;
  final String title;
  final String description;
  final PlanEntitlements entitlements;
  final List<PlanPrice> prices;
}

@immutable
class MyEntitlements {
  const MyEntitlements({
    required this.planId,
    required this.planTitle,
    required this.entitlements,
    required this.activeListings,
    required this.promotionCredits,
    this.subscriptionId,
    this.businessId,
  });

  factory MyEntitlements.fromJson(Json json) {
    final plan = json['plan'] as Json? ?? const {};
    return MyEntitlements(
      planId: plan['id'] as String? ?? 'FREE',
      planTitle: plan['title'] as String? ?? '',
      entitlements: PlanEntitlements.fromJson(json['entitlements'] as Json? ?? const {}),
      activeListings: ((json['usage'] as Json?)?['activeListings'] as num?)?.toInt() ?? 0,
      promotionCredits: (json['promotionCredits'] as num?)?.toInt() ?? 0,
      subscriptionId: json['subscriptionId'] as String?,
      businessId: json['businessId'] as String?,
    );
  }

  final String planId;
  final String planTitle;
  final PlanEntitlements entitlements;
  final int activeListings;
  final int promotionCredits;
  final String? subscriptionId;
  final String? businessId;

  bool get isFree => planId == 'FREE';
}

@immutable
class Quote {
  const Quote({
    required this.list,
    required this.discount,
    required this.total,
    required this.methods,
    required this.creditsUsable,
    this.creditCost,
  });

  factory Quote.fromJson(Json json) {
    final credits = json['credits'] as Json? ?? const {};
    return Quote(
      list: Price.fromJson(json['list'] as Json),
      discount: Price.fromJson(json['discount'] as Json),
      total: Price.fromJson(json['total'] as Json),
      methods: [for (final m in json['providers'] as List<dynamic>? ?? const []) ?PaymentMethod.parse(m)],
      creditCost: (credits['cost'] as num?)?.toInt(),
      creditsUsable: credits['usable'] as bool? ?? false,
    );
  }

  final Price list;
  final Price discount;
  final Price total;
  final List<PaymentMethod> methods;
  final int? creditCost;
  final bool creditsUsable;
}

/// What the app must do after `POST /checkout`.
sealed class CheckoutAction {
  const CheckoutAction();

  static CheckoutAction? fromJson(Json? json) => switch (json?['type']) {
    'redirect' => RedirectAction(Uri.parse(json!['url'] as String)),
    'store' => StoreAction(
      json!['store'] as String,
      json['storeProductId'] as String,
      json['accountToken'] as String? ?? '',
    ),
    'none' => const NoAction(),
    _ => null,
  };
}

/// Hosted payment page of the provider (opened outside the app).
final class RedirectAction extends CheckoutAction {
  const RedirectAction(this.url);

  final Uri url;
}

/// App Store / Google Play billing (see [StoreBilling]).
final class StoreAction extends CheckoutAction {
  const StoreAction(this.store, this.productId, this.accountToken);

  final String store;
  final String productId;

  /// The server's payment id, attached to the store transaction.
  final String accountToken;
}

/// Nothing to pay (credits, 100 % coupon) — the server already settled it.
final class NoAction extends CheckoutAction {
  const NoAction();
}

enum PurchaseStatus {
  awaitingPayment,
  fulfilled,
  failed,
  cancelled,
  refunded,
  needsReview;

  static PurchaseStatus parse(Object? value) =>
      PurchaseStatus.values.where((s) => s.name == value).firstOrNull ?? PurchaseStatus.awaitingPayment;

  bool get isFinal => this != PurchaseStatus.awaitingPayment;

  String get label => switch (this) {
    PurchaseStatus.awaitingPayment => tr('To‘lov kutilmoqda'),
    PurchaseStatus.fulfilled => tr('Faollashtirildi'),
    PurchaseStatus.failed => tr('To‘lov o‘tmadi'),
    PurchaseStatus.cancelled => tr('Bekor qilindi'),
    PurchaseStatus.refunded => tr('Qaytarildi'),
    PurchaseStatus.needsReview => tr('Tekshirilmoqda'),
  };
}

String paymentStatusLabel(String? status) => switch (status) {
  'created' || 'pending' => tr('Kutilmoqda'),
  'succeeded' => tr('To‘landi'),
  'failed' => tr('Xato'),
  'cancelled' => tr('Bekor qilindi'),
  'refunded' => tr('To‘liq qaytarildi'),
  'partiallyRefunded' => tr('Qisman qaytarildi'),
  _ => '—',
};

@immutable
class PaymentRecord {
  const PaymentRecord({
    required this.id,
    required this.method,
    required this.status,
    required this.amount,
    required this.refunded,
    required this.createdAt,
    this.succeededAt,
    this.refunds = const [],
  });

  factory PaymentRecord.fromJson(Json json) => PaymentRecord(
    id: json['id'] as String,
    method: PaymentMethod.parse(json['provider']),
    status: json['status'] as String? ?? '',
    amount: Price.fromJson(json['amount'] as Json),
    refunded: Price.fromJson(json['refunded'] as Json),
    createdAt: _date(json['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    succeededAt: _date(json['succeededAt']),
    refunds: [
      for (final r in json['refunds'] as List<dynamic>? ?? const [])
        (
          status: (r as Json)['status'] as String? ?? '',
          amount: Price.fromJson(r['amount'] as Json),
          createdAt: _date(r['createdAt']),
        ),
    ],
  );

  final String id;
  final PaymentMethod? method;
  final String status;
  final Price amount;
  final Price refunded;
  final DateTime createdAt;
  final DateTime? succeededAt;
  final List<({String status, Price amount, DateTime? createdAt})> refunds;
}

@immutable
class Purchase {
  const Purchase({
    required this.id,
    required this.kind,
    required this.status,
    required this.title,
    required this.list,
    required this.discount,
    required this.total,
    required this.creditsUsed,
    required this.createdAt,
    this.productId,
    this.planId,
    this.target,
    this.targetId,
    this.paymentStatus,
    this.method,
    this.fulfilledAt,
    this.payments = const [],
    this.activationStartsAt,
    this.activationExpiresAt,
    this.activationId,
    this.subscriptionEnd,
    this.action,
  });

  factory Purchase.fromJson(Json json) {
    final activation = json['activation'] as Json?;
    final subscription = json['subscription'] as Json?;
    return Purchase(
      id: json['id'] as String,
      kind: json['kind'] as String? ?? 'promotion',
      status: PurchaseStatus.parse(json['status']),
      title: json['title'] as String? ?? '',
      productId: json['productId'] as String?,
      planId: json['planId'] as String?,
      target: json['target'] == null ? null : PromotionTarget.parse(json['target']),
      targetId: json['targetId'] as String?,
      list: Price.fromJson(json['list'] as Json),
      discount: Price.fromJson(json['discount'] as Json),
      total: Price.fromJson(json['total'] as Json),
      creditsUsed: (json['creditsUsed'] as num?)?.toInt() ?? 0,
      paymentStatus: json['paymentStatus'] as String?,
      method: PaymentMethod.parse(json['provider']),
      createdAt: _date(json['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      fulfilledAt: _date(json['fulfilledAt']),
      payments: [for (final p in json['payments'] as List<dynamic>? ?? const []) PaymentRecord.fromJson(p as Json)],
      activationId: activation?['id'] as String?,
      activationStartsAt: _date(activation?['startsAt']),
      activationExpiresAt: _date(activation?['expiresAt']),
      subscriptionEnd: _date(subscription?['currentPeriodEnd']),
      action: CheckoutAction.fromJson(json['action'] as Json?),
    );
  }

  final String id;

  /// `promotion` or `subscription`.
  final String kind;
  final PurchaseStatus status;
  final String title;
  final String? productId;
  final String? planId;
  final PromotionTarget? target;
  final String? targetId;
  final Price list;
  final Price discount;
  final Price total;
  final int creditsUsed;
  final String? paymentStatus;
  final PaymentMethod? method;
  final DateTime createdAt;
  final DateTime? fulfilledAt;
  final List<PaymentRecord> payments;
  final String? activationId;
  final DateTime? activationStartsAt;
  final DateTime? activationExpiresAt;
  final DateTime? subscriptionEnd;

  /// Present only on the checkout response.
  final CheckoutAction? action;

  bool get isSubscription => kind == 'subscription';
}

@immutable
class CreditEntry {
  const CreditEntry({
    required this.type,
    required this.amount,
    required this.reason,
    required this.createdAt,
    this.expiresAt,
  });

  factory CreditEntry.fromJson(Json json) => CreditEntry(
    type: json['type'] as String? ?? '',
    amount: (json['amount'] as num?)?.toInt() ?? 0,
    reason: json['reason'] as String? ?? '',
    createdAt: _date(json['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    expiresAt: _date(json['expiresAt']),
  );

  final String type;
  final int amount;
  final String reason;
  final DateTime createdAt;
  final DateTime? expiresAt;
}

@immutable
class Subscription {
  const Subscription({
    required this.id,
    required this.planId,
    required this.planTitle,
    required this.status,
    required this.method,
    required this.currentPeriodEnd,
    required this.cancelAtPeriodEnd,
  });

  factory Subscription.fromJson(Json json) {
    final plan = json['plan'] as Json? ?? const {};
    return Subscription(
      id: json['id'] as String,
      planId: plan['id'] as String? ?? '',
      planTitle: plan['title'] as String? ?? '',
      status: json['status'] as String? ?? '',
      method: PaymentMethod.parse(json['provider']),
      currentPeriodEnd: _date(json['currentPeriodEnd']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      cancelAtPeriodEnd: json['cancelAtPeriodEnd'] as bool? ?? false,
    );
  }

  final String id;
  final String planId;
  final String planTitle;

  /// `active`, `pastDue`, `gracePeriod`, `cancelled`, `expired`.
  final String status;
  final PaymentMethod? method;
  final DateTime currentPeriodEnd;
  final bool cancelAtPeriodEnd;

  bool get isLive => status == 'active' || status == 'gracePeriod' || status == 'pastDue';

  /// Store subscriptions are managed in the store, not in the app.
  bool get cancellableHere => isLive && !cancelAtPeriodEnd && !(method?.isStore ?? false);

  String get statusLabel => switch (status) {
    'active' => cancelAtPeriodEnd ? tr('Muddat oxirida tugaydi') : tr('Faol'),
    'gracePeriod' => tr('Imtiyozli davr'),
    'pastDue' => tr('To‘lov kutilmoqda'),
    'cancelled' => tr('Bekor qilingan'),
    'expired' => tr('Muddati tugagan'),
    _ => status,
  };
}

/// The request the UI builds; everything else is decided by the server.
@immutable
class CheckoutRequest {
  const CheckoutRequest({
    required this.method,
    required this.platform,
    required this.idempotencyKey,
    this.productId,
    this.planPriceId,
    this.targetId,
    this.couponCode,
  });

  final String? productId;
  final String? planPriceId;
  final String? targetId;
  final String? couponCode;
  final PaymentMethod method;

  /// `ios`, `android` or `web` — decides allowed payment routes server-side.
  final String platform;

  /// Same key on retry ⇒ same purchase (no double charge).
  final String idempotencyKey;

  Map<String, Object?> toJson() => {
    'productId': ?productId,
    'planPriceId': ?planPriceId,
    'targetId': ?targetId,
    if (couponCode != null && couponCode!.trim().isNotEmpty) 'couponCode': couponCode!.trim(),
    'provider': method.name,
    'platform': platform,
    'idempotencyKey': idempotencyKey,
  };

  Map<String, Object?> toQuoteJson() => {
    'productId': ?productId,
    'planPriceId': ?planPriceId,
    'targetId': ?targetId,
    if (couponCode != null && couponCode!.trim().isNotEmpty) 'couponCode': couponCode!.trim(),
    'platform': platform,
  };
}

/// Re-exported so presentation can show server-configured free limits.
typedef FreeLimits = FreePlanLimits;
