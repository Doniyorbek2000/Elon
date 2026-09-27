import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/design/app_colors.dart';
import '../../../../core/design/app_icons.dart';
import '../../../../core/design/app_tokens.dart';
import '../../../../core/domain/money.dart';
import '../../../../core/utils/input_formatters.dart';
import '../../../../core/widgets/common.dart';
import '../../../catalog/application/catalog_providers.dart';
import '../../../catalog/domain/category.dart';
import '../../../listings/domain/listing.dart';
import '../../../location/domain/location.dart';
import '../../application/create_listing_controller.dart';
import '../../domain/listing_draft.dart';
import '../widgets/category_picker_sheet.dart';

/// Step 1: category, title, price, condition, category-specific attributes,
/// description and location.
class DetailsStep extends ConsumerStatefulWidget {
  const DetailsStep({super.key, required this.errors});

  final Map<String, String> errors;

  @override
  ConsumerState<DetailsStep> createState() => _DetailsStepState();
}

class _DetailsStepState extends ConsumerState<DetailsStep> {
  late final ListingDraft _initial = ref.read(createListingProvider);
  late final _title = TextEditingController(text: _initial.title);
  late final _description = TextEditingController(text: _initial.description);
  late final _price = TextEditingController(text: ThousandsInputFormatter.format(_initial.price));
  late final _priceMax = TextEditingController(text: ThousandsInputFormatter.format(_initial.priceMax));
  final Map<String, TextEditingController> _attributeControllers = {};

