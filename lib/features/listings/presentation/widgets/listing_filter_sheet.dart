import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/design/app_colors.dart';
import '../../../../core/design/app_tokens.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/widgets/sheets.dart';
import '../../domain/listing.dart';
import '../../domain/listing_query.dart';

/// Filters + sorting for listing results. Edits a local copy and returns the
/// new query only when the user applies it.
Future<ListingQuery?> showListingFilterSheet(BuildContext context, ListingQuery query, {required String areaLabel}) {
  return showAppSheet<ListingQuery>(
    context,
    builder: (_) => ListingFilterSheet(initial: query, areaLabel: areaLabel),
  );
}

class ListingFilterSheet extends StatefulWidget {
  const ListingFilterSheet({super.key, required this.initial, required this.areaLabel});

  final ListingQuery initial;
  final String areaLabel;

  @override
  State<ListingFilterSheet> createState() => _ListingFilterSheetState();
}

class _ListingFilterSheetState extends State<ListingFilterSheet> {
  late ListingQuery _query = widget.initial;
  late final _min = TextEditingController(text: widget.initial.minPrice?.toString() ?? '');
  late final _max = TextEditingController(text: widget.initial.maxPrice?.toString() ?? '');
  String? _priceError;

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  void _apply() {
    final min = int.tryParse(_min.text);
    final max = int.tryParse(_max.text);
    if (min != null && max != null && min > max) {
      setState(() => _priceError = tr('Minimal narx maksimaldan katta bo‘lmasin'));
      return;
    }
    Navigator.pop(context, _query.copyWith(minPrice: () => min, maxPrice: () => max));
  }

  void _reset() {
    _min.clear();
    _max.clear();
    setState(() {
      _priceError = null;
      _query = widget.initial.clearedRefinements();
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final palette = context.palette;
    Widget label(String value) => Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl, bottom: AppSpacing.sm),
      child: Text(value, style: text.titleSmall),
    );

    return SheetScaffold(
      title: tr('Filtrlar'),
      trailing: TextButton(onPressed: _reset, child: Text(tr('Tozalash'))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            label(tr('Saralash')),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final sort in ListingSort.values)
                  ChoiceChip(
                    label: Text(sort.label),
                    selected: _query.sort == sort,
                    onSelected: (_) => setState(() => _query = _query.copyWith(sort: sort)),
                    labelStyle: text.labelMedium?.copyWith(
                      color: _query.sort == sort ? palette.onPrimary : palette.textPrimary,
                    ),
                  ),
              ],
            ),
            label(tr('Narx, so‘m')),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _min,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(hintText: 'dan'),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: TextField(
                    controller: _max,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(hintText: 'gacha'),
                  ),
                ),
              ],
            ),
            if (_priceError != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(_priceError!, style: text.bodySmall?.copyWith(color: palette.danger)),
              ),
            label(tr('Holati')),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<ItemCondition?>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: null, label: Text(tr('Barchasi'))),
                  ButtonSegment(value: ItemCondition.newItem, label: Text(tr('Yangi'))),
                  ButtonSegment(value: ItemCondition.used, label: Text(tr('Ishlatilgan'))),
                ],
                selected: {_query.condition},
                onSelectionChanged: (value) => setState(() => _query = _query.copyWith(condition: () => value.first)),
              ),
            ),
            label(tr('Masofa')),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                ChoiceChip(
                  label: Text(tr('Butun hudud · {areaLabel}', {'areaLabel': widget.areaLabel})),
                  selected: _query.radiusKm == null,
                  onSelected: (_) => setState(() => _query = _query.copyWith(radiusKm: () => null)),
                  labelStyle: text.labelMedium?.copyWith(
                    color: _query.radiusKm == null ? palette.onPrimary : palette.textPrimary,
                  ),
                ),
                for (final km in listingRadiusOptionsKm)
                  ChoiceChip(
                    label: Text(tr('{km} km', {'km': km})),
                    selected: _query.radiusKm == km,
                    onSelected: (_) => setState(() => _query = _query.copyWith(radiusKm: () => km)),
                    labelStyle: text.labelMedium?.copyWith(
                      color: _query.radiusKm == km ? palette.onPrimary : palette.textPrimary,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: FilledButton(onPressed: _apply, child: Text(tr('Natijalarni ko‘rsatish'))),
    );
  }
}
