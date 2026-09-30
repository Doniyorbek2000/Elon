import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/app_colors.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/avatar.dart';
import '../../../core/widgets/badges.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/contact_sheet.dart';
import '../../../core/widgets/detail_widgets.dart';
import '../../../core/widgets/sheets.dart' show StickyActionBar;
import '../../../core/widgets/state_views.dart';
import '../../chat/domain/chat.dart';
import '../../chat/presentation/start_chat.dart';
import '../../trust_safety/domain/trust_safety.dart';
import '../../trust_safety/presentation/report_sheet.dart';
import '../application/job_providers.dart';
import '../domain/job.dart';

class CandidateDetailScreen extends ConsumerWidget {
  const CandidateDetailScreen({super.key, required this.candidateId});

  final String candidateId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(candidateDetailProvider(candidateId))
        .when(
          data: (candidate) => _CandidateView(candidate: candidate),
          loading: () => Scaffold(
            appBar: AppBar(),
            body: const Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => Scaffold(
            appBar: AppBar(),
            body: FailureView(error: error, onRetry: () => ref.invalidate(candidateDetailProvider(candidateId))),
          ),
        );
  }
}

class _CandidateView extends ConsumerWidget {
  const _CandidateView({required this.candidate});

  final CandidateProfile candidate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final palette = context.palette;
    final now = ref.watch(clockProvider)();
    final profile = candidate.profile;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Rezyume')),
        actions: [
          IconButton(
            tooltip: tr('Shikoyat'),
            icon: const Icon(Icons.flag_outlined),
            onPressed: () => showReportSheet(context, type: ReportTargetType.user, targetId: profile.id),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.huge),
        children: [
          ContentWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: AppAvatar(name: profile.name, image: profile.avatar, size: 96, isOnline: profile.isOnline),
                ),
                const SizedBox(height: AppSpacing.md),
                Center(
                  child: Text(candidate.desiredPosition, style: text.titleLarge, textAlign: TextAlign.center),
                ),
                const SizedBox(height: AppSpacing.xs),
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(profile.name, style: text.bodyMedium?.copyWith(color: palette.textSecondary)),
                      const SizedBox(width: AppSpacing.xs),
                      VerifiedBadge(level: profile.verification),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                SurfaceCard(
                  color: palette.surfaceMuted,
                  borderColor: Colors.transparent,
                  child: Row(
                    children: [
                      Expanded(
                        child: InfoTile(
                          label: tr('Tajriba'),
                          value: tr('{experienceYears} yil', {'experienceYears': candidate.experienceYears}),
                        ),
                      ),
                      Expanded(
                        child: InfoTile(
                          label: tr('Kutilayotgan maosh'),
                          value: candidate.expectedSalary == null
                              ? tr('Kelishiladi')
                              : Formatters.money(candidate.expectedSalary!),
                        ),
                      ),
                      Expanded(
                        child: InfoTile(label: tr('Hudud'), value: candidate.place.shortLabel),
                      ),
                    ],
                  ),
                ),
                DetailSection(
                  title: tr('Ko‘nikmalar'),
                  child: Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      for (final skill in candidate.skills) StatusPill(label: skill, style: PillStyle.primary),
                    ],
                  ),
                ),
                DetailSection(
                  title: tr('Qulay bandlik'),
                  child: Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [for (final type in candidate.employmentTypes) StatusPill(label: type.label)],
                  ),
                ),
                DetailSection(
                  title: tr('O‘zi haqida'),
                  child: Text(candidate.about, style: text.bodyMedium),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  tr('Yangilangan: {p0}', {'p0': Formatters.relativeTime(candidate.updatedAt, now)}),
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: StickyActionBar(
        children: [
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: palette.success),
            onPressed: () => showContactSheet(
              context,
              person: profile,
              loadPhone: () => ref.read(jobRepositoryProvider).revealCandidatePhone(candidate.id),
            ),
            icon: const Icon(Icons.call_rounded),
            label: Text(tr('Qo‘ng‘iroq')),
          ),
          FilledButton.icon(
            onPressed: () => startChat(
              context,
              ref,
              peer: profile,
              subject: ConversationContext(
                subject: ConversationSubject.candidate,
                refId: candidate.id,
                title: candidate.desiredPosition,
                subtitle: tr('{experienceYears} yil tajriba', {'experienceYears': candidate.experienceYears}),
                image: profile.avatar,
              ),
            ),
            icon: const Icon(Icons.chat_bubble_rounded),
            label: Text(tr('Chat')),
          ),
        ],
      ),
    );
  }
}
