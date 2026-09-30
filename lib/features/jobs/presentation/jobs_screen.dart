import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/utils/input_formatters.dart';
import '../../../core/widgets/app_search_field.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/paged_sliver.dart';
import '../../../core/widgets/sheets.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/state_views.dart';
import '../../location/application/location_controller.dart';
import '../../monetization/presentation/promoted_blocks.dart';
import '../application/job_providers.dart';
import '../domain/job.dart';
import 'widgets/job_cards.dart';

class JobsScreen extends ConsumerStatefulWidget {
  const JobsScreen({super.key, this.initialHiring = false});

  final bool initialHiring;

  @override
  ConsumerState<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends ConsumerState<JobsScreen> {
  late bool _hiring = widget.initialHiring;
  final _search = TextEditingController();
  JobQuery _refinements = const JobQuery();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  JobQuery get _query => _refinements.copyWith(regionId: () => ref.watch(locationProvider).regionId);

  Future<void> _openFilters() async {
    final result = await showAppSheet<JobQuery>(context, builder: (_) => _JobFilterSheet(initial: _refinements));
    if (result != null && mounted) setState(() => _refinements = result);
  }

  @override
  Widget build(BuildContext context) {
    final gutter = adaptiveGutter(context, maxWidth: AppBreakpoints.contentMaxWidth);
    final query = _query;
    final selectedType = _refinements.types.length == 1 ? _refinements.types.first : null;

    return Scaffold(
      appBar: AppBar(title: Text(tr('Ish'))),
      body: RefreshIndicator.adaptive(
        onRefresh: () async {
          ref.invalidate(jobSearchProvider(query));
          ref.invalidate(candidateSearchProvider(query));
        },
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(gutter, AppSpacing.sm, gutter, 0),
              sliver: SliverToBoxAdapter(
                child: _IntentSwitch(
                  hiring: _hiring,
                  onChanged: (value) {
                    HapticFeedback.selectionClick();
                    setState(() => _hiring = value);
                  },
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(gutter, AppSpacing.md, gutter, 0),
              sliver: SliverToBoxAdapter(
                child: AppSearchField(
                  controller: _search,
                  hint: _hiring ? tr('Kasb yoki ko‘nikma...') : tr('Kasb yoki kompaniya...'),
                  activeFilters: _refinements.activeFilterCount - (selectedType != null ? 1 : 0),
                  onFilterTap: _openFilters,
                  onSubmitted: (value) => setState(() => _refinements = _refinements.copyWith(text: value.trim())),
                  onClear: () => setState(() => _refinements = _refinements.copyWith(text: '')),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: ChoiceChipsRow<EmploymentType?>(
                  padding: EdgeInsets.symmetric(horizontal: gutter),
                  items: const [null, ...EmploymentType.values],
                  selected: selectedType,
                  labelOf: (type) => type?.label ?? tr('Barchasi'),
                  onSelected: (type) =>
                      setState(() => _refinements = _refinements.copyWith(types: type == null ? const {} : {type})),
                ),
              ),
            ),
            if (_hiring)
              SliverPadding(
                padding: EdgeInsets.fromLTRB(gutter, AppSpacing.md, gutter, 0),
                sliver: SliverToBoxAdapter(
                  child: _PostVacancyCard(onTap: () => context.push(AppRoutes.createIn('jobs'))),
                ),
              ),
            if (!_hiring)
              SliverPadding(
                padding: EdgeInsets.fromLTRB(gutter, AppSpacing.md, gutter, 0),
                sliver: SliverToBoxAdapter(child: PromotedJobsBlock(query: query)),
              ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(gutter, AppSpacing.md, gutter, AppSpacing.xxxl),
              sliver: _hiring ? _CandidateResults(query: query) : _JobResults(query: query),
            ),
          ],
        ),
      ),
    );
  }
}

class _IntentSwitch extends StatelessWidget {
  const _IntentSwitch({required this.hiring, required this.onChanged});

  final bool hiring;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = Theme.of(context).textTheme;
    Widget segment(String label, IconData icon, bool value) {
      final selected = hiring == value;
      return Expanded(
        child: Semantics(
          selected: selected,
          button: true,
          child: GestureDetector(
            onTap: () => onChanged(value),
            child: AnimatedContainer(
              duration: AppMotion.of(context, AppMotion.fast),
              constraints: const BoxConstraints(minHeight: AppTouch.minTarget),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
              decoration: BoxDecoration(
                color: selected ? palette.surface : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadii.md - 2),
                boxShadow: selected
                    ? AppShadows.card(palette, dark: Theme.of(context).brightness == Brightness.dark)
                    : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: AppIconSize.sm, color: selected ? palette.primary : palette.textSecondary),
                  const SizedBox(width: AppSpacing.xs + 2),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.labelLarge?.copyWith(color: selected ? palette.textPrimary : palette.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(color: palette.surfaceMuted, borderRadius: AppRadii.mdAll),
      child: Row(
        children: [
          segment(tr('Ish qidiraman'), Icons.person_search_rounded, false),
          segment(tr('Ishchi qidiraman'), Icons.groups_rounded, true),
        ],
      ),
    );
  }
}

class _PostVacancyCard extends StatelessWidget {
  const _PostVacancyCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = Theme.of(context).textTheme;
    return SurfaceCard(
      color: palette.primary,
      borderColor: Colors.transparent,
      onTap: onTap,
      child: Row(
        children: [
          const Icon(Icons.campaign_rounded, color: Colors.white, size: AppIconSize.xl),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('Vakansiya joylash'), style: text.titleSmall?.copyWith(color: Colors.white)),
                Text(
                  tr('Bepul. Hududingizdagi nomzodlar ko‘radi.'),
                  style: text.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.85)),
                ),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_rounded, color: Colors.white),
        ],
      ),
    );
  }
}

