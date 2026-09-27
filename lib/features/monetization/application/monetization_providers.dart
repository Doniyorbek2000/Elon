import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/feature_flags.dart';
import '../../../core/domain/money.dart';
import '../../../core/domain/promotion.dart';

/// Catalog of paid products. Served by the billing backend once payments
/// (Click/Payme/Uzum) are integrated; until then this is the reference
/// catalog, exposed only when monetization flags are on.
abstract interface class MonetizationRepository {
  Future<List<PromotionProduct>> promotionProducts(PromotionTarget target);
  Future<List<SubscriptionPlan>> subscriptionPlans();
}

class StaticMonetizationRepository implements MonetizationRepository {
  const StaticMonetizationRepository();

  static const _products = [
    PromotionProduct(
      id: 'bump_1',
      type: PromotionType.bump,
      target: PromotionTarget.listing,
      title: 'Ko‘tarish',
      description: 'E’lon ro‘yxat boshiga qaytadi',
      durationDays: 1,
      price: Money.uzs(9000),
    ),
    PromotionProduct(
      id: 'top_7',
      type: PromotionType.top,
      target: PromotionTarget.listing,
      title: 'TOP e’lon',
      description: 'Kategoriya va qidiruvda yuqorida, TOP belgisi bilan',
      durationDays: 7,
      price: Money.uzs(29000),
    ),
    PromotionProduct(
      id: 'vip_7',
      type: PromotionType.vip,
      target: PromotionTarget.listing,
      title: 'VIP e’lon',
      description: 'Bosh sahifada ajratilgan joy va VIP belgisi',
      durationDays: 7,
      price: Money.uzs(59000),
    ),
    PromotionProduct(
      id: 'premium_vacancy_14',
      type: PromotionType.premiumVacancy,
      target: PromotionTarget.vacancy,
      title: 'Premium vakansiya',
      description: 'Vakansiyalar ro‘yxatida yuqorida 14 kun',
      durationDays: 14,
      price: Money.uzs(49000),
    ),
    PromotionProduct(
      id: 'featured_provider_30',
      type: PromotionType.featured,
      target: PromotionTarget.provider,
      title: 'Tavsiya etilgan usta',
      description: '«Tavsiya etilgan ustalar» blokida 30 kun',
      durationDays: 30,
      price: Money.uzs(99000),
    ),
  ];

  @override
  Future<List<PromotionProduct>> promotionProducts(PromotionTarget target) async =>
      _products.where((p) => p.target == target).toList();

  @override
  Future<List<SubscriptionPlan>> subscriptionPlans() async => const [
    SubscriptionPlan(
      id: 'business_start',
      title: 'Biznes Start',
      monthlyPrice: Money.uzs(149000),
      benefits: ['Do‘kon sahifasi', '50 tagacha faol e’lon', 'Statistika'],
    ),
    SubscriptionPlan(
      id: 'business_pro',
      title: 'Biznes Pro',
      monthlyPrice: Money.uzs(349000),
      highlighted: true,
      benefits: ['Cheksiz e’lonlar', 'Har hafta 5 ta TOP', 'Tasdiqlangan biznes belgisi', 'Ustuvor qo‘llab-quvvatlash'],
    ),
  ];
}

final monetizationRepositoryProvider = Provider<MonetizationRepository>((ref) => const StaticMonetizationRepository());

final promotionProductsProvider = FutureProvider.family<List<PromotionProduct>, PromotionTarget>((ref, target) {
  if (!ref.watch(featureFlagsProvider).canSellPromotions) return const [];
  return ref.watch(monetizationRepositoryProvider).promotionProducts(target);
});

final subscriptionPlansProvider = FutureProvider<List<SubscriptionPlan>>((ref) {
  final flags = ref.watch(featureFlagsProvider);
  if (!flags.monetizationEnabled || !flags.subscriptionsEnabled) return const [];
  return ref.watch(monetizationRepositoryProvider).subscriptionPlans();
});
