import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/config/feature_flags.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/sharing/share_service.dart';
import '../../../core/sharing/share_sheet.dart';
import '../../../core/utils/external_actions.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/avatar.dart';
import '../../../core/widgets/badges.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/state_views.dart';
import '../../jobs/presentation/widgets/job_cards.dart';
import '../../listings/presentation/widgets/listing_cards.dart';
import '../../location/application/location_controller.dart';
import '../../monetization/domain/monetization.dart';
import '../../monetization/presentation/promote_sheet.dart';
import '../../services/presentation/widgets/provider_cards.dart';
import '../application/business_providers.dart';
import '../domain/business.dart';

// ───────────────────────────────────────────────────────────── my business

class MyBusinessScreen extends ConsumerWidget {
  const MyBusinessScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flags = ref.watch(featureFlagsProvider);
    final mine = ref.watch(myBusinessProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Biznes profil')),
      body: mine.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => FailureView(error: error, onRetry: () => ref.invalidate(myBusinessProvider)),
        data: (business) => business == null
            ? EmptyState(
                icon: Icons.storefront_outlined,
                title: 'Biznesingizni Bozor’da tanishtiring',
                message: flags.businessAccounts
                    ? 'Biznes profil bepul. Do‘kon sahifasi va kengaytirilgan statistika biznes tariflarida mavjud.'
                    : 'Biznes profillar tez orada ishga tushadi.',
                actionLabel: flags.businessAccounts ? 'Biznes profil yaratish' : null,
                onAction: flags.businessAccounts ? () => context.push(AppRoutes.businessEditor) : null,
              )
            : _BusinessDashboard(mine: business),
      ),
    );
  }
}

class _BusinessDashboard extends ConsumerWidget {
  const _BusinessDashboard({required this.mine});

  final MyBusiness mine;

  Future<void> _run(BuildContext context, WidgetRef ref, Future<Object?> Function() action, String done) async {
    try {
      await action();
      ref.invalidate(myBusinessProvider);
      if (context.mounted) showAppSnack(context, done, icon: Icons.check_rounded);
    } on Object catch (error) {
      if (context.mounted) showAppSnack(context, error.asFailure().message);
    }
  }

