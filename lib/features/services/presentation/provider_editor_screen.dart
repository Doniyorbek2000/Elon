import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/sheets.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/application/session_controller.dart';
import '../../catalog/application/catalog_providers.dart';
import '../../location/application/location_controller.dart';
import '../application/services_providers.dart';
import '../domain/service_provider.dart';

/// Create/edit the signed-in user's provider profile and service offerings.
class ProviderEditorScreen extends ConsumerStatefulWidget {
  const ProviderEditorScreen({super.key});

  @override
  ConsumerState<ProviderEditorScreen> createState() => _ProviderEditorScreenState();
}

class _ProviderEditorScreenState extends ConsumerState<ProviderEditorScreen> {
  final _name = TextEditingController();
  final _profession = TextEditingController();
  final _description = TextEditingController();
  final _experience = TextEditingController(text: '0');
  final Set<String> _categoryIds = {};
  bool _loaded = false;
  bool _saving = false;
  Map<String, String> _errors = const {};

  @override
  void dispose() {
    for (final controller in [_name, _profession, _description, _experience]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _fill(ServiceProvider? provider) {
    if (_loaded) return;
    _loaded = true;
    _name.text = provider?.name ?? ref.read(sessionProvider)?.name ?? '';
    if (provider == null) return;
    _profession.text = provider.profession;
    _description.text = provider.description;
    _experience.text = '${provider.experienceYears}';
    _categoryIds
      ..clear()
      ..add(provider.categoryId);
  }

  Future<void> _save() async {
    final errors = <String, String>{
      if (_name.text.trim().length < 2) 'displayName': 'Ismni kiriting',
      if (_profession.text.trim().length < 2) 'profession': 'Kasbni kiriting',
      if (_description.text.trim().length < 20) 'description': 'Kamida 20 belgi yozing',
      if (_categoryIds.isEmpty) 'categoryIds': 'Kamida bitta yo‘nalish tanlang',
    };
    setState(() => _errors = errors);
    if (errors.isNotEmpty) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(servicesRepositoryProvider)
          .saveProvider(
            ProviderDraft(
              displayName: _name.text.trim(),
              profession: _profession.text.trim(),
              description: _description.text.trim(),
              categoryIds: _categoryIds.toList(),
              experienceYears: int.tryParse(_experience.text) ?? 0,
              place: ref.read(locationProvider).toPlace(),
            ),
          );
      ref.invalidate(myProviderProvider);
      if (mounted) showAppSnack(context, 'Profil saqlandi');
    } on Object catch (error) {
      final failure = error.asFailure();
      if (!mounted) return;
      if (failure is ValidationFailure && failure.fieldErrors.isNotEmpty) setState(() => _errors = failure.fieldErrors);
      showAppSnack(context, failure.message, icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final palette = context.palette;
    final categories = ref.watch(serviceCategoriesProvider);
    final location = ref.watch(locationProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Usta profilim')),
      body: ref
          .watch(myProviderProvider)
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => FailureView(error: error, onRetry: () => ref.invalidate(myProviderProvider)),
            data: (provider) {
              _fill(provider);
              return ContentWidth(
                maxWidth: AppBreakpoints.formMaxWidth,
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: [
                    if (provider != null)
                      SurfaceCard(
                        onTap: () => context.push(AppRoutes.provider(provider.id)),
                        child: Row(
                          children: [
                            Icon(Icons.visibility_outlined, color: palette.primary),
                            const SizedBox(width: AppSpacing.md),
                            const Expanded(child: Text('Profilingiz mijozlarga qanday ko‘rinadi')),
                            const Icon(Icons.chevron_right_rounded),
                          ],
                        ),
                      ),
                    const SizedBox(height: AppSpacing.lg),
                    TextField(
                      controller: _name,
                      decoration: InputDecoration(labelText: 'Ism yoki usta nomi', errorText: _errors['displayName']),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      controller: _profession,
                      decoration: InputDecoration(
                        labelText: 'Kasb',
                        hintText: 'Masalan: Santexnik',
                        errorText: _errors['profession'],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      controller: _experience,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Tajriba (yil)'),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      controller: _description,
                      minLines: 3,
                      maxLines: 8,
                      maxLength: 3000,
                      decoration: InputDecoration(
                        labelText: 'Xizmatlaringiz haqida',
                        errorText: _errors['description'],
                      ),
                    ),
                    Text('Yo‘nalishlar', style: text.titleSmall),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        for (final category in categories)
                          FilterChip(
                            label: Text(category.name),
                            selected: _categoryIds.contains(category.id),
                            onSelected: (value) => setState(() {
                              if (value && _categoryIds.length < 5) {
                                _categoryIds.add(category.id);
                              } else {
                                _categoryIds.remove(category.id);
                              }
                            }),
                          ),
                      ],
                    ),
                    if (_errors['categoryIds'] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xs),
                        child: Text(_errors['categoryIds']!, style: text.bodySmall?.copyWith(color: palette.danger)),
                      ),
                    const SizedBox(height: AppSpacing.md),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.place_outlined),
                      title: Text(location.label),
                      subtitle: const Text('Xizmat ko‘rsatish hududi'),
                      trailing: TextButton(
                        onPressed: () => context.push(AppRoutes.location),
                        child: const Text('O‘zgartirish'),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(provider == null ? 'Profil yaratish' : 'Saqlash'),
                    ),
                    if (provider != null) ...[
                      const SizedBox(height: AppSpacing.xxl),
                      SectionHeader(
                        title: 'Xizmatlar va narxlar',
                        actionLabel: 'Qo‘shish',
                        onAction: () => _addOffering(context, provider),
                        padding: EdgeInsets.zero,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      if (provider.offerings.isEmpty)
                        Text('Hali xizmat qo‘shilmagan', style: text.bodySmall)
                      else
                        for (final offering in provider.offerings)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(offering.title),
                            subtitle: Text(
                              offering.priceFrom == null
                                  ? offering.pricingType.label
                                  : '${Formatters.money(offering.priceFrom!)} · ${offering.pricingType.label}',
                            ),
                            trailing: IconButton(
                              tooltip: 'O‘chirish',
                              icon: const Icon(Icons.delete_outline_rounded),
                              onPressed: () => _deleteOffering(offering),
                            ),
                          ),
                    ],
                  ],
                ),
              );
            },
          ),
    );
  }

  Future<void> _deleteOffering(ServiceOffering offering) async {
    try {
      await ref.read(servicesRepositoryProvider).deleteOffering(offering.id);
      ref.invalidate(myProviderProvider);
    } on Object catch (error) {
      if (mounted) showAppSnack(context, error.asFailure().message, icon: Icons.error_outline_rounded);
    }
  }

  Future<void> _addOffering(BuildContext context, ServiceProvider provider) async {
    final draft = await showAppSheet<OfferingDraft>(
      context,
      builder: (_) => _OfferingSheet(categoryId: provider.categoryId),
    );
    if (draft == null) return;
    try {
      await ref.read(servicesRepositoryProvider).addOffering(draft);
      ref.invalidate(myProviderProvider);
    } on Object catch (error) {
      if (context.mounted) showAppSnack(context, error.asFailure().message, icon: Icons.error_outline_rounded);
    }
  }
}

