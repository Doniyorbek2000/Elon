import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/feature_flags.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/sheets.dart';
import '../../../core/widgets/state_views.dart';
import '../application/monetization_providers.dart';
import '../domain/monetization.dart';
import 'checkout_screen.dart';

/// "E’lonni tezroq soting": server products for one of the user's items.
/// Returns true when something was activated.
Future<bool> showPromoteSheet(
  BuildContext context, {
  required PromotionTarget target,
  required String targetId,
  required String itemTitle,
}) async {
  final purchase = await showAppSheet<Purchase>(
    context,
    expand: true,
    builder: (_) => PromoteSheet(target: target, targetId: targetId, itemTitle: itemTitle),
  );
  return purchase != null;
}

class PromoteSheet extends ConsumerStatefulWidget {
  const PromoteSheet({super.key, required this.target, required this.targetId, required this.itemTitle});

  final PromotionTarget target;
  final String targetId;
  final String itemTitle;

  @override
  ConsumerState<PromoteSheet> createState() => _PromoteSheetState();
}

class _PromoteSheetState extends ConsumerState<PromoteSheet> {
  String? _productId;
  PaymentMethod? _method;
  final _coupon = TextEditingController();
  Quote? _quote;
  String? _couponError;
  bool _quoting = false;

  @override
  void dispose() {
    _coupon.dispose();
    super.dispose();
  }

  OfferKey get _key => (target: widget.target, targetId: widget.targetId);

  String get _title => switch (widget.target) {
    PromotionTarget.job => tr('Vakansiyani ko‘proq odamga ko‘rsating'),
    PromotionTarget.provider => tr('Ko‘proq mijoz toping'),
    PromotionTarget.business => tr('Reklamani ishga tushirish'),
    _ => tr('E’lonni tezroq soting'),
  };

  bool _bumpBlocked(PromotionProduct product, PromotionOffer offer, DateTime now) =>
      product.kind.isBump && offer.bumpAvailableAt != null && offer.bumpAvailableAt!.isAfter(now);

  List<PaymentMethod> _methods(PromotionOffer offer, PromotionProduct? product) => [
    ...offer.methods.where((m) => m != PaymentMethod.credits && m != PaymentMethod.free),
    if (product?.creditCost != null && offer.creditsEnabled && offer.creditBalance >= product!.creditCost!)
      PaymentMethod.credits,
  ];

  Future<void> _applyCoupon(PromotionProduct product) async {
    setState(() {
      _quoting = true;
      _couponError = null;
    });
    try {
      final quote = await ref
          .read(monetizationRepositoryProvider)
          .quote(
            CheckoutRequest(
              method: PaymentMethod.dev,
              platform: ref.read(checkoutPlatformProvider),
              idempotencyKey: 'quote_only',
              productId: product.id,
              targetId: widget.targetId,
              couponCode: _coupon.text,
            ),
          );
      if (mounted) setState(() => _quote = quote);
    } on AppFailure catch (failure) {
      if (mounted) setState(() => _couponError = failure.message);
    } finally {
      if (mounted) setState(() => _quoting = false);
    }
  }

  Future<void> _continue(PromotionProduct product, PaymentMethod method) async {
    final request = ref
        .read(checkoutControllerProvider.notifier)
        .request(
          method: method,
          productId: product.id,
          targetId: widget.targetId,
          couponCode: method == PaymentMethod.credits || _quote == null ? null : _coupon.text,
        );
    final purchase = await openCheckout(context, request, successTitle: product.kind.activatedTitle);
    if (!mounted) return;
    ref.invalidate(promotionOfferProvider(_key));
    if (purchase != null) Navigator.of(context).pop(purchase);
  }

