import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/widgets/app_search_field.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/paged_sliver.dart';
import '../../catalog/application/catalog_providers.dart';
import '../../catalog/domain/category.dart';
import '../../location/application/location_controller.dart';
import '../application/listing_providers.dart';
import '../domain/listing_query.dart';
import 'widgets/listing_feed_slivers.dart';
import 'widgets/listing_filter_sheet.dart';

/// Category/marketplace browsing: search, subcategory chips, location,
/// sorting and filters over an infinite list.
class ListingsScreen extends ConsumerStatefulWidget {
  const ListingsScreen({
    super.key,
    this.categoryId,
    this.initialText = '',
    this.initialSort = ListingSort.newest,
  });

  final String? categoryId;
  final String initialText;
  final ListingSort initialSort;

  @override
  ConsumerState<ListingsScreen> createState() => _ListingsScreenState();
}

class _ListingsScreenState extends ConsumerState<ListingsScreen> {
  late final _search = TextEditingController(text: widget.initialText);

  /// User refinements; location is layered on from [locationProvider].
  late ListingQuery _refinements = ListingQuery(
    text: widget.initialText,
    categoryId: widget.categoryId,
    sort: widget.initialSort,
  );

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  ListingQuery _effectiveQuery() {
    final location = ref.watch(locationProvider);
    final radius =
        _refinements.radiusKm ??
        (_refinements.sort == ListingSort.nearest
            ? location.radiusKm ?? 50
            : null);
    return _refinements.copyWith(
      regionId: () => location.regionId,
      districtId: () => radius == null ? null : location.districtId,
      radiusKm: () => radius,
    );
  }

  Future<void> _openFilters(ListingQuery effective, String areaLabel) async {
    final result = await showListingFilterSheet(
      context,
      _refinements,
      areaLabel: areaLabel,
    );
    if (result != null && mounted) setState(() => _refinements = result);
  }

  /// Chips show the children of the selected root, or siblings of a leaf.
  (Category?, List<Category>) _chipContext(CategoryTree tree) {
    final selected = tree.byId(_refinements.categoryId);
    if (selected == null) return (null, const []);
    final root = selected.hasChildren ? selected : tree.parentOf(selected.id);
    return (root, root?.children ?? const []);
  }

  @override
  Widget build(BuildContext context) {
    final tree = ref.watch(categoryTreeProvider);
    final location = ref.watch(locationProvider);
    final query = _effectiveQuery();
    final selected = tree.byId(_refinements.categoryId);
    final (root, chips) = _chipContext(tree);
    final gutter = adaptiveGutter(context);
    final title = selected == null
        ? 'Barcha e’lonlar'
        : (root?.name ?? selected.name);
    final areaLabel = location.regionName.replaceAll(' viloyati', '');
    final palette = context.palette;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: InfiniteScrollTrigger(
        onLoadMore: () =>
            ref.read(listingFeedProvider(query).notifier).loadMore(),
        child: RefreshIndicator.adaptive(
          onRefresh: () =>
              ref.read(listingFeedProvider(query).notifier).refresh(),
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(gutter, AppSpacing.sm, gutter, 0),
                sliver: SliverToBoxAdapter(
                  child: AppSearchField(
                    controller: _search,
                    hint: 'Qidirish...',
                    activeFilters: _refinements.activeFilterCount,
                    onFilterTap: () => _openFilters(query, areaLabel),
                    onSubmitted: (value) => setState(
                      () => _refinements = _refinements.copyWith(
                        text: value.trim(),
                      ),
                    ),
                    onClear: () => setState(
                      () => _refinements = _refinements.copyWith(text: ''),
                    ),
                  ),
                ),
              ),
              if (chips.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: ChoiceChipsRow<Category?>(
                      padding: EdgeInsets.symmetric(horizontal: gutter),
                      items: [null, ...chips],
                      selected: selected?.hasChildren ?? false
                          ? null
                          : selected,
                      labelOf: (c) => c?.name ?? 'Barchasi',
                      onSelected: (c) => setState(
                        () => _refinements = _refinements.copyWith(
                          categoryId: () => c?.id ?? root?.id,
                        ),
                      ),
                    ),
                  ),
                ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  gutter,
                  AppSpacing.sm,
                  gutter,
                  AppSpacing.xs,
                ),
                sliver: SliverToBoxAdapter(
                  child: Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ActionChip(
                        avatar: Icon(
                          Icons.location_on_rounded,
                          size: AppIconSize.sm,
                          color: palette.primary,
                        ),
                        label: Text(
                          query.radiusKm == null
                              ? areaLabel
                              : '${location.label} · ${query.radiusKm} km',
                        ),
                        onPressed: () => context.push(AppRoutes.location),
                      ),
                      ActionChip(
                        avatar: Icon(
                          Icons.swap_vert_rounded,
                          size: AppIconSize.sm,
                          color: palette.primary,
                        ),
                        label: Text(_refinements.sort.label),
                        onPressed: () => _openFilters(query, areaLabel),
                      ),
                    ],
                  ),
                ),
              ),
              ListingFeedSlivers(
                query: query,
                gutter: gutter,
                layout: ListingLayout.list,
                heroPrefix: 'browse',
              ),
              const SliverSafeArea(
                top: false,
                sliver: SliverToBoxAdapter(
                  child: SizedBox(height: AppSpacing.lg),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