class _OfferingSheet extends StatefulWidget {
  const _OfferingSheet({required this.categoryId});

  final String categoryId;

  @override
  State<_OfferingSheet> createState() => _OfferingSheetState();
}

class _OfferingSheetState extends State<_OfferingSheet> {
  final _title = TextEditingController();
  final _price = TextEditingController();
  final _unit = TextEditingController();
  PricingType _pricing = PricingType.from;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _price.dispose();
    _unit.dispose();
    super.dispose();
  }

  void _submit() {
    final price = int.tryParse(_price.text.replaceAll(' ', ''));
    if (_title.text.trim().length < 3) {
      setState(() => _error = 'Xizmat nomini kiriting');
      return;
    }
    if (_pricing != PricingType.negotiable && price == null) {
      setState(() => _error = 'Narxni kiriting yoki «Kelishiladi»ni tanlang');
      return;
    }
    Navigator.of(context).pop(
      OfferingDraft(
        categoryId: widget.categoryId,
        title: _title.text.trim(),
        pricingType: _pricing,
        priceFrom: _pricing == PricingType.negotiable ? null : price,
        priceUnit: _unit.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.sm,
      AppSpacing.lg,
      AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Yangi xizmat', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _title,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nomi', hintText: 'Masalan: Kran almashtirish'),
        ),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<PricingType>(
          initialValue: _pricing,
          decoration: const InputDecoration(labelText: 'Narx turi'),
          items: [for (final type in PricingType.values) DropdownMenuItem(value: type, child: Text(type.label))],
          onChanged: (value) => setState(() => _pricing = value ?? _pricing),
        ),
        if (_pricing != PricingType.negotiable) ...[
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _price,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Narx (so‘m)'),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _unit,
            decoration: const InputDecoration(labelText: 'Birlik', hintText: 'Masalan: xizmat uchun, soatiga'),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(_error!, style: TextStyle(color: context.palette.danger)),
        ],
        const SizedBox(height: AppSpacing.lg),
        FilledButton(onPressed: _submit, child: const Text('Qo‘shish')),
      ],
    ),
  );
}

/// Star rating + text. The server only accepts it after a two-way chat.
Future<void> showReviewSheet(BuildContext context, WidgetRef ref, {required ServiceProvider provider}) async {
  final result = await showAppSheet<(int, String)>(context, builder: (_) => const _ReviewSheet());
  if (result == null) return;
  try {
    await ref.read(servicesRepositoryProvider).submitReview(provider.id, rating: result.$1, text: result.$2);
    ref.invalidate(providerDetailProvider(provider.id));
    if (context.mounted) showAppSnack(context, 'Rahmat! Sharhingiz qabul qilindi');
  } on Object catch (error) {
    if (context.mounted) showAppSnack(context, error.asFailure().message, icon: Icons.info_outline_rounded);
  }
}

class _ReviewSheet extends StatefulWidget {
  const _ReviewSheet();

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  final _text = TextEditingController();
  int _rating = 0;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Ustani baholang', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var star = 1; star <= 5; star++)
                IconButton(
                  tooltip: '$star',
                  iconSize: 36,
                  onPressed: () => setState(() => _rating = star),
                  icon: Icon(
                    star <= _rating ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: star <= _rating ? palette.warning : palette.textTertiary,
                  ),
                ),
            ],
          ),
          TextField(
            controller: _text,
            minLines: 2,
            maxLines: 5,
            maxLength: 1000,
            decoration: const InputDecoration(hintText: 'Ish sifati, vaqtida kelgani…'),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            onPressed: _rating == 0 ? null : () => Navigator.of(context).pop((_rating, _text.text)),
            child: const Text('Yuborish'),
          ),
        ],
      ),
    );
  }
}
