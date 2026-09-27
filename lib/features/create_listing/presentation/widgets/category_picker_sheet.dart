import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/app_colors.dart';
import '../../../../core/design/app_icons.dart';
import '../../../../core/design/app_tokens.dart';
import '../../../../core/widgets/common.dart';
import '../../../../core/widgets/sheets.dart';
import '../../../catalog/application/catalog_providers.dart';
import '../../../catalog/domain/category.dart';

/// Two-level category chooser; returns the chosen category id.
Future<String?> showCategoryPicker(BuildContext context) =>
    showAppSheet<String>(context, expand: true, builder: (_) => const _CategoryPickerSheet());

class _CategoryPickerSheet extends ConsumerStatefulWidget {
  const _CategoryPickerSheet();

  @override
  ConsumerState<_CategoryPickerSheet> createState() => _CategoryPickerSheetState();
}

class _CategoryPickerSheetState extends ConsumerState<_CategoryPickerSheet> {
  Category? _parent;

  @override
  Widget build(BuildContext context) {
    final tree = ref.watch(categoryTreeProvider);
    final parent = _parent;
    final items = parent?.children ?? tree.roots;
    final palette = context.palette;

    return SheetScaffold(
      title: parent?.name ?? 'Kategoriyani tanlang',
      trailing: parent == null
          ? null
          : TextButton.icon(
              onPressed: () => setState(() => _parent = null),
              icon: const Icon(Icons.arrow_back_rounded, size: AppIconSize.sm),
              label: const Text('Orqaga'),
            ),
      body: AnimatedSwitcher(
        duration: AppMotion.of(context, AppMotion.fast),
        child: ListView.builder(
          key: ValueKey(parent?.id),
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.xl),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final category = items[index];
            return ListTile(
              shape: const RoundedRectangleBorder(borderRadius: AppRadii.mdAll),
              leading: ToneIcon(icon: AppIcons.forKey(category.iconKey), tone: category.tone, size: 40),
              title: Text(category.name),
              subtitle: category.subtitle == null ? null : Text(category.subtitle!, maxLines: 1),
              trailing: category.hasChildren ? Icon(Icons.chevron_right_rounded, color: palette.textTertiary) : null,
              onTap: () {
                if (category.hasChildren) {
                  setState(() => _parent = category);
                } else {
                  Navigator.pop(context, category.id);
                }
              },
            );
          },
        ),
      ),
    );
  }
}
