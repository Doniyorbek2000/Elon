import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/config/feature_flags.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/badges.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/application/session_controller.dart';
import '../application/monetization_providers.dart';
import '../domain/monetization.dart';
import 'checkout_screen.dart';

/// "To‘lovlar va tariflar": current plan, subscriptions, credits, receipts.
class PaymentsScreen extends ConsumerWidget {
  const PaymentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flags = ref.watch(featureFlagsProvider);
    final signedIn = ref.watch(sessionProvider) != null;
    final history = ref.watch(purchaseHistoryProvider);
    final text = Theme.of(context).textTheme;

    Future<void> refresh() async {
      ref
        ..invalidate(remoteConfigProvider)
        ..invalidate(myEntitlementsProvider)
        ..invalidate(mySubscriptionsProvider)
        ..invalidate(myCreditsProvider)
        ..invalidate(purchaseHistoryProvider);
    }

    return Scaffold(
      appBar: AppBar(title: Text(tr('To‘lovlar va tariflar'))),
      body: RefreshIndicator.adaptive(
        onRefresh: refresh,
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.metrics.extentAfter < 400) ref.read(purchaseHistoryProvider.notifier).loadMore();
            return false;
          },
          child: ContentWidth(
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                const _CurrentPlanCard(),
                if (flags.canBuyPlans) ...[
                  const SizedBox(height: AppSpacing.md),
                  OutlinedButton.icon(
                    onPressed: () => context.push(AppRoutes.businessPlans),
                    icon: const Icon(Icons.workspace_premium_outlined),
                    label: Text(tr('Biznes uchun tariflar')),
                  ),
                ],
                if (signedIn) ...[
                  const _SubscriptionsSection(),
                  if (flags.promotionCredits) const _CreditsSection(),
                  const SizedBox(height: AppSpacing.xl),
                  Text(tr('To‘lovlar tarixi'), style: text.titleSmall),
                  const SizedBox(height: AppSpacing.sm),
                  history.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.all(AppSpacing.xl),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (error, _) => FailureView(
                      error: error,
                      compact: true,
                      onRetry: () => ref.invalidate(purchaseHistoryProvider),
                    ),
                    data: (page) => page.items.isEmpty
                        ? EmptyState(icon: Icons.receipt_long_outlined, title: tr('To‘lovlar yo‘q'), compact: true)
                        : Column(
                            children: [
                              for (final purchase in page.items) _PurchaseTile(purchase: purchase),
                              LoadMoreFooter(
                                isLoading: page.isLoadingMore,
                                hasMore: page.hasMore,
                                error: page.loadMoreError,
                                onRetry: () => ref.read(purchaseHistoryProvider.notifier).loadMore(),
                              ),
                            ],
                          ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _limit(int? value, String unit) =>
    value == null ? tr('Cheksiz {unit}', {'unit': unit}) : tr('{value} ta {unit}', {'value': value, 'unit': unit});

class _CurrentPlanCard extends ConsumerWidget {
  const _CurrentPlanCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final text = Theme.of(context).textTheme;
    final mine = ref.watch(myEntitlementsProvider).value;
    final free = ref.watch(remoteConfigProvider).value?.freePlan;
    final paid = mine != null && !mine.isFree;
    final activeLimit = mine?.entitlements.activeListingLimit ?? free?.activeListingLimit;
    return SurfaceCard(
      color: paid ? palette.vipSoft : palette.successSoft,
      borderColor: Colors.transparent,
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                paid ? Icons.workspace_premium_rounded : Icons.celebration_rounded,
                color: paid ? palette.vip : palette.success,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  paid ? tr('Tarif: {planTitle}', {'planTitle': tr(mine.planTitle)}) : tr('Bepul tarif'),
                  style: text.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            tr('Ko‘rish, qidirish, chat, sevimlilar, e’lon joylash va ishga ariza berish — bepul.'),
            style: text.bodyMedium,
          ),
          if (activeLimit != null || mine != null) ...[
            const SizedBox(height: AppSpacing.md),
            if (mine != null)
              MetaLine(
                icon: Icons.inventory_2_outlined,
                text: activeLimit == null
                    ? tr('Faol e’lonlar: {activeListings}', {'activeListings': mine.activeListings})
                    : tr('Faol e’lonlar: {activeListings} / {activeLimit}', {
                        'activeListings': mine.activeListings,
                        'activeLimit': activeLimit,
                      }),
              )
            else
              MetaLine(icon: Icons.inventory_2_outlined, text: _limit(activeLimit, tr('faol e’lon'))),
            MetaLine(
              icon: Icons.photo_library_outlined,
              text: tr('E’londa {p0} tagacha rasm', {'p0': mine?.entitlements.photoLimit ?? free?.photoLimit ?? '—'}),
            ),
          ],
        ],
      ),
    );
  }
}