  Future<void> _addManager(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final phone = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Menejer qo‘shish'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Telefon raqami', hintText: '+998 90 123 45 67'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Bekor qilish')),
          FilledButton(onPressed: () => Navigator.pop(dialog, controller.text), child: const Text('Qo‘shish')),
        ],
      ),
    );
    controller.dispose();
    if (phone == null || phone.trim().isEmpty || !context.mounted) return;
    await _run(context, ref, () => ref.read(businessRepositoryProvider).addManager(phone.trim()), 'Menejer qo‘shildi');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flags = ref.watch(featureFlagsProvider);
    final business = mine.business;
    final text = Theme.of(context).textTheme;
    final palette = context.palette;
    return RefreshIndicator.adaptive(
      onRefresh: () async => ref.invalidate(myBusinessProvider),
      child: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            SurfaceCard(
              child: Row(
                children: [
                  AppAvatar(name: business.name, image: business.logo, size: 56),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(business.name, style: text.titleMedium),
                        const SizedBox(height: AppSpacing.xs),
                        Wrap(
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xs,
                          children: [
                            StatusPill(
                              label: business.verificationLabel,
                              style: business.verified ? PillStyle.success : PillStyle.neutral,
                              icon: business.verified ? Icons.verified_rounded : null,
                              dense: true,
                            ),
                            StatusPill(label: 'Tarif: ${mine.planTitle}', style: PillStyle.primary, dense: true),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            if (mine.isOwner)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Ma’lumotlarni tahrirlash'),
                onTap: () => context.push(AppRoutes.businessEditor, extra: business),
              ),
            if (mine.isOwner && !business.verified && business.verification != 'pending')
              ListTile(
                leading: const Icon(Icons.verified_outlined),
                title: const Text('Tasdiqlashni so‘rash'),
                subtitle: const Text('Belgi faqat moderator tekshiruvidan so‘ng beriladi'),
                onTap: () => _run(
                  context,
                  ref,
                  () => ref.read(businessRepositoryProvider).requestVerification(),
                  'So‘rov yuborildi',
                ),
              ),
            ListTile(
              leading: const Icon(Icons.storefront_outlined),
              title: const Text('Do‘kon sahifasi'),
              subtitle: Text(mine.storefront ? 'Ochiq · havolani ulashing' : 'Biznes tarifida mavjud'),
              onTap: () => mine.storefront
                  ? context.push(AppRoutes.business(business.id))
                  : context.push(AppRoutes.businessPlans),
            ),
            if (flags.canAdvertise)
              ListTile(
                leading: const Icon(Icons.campaign_outlined),
                title: const Text('Mahalliy reklama'),
                onTap: () => context.push(AppRoutes.businessAds),
              ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Row(
                children: [
                  Expanded(child: Text('Jamoa', style: text.titleSmall)),
                  Text('${mine.managerCount} / ${mine.maxManagers} menejer', style: text.bodySmall),
                ],
              ),
            ),
            for (final member in mine.members)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: AppAvatar(name: member.name, size: 40),
                title: Text(member.name.isEmpty ? 'Foydalanuvchi' : member.name),
                subtitle: Text(member.role.label),
                trailing: mine.isOwner && member.role == BusinessRole.manager
                    ? IconButton(
                        tooltip: 'Olib tashlash',
                        icon: Icon(Icons.person_remove_outlined, color: palette.danger),
                        onPressed: () => _run(
                          context,
                          ref,
                          () => ref.read(businessRepositoryProvider).removeManager(member.userId),
                          'Menejer olib tashlandi',
                        ),
                      )
                    : null,
              ),
            if (mine.isOwner)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: mine.managerCount < mine.maxManagers
                      ? () => _addManager(context, ref)
                      : () => context.push(AppRoutes.businessPlans),
                  icon: const Icon(Icons.person_add_alt_rounded),
                  label: Text(mine.managerCount < mine.maxManagers ? 'Menejer qo‘shish' : 'Ko‘proq menejer — tariflar'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────── editor

class BusinessEditorScreen extends ConsumerStatefulWidget {
  const BusinessEditorScreen({super.key, this.initial});

  final Business? initial;

  @override
  ConsumerState<BusinessEditorScreen> createState() => _BusinessEditorScreenState();
}

class _BusinessEditorScreenState extends ConsumerState<BusinessEditorScreen> {
  late final _name = TextEditingController(text: widget.initial?.name);
  late final _description = TextEditingController(text: widget.initial?.description);
  late final _phone = TextEditingController(text: widget.initial?.phone);
  late final _telegram = TextEditingController(text: widget.initial?.telegram);
  late final _website = TextEditingController(text: widget.initial?.website);
  late final _address = TextEditingController(text: widget.initial?.address);
  late final _hours = TextEditingController(text: widget.initial?.openingHours);
  bool _saving = false;
  Map<String, String> _errors = const {};

  @override
  void dispose() {
    for (final c in [_name, _description, _phone, _telegram, _website, _address, _hours]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().length < 2) {
      setState(() => _errors = {'name': 'Nom kamida 2 ta belgidan iborat bo‘lsin'});
      return;
    }
    final location = ref.read(locationProvider);
    final draft = BusinessDraft(
      name: _name.text,
      description: _description.text,
      regionId: widget.initial?.place.regionId ?? location.regionId,
      districtId: widget.initial?.place.districtId ?? location.districtId,
      phone: _phone.text,
      telegram: _telegram.text,
      website: _website.text,
      address: _address.text,
      openingHours: _hours.text,
    );
    setState(() {
      _saving = true;
      _errors = const {};
    });
    final repository = ref.read(businessRepositoryProvider);
    try {
      if (widget.initial == null) {
        await repository.create(draft);
      } else {
        await repository.update(draft);
      }
      ref.invalidate(myBusinessProvider);
      if (!mounted) return;
      context.pop();
      showAppSnack(context, 'Saqlandi', icon: Icons.check_rounded);
    } on ValidationFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errors = failure.fieldErrors.isEmpty ? {'name': failure.message} : failure.fieldErrors;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppSnack(context, error.asFailure().message);
    }
  }

  Widget _field(
    TextEditingController controller,
    String key,
    String label, {
    String? hint,
    TextInputType? type,
    int lines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.lg),
    child: TextField(
      controller: controller,
      keyboardType: type,
      minLines: lines,
      maxLines: lines == 1 ? 1 : lines + 3,
      decoration: InputDecoration(labelText: label, hintText: hint, errorText: _errors[key]),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final location = ref.watch(locationProvider);
    return Scaffold(
      appBar: AppBar(title: Text(widget.initial == null ? 'Biznes profil yaratish' : 'Biznes ma’lumotlari')),
      body: ContentWidth(
        maxWidth: AppBreakpoints.formMaxWidth,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            _field(_name, 'name', 'Biznes nomi'),
            _field(_description, 'description', 'Tavsif', lines: 3),
            _field(_phone, 'phone', 'Telefon', hint: '+998 90 123 45 67', type: TextInputType.phone),
            _field(_telegram, 'telegram', 'Telegram', hint: '@username'),
            _field(_website, 'website', 'Veb-sayt', hint: 'https://…', type: TextInputType.url),
            _field(_address, 'address', 'Manzil'),
            _field(_hours, 'openingHours', 'Ish vaqti', hint: 'Du–Sh 09:00–19:00'),
            if (widget.initial == null) MetaLine(icon: Icons.location_on_outlined, text: 'Hudud: ${location.label}'),
            const SizedBox(height: AppSpacing.xl),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
                  : const Text('Saqlash'),
            ),
            if (widget.initial?.verified ?? false)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.md),
                child: Text(
                  'Nomni o‘zgartirsangiz, tasdiqlash qayta tekshiriladi.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────── storefront

/// Public storefront, deep link `/business/:id`.
class StorefrontScreen extends ConsumerWidget {
  const StorefrontScreen({super.key, required this.businessId});

  final String businessId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(storefrontProvider(businessId));
    final listings = ref.watch(storefrontListingsProvider(businessId));
    final text = Theme.of(context).textTheme;
    final palette = context.palette;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Do‘kon'),
        actions: [
          if (store.value != null)
            IconButton(
              tooltip: 'Ulashish',
              icon: const Icon(Icons.ios_share_rounded),
              onPressed: () => showShareSheet(
                context,
                SharePayload(
                  target: ShareTarget.business,
                  id: businessId,
                  title: '${store.value!.business.name} — Bozor.uz',
                  image: store.value!.business.logo,
                  url: ref.read(deepLinksProvider).web(ShareTarget.business, businessId),
                ),
              ),
            ),
        ],
      ),
      body: store.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => FailureView(error: error, onRetry: () => ref.invalidate(storefrontProvider(businessId))),
        data: (store) {
          final b = store.business;
          return RefreshIndicator.adaptive(
            onRefresh: () async => ref
              ..invalidate(storefrontProvider(businessId))
              ..invalidate(storefrontListingsProvider(businessId)),
            child: ContentWidth(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  Row(
                    children: [
                      AppAvatar(name: b.name, image: b.logo, size: 72),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(b.name, style: text.titleLarge),
                            const SizedBox(height: AppSpacing.xs),
                            Wrap(
                              spacing: AppSpacing.xs,
                              runSpacing: AppSpacing.xs,
                              children: [
                                if (b.verified)
                                  const StatusPill(
                                    label: 'Tasdiqlangan biznes',
                                    style: PillStyle.success,
                                    icon: Icons.verified_rounded,
                                    dense: true,
                                  ),
                                if (b.businessBadge && !b.verified)
                                  const StatusPill(label: 'Biznes', style: PillStyle.primary, dense: true),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            if (store.rating != null)
                              RatingLabel(rating: store.rating!, count: store.reviewCount, compact: true)
                            else
                              Text('Hali sharhlar yo‘q', style: text.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (b.description.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.lg),
                    Text(b.description, style: text.bodyMedium),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  MetaLine(icon: Icons.location_on_outlined, text: [b.place.shortLabel, ?b.address].join(', ')),
                  if (b.openingHours != null) MetaLine(icon: Icons.schedule_rounded, text: b.openingHours!),
                  MetaLine(icon: Icons.inventory_2_outlined, text: '${store.activeListings} ta faol e’lon'),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      if (b.phone != null)
                        FilledButton.icon(
                          onPressed: () => ref.read(externalActionsProvider).call(b.phone!),
                          icon: const Icon(Icons.call_rounded),
                          label: const Text('Qo‘ng‘iroq'),
                        ),
                      if (b.telegram != null)
                        OutlinedButton.icon(
                          onPressed: () =>
                              ref.read(externalActionsProvider).openUrl(Uri.parse('https://t.me/${b.telegram}')),
                          icon: const Icon(Icons.send_rounded),
                          label: const Text('Telegram'),
                        ),
                      if (b.website != null)
                        OutlinedButton.icon(
                          onPressed: () => ref.read(externalActionsProvider).openUrl(Uri.parse(b.website!)),
                          icon: const Icon(Icons.language_rounded),
                          label: const Text('Sayt'),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text('E’lonlar', style: text.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  listings.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.all(AppSpacing.xl),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (error, _) => FailureView(error: error, compact: true),
                    data: (page) => page.items.isEmpty
                        ? Text('Hozircha e’lonlar yo‘q', style: text.bodySmall?.copyWith(color: palette.textSecondary))
                        : Column(
                            children: [
                              for (final listing in page.items) ListingTile(listing: listing, heroPrefix: 'store'),
                            ],
                          ),
                  ),
                  if (store.jobs.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xl),
                    Text('Vakansiyalar', style: text.titleMedium),
                    const SizedBox(height: AppSpacing.sm),
                    for (final job in store.jobs)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: JobCard(job: job),
                      ),
                  ],
                  if (store.providers.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xl),
                    Text('Xizmatlar', style: text.titleMedium),
                    const SizedBox(height: AppSpacing.sm),
                    for (final provider in store.providers)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: ProviderTile(provider: provider),
                      ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'A’zo: ${Formatters.monthYear(b.memberSince)}',
                    style: text.bodySmall?.copyWith(color: palette.textSecondary),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────── ads

class CampaignsScreen extends ConsumerWidget {
  const CampaignsScreen({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref, MyBusiness mine) async {
    final title = TextEditingController();
    final body = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Yangi reklama'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: title,
              maxLength: 60,
              decoration: const InputDecoration(labelText: 'Sarlavha'),
            ),
            TextField(
              controller: body,
              maxLength: 160,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Matn'),
            ),
            Text(
              'Reklama do‘kon sahifangizga olib boradi va «${mine.business.place.regionName}» hududida '
              '«Reklama» belgisi bilan ko‘rsatiladi. Moderator tekshiradi.',
              style: Theme.of(dialog).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Bekor qilish')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Yaratish')),
        ],
      ),
    );
    final values = (title.text, body.text);
    title.dispose();
    body.dispose();
    if (ok != true || !context.mounted) return;
    try {
      final campaign = await ref
          .read(businessRepositoryProvider)
          .createCampaign(
            title: values.$1,
            body: values.$2,
            destination: 'business',
            destinationId: mine.business.id,
            regionId: mine.business.place.regionId,
          );
      ref.invalidate(campaignsProvider);
      if (context.mounted) await _pay(context, ref, campaign);
    } on Object catch (error) {
      if (context.mounted) showAppSnack(context, error.asFailure().message);
    }
  }

  Future<void> _pay(BuildContext context, WidgetRef ref, AdCampaign campaign) async {
    final paid = await showPromoteSheet(
      context,
      target: PromotionTarget.business,
      targetId: campaign.id,
      itemTitle: campaign.title,
    );
    if (paid) ref.invalidate(campaignsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = ref.watch(myBusinessProvider).value;
    final campaigns = ref.watch(campaignsProvider);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Mahalliy reklama')),
      floatingActionButton: mine == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _create(context, ref, mine),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Reklama yaratish'),
            ),
      body: campaigns.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => FailureView(error: error, onRetry: () => ref.invalidate(campaignsProvider)),
        data: (items) => items.isEmpty
            ? const EmptyState(
                icon: Icons.campaign_outlined,
                title: 'Reklamalar yo‘q',
                message: 'Hududingizdagi xaridorlarga do‘koningizni ko‘rsating.',
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 96),
                children: [
                  for (final c in items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: SurfaceCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(child: Text(c.title, style: text.titleSmall)),
                                StatusPill(label: c.statusLabel, dense: true),
                              ],
                            ),
                            Text(c.body, style: text.bodySmall),
                            const SizedBox(height: AppSpacing.sm),
                            Text('Ko‘rsatildi: ${c.impressions} · Bosildi: ${c.clicks}', style: text.bodySmall),
                            if (c.rejectReason != null) Text('Sabab: ${c.rejectReason}', style: text.bodySmall),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (c.payable)
                                  TextButton(onPressed: () => _pay(context, ref, c), child: const Text('To‘lash')),
                                if (c.status == 'active' || c.status == 'paused')
                                  TextButton(
                                    onPressed: () async {
                                      try {
                                        await ref
                                            .read(businessRepositoryProvider)
                                            .setCampaignPaused(c.id, paused: c.status == 'active');
                                        ref.invalidate(campaignsProvider);
                                      } on Object catch (error) {
                                        if (context.mounted) showAppSnack(context, error.asFailure().message);
                                      }
                                    },
                                    child: Text(c.status == 'active' ? 'To‘xtatish' : 'Davom ettirish'),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────── listing stats

/// Seller analytics from real counted events only.
class ListingStatsScreen extends ConsumerStatefulWidget {
  const ListingStatsScreen({super.key, required this.listingId});

  final String listingId;

  @override
  ConsumerState<ListingStatsScreen> createState() => _ListingStatsScreenState();
}

class _ListingStatsScreenState extends ConsumerState<ListingStatsScreen> {
  int _days = 7;

  @override
  Widget build(BuildContext context) {
    final stats = ref.watch(listingStatsProvider((listingId: widget.listingId, days: _days)));
    final promotions = (ref.watch(myPromotionsProvider).value ?? const [])
        .where((p) => p.targetId == widget.listingId && p.kind != 'listingBump')
        .toList();
    final text = Theme.of(context).textTheme;
    final palette = context.palette;
    return Scaffold(
      appBar: AppBar(title: const Text('E’lon statistikasi')),
      body: stats.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => FailureView(
          error: error,
          onRetry: () => ref.invalidate(listingStatsProvider((listingId: widget.listingId, days: _days))),
        ),
        data: (s) => ContentWidth(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              if (s.advanced)
                ChoiceChipsRow<int>(
                  padding: EdgeInsets.zero,
                  items: const [7, 30, 90],
                  selected: _days,
                  labelOf: (d) => '$d kun',
                  onSelected: (d) => setState(() => _days = d),
                )
              else
                Text('So‘nggi 7 kun', style: text.titleSmall),
              const SizedBox(height: AppSpacing.md),
              _TotalsGrid(totals: s.totals),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Jami: ${s.lifetimeViews} ko‘rish · ${s.lifetimeFavorites} sevimli',
                style: text.bodySmall?.copyWith(color: palette.textSecondary),
              ),
              if (s.advanced && s.daily.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xl),
                Text('Kunlik ko‘rishlar', style: text.titleSmall),
                const SizedBox(height: AppSpacing.sm),
                _DailyBars(days: s.daily),
              ],
              if (!s.advanced) ...[
                const SizedBox(height: AppSpacing.xl),
                SurfaceCard(
                  color: palette.surfaceMuted,
                  onTap: ref.watch(featureFlagsProvider).canBuyPlans
                      ? () => context.push(AppRoutes.businessPlans)
                      : null,
                  child: Text(
                    'Kunlik grafik va 90 kunlik statistika biznes tariflarida mavjud.',
                    style: text.bodyMedium,
                  ),
                ),
              ],
              if (promotions.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xl),
                Text('Targ‘ibot natijalari', style: text.titleSmall),
                for (final p in promotions) _PromotionResultTile(promotion: p),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TotalsGrid extends StatelessWidget {
  const _TotalsGrid({required this.totals});

  final StatTotals totals;

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.visibility_outlined, 'Ko‘rishlar', totals.views),
      (Icons.favorite_border_rounded, 'Sevimlilar', totals.favorites),
      (Icons.call_outlined, 'Raqam ko‘rildi', totals.contacts),
      (Icons.chat_bubble_outline_rounded, 'Chatlar', totals.chats),
      (Icons.ios_share_rounded, 'Ulashishlar', totals.shares),
    ];
    final text = Theme.of(context).textTheme;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final (icon, label, value) in items)
          SizedBox(
            width: 160,
            child: SurfaceCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Semantics(
                label: '$label: $value',
                excludeSemantics: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, size: AppIconSize.sm),
                    const SizedBox(height: AppSpacing.xs),
                    Text('$value', style: text.titleLarge),
                    Text(label, style: text.bodySmall),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _DailyBars extends StatelessWidget {
  const _DailyBars({required this.days});

  final List<({String day, StatTotals totals})> days;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final max = days.fold<int>(1, (m, d) => d.totals.views > m ? d.totals.views : m);
    return SizedBox(
      height: 120,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final d in days)
            Expanded(
              child: Tooltip(
                message: '${d.day}: ${d.totals.views}',
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  height: 4 + 116 * d.totals.views / max,
                  decoration: BoxDecoration(
                    color: palette.primary,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PromotionResultTile extends ConsumerWidget {
  const _PromotionResultTile({required this.promotion});

  final MyPromotion promotion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(promotionResultsProvider(promotion.id)).value;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(promotion.title, style: text.titleSmall),
            if (results != null) ...[
              Text(
                'Davomida: ${results.during.views} ko‘rish, ${results.during.contacts} raqam, ${results.during.chats} chat',
              ),
              if (results.comparable && results.before != null)
                Text('Oldingi shuncha davr: ${results.before!.views} ko‘rish, ${results.before!.contacts} raqam')
              else
                Text('Taqqoslash uchun oldingi davr ma’lumoti yetarli emas.', style: text.bodySmall),
              Text('Bu hisoblangan hodisalar, kafolat yoki bashorat emas.', style: text.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}
