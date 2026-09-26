import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/domain/public_profile.dart';
import '../../../core/widgets/app_search_field.dart';
import '../../../core/widgets/avatar.dart';
import '../../../core/widgets/badges.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/state_views.dart';
import '../../jobs/presentation/widgets/job_cards.dart';
import '../../listings/domain/listing_query.dart';
import '../../listings/presentation/widgets/listing_cards.dart';
import '../../listings/presentation/widgets/listing_filter_sheet.dart';
import '../../location/application/location_controller.dart';
import '../../services/presentation/widgets/provider_cards.dart';
import '../application/search_providers.dart';
import '../domain/search.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.initialQuery});

  final String? initialQuery;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final _controller = TextEditingController(text: widget.initialQuery ?? '');
  final _focus = FocusNode();
  late String? _submitted = _nonEmpty(widget.initialQuery);
  String _typing = '';
  SearchScope _scope = SearchScope.all;
  ListingQuery _filters = const ListingQuery();

  static String? _nonEmpty(String? value) => value == null || value.trim().isEmpty ? null : value.trim();

  @override
  void didUpdateWidget(SearchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _nonEmpty(widget.initialQuery);
    if (next != null && next != _nonEmpty(oldWidget.initialQuery)) _submit(next);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    _focus.unfocus();
    _controller.value = TextEditingValue(
      text: trimmed,
      selection: TextSelection.collapsed(offset: trimmed.length),
    );
    ref.read(recentSearchesProvider.notifier).add(trimmed);
    setState(() {
      _submitted = trimmed;
      _typing = '';
      _scope = SearchScope.all;
    });
  }

  void _clear() => setState(() {
    _submitted = null;
    _typing = '';
  });

  Future<void> _openFilters() async {
    final location = ref.read(locationProvider);
    final result = await showListingFilterSheet(
      context,
      _filters,
      areaLabel: location.regionName.replaceAll(' viloyati', ''),
    );
    if (result != null && mounted) setState(() => _filters = result);
  }

  void _onSuggestion(SearchSuggestion suggestion) {
    switch (suggestion.kind) {
      case SuggestionKind.category:
        context.push(AppRoutes.listingsFor(categoryId: suggestion.refId));
      case SuggestionKind.job:
        context.push(AppRoutes.job(suggestion.refId!));
      case SuggestionKind.service:
        context.push(AppRoutes.provider(suggestion.refId!));
      case SuggestionKind.query || SuggestionKind.listing:
        _submit(suggestion.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = ref.watch(locationProvider);
    final gutter = AppBreakpoints.pagePadding(context);
    final submitted = _submitted;

    Widget body;
    if (_typing.trim().isNotEmpty && _typing.trim() != submitted) {
      body = _Suggestions(query: _typing.trim(), onSelect: _onSuggestion, onSubmit: () => _submit(_typing));
    } else if (submitted == null) {
      body = _Discovery(onSearch: _submit);
    } else {
      final filters = _filters.copyWith(regionId: () => location.regionId);
      body = _Results(
        request: (text: submitted, filters: filters),
        scope: _scope,
        onScope: (scope) => setState(() => _scope = scope),
        onSearch: _submit,
      );
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ContentWidth(
          maxWidth: AppBreakpoints.wideContentMaxWidth,
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(gutter, AppSpacing.md, gutter, AppSpacing.sm),
                child: Row(
                  children: [
                    if (submitted != null || _typing.isNotEmpty)
                      IconButton(
                        tooltip: 'Orqaga',
                        icon: const Icon(Icons.arrow_back_rounded),
                        onPressed: () {
                          _controller.clear();
                          _focus.unfocus();
                          _clear();
                        },
                      ),
                    Expanded(
                      child: AppSearchField(
                        controller: _controller,
                        focusNode: _focus,
                        hint: 'iPhone 14, haydovchi, santexnik...',
                        activeFilters: _filters.activeFilterCount,
                        onFilterTap: _openFilters,
                        onChanged: (value) => setState(() => _typing = value),
                        onSubmitted: _submit,
                        onClear: _clear,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(child: body),
            ],
          ),
        ),
      ),
    );
  }
}

class _Discovery extends ConsumerWidget {
  const _Discovery({required this.onSearch});

  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(recentSearchesProvider);
    final popular = ref.watch(popularSearchesProvider).value ?? const <String>[];
    final text = Theme.of(context).textTheme;
    final palette = context.palette;
    final gutter = AppBreakpoints.pagePadding(context);

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(gutter, AppSpacing.sm, gutter, AppSpacing.xxxl),
      children: [
        if (recent.isNotEmpty) ...[
          SectionHeader(
            title: 'Oxirgi qidiruvlar',
            actionLabel: 'Tozalash',
            onAction: () => ref.read(recentSearchesProvider.notifier).clear(),
          ),
          for (final query in recent)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.history_rounded, color: palette.textTertiary),
              title: Text(query, style: text.bodyMedium),
              onTap: () => onSearch(query),
              trailing: IconButton(
                tooltip: 'O‘chirish',
                icon: Icon(Icons.close_rounded, size: AppIconSize.sm, color: palette.textTertiary),
                onPressed: () => ref.read(recentSearchesProvider.notifier).remove(query),
              ),
            ),
          const SizedBox(height: AppSpacing.lg),
        ],
        const SectionHeader(title: 'Ommabop qidiruvlar'),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final query in popular)
              ActionChip(
                avatar: Icon(Icons.trending_up_rounded, size: AppIconSize.sm, color: palette.primary),
                label: Text(query),
                onPressed: () => onSearch(query),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xxl),
        const SectionHeader(title: 'Bo‘limlar'),
        const SizedBox(height: AppSpacing.sm),
        _ShortcutTile(
          icon: Icons.storefront_rounded,
          tone: AccentTone.blue,
          title: 'Bozor',
          subtitle: 'Barcha kategoriyalar',
          onTap: () => context.push(AppRoutes.categories),
        ),
        _ShortcutTile(
          icon: Icons.work_rounded,
          tone: AccentTone.green,
          title: 'Ish',
          subtitle: 'Vakansiyalar va rezyumelar',
          onTap: () => context.push(AppRoutes.jobs),
        ),
        _ShortcutTile(
          icon: Icons.handyman_rounded,
          tone: AccentTone.orange,
          title: 'Xizmatlar',
          subtitle: 'Ustalar va mutaxassislar',
          onTap: () => context.push(AppRoutes.services),
        ),
      ],
    );
  }
}