  CreateListingController get _controller => ref.read(createListingProvider.notifier);

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _price.dispose();
    _priceMax.dispose();
    for (final controller in _attributeControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _attributeController(String key, String? value) =>
      _attributeControllers.putIfAbsent(key, () => TextEditingController(text: value ?? ''));

  Future<void> _pickCategory() async {
    final id = await showCategoryPicker(context);
    if (id != null) _controller.setCategory(id);
  }

  Future<void> _pickPlace() async {
    final selection = await context.push<LocationSelection>(
      Uri(path: AppRoutes.location, queryParameters: {'pick': '1'}).toString(),
    );
    if (selection != null) _controller.setPlace(selection.toPlace());
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(createListingProvider);
    final tree = ref.watch(categoryTreeProvider);
    final schema = draft.categoryId == null ? CategoryFormSchema.generic : tree.schemaFor(draft.categoryId!);
    final category = tree.byId(draft.categoryId);
    final parent = category == null ? null : tree.parentOf(category.id);
    final errors = widget.errors;
    final text = Theme.of(context).textTheme;
    final palette = context.palette;

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xxxl),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        const _FieldLabel('Kategoriya', required: true),
        _PickerField(
          icon: category == null ? Icons.category_outlined : AppIcons.forKey(category.iconKey),
          tone: category?.tone ?? AccentTone.slate,
          value: category == null ? null : [?parent?.name, category.name].join(' › '),
          placeholder: 'Kategoriyani tanlang',
          error: errors[DraftField.category],
          onTap: _pickCategory,
        ),
        const SizedBox(height: AppSpacing.lg),
        const _FieldLabel('Sarlavha', required: true),
        TextField(
          controller: _title,
          maxLength: ListingDraft.titleMaxLength,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.next,
          onChanged: _controller.setTitle,
          decoration: InputDecoration(hintText: schema.titleHint, errorText: errors[DraftField.title]),
        ),
        if (schema.priceMode != PriceMode.none) ...[
          const SizedBox(height: AppSpacing.sm),
          _FieldLabel(schema.priceLabel, required: schema.priceMode == PriceMode.required),
          if (schema.priceMode == PriceMode.salary)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _price,
                    keyboardType: TextInputType.number,
                    inputFormatters: const [ThousandsInputFormatter()],
                    onChanged: (v) => _controller.setPrice(ThousandsInputFormatter.parse(v)),
                    decoration: InputDecoration(
                      hintText: 'dan',
                      suffixText: 'so‘m',
                      errorText: errors[DraftField.price],
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: TextField(
                    controller: _priceMax,
                    keyboardType: TextInputType.number,
                    inputFormatters: const [ThousandsInputFormatter()],
                    onChanged: (v) => _controller.setPriceMax(ThousandsInputFormatter.parse(v)),
                    decoration: const InputDecoration(hintText: 'gacha', suffixText: 'so‘m'),
                  ),
                ),
              ],
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _price,
                    enabled: !draft.negotiable || schema.priceMode == PriceMode.optional,
                    keyboardType: TextInputType.number,
                    inputFormatters: const [ThousandsInputFormatter()],
                    onChanged: (v) => _controller.setPrice(ThousandsInputFormatter.parse(v)),
                    decoration: InputDecoration(
                      hintText: '0',
                      suffixText: schema.allowUsd ? null : 'so‘m',
                      errorText: errors[DraftField.price],
                    ),
                  ),
                ),
                if (schema.allowUsd) ...[
                  const SizedBox(width: AppSpacing.sm),
                  SegmentedButton<Currency>(
                    showSelectedIcon: false,
                    style: SegmentedButton.styleFrom(minimumSize: const Size(0, AppTouch.inputHeight)),
                    segments: const [
                      ButtonSegment(value: Currency.uzs, label: Text('so‘m')),
                      ButtonSegment(value: Currency.usd, label: Text('\$')),
                    ],
                    selected: {draft.currency},
                    onSelectionChanged: (value) => _controller.setCurrency(value.first),
                  ),
                ],
              ],
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text('Kelishiladi', style: text.bodyMedium),
              subtitle: Text('Narx bo‘yicha savdolashish mumkin', style: text.bodySmall),
              value: draft.negotiable,
              onChanged: (value) => _controller.setNegotiable(value: value),
            ),
          ],
        ],
        if (schema.supportsCondition) ...[
          const SizedBox(height: AppSpacing.sm),
          const _FieldLabel('Holati'),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<ItemCondition>(
              showSelectedIcon: false,
              emptySelectionAllowed: true,
              segments: [
                for (final condition in ItemCondition.values)
                  ButtonSegment(value: condition, label: Text(condition.label)),
              ],
              selected: {?draft.condition},
              onSelectionChanged: (value) => _controller.setCondition(value.isEmpty ? null : value.first),
            ),
          ),
        ],
        for (final field in schema.fields) ...[
          const SizedBox(height: AppSpacing.lg),
          _FieldLabel(field.unit == null ? field.label : '${field.label}, ${field.unit}', required: field.required),
          if (field.type == AttributeInputType.select)
            _OptionChips(
              options: field.options,
              selected: draft.attributes[field.key],
              error: errors[DraftField.attribute(field.key)],
              onSelected: (value) => _controller.setAttribute(field.key, value ?? ''),
            )
          else if (field.type == AttributeInputType.multiSelect)
            _MultiOptionChips(
              options: field.options,
              selected: (draft.attributes[field.key] ?? '')
                  .split(multiSelectSeparator)
                  .where((v) => v.isNotEmpty)
                  .toSet(),
              error: errors[DraftField.attribute(field.key)],
              onChanged: (values) => _controller.setAttribute(
                field.key,
                [
                  for (final option in field.options)
                    if (values.contains(option)) option,
                ].join(multiSelectSeparator),
              ),
            )
          else if (field.type == AttributeInputType.boolean)
            SegmentedButton<String>(
              emptySelectionAllowed: !field.required,
              segments: const [
                ButtonSegment(value: 'true', label: Text('Ha')),
                ButtonSegment(value: 'false', label: Text('Yo‘q')),
              ],
              selected: {?draft.attributes[field.key]},
              onSelectionChanged: (value) => _controller.setAttribute(field.key, value.isEmpty ? '' : value.first),
            )
          else
            TextField(
              controller: _attributeController(field.key, draft.attributes[field.key]),
              keyboardType: field.type == AttributeInputType.number ? TextInputType.number : TextInputType.text,
              inputFormatters: field.type == AttributeInputType.number
                  ? [FilteringTextInputFormatter.digitsOnly]
                  : null,
              textInputAction: TextInputAction.next,
              onChanged: (value) => _controller.setAttribute(field.key, value),
              decoration: InputDecoration(hintText: field.hint, errorText: errors[DraftField.attribute(field.key)]),
            ),
        ],
        const SizedBox(height: AppSpacing.lg),
        const _FieldLabel('Tavsif', required: true),
        TextField(
          controller: _description,
          minLines: 4,
          maxLines: 10,
          maxLength: ListingDraft.descriptionMaxLength,
          textCapitalization: TextCapitalization.sentences,
          keyboardType: TextInputType.multiline,
          onChanged: _controller.setDescription,
          decoration: InputDecoration(
            hintText: 'Batafsil ma’lumot yozing: holati, xususiyatlari, nima uchun sotilyapti…',
            errorText: errors[DraftField.description],
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        const _FieldLabel('Manzil', required: true),
        _PickerField(
          icon: Icons.location_on_rounded,
          tone: AccentTone.teal,
          value: draft.place?.fullLabel,
          placeholder: 'Manzilni tanlang',
          error: errors[DraftField.place],
          onTap: _pickPlace,
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Icon(Icons.lock_outline_rounded, size: AppIconSize.sm, color: palette.textTertiary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'Telefon raqamingiz e’londa ko‘rsatilmaydi — xaridor so‘raganda xavfsiz tarzda beriladi.',
                style: text.bodySmall,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label, {this.required = false});

  final String label;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text.rich(
        TextSpan(
          text: label,
          children: [
            if (required)
              TextSpan(
                text: ' *',
                style: TextStyle(color: palette.danger),
              ),
          ],
        ),
        style: Theme.of(context).textTheme.titleSmall,
      ),
    );
  }
}

