import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/design/app_icons.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/widgets/app_search_field.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/paged_sliver.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/state_views.dart';
import '../../catalog/application/catalog_providers.dart';
import '../../location/application/location_controller.dart';
import '../application/services_providers.dart';
import '../data/bundled_service_categories.dart';
import '../domain/service_provider.dart';
import 'widgets/provider_cards.dart';

class ServicesScreen extends ConsumerStatefulWidget {
  const ServicesScreen({super.key});

  @override
  ConsumerState<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends ConsumerState<ServicesScreen> {
  final _search = TextEditingController();
  String _text = '';
  ProviderFilter _filter = ProviderFilter.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final regionId = ref.watch(locationProvider).regionId;
    final categories = ref.watch(serviceCategoriesProvider);
    final gutter = adaptiveGutter(context);
    final query = ProviderQuery(text: _text, filter: _filter, regionId: regionId);
    final searching = _text.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Xizmatlar')),
      body: RefreshIndicator.adaptive(
        onRefresh: () async {
          ref.invalidate(recommendedProvidersProvider(regionId));
          ref.invalidate(providerSearchProvider(query));
        },
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(gutter, AppSpacing.sm, gutter, AppSpacing.lg),
              sliver: SliverToBoxAdapter(
                child: AppSearchField(
                  controller: _search,
                  hint: 'Usta yoki xizmat qidirish...',
                  onSubmitted: (value) => setState(() => _text = value.trim()),
                  onClear: () => setState(() => _text = ''),
                ),
              ),
            ),
            if (!searching) ...[
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: gutter),
                sliver: SliverToBoxAdapter(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final largeText = MediaQuery.textScalerOf(context).scale(10) > 14;
                      final columns = constraints.maxWidth >= AppBreakpoints.medium ? 6 : (largeText ? 3 : 4);
                      final width = (constraints.maxWidth - AppSpacing.sm * (columns - 1)) / columns;
                      return Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.md,
                        children: [
                          for (final category in categories)
                            SizedBox(
                              width: width,
                              child: Pressable(
                                semanticLabel: category.name,
                                onTap: () => context.push(AppRoutes.serviceCategory(category.id)),
                                child: Column(
                                  children: [
                                    ToneIcon(
                                      icon: AppIcons.forKey(category.iconKey),
                                      tone: category.tone,
                                      size: 54,
                                      radius: AppRadii.lg,
                                    ),
                                    const SizedBox(height: AppSpacing.xs + 2),
                                    Text(
                                      category.name,
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context).textTheme.labelSmall
                                          ?.copyWith(fontWeight: FontWeight.w500),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(gutter, AppSpacing.xl, gutter - AppSpacing.sm, AppSpacing.sm),
                sliver: const SliverToBoxAdapter(child: SectionHeader(title: 'Tavsiya etilgan ustalar')),
              ),
              SliverToBoxAdapter(
                child: _RecommendedCarousel(regionId: regionId, gutter: gutter),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(gutter, AppSpacing.xl, gutter, AppSpacing.sm),
                sliver: const SliverToBoxAdapter(child: SectionHeader(title: 'Barcha ustalar')),
              ),
            ],
            SliverToBoxAdapter(
              child: ChoiceChipsRow<ProviderFilter>(
                padding: EdgeInsets.symmetric(horizontal: gutter),
                items: ProviderFilter.values,
                selected: _filter,
                labelOf: (f) => f.label,
                onSelected: (f) => setState(() => _filter = f),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(gutter, AppSpacing.md, gutter, AppSpacing.xxxl),
              sliver: ProviderResultsSliver(query: query),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecommendedCarousel extends ConsumerWidget {
  const _RecommendedCarousel({required this.regionId, required this.gutter});

  final String regionId;
  final double gutter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recommended = ref.watch(recommendedProvidersProvider(regionId));
    final textScale = (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(1.0, 2.0);
    final height = 196 + 60 * textScale;
    return SizedBox(
      height: height,
      child: recommended.when(
        loading: () => Shimmer(
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: gutter),
            itemCount: 3,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
            itemBuilder: (_, _) => const SizedBox(width: 156, child: SkeletonBox(radius: AppRadii.lg)),
          ),
        ),
        error: (error, _) => FailureView(
          error: error,
          compact: true,
          onRetry: () => ref.invalidate(recommendedProvidersProvider(regionId)),
        ),
        data: (providers) => ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: gutter),
          itemCount: providers.length,
          separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
          itemBuilder: (_, index) => SizedBox(width: 156, child: ProviderCard(provider: providers[index])),
        ),
      ),
    );
  }
}

class ProviderResultsSliver extends ConsumerWidget {
  const ProviderResultsSliver({super.key, required this.query});

  final ProviderQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(providerSearchProvider(query))
        .when(
          skipLoadingOnRefresh: true,
          loading: () => SliverToBoxAdapter(
            child: Shimmer(
              child: Column(
                children: List.generate(
                  3,
                  (_) => const Padding(
                    padding: EdgeInsets.only(bottom: AppSpacing.md),
                    child: ProviderTileSkeleton(),
                  ),
                ),
              ),
            ),
          ),
          error: (error, _) => SliverToBoxAdapter(
            child: FailureView(
              error: error,
              compact: true,
              onRetry: () => ref.invalidate(providerSearchProvider(query)),
            ),
          ),
          data: (providers) => providers.isEmpty
              ? const SliverToBoxAdapter(
                  child: EmptyState(
                    icon: Icons.handyman_outlined,
                    title: 'Usta topilmadi',
                    message: 'Boshqa filtr yoki kategoriyani tanlab ko‘ring.',
                    compact: true,
                  ),
                )
              : SliverList.separated(
                  itemCount: providers.length,
                  separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
                  itemBuilder: (_, index) =>
                      ProviderTile(key: ValueKey(providers[index].id), provider: providers[index]),
                ),
        );
  }
}

class ServiceCategoryScreen extends ConsumerStatefulWidget {
  const ServiceCategoryScreen({super.key, required this.categoryId});

  final String categoryId;

  @override
  ConsumerState<ServiceCategoryScreen> createState() => _ServiceCategoryScreenState();
}

class _ServiceCategoryScreenState extends ConsumerState<ServiceCategoryScreen> {
  ProviderFilter _filter = ProviderFilter.all;

  @override
  Widget build(BuildContext context) {
    final category = BundledServiceCategories.byId(widget.categoryId);
    final regionId = ref.watch(locationProvider).regionId;
    final query = ProviderQuery(categoryId: widget.categoryId, filter: _filter, regionId: regionId);
    final gutter = adaptiveGutter(context, maxWidth: AppBreakpoints.contentMaxWidth);
    return Scaffold(
      appBar: AppBar(title: Text(category?.name ?? 'Xizmatlar')),
      body: RefreshIndicator.adaptive(
        onRefresh: () async => ref.invalidate(providerSearchProvider(query)),
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: ChoiceChipsRow<ProviderFilter>(
                  padding: EdgeInsets.symmetric(horizontal: gutter),
                  items: ProviderFilter.values,
                  selected: _filter,
                  labelOf: (f) => f.label,
                  onSelected: (f) => setState(() => _filter = f),
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(gutter, AppSpacing.md, gutter, AppSpacing.md),
              sliver: ProviderResultsSliver(query: query),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(gutter, 0, gutter, AppSpacing.xxxl),
              sliver: SliverSafeArea(
                top: false,
                sliver: SliverToBoxAdapter(
                  child: OutlinedButton.icon(
                    onPressed: () => context.push(AppRoutes.createIn('services')),
                    icon: const Icon(Icons.add_business_rounded),
                    label: const Text('O‘z xizmatingizni joylang'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