class _ShortcutTile extends StatelessWidget {
  const _ShortcutTile({
    required this.icon,
    required this.tone,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final AccentTone tone;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: ToneIcon(icon: icon, tone: tone, size: 42),
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: Icon(Icons.chevron_right_rounded, color: context.palette.textTertiary),
    onTap: onTap,
  );
}

class _Suggestions extends ConsumerWidget {
  const _Suggestions({required this.query, required this.onSelect, required this.onSubmit});

  final String query;
  final ValueChanged<SearchSuggestion> onSelect;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggestions = ref.watch(searchSuggestionsProvider(query)).value ?? const <SearchSuggestion>[];
    final palette = context.palette;
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        ListTile(
          leading: Icon(Icons.search_rounded, color: palette.primary),
          title: Text.rich(
            TextSpan(
              text: '«$query» ',
              children: const [TextSpan(text: 'bo‘yicha qidirish')],
            ),
          ),
          onTap: onSubmit,
        ),
        for (final suggestion in suggestions)
          ListTile(
            leading: Icon(switch (suggestion.kind) {
              SuggestionKind.category => Icons.category_outlined,
              SuggestionKind.job => Icons.work_outline_rounded,
              SuggestionKind.service => Icons.handyman_outlined,
              _ => Icons.north_west_rounded,
            }, color: palette.textTertiary),
            title: Text(suggestion.text),
            subtitle: suggestion.subtitle == null ? null : Text(suggestion.subtitle!),
            onTap: () => onSelect(suggestion),
          ),
      ],
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results({required this.request, required this.scope, required this.onScope, required this.onSearch});

