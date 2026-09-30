import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/design/app_colors.dart';
import '../../../../core/design/app_icons.dart';
import '../../../../core/design/app_tokens.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/utils/clock.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/avatar.dart';
import '../../../../core/widgets/badges.dart';
import '../../../../core/widgets/common.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../domain/job.dart';

class JobCard extends ConsumerWidget {
  const JobCard({super.key, required this.job});

  final Job job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final text = Theme.of(context).textTheme;
    final now = ref.watch(clockProvider)();
    final salary = Formatters.salaryRange(job.salaryMin, job.salaryMax, job.currency);
    final meta = '${job.place.shortLabel} · ${Formatters.relativeTime(job.publishedAt, now)}';

    return SurfaceCard(
      padding: const EdgeInsets.all(AppSpacing.md + 2),
      onTap: () => context.push(AppRoutes.job(job.id)),
      child: Semantics(
        label: '${job.title}, ${job.company.name}, $salary, ${job.employmentType.label}, $meta',
        excludeSemantics: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ToneIcon(icon: AppIcons.forKey(job.company.iconKey), tone: job.company.tone, size: 48),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(job.title, style: text.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      if (job.isNew(now)) StatusPill(label: tr('Yangi'), style: PillStyle.success, dense: true),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          job.company.name,
                          style: text.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      VerifiedBadge(level: job.company.verification, size: 14),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs + 2),
                  Text(
                    salary,
                    style: text.titleSmall?.copyWith(color: palette.price, fontWeight: FontWeight.w800),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.xs + 2),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      StatusPill(label: job.employmentType.label, dense: true),
                      Text(meta, style: text.bodySmall?.copyWith(color: palette.textTertiary)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CandidateCard extends ConsumerWidget {
  const CandidateCard({super.key, required this.candidate});

  final CandidateProfile candidate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final text = Theme.of(context).textTheme;
    final now = ref.watch(clockProvider)();
    return SurfaceCard(
      padding: const EdgeInsets.all(AppSpacing.md + 2),
      onTap: () => context.push(AppRoutes.candidate(candidate.id)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppAvatar(
            name: candidate.profile.name,
            image: candidate.profile.avatar,
            size: 52,
            isOnline: candidate.profile.isOnline,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(candidate.desiredPosition, style: text.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Flexible(
                      child: Text(candidate.profile.name, style: text.bodySmall, overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    VerifiedBadge(level: candidate.profile.verification, size: 14),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs + 2),
                Text(
                  candidate.expectedSalary == null
                      ? tr('Maosh: kelishiladi')
                      : tr('{p0} dan', {'p0': Formatters.money(candidate.expectedSalary!)}),
                  style: text.titleSmall?.copyWith(color: palette.price, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: AppSpacing.xs + 2),
                Text(
                  tr('{experienceYears} yil tajriba · {shortLabel} · {p2}', {
                    'experienceYears': candidate.experienceYears,
                    'shortLabel': candidate.place.shortLabel,
                    'p2': Formatters.relativeTime(candidate.updatedAt, now),
                  }),
                  style: text.bodySmall?.copyWith(color: palette.textTertiary),
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class JobCardSkeleton extends StatelessWidget {
  const JobCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) => const SurfaceCard(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SkeletonBox(width: 48, height: 48, radius: AppRadii.md),
        SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonLine(widthFactor: 0.6, height: 14),
              SizedBox(height: AppSpacing.sm),
              SkeletonLine(widthFactor: 0.4, height: 10),
              SizedBox(height: AppSpacing.md),
              SkeletonLine(widthFactor: 0.7, height: 14),
            ],
          ),
        ),
      ],
    ),
  );
}
