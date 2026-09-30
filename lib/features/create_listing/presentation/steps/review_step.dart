import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/app_colors.dart';
import '../../../../core/design/app_tokens.dart';
import '../../../../core/domain/media_image.dart';
import '../../../../core/domain/public_profile.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/utils/clock.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/common.dart';
import '../../../auth/application/session_controller.dart';
import '../../../catalog/application/catalog_providers.dart';
import '../../../listings/domain/listing.dart';
import '../../../listings/presentation/widgets/listing_cards.dart';
import '../../../trust_safety/domain/trust_safety.dart';
import '../../application/create_listing_controller.dart';
import '../../domain/listing_draft.dart';

/// Step 3: preview exactly as buyers will see it, summary with quick edits,
/// and pre-publish safety checks.
class ReviewStep extends ConsumerWidget {
  const ReviewStep({super.key});

  Listing _preview(ListingDraft draft, WidgetRef ref) {
    final user = ref.read(sessionProvider);
    final now = ref.read(clockProvider)();
    return Listing(
      id: 'preview',
      title: draft.title.trim().isEmpty ? tr('Sarlavha') : draft.title.trim(),
      description: draft.description,
      categoryId: draft.categoryId ?? 'other',
      images: [for (final p in draft.photos) MediaImage.local(p.id, p.localPath)],
      place: draft.place!,
      publishedAt: now,
      seller: user?.toPublic() ?? PublicProfile(id: 'guest', name: 'Siz', memberSince: now),
      price: draft.negotiable && draft.price == null ? null : draft.money,
      negotiable: draft.negotiable,
      condition: draft.condition,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(createListingProvider);
    final controller = ref.read(createListingProvider.notifier);
    final tree = ref.watch(categoryTreeProvider);
    final category = tree.byId(draft.categoryId);
    final schema = controller.schema;
    final signals = controller.riskSignals();
    final moderation = ListingRiskAssessor.requiresModeration(signals);
    final palette = context.palette;
    final text = Theme.of(context).textTheme;

    final priceLabel = switch (draft) {
      ListingDraft(price: null, negotiable: true) => tr('Kelishiladi'),
      ListingDraft(price: null) => '—',
      _ when schema.priceLabel == 'Maosh' => Formatters.salaryRange(draft.price, draft.priceMax, draft.currency),
      _ => '${Formatters.money(draft.money!)}${draft.negotiable ? ' · kelishiladi' : ''}',
    };

    final rows = <(String, String, CreateStep)>[
      (
        tr('Kategoriya'),
        [?tree.parentOf(draft.categoryId ?? '')?.name, ?category?.name].join(' › '),
        CreateStep.details,
      ),
      (tr('Sarlavha'), draft.title, CreateStep.details),
      (schema.priceLabel, priceLabel, CreateStep.details),
      if (draft.condition != null) (tr('Holati'), draft.condition!.label, CreateStep.details),
      for (final field in schema.fields)
        if (draft.attributes[field.key] case final String value)
          (
            tr(field.label),
            field.unit == null ? trValue(value) : '${trValue(value)} ${tr(field.unit!)}',
            CreateStep.details,
          ),
      (tr('Manzil'), draft.place?.fullLabel ?? '—', CreateStep.details),
      (tr('Rasmlar'), tr('{length} ta', {'length': draft.photos.length}), CreateStep.photos),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xxxl),
      children: [
        Text(tr('Xaridorlar e’loningizni shunday ko‘radi'), style: text.titleSmall),
        const SizedBox(height: AppSpacing.md),
        if (draft.place != null)
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: ListingCard(listing: _preview(draft, ref), heroPrefix: 'preview'),
                ),
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.xl),
        SurfaceCard(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Column(
            children: [
              for (final (label, value, step) in rows)
                ListTile(
                  dense: true,
                  title: Text(label, style: text.bodySmall),
                  subtitle: Text(
                    value.isEmpty ? '—' : value,
                    style: text.bodyMedium?.copyWith(color: palette.textPrimary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: TextButton(onPressed: () => controller.goTo(step), child: Text(tr('Tahrirlash'))),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('Tavsif'), style: text.bodySmall),
              const SizedBox(height: AppSpacing.xs),
              Text(draft.description, style: text.bodyMedium, maxLines: 6, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        if (signals.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          for (final signal in signals)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _SignalCard(signal: signal),
            ),
        ],
        const SizedBox(height: AppSpacing.lg),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              moderation ? Icons.hourglass_top_rounded : Icons.verified_user_outlined,
              size: AppIconSize.sm,
              color: moderation ? palette.warning : palette.success,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                moderation
                    ? tr('E’lon joylangandan so‘ng moderator tomonidan tekshiriladi (odatda 15 daqiqagacha).')
                    : tr('E’lon darhol faol bo‘ladi. Qoidalarni buzgan e’lonlar o‘chiriladi.'),
                style: text.bodySmall,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SignalCard extends StatelessWidget {
  const _SignalCard({required this.signal});

  final RiskSignal signal;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final (bg, fg, icon) = switch (signal.severity) {
      RiskSeverity.blocking => (palette.dangerSoft, palette.danger, Icons.gpp_bad_outlined),
      RiskSeverity.warning => (palette.warningSoft, palette.warning, Icons.warning_amber_rounded),
      RiskSeverity.info => (palette.primarySoft, palette.primary, Icons.lightbulb_outline_rounded),
    };
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: bg, borderRadius: AppRadii.mdAll),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: fg, size: AppIconSize.md),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              signal.message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: palette.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