  @override
  Widget build(BuildContext context) {
    final offer = ref.watch(promotionOfferProvider(_key));
    final flags = ref.watch(featureFlagsProvider);
    final now = ref.watch(clockProvider)();
    final text = Theme.of(context).textTheme;
    final palette = context.palette;

    return offer.when(
      loading: () => SheetScaffold(
        title: _title,
        body: const Padding(
          padding: EdgeInsets.all(AppSpacing.huge),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (error, _) => SheetScaffold(
        title: _title,
        body: FailureView(error: error, compact: true, onRetry: () => ref.invalidate(promotionOfferProvider(_key))),
      ),
      data: (offer) {
        final products = offer.products;
        final selected = products.where((p) => p.id == _productId).firstOrNull;
        final methods = _methods(offer, selected);
        final method = methods.contains(_method) ? _method : methods.firstOrNull;
        final price = _quote != null && selected != null && method != PaymentMethod.credits
            ? _quote!.total
            : selected?.price;

        return SheetScaffold(
          title: _title,
          body: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xl),
            children: [
              Text(widget.itemTitle, style: text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: AppSpacing.md),
              if (!offer.eligible)
                EmptyState(
                  icon: Icons.info_outline_rounded,
                  title: tr('Faqat faol e’lonlarni targ‘ib qilish mumkin'),
                  compact: true,
                )
              else if (products.isEmpty)
                EmptyState(
                  icon: Icons.storefront_outlined,
                  title: tr('Hozircha takliflar yo‘q'),
                  message: tr('Targ‘ib qilish xizmatlari hali yoqilmagan.'),
                  compact: true,
                )
              else ...[
                for (final product in products)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: _ProductTile(
                      product: product,
                      selected: product.id == _productId,
                      disabledReason: _bumpBlocked(product, offer, now)
                          ? tr('Keyingi ko‘tarish: {p0}, {p1}', {
                              'p0': Formatters.date(offer.bumpAvailableAt!, now: now),
                              'p1': Formatters.clock(offer.bumpAvailableAt!),
                            })
                          : null,
                      onTap: () => setState(() {
                        _productId = product.id;
                        _quote = null;
                        _couponError = null;
                      }),
                    ),
                  ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  tr(
                    'Ko‘rsatilish va ko‘rishlar soni kafolatlanmaydi. Reklama e’lonlari «TOP», «VIP» yoki «Tavsiya» belgisi bilan ko‘rsatiladi.',
                  ),
                  style: text.bodySmall?.copyWith(color: palette.textSecondary),
                ),
                if (selected != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Text(tr('To‘lov usuli'), style: text.titleSmall),
                  const SizedBox(height: AppSpacing.sm),
                  if (methods.isEmpty)
                    SurfaceCard(
                      color: palette.surfaceMuted,
                      child: Text(
                        tr('Bu xizmatni hozircha ushbu qurilmada sotib olib bo‘lmaydi.'),
                        style: text.bodyMedium,
                      ),
                    )
                  else
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        for (final m in methods)
                          ChoiceChip(
                            label: Text(
                              m == PaymentMethod.credits
                                  ? tr('Kredit ({creditCost} ta, balans {creditBalance})', {
                                      'creditCost': selected.creditCost,
                                      'creditBalance': offer.creditBalance,
                                    })
                                  : m.label,
                            ),
                            selected: m == method,
                            onSelected: (_) => setState(() => _method = m),
                          ),
                      ],
                    ),
                  if (flags.coupons && method != PaymentMethod.credits && methods.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.lg),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _coupon,
                            textCapitalization: TextCapitalization.characters,
                            decoration: InputDecoration(labelText: tr('Promo kod'), errorText: _couponError),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.xs),
                          child: OutlinedButton(
                            onPressed: _quoting || _coupon.text.trim().length < 3 ? null : () => _applyCoupon(selected),
                            child: Text(tr('Qo‘llash')),
                          ),
                        ),
                      ],
                    ),
                    if (_quote != null && !_quote!.discount.isZero)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xs),
                        child: Text(
                          tr('Chegirma: −{p0}', {'p0': Formatters.money(_quote!.discount.money)}),
                          style: text.bodySmall?.copyWith(color: palette.success),
                        ),
                      ),
                  ],
                ],
              ],
            ],
          ),
          actions: selected == null || method == null
              ? null
              : FilledButton(
                  onPressed: _quoting ? null : () => _continue(selected, method),
                  child: Text(
                    method == PaymentMethod.credits
                        ? tr('Davom etish · {creditCost} kredit', {'creditCost': selected.creditCost})
                        : tr('Davom etish · {p0}', {'p0': Formatters.money(price!.money)}),
                  ),
                ),
        );
      },
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product, required this.selected, required this.onTap, this.disabledReason});

  final PromotionProduct product;
  final bool selected;
  final String? disabledReason;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = Theme.of(context).textTheme;
    final disabled = disabledReason != null;
    final duration = product.durationDays == null
        ? null
        : tr('{durationDays} kun', {'durationDays': product.durationDays});
    return Semantics(
      selected: selected,
      enabled: !disabled,
      child: SurfaceCard(
        borderColor: selected ? palette.primary : null,
        color: selected ? palette.primarySoft : null,
        onTap: disabled ? null : onTap,
        child: Opacity(
          opacity: disabled ? 0.55 : 1,
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                color: selected ? palette.primary : palette.textTertiary,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text([tr(product.title), ?duration].join(' · '), style: text.titleSmall),
                    Text(disabledReason ?? tr(product.description), style: text.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(Formatters.money(product.price.money), style: text.titleSmall?.copyWith(color: palette.price)),
            ],
          ),
        ),
      ),
    );
  }
}