class _SubscriptionsSection extends ConsumerWidget {
  const _SubscriptionsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subscriptions = ref.watch(mySubscriptionsProvider).value ?? const [];
    final live = subscriptions.where((s) => s.isLive).toList();
    if (live.isEmpty) return const SizedBox.shrink();
    final now = ref.watch(clockProvider)();
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(tr('Obunalar'), style: text.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          for (final s in live)
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(tr(s.planTitle), style: text.titleSmall)),
                      StatusPill(label: s.statusLabel, style: PillStyle.success, dense: true),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(tr('{p0} gacha', {'p0': Formatters.date(s.currentPeriodEnd, now: now)}), style: text.bodySmall),
                  if (s.method?.isStore ?? false)
                    Text(tr('Obuna {p0} orqali boshqariladi', {'p0': s.method!.label}), style: text.bodySmall),
                  if (s.cancellableHere)
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: TextButton(
                        onPressed: () async {
                          final ok = await confirmDialog(
                            context,
                            title: tr('Obuna bekor qilinsinmi?'),
                            message: tr(
                              'Tarif {p0} gacha ishlaydi, keyin bepul tarifga o‘tasiz. E’lonlaringiz o‘chirilmaydi.',
                              {'p0': Formatters.date(s.currentPeriodEnd, now: now)},
                            ),
                            confirmLabel: tr('Bekor qilish'),
                            destructive: true,
                          );
                          if (!ok) return;
                          try {
                            await ref.read(monetizationRepositoryProvider).cancelSubscription(s.id);
                            ref.invalidate(mySubscriptionsProvider);
                          } on Object {
                            if (context.mounted) showAppSnack(context, tr('Bekor qilib bo‘lmadi'));
                          }
                        },
                        child: Text(tr('Obunani bekor qilish')),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CreditsSection extends ConsumerWidget {
  const _CreditsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final credits = ref.watch(myCreditsProvider).value;
    if (credits == null || (credits.balance == 0 && credits.entries.isEmpty)) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: SurfaceCard(
        child: Row(
          children: [
            const Icon(Icons.toll_rounded),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text(tr('Reklama kreditlari'), style: text.titleSmall)),
            Text(tr('{balance} ta', {'balance': credits.balance}), style: text.titleSmall),
          ],
        ),
      ),
    );
  }
}

class _PurchaseTile extends ConsumerWidget {
  const _PurchaseTile({required this.purchase});

  final Purchase purchase;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider)();
    final text = Theme.of(context).textTheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: () => context.push(AppRoutes.purchase(purchase.id)),
      title: Text(tr(purchase.title), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${Formatters.date(purchase.createdAt, now: now)} · ${purchase.status.label}'),
      trailing: Text(
        purchase.creditsUsed > 0
            ? tr('{creditsUsed} kredit', {'creditsUsed': purchase.creditsUsed})
            : Formatters.money(purchase.total.money),
        style: text.titleSmall,
      ),
    );
  }
}

/// Receipt: amounts, payment attempts, refunds and what was activated.
class PurchaseDetailScreen extends ConsumerWidget {
  const PurchaseDetailScreen({super.key, required this.purchaseId});