  final SearchRequest request;
  final SearchScope scope;
  final ValueChanged<SearchScope> onScope;
  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(searchResultsProvider(request));
    final gutter = AppBreakpoints.pagePadding(context);
    return Column(
      children: [
        ChoiceChipsRow<SearchScope>(
          padding: EdgeInsets.symmetric(horizontal: gutter),
          items: SearchScope.values,
          selected: scope,
          labelOf: (s) {
            final data = results.value;
            final count = switch (s) {
              SearchScope.all => data?.total,
              SearchScope.listings => data?.listings.length,
              SearchScope.jobs => data?.jobs.length,
              SearchScope.services => data?.providers.length,
              SearchScope.users => data?.users.length,
            };
            return count == null || count == 0 ? s.label : '${s.label} $count';
          },
          onSelected: onScope,
        ),
        Expanded(
          child: results.when(
            loading: () => Shimmer(
              child: ListView(
                padding: EdgeInsets.symmetric(horizontal: gutter, vertical: AppSpacing.md),
                physics: const NeverScrollableScrollPhysics(),
                children: List.generate(5, (_) => const ListingTileSkeleton()),
              ),
            ),
            error: (error, _) =>
                FailureView(error: error, onRetry: () => ref.invalidate(searchResultsProvider(request))),
            data: (data) =>
                _ResultsList(data: data, scope: scope, onScope: onScope, onSearch: onSearch, query: request.text),
          ),
        ),
      ],
    );
  }
}

class _ResultsList extends StatelessWidget {
  const _ResultsList({
    required this.data,
    required this.scope,
    required this.onScope,
    required this.onSearch,
    required this.query,
  });

  final SearchResults data;
  final SearchScope scope;
  final ValueChanged<SearchScope> onScope;
  final ValueChanged<String> onSearch;
  final String query;

  @override
  Widget build(BuildContext context) {
    final gutter = AppBreakpoints.pagePadding(context);
    final text = Theme.of(context).textTheme;
    if (data.isEmpty) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: '«$query» bo‘yicha hech narsa topilmadi',
        message: 'So‘zni qisqartiring yoki boshqa hududni tanlang.',
      );
    }
    final all = scope == SearchScope.all;
    const preview = 3;

    List<Widget> section<T>(
      SearchScope target,
      String title,
      List<T> items,
      Widget Function(T) build, {
      double spacing = AppSpacing.md,
    }) {
      if (items.isEmpty || (!all && scope != target)) return const [];
      final shown = all ? items.take(preview).toList() : items;
      return [
        if (all)
          SectionHeader(
            title: title,
            actionLabel: items.length > preview ? 'Hammasi (${items.length})' : null,
            onAction: () => onScope(target),
            padding: const EdgeInsets.only(top: AppSpacing.md),
          ),
        for (final item in shown)
          Padding(
            padding: EdgeInsets.only(bottom: spacing),
            child: build(item),
          ),
      ];
    }

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(gutter, AppSpacing.sm, gutter, AppSpacing.xxxl),
      children: [
        if (data.correctedQuery != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text.rich(
              TextSpan(
                text: 'Natijalar: ',
                children: [
                  TextSpan(
                    text: '«${data.correctedQuery}»',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              style: text.bodySmall,
            ),
          ),
        ...section(
          SearchScope.listings,
          'E’lonlar',
          data.listings,
          (l) => ListingTile(listing: l, heroPrefix: 'search'),
          spacing: 0,
        ),
        ...section(SearchScope.jobs, 'Ishlar', data.jobs, (j) => JobCard(job: j)),
        ...section(SearchScope.services, 'Xizmatlar', data.providers, (p) => ProviderTile(provider: p)),
        ...section(SearchScope.users, 'Foydalanuvchilar', data.users, (u) => _UserTile(user: u)),
        if (!all && _scopeEmpty())
          const EmptyState(icon: Icons.search_off_rounded, title: 'Bu bo‘limda natija yo‘q', compact: true),
      ],
    );
  }

  bool _scopeEmpty() => switch (scope) {
    SearchScope.all => false,
    SearchScope.listings => data.listings.isEmpty,
    SearchScope.jobs => data.jobs.isEmpty,
    SearchScope.services => data.providers.isEmpty,
    SearchScope.users => data.users.isEmpty,
  };
}

class _UserTile extends StatelessWidget {
  const _UserTile({required this.user});

  final PublicProfile user;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      onTap: () => context.push(AppRoutes.seller(user.id)),
      child: Row(
        children: [
          AppAvatar(name: user.name, image: user.avatar, isOnline: user.isOnline),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(child: Text(user.name, style: Theme.of(context).textTheme.titleSmall)),
                    const SizedBox(width: AppSpacing.xs),
                    VerifiedBadge(level: user.verification),
                  ],
                ),
                Text('${user.activeListings} ta faol e’lon', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          if (user.rating != null) RatingLabel(rating: user.rating!, compact: true),
        ],
      ),
    );
  }
}
