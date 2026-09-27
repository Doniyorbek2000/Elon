import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_icons.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/widgets/app_search_field.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/state_views.dart';
import '../../search/domain/search_normalizer.dart';
import '../application/catalog_providers.dart';
import '../domain/category.dart';

void openCategory(BuildContext context, Category category) {
  switch (category.kind) {
    case CategoryKind.jobs:
      context.push(AppRoutes.jobs);
    case CategoryKind.services:
      context.push(AppRoutes.services);
    case CategoryKind.marketplace:
      context.push(AppRoutes.listingsFor(categoryId: category.id));
  }
}

class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  final _controller = TextEditingController();
  String _filter = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<Category> _visible(CategoryTree tree) {
    final tokens = SearchNormalizer.tokens(_filter);
    if (tokens.isEmpty) return tree.roots;
    final matches = <Category>[];
    void visit(Category category) {
      if (SearchNormalizer.matches(
        tokens,
        '${category.name} ${category.subtitle ?? ''}',
      ))
        matches.add(category);
      category.children.forEach(visit);
    }

    tree.roots.forEach(visit);
    return matches;
  }

  @override
  Widget build(BuildContext context) {
    final tree = ref.watch(categoryTreeProvider);
    final categories = _visible(tree);
    return Scaffold(
      appBar: AppBar(title: const Text('Kategoriyalar')),
      body: ContentWidth(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: AppSearchField(
                controller: _controller,
                hint: 'Kategoriya qidirish...',
                onChanged: (value) => setState(() => _filter = value),
              ),
            ),
            Expanded(
              child: categories.isEmpty
                  ? const EmptyState(
                      icon: Icons.category_outlined,
                      title: 'Kategoriya topilmadi',
                      compact: true,
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.xs,
                        AppSpacing.lg,
                        AppSpacing.xxl,
                      ),
                      itemCount: categories.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (context, index) {
                        final category = categories[index];
                        final parent = tree.parentOf(category.id);
                        return _CategoryRow(
                          category: category,
                          subtitle: parent == null
                              ? category.subtitle
                              : parent.name,
                          onTap: () => openCategory(context, category),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.category,
    required this.subtitle,
    required this.onTap,
  });

  final Category category;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = Theme.of(context).textTheme;
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      onTap: onTap,
      child: Row(
        children: [
          ToneIcon(
            icon: AppIcons.forKey(category.iconKey),
            tone: category.tone,
            size: 46,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(category.name, style: text.titleSmall),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: text.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: palette.textTertiary),
        ],
      ),
    );
  }
}