  final String purchaseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(purchaseDetailProvider(purchaseId));
    final now = ref.watch(clockProvider)();
    final text = Theme.of(context).textTheme;
    final palette = context.palette;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Chek'))),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            FailureView(error: error, onRetry: () => ref.invalidate(purchaseDetailProvider(purchaseId))),
        data: (p) => ContentWidth(
          maxWidth: AppBreakpoints.formMaxWidth,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Text(tr(p.title), style: text.titleLarge),
              const SizedBox(height: AppSpacing.xs),
              StatusPill(
                label: p.status.label,
                style: switch (p.status) {
                  PurchaseStatus.fulfilled => PillStyle.success,
                  PurchaseStatus.failed || PurchaseStatus.cancelled => PillStyle.danger,
                  PurchaseStatus.refunded => PillStyle.neutral,
                  _ => PillStyle.warning,
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              InfoTile(
                label: tr('Sana'),
                value: '${Formatters.date(p.createdAt, now: now)}, ${Formatters.clock(p.createdAt)}',
              ),
              if (p.creditsUsed > 0)
                InfoTile(label: tr('Kreditlar'), value: tr('{creditsUsed} ta', {'creditsUsed': p.creditsUsed}))
              else ...[
                InfoTile(label: tr('Narx'), value: Formatters.money(p.list.money)),
                if (!p.discount.isZero)
                  InfoTile(label: tr('Chegirma'), value: '−${Formatters.money(p.discount.money)}'),
                InfoTile(label: tr('Jami'), value: Formatters.money(p.total.money)),
              ],
              if (p.activationExpiresAt != null)
                InfoTile(
                  label: tr('Amal qilish muddati'),
                  value:
                      '${p.activationStartsAt == null ? '' : '${Formatters.date(p.activationStartsAt!, now: now)} — '}'
                      '${Formatters.date(p.activationExpiresAt!, now: now)}',
                ),
              if (p.subscriptionEnd != null)
                InfoTile(
                  label: tr('Tarif muddati'),
                  value: tr('{p0} gacha', {'p0': Formatters.date(p.subscriptionEnd!, now: now)}),
                ),
              if (p.payments.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                Text(tr('To‘lovlar'), style: text.titleSmall),
                for (final payment in p.payments)
                  SurfaceCard(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(payment.method?.label ?? '—', style: text.titleSmall)),
                            Text(paymentStatusLabel(payment.status), style: text.bodySmall),
                          ],
                        ),
                        Text(Formatters.money(payment.amount.money), style: text.bodyMedium),
                        for (final refund in payment.refunds)
                          Text(
                            tr('Qaytarish: {p0} · {p1}', {
                              'p0': Formatters.money(refund.amount.money),
                              'p1': switch (refund.status) {
                                'succeeded' => 'bajarildi',
                                'failed' => tr('amalga oshmadi'),
                                _ => 'jarayonda',
                              },
                            }),
                            style: text.bodySmall?.copyWith(color: palette.textSecondary),
                          ),
                      ],
                    ),
                  ),
              ],
              if (p.status == PurchaseStatus.awaitingPayment) ...[
                const SizedBox(height: AppSpacing.xl),
                OutlinedButton(
                  onPressed: () async {
                    try {
                      await ref.read(monetizationRepositoryProvider).cancelPurchase(p.id);
                    } on Object {
                      if (context.mounted) showAppSnack(context, tr('Bekor qilib bo‘lmadi'));
                    }
                    ref
                      ..invalidate(purchaseDetailProvider(purchaseId))
                      ..invalidate(purchaseHistoryProvider);
                  },
                  child: Text(tr('To‘lovni bekor qilish')),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              Text(
                tr(
                  'Karta ma’lumotlari ilovada saqlanmaydi. Savollar bo‘lsa, qo‘llab-quvvatlash xizmatiga chek raqamini yuboring: {p0}',
                  {'p0': p.id.substring(0, 8)},
                ),
                style: text.bodySmall?.copyWith(color: palette.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Biznes uchun": FREE vs paid plans, all values from the server.
class BusinessPlansScreen extends ConsumerWidget {
  const BusinessPlansScreen({super.key});

  Future<void> _choose(BuildContext context, WidgetRef ref, Plan plan, PlanPrice price) async {
    if (ref.read(sessionProvider) == null) {
      await context.push<void>(AppRoutes.verifyThen(AppRoutes.businessPlans));
      return;
    }
    final controller = ref.read(checkoutControllerProvider.notifier);
    final probe = controller.request(method: PaymentMethod.dev, planPriceId: price.id);
    Quote quote;
    try {
      quote = await ref.read(monetizationRepositoryProvider).quote(probe);
    } on Object catch (error) {
      if (context.mounted) showAppSnack(context, error.asFailure().message);
      return;
    }
    if (!context.mounted) return;
    final methods = quote.methods.where((m) => m != PaymentMethod.credits && m != PaymentMethod.free).toList();
    if (methods.isEmpty) {
      showAppSnack(context, tr('Bu tarifni hozircha ushbu qurilmada sotib olib bo‘lmaydi'));
      return;
    }
    final method = methods.length == 1
        ? methods.first
        : await showModalBottomSheet<PaymentMethod>(
            context: context,
            builder: (sheet) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final m in methods) ListTile(title: Text(m.label), onTap: () => Navigator.of(sheet).pop(m)),
                ],
              ),
            ),
          );
    if (method == null || !context.mounted) return;
    final purchase = await openCheckout(
      context,
      controller.request(method: method, planPriceId: price.id),
      successTitle: tr('{title} tarifi faollashtirildi', {'title': tr(plan.title)}),
    );
    if (purchase != null) {
      ref
        ..invalidate(myEntitlementsProvider)
        ..invalidate(mySubscriptionsProvider)
        ..invalidate(purchaseHistoryProvider);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = ref.watch(plansProvider);
    final free = ref.watch(remoteConfigProvider).value?.freePlan;
    final current = ref.watch(myEntitlementsProvider).value?.planId ?? 'FREE';
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Biznes uchun'))),
      body: plans.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => FailureView(error: error, onRetry: () => ref.invalidate(plansProvider)),
        data: (plans) => ContentWidth(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Text(
                tr(
                  'Do‘kon sahifasi, kengaytirilgan statistika va jamoa bilan ishlash. Bepul imkoniyatlar saqlanib qoladi.',
                ),
                style: text.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.lg),
              _PlanCard(
                title: tr('Bepul'),
                current: current == 'FREE',
                rows: [
                  _limit(free?.activeListingLimit, tr('faol e’lon')),
                  if (free?.photoLimit != null) tr('E’londa {p0} tagacha rasm', {'p0': free!.photoLimit}),
                  tr('Asosiy statistika (7 kun)'),
                  tr('Chat, qidiruv, sevimlilar — cheksiz'),
                ],
              ),
              if (plans.isEmpty)
                EmptyState(
                  icon: Icons.workspace_premium_outlined,
                  title: tr('Biznes tariflar hali ishga tushmagan'),
                  compact: true,
                ),
              for (final plan in plans)
                _PlanCard(
                  title: tr(plan.title),
                  description: tr(plan.description),
                  current: current == plan.id,
                  rows: [
                    _limit(plan.entitlements.activeListingLimit, tr('faol e’lon')),
                    tr('E’londa {photoLimit} tagacha rasm', {'photoLimit': plan.entitlements.photoLimit}),
                    if (plan.entitlements.storefront) tr('Do‘kon sahifasi va havola'),
                    if (plan.entitlements.businessBadge) tr('Biznes belgisi'),
                    plan.entitlements.advancedAnalytics
                        ? tr('Kengaytirilgan statistika (90 kun)')
                        : tr('Asosiy statistika'),
                    if (plan.entitlements.maxManagers > 0)
                      tr('{maxManagers} tagacha menejer', {'maxManagers': plan.entitlements.maxManagers}),
                    if (plan.entitlements.monthlyPromotionCredits > 0)
                      tr('Har oy {monthlyPromotionCredits} ta reklama krediti', {
                        'monthlyPromotionCredits': plan.entitlements.monthlyPromotionCredits,
                      }),
                    if (plan.entitlements.prioritySupport) tr('Ustuvor qo‘llab-quvvatlash'),
                  ],
                  prices: plan.prices,
                  onChoose: (price) => _choose(context, ref, plan, price),
                ),
              const SizedBox(height: AppSpacing.md),
              Text(
                tr(
                  '«Tasdiqlangan biznes» belgisi pul evaziga berilmaydi — u faqat hujjatlar tekshirilgandan so‘ng qo‘yiladi.',
                ),
                style: text.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.title,
    required this.rows,
    required this.current,
    this.description,
    this.prices = const [],
    this.onChoose,
  });

  final String title;
  final String? description;
  final List<String> rows;
  final bool current;
  final List<PlanPrice> prices;
  final void Function(PlanPrice price)? onChoose;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: SurfaceCard(
        borderColor: current ? palette.primary : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: text.titleMedium)),
                if (current) StatusPill(label: tr('Joriy tarif'), style: PillStyle.primary, dense: true),
              ],
            ),
            if (description != null && description!.isNotEmpty) Text(description!, style: text.bodySmall),
            const SizedBox(height: AppSpacing.sm),
            for (final row in rows) MetaLine(icon: Icons.check_rounded, text: row, color: palette.textSecondary),
            if (!current && onChoose != null)
              for (final price in prices)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: FilledButton(
                    onPressed: () => onChoose!(price),
                    child: Text('${Formatters.money(price.price.money)} / ${price.periodLabel}'),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