class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.icon,
    required this.tone,
    required this.value,
    required this.placeholder,
    required this.onTap,
    this.error,
  });

  final IconData icon;
  final AccentTone tone;
  final String? value;
  final String placeholder;
  final VoidCallback onTap;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          label: value ?? placeholder,
          excludeSemantics: true,
          child: Material(
            color: palette.surfaceMuted,
            shape: RoundedRectangleBorder(
              borderRadius: AppRadii.mdAll,
              side: BorderSide(color: error == null ? Colors.transparent : palette.danger),
            ),
            child: InkWell(
              borderRadius: AppRadii.mdAll,
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
                child: Row(
                  children: [
                    ToneIcon(icon: icon, tone: tone, size: 34, radius: AppRadii.sm),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        value ?? placeholder,
                        style: text.bodyMedium?.copyWith(
                          color: value == null ? palette.textTertiary : palette.textPrimary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(Icons.keyboard_arrow_down_rounded, color: palette.textTertiary),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs, left: AppSpacing.md),
            child: Text(error!, style: text.bodySmall?.copyWith(color: palette.danger)),
          ),
      ],
    );
  }
}

class _MultiOptionChips extends StatelessWidget {
  const _MultiOptionChips({required this.options, required this.selected, required this.onChanged, this.error});

  final List<String> options;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final option in options)
              FilterChip(
                label: Text(option),
                selected: selected.contains(option),
                onSelected: (value) => onChanged(value ? {...selected, option} : ({...selected}..remove(option))),
              ),
          ],
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs, left: AppSpacing.xs),
            child: Text(error!, style: text.bodySmall?.copyWith(color: palette.danger)),
          ),
      ],
    );
  }
}

class _OptionChips extends StatelessWidget {
  const _OptionChips({required this.options, required this.selected, required this.onSelected, this.error});

  final List<String> options;
  final String? selected;
  final ValueChanged<String?> onSelected;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final option in options)
              ChoiceChip(
                label: Text(option),
                selected: selected == option,
                labelStyle: text.labelMedium?.copyWith(
                  color: selected == option ? palette.onPrimary : palette.textPrimary,
                ),
                onSelected: (value) => onSelected(value ? option : null),
              ),
          ],
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs, left: AppSpacing.xs),
            child: Text(error!, style: text.bodySmall?.copyWith(color: palette.danger)),
          ),
      ],
    );
  }
}
