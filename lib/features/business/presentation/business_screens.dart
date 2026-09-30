import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/l10n/l10n.dart';
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
import '../../services/presentation/widgets/provider_cards.dart';
import '../application/business_providers.dart';
import '../domain/business.dart';

// ───────────────────────────────────────────────────────────── my business

class MyBusinessScreen extends ConsumerWidget {
  const MyBusinessScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = ref.watch(myBusinessProvider);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Biznes profil'))),
      body: mine.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => FailureView(error: error, onRetry: () => ref.invalidate(myBusinessProvider)),
        data: (business) => business == null
            ? EmptyState(
                icon: Icons.storefront_outlined,
                title: tr('Biznesingizni Bozor’da tanishtiring'),
                message: tr('Biznes profil, do‘kon sahifasi va statistika bepul.'),
                actionLabel: tr('Biznes profil yaratish'),
                onAction: () => context.push(AppRoutes.businessEditor),
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
        title: Text(tr('Menejer qo‘shish')),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(labelText: tr('Telefon raqami'), hintText: '+998 90 123 45 67'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog), child: Text(tr('Bekor qilish'))),
          FilledButton(onPressed: () => Navigator.pop(dialog, controller.text), child: Text(tr('Qo‘shish'))),
        ],
      ),
    );
    controller.dispose();
    if (phone == null || phone.trim().isEmpty || !context.mounted) return;
    await _run(
      context,
      ref,
      () => ref.read(businessRepositoryProvider).addManager(phone.trim()),
      tr('Menejer qo‘shildi'),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                title: Text(tr('Ma’lumotlarni tahrirlash')),
                onTap: () => context.push(AppRoutes.businessEditor, extra: business),
              ),
            if (mine.isOwner && !business.verified && business.verification != 'pending')
              ListTile(
                leading: const Icon(Icons.verified_outlined),
                title: Text(tr('Tasdiqlashni so‘rash')),
                subtitle: Text(tr('Belgi faqat moderator tekshiruvidan so‘ng beriladi')),
                onTap: () => _run(
                  context,
                  ref,
                  () => ref.read(businessRepositoryProvider).requestVerification(),
                  tr('So‘rov yuborildi'),
                ),
              ),
            ListTile(
              leading: const Icon(Icons.storefront_outlined),
              title: Text(tr('Do‘kon sahifasi')),
              subtitle: Text(tr('Ochiq · havolani ulashing')),
              onTap: () => context.push(AppRoutes.business(business.id)),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Row(
                children: [
                  Expanded(child: Text(tr('Jamoa'), style: text.titleSmall)),
                  Text(
                    tr('{managerCount} / {maxManagers} menejer', {
                      'managerCount': mine.managerCount,
                      'maxManagers': mine.maxManagers,
                    }),
                    style: text.bodySmall,
                  ),
                ],
              ),
            ),
            for (final member in mine.members)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: AppAvatar(name: member.name, size: 40),
                title: Text(member.name.isEmpty ? tr('Foydalanuvchi') : member.name),
                subtitle: Text(member.role.label),
                trailing: mine.isOwner && member.role == BusinessRole.manager
                    ? IconButton(
                        tooltip: tr('Olib tashlash'),
                        icon: Icon(Icons.person_remove_outlined, color: palette.danger),
                        onPressed: () => _run(
                          context,
                          ref,
                          () => ref.read(businessRepositoryProvider).removeManager(member.userId),
                          tr('Menejer olib tashlandi'),
                        ),
                      )
                    : null,
              ),
            if (mine.isOwner)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: mine.managerCount < mine.maxManagers ? () => _addManager(context, ref) : null,
                  icon: const Icon(Icons.person_add_alt_rounded),
                  label: Text(tr('Menejer qo‘shish')),
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
      setState(() => _errors = {'name': tr('Nom kamida 2 ta belgidan iborat bo‘lsin')});
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
      showAppSnack(context, tr('Saqlandi'), icon: Icons.check_rounded);
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
      appBar: AppBar(title: Text(widget.initial == null ? tr('Biznes profil yaratish') : tr('Biznes ma’lumotlari'))),
      body: ContentWidth(
        maxWidth: AppBreakpoints.formMaxWidth,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            _field(_name, 'name', tr('Biznes nomi')),
            _field(_description, 'description', tr('Tavsif'), lines: 3),
            _field(_phone, 'phone', tr('Telefon'), hint: '+998 90 123 45 67', type: TextInputType.phone),
            _field(_telegram, 'telegram', 'Telegram', hint: '@username'),
            _field(_website, 'website', tr('Veb-sayt'), hint: 'https://…', type: TextInputType.url),
            _field(_address, 'address', tr('Manzil')),
            _field(_hours, 'openingHours', tr('Ish vaqti'), hint: tr('Du–Sh 09:00–19:00')),
            if (widget.initial == null)
              MetaLine(icon: Icons.location_on_outlined, text: tr('Hudud: {label}', {'label': location.label})),
            const SizedBox(height: AppSpacing.xl),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
                  : Text(tr('Saqlash')),
            ),
            if (widget.initial?.verified ?? false)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.md),
                child: Text(
                  tr('Nomni o‘zgartirsangiz, tasdiqlash qayta tekshiriladi.'),
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
        title: Text(tr('Do‘kon')),
        actions: [
          if (store.value != null)
            IconButton(
              tooltip: tr('Ulashish'),
              icon: const Icon(Icons.ios_share_rounded),
              onPressed: () => showShareSheet(
                context,
                SharePayload(
                  target: ShareTarget.business,
                  id: businessId,
                  title: tr('{p0} — Bozor.uz', {'p0': store.value!.business.name}),
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
                                  StatusPill(
                                    label: tr('Tasdiqlangan biznes'),
                                    style: PillStyle.success,
                                    icon: Icons.verified_rounded,
                                    dense: true,
                                  ),
                                if (b.businessBadge && !b.verified)
                                  StatusPill(label: tr('Biznes'), style: PillStyle.primary, dense: true),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            if (store.rating != null)
                              RatingLabel(rating: store.rating!, count: store.reviewCount, compact: true)
                            else
                              Text(tr('Hali sharhlar yo‘q'), style: text.bodySmall),
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
                  MetaLine(
                    icon: Icons.inventory_2_outlined,
                    text: tr('{activeListings} ta faol e’lon', {'activeListings': store.activeListings}),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      if (b.phone != null)
                        FilledButton.icon(
                          onPressed: () => ref.read(externalActionsProvider).call(b.phone!),
                          icon: const Icon(Icons.call_rounded),
                          label: Text(tr('Qo‘ng‘iroq')),
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
                          label: Text(tr('Sayt')),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text(tr('E’lonlar'), style: text.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  listings.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.all(AppSpacing.xl),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (error, _) => FailureView(error: error, compact: true),
                    data: (page) => page.items.isEmpty
                        ? Text(
                            tr('Hozircha e’lonlar yo‘q'),
                            style: text.bodySmall?.copyWith(color: palette.textSecondary),
                          )
                        : Column(
                            children: [
                              for (final listing in page.items) ListingTile(listing: listing, heroPrefix: 'store'),
                            ],
                          ),
                  ),
                  if (store.jobs.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xl),
                    Text(tr('Vakansiyalar'), style: text.titleMedium),
                    const SizedBox(height: AppSpacing.sm),
                    for (final job in store.jobs)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: JobCard(job: job),
                      ),
                  ],
                  if (store.providers.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xl),
                    Text(tr('Xizmatlar'), style: text.titleMedium),
                    const SizedBox(height: AppSpacing.sm),
                    for (final provider in store.providers)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: ProviderTile(provider: provider),
                      ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    tr('A’zo: {p0}', {'p0': Formatters.monthYear(b.memberSince)}),
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
    final text = Theme.of(context).textTheme;
    final palette = context.palette;
    return Scaffold(
      appBar: AppBar(title: Text(tr('E’lon statistikasi'))),
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
              ChoiceChipsRow<int>(
                padding: EdgeInsets.zero,
                items: const [7, 30, 90],
                selected: _days,
                labelOf: (d) => tr('{d} kun', {'d': d}),
                onSelected: (d) => setState(() => _days = d),
              ),
              const SizedBox(height: AppSpacing.md),
              _TotalsGrid(totals: s.totals),
              const SizedBox(height: AppSpacing.md),
              Text(
                tr('Jami: {lifetimeViews} ko‘rish · {lifetimeFavorites} sevimli', {
                  'lifetimeViews': s.lifetimeViews,
                  'lifetimeFavorites': s.lifetimeFavorites,
                }),
                style: text.bodySmall?.copyWith(color: palette.textSecondary),
              ),
              if (s.daily.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xl),
                Text(tr('Kunlik ko‘rishlar'), style: text.titleSmall),
                const SizedBox(height: AppSpacing.sm),
                _DailyBars(days: s.daily),
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
      (Icons.visibility_outlined, tr('Ko‘rishlar'), totals.views),
      (Icons.favorite_border_rounded, tr('Sevimlilar'), totals.favorites),
      (Icons.call_outlined, tr('Raqam ko‘rildi'), totals.contacts),
      (Icons.chat_bubble_outline_rounded, tr('Chatlar'), totals.chats),
      (Icons.ios_share_rounded, tr('Ulashishlar'), totals.shares),
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