Widget _skeletonList() => SliverToBoxAdapter(
  child: Shimmer(
    child: Column(
      children: List.generate(
        4,
        (_) => const Padding(
          padding: EdgeInsets.only(bottom: AppSpacing.md),
          child: JobCardSkeleton(),
        ),
      ),
    ),
  ),
);

class _JobResults extends ConsumerWidget {
  const _JobResults({required this.query});

  final JobQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(jobSearchProvider(query))
        .when(
          skipLoadingOnRefresh: true,
          loading: _skeletonList,
          error: (error, _) => SliverToBoxAdapter(
            child: FailureView(error: error, compact: true, onRetry: () => ref.invalidate(jobSearchProvider(query))),
          ),
          data: (jobs) => jobs.isEmpty
              ? SliverToBoxAdapter(
                  child: EmptyState(
                    icon: Icons.work_off_outlined,
                    title: tr('Vakansiya topilmadi'),
                    message: tr('Filtrlarni o‘zgartiring yoki keyinroq qayta tekshiring.'),
                    compact: true,
                  ),
                )
              : SliverList.separated(
                  itemCount: jobs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
                  itemBuilder: (_, index) => JobCard(key: ValueKey(jobs[index].id), job: jobs[index]),
                ),
        );
  }
}

class _CandidateResults extends ConsumerWidget {
  const _CandidateResults({required this.query});

  final JobQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(candidateSearchProvider(query))
        .when(
          skipLoadingOnRefresh: true,
          loading: _skeletonList,
          error: (error, _) => SliverToBoxAdapter(
            child: FailureView(
              error: error,
              compact: true,
              onRetry: () => ref.invalidate(candidateSearchProvider(query)),
            ),
          ),
          data: (candidates) => candidates.isEmpty
              ? SliverToBoxAdapter(
                  child: EmptyState(
                    icon: Icons.person_search_outlined,
                    title: tr('Nomzod topilmadi'),
                    message: tr('Vakansiya joylang — mos nomzodlar o‘zlari bog‘lanadi.'),
                    compact: true,
                  ),
                )
              : SliverList.separated(
                  itemCount: candidates.length,
                  separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
                  itemBuilder: (_, index) => CandidateCard(candidate: candidates[index]),
                ),
        );
  }
}

class _JobFilterSheet extends StatefulWidget {
  const _JobFilterSheet({required this.initial});

  final JobQuery initial;

  @override
  State<_JobFilterSheet> createState() => _JobFilterSheetState();
}

class _JobFilterSheetState extends State<_JobFilterSheet> {
  late JobQuery _query = widget.initial;
  late final _salary = TextEditingController(text: ThousandsInputFormatter.format(widget.initial.minSalary));

  @override
  void dispose() {
    _salary.dispose();
    super.dispose();
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
      trailing: TextButton(
        onPressed: () {
          _salary.clear();
          setState(() => _query = JobQuery(text: _query.text));
        },
        child: Text(tr('Tozalash')),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            label(tr('Bandlik turi')),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final type in EmploymentType.values)
                  FilterChip(
                    label: Text(type.label),
                    selected: _query.types.contains(type),
                    labelStyle: text.labelMedium?.copyWith(
                      color: _query.types.contains(type) ? palette.onPrimary : palette.textPrimary,
                    ),
                    onSelected: (selected) => setState(() {
                      final types = {..._query.types};
                      selected ? types.add(type) : types.remove(type);
                      _query = _query.copyWith(types: types);
                    }),
                  ),
              ],
            ),
            label(tr('Tajriba')),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final level in <ExperienceLevel?>[null, ...ExperienceLevel.values])
                  ChoiceChip(
                    label: Text(level?.label ?? tr('Farqi yo‘q')),
                    selected: _query.experience == level,
                    labelStyle: text.labelMedium?.copyWith(
                      color: _query.experience == level ? palette.onPrimary : palette.textPrimary,
                    ),
                    onSelected: (_) => setState(() => _query = _query.copyWith(experience: () => level)),
                  ),
              ],
            ),
            label(tr('Maosh (dan)')),
            TextField(
              controller: _salary,
              keyboardType: TextInputType.number,
              inputFormatters: const [ThousandsInputFormatter()],
              decoration: InputDecoration(hintText: tr('Masalan: 4 000 000'), suffixText: tr('so‘m')),
            ),
            const SizedBox(height: AppSpacing.md),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('Avval yuqori maoshlilar')),
              value: _query.sortBySalary,
              onChanged: (value) => setState(() => _query = _query.copyWith(sortBySalary: value)),
            ),
          ],
        ),
      ),
      actions: FilledButton(
        onPressed: () =>
            Navigator.pop(context, _query.copyWith(minSalary: () => ThousandsInputFormatter.parse(_salary.text))),
        child: Text(tr('Natijalarni ko‘rsatish')),
      ),
    );
  }
}
