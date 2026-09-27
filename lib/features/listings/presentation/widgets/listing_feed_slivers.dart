import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/app_tokens.dart';
import '../../../../core/domain/paged.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../../../core/widgets/state_views.dart';
import '../../application/listing_providers.dart';
import '../../domain/listing.dart';
import '../../domain/listing_query.dart';
import 'listing_cards.dart';

enum ListingLayout { grid, list }

/// Renders a [listingFeedProvider] as slivers with skeleton, error, empty,
/// data and load-more states. Parent supplies scroll + refresh.
class ListingFeedSlivers extends ConsumerWidget {
  const ListingFeedSlivers({
    super.key,
    required this.query,
    required this.gutter,
    this.layout = ListingLayout.grid,
    this.heroPrefix = 'feed',
    this.empty,
  });

  final ListingQuery query;
  final double gutter;
  final ListingLayout layout;
  final String heroPrefix;
  final Widget? empty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(listingFeedProvider(query));
    final width = MediaQuery.sizeOf(context).width - gutter * 2;
    final padding = EdgeInsets.symmetric(horizontal: gutter);

    return feed.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      loading: () => SliverPadding(
        padding: padding,
        sliver: SliverToBoxAdapter(
          child: Shimmer(
            child: layout == ListingLayout.grid
                ? GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: EdgeInsets.zero,
                    gridDelegate: listingGridDelegate(context, width),
                    itemCount: 6,
                    itemBuilder: (_, _) => const ListingCardSkeleton(),
                  )
                : Column(children: List.generate(6, (_) => const ListingTileSkeleton())),
          ),
        ),
      ),
      error: (error, _) => SliverToBoxAdapter(
        child: FailureView(error: error, compact: true, onRetry: () => ref.invalidate(listingFeedProvider(query))),
      ),
      data: (state) {
        if (state.isEmpty) {
          return SliverToBoxAdapter(
            child:
                empty ??
                const EmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: 'Hech narsa topilmadi',
                  message: 'Filtrlarni o‘zgartirib yoki hududni kengaytirib ko‘ring.',
                  compact: true,
                ),
          );
        }
        return SliverMainAxisGroup(
          slivers: [
            SliverPadding(
              padding: padding,
              sliver: layout == ListingLayout.grid
                  ? SliverGrid.builder(
                      gridDelegate: listingGridDelegate(context, width),
                      itemCount: state.items.length,
                      itemBuilder: (_, index) => ListingCard(
                        key: ValueKey(state.items[index].id),
                        listing: state.items[index],
                        heroPrefix: heroPrefix,
                      ),
                    )
                  : _TileList(items: state.items, width: width, heroPrefix: heroPrefix),
            ),
            SliverToBoxAdapter(child: _footer(ref, state)),
          ],
        );
      },
    );
  }

  Widget _footer(WidgetRef ref, PagedState<Listing> state) => LoadMoreFooter(
    isLoading: state.isLoadingMore,
    hasMore: state.hasMore,
    error: state.loadMoreError,
    onRetry: () => ref.read(listingFeedProvider(query).notifier).loadMore(),
  );
}

class _TileList extends StatelessWidget {
  const _TileList({required this.items, required this.width, required this.heroPrefix});

  final List<Listing> items;
  final double width;
  final String heroPrefix;

  @override
  Widget build(BuildContext context) {
    // Two columns of tiles on tablets, one on phones.
    final columns = width >= AppBreakpoints.medium ? 2 : 1;
    if (columns == 1) {
      return SliverList.separated(
        itemCount: items.length,
        separatorBuilder: (_, _) => const Divider(height: AppSpacing.sm),
        itemBuilder: (_, index) =>
            ListingTile(key: ValueKey(items[index].id), listing: items[index], heroPrefix: heroPrefix),
      );
    }
    final rows = (items.length / columns).ceil();
    return SliverList.builder(
      itemCount: rows,
      itemBuilder: (_, row) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var column = 0; column < columns; column++) ...[
            if (column > 0) const SizedBox(width: AppSpacing.xl),
            Expanded(
              child: row * columns + column < items.length
                  ? ListingTile(listing: items[row * columns + column], heroPrefix: heroPrefix)
                  : const SizedBox.shrink(),
            ),
          ],
        ],
      ),
    );
  }
}
