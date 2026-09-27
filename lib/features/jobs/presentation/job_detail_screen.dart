import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/app_colors.dart';
import '../../../core/design/app_icons.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/sharing/share_service.dart';
import '../../../core/sharing/share_sheet.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/avatar.dart';
import '../../../core/widgets/badges.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/contact_sheet.dart';
import '../../../core/widgets/detail_widgets.dart';
import '../../../core/widgets/favorite_button.dart';
import '../../../core/widgets/sheets.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/application/session_controller.dart';
import '../../auth/presentation/auth_gate.dart';
import '../../chat/domain/chat.dart';
import '../../chat/presentation/start_chat.dart';
import '../../saved/application/saved_items_controller.dart';
import '../../trust_safety/domain/trust_safety.dart';
import '../../trust_safety/presentation/report_sheet.dart';
import '../application/job_providers.dart';
import '../domain/job.dart';

class JobDetailScreen extends ConsumerWidget {
  const JobDetailScreen({super.key, required this.jobId});

  final String jobId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(jobDetailProvider(jobId))
        .when(
          data: (job) => _JobDetailView(job: job),
          loading: () => Scaffold(
            appBar: AppBar(),
            body: const Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => Scaffold(
            appBar: AppBar(),
            body: FailureView(error: error, onRetry: () => ref.invalidate(jobDetailProvider(jobId))),
          ),
        );
  }
}

class _JobDetailView extends ConsumerWidget {
  const _JobDetailView({required this.job});

  final Job job;

  SharePayload _payload(WidgetRef ref) => SharePayload(
    target: ShareTarget.job,
    id: job.id,
    title: '${job.title} — ${job.company.name}',
    subtitle: Formatters.salaryRange(job.salaryMin, job.salaryMax, job.currency).replaceAll(' ', ' '),
    location: job.place.shortLabel,
    url: ref.read(deepLinksProvider).web(ShareTarget.job, job.id),
  );

  Future<void> _apply(BuildContext context, WidgetRef ref) async {
    if (!await ensureSignedIn(context, ref) || !context.mounted) return;
    await showAppSheet<void>(context, builder: (_) => _ApplySheet(job: job));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final text = Theme.of(context).textTheme;
    final now = ref.watch(clockProvider)();
    final application = ref.watch(applicationForJobProvider(job.id));
    final isMine = ref.watch(sessionProvider)?.id == job.employer.id;
    final gutter = AppBreakpoints.pagePadding(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vakansiya'),
        actions: [
          IconButton(
            tooltip: 'Ulashish',
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: () => showShareSheet(context, _payload(ref)),
          ),
          FavoriteButton(kind: SavedKind.job, id: job.id),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(gutter, AppSpacing.md, gutter, AppSpacing.huge),
        children: [
          ContentWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          ToneIcon(icon: AppIcons.forKey(job.company.iconKey), tone: job.company.tone, size: 56),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(job.title, style: text.titleLarge),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        job.company.name,
                                        style: text.bodyMedium?.copyWith(color: palette.textSecondary),
                                      ),
                                    ),
                                    const SizedBox(width: AppSpacing.xs),
                                    VerifiedBadge(level: job.company.verification),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        Formatters.salaryRange(job.salaryMin, job.salaryMax, job.currency),
                        style: text.headlineSmall?.copyWith(color: palette.price, fontSize: 22),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: [
                          StatusPill(
                            label: job.employmentType.label,
                            style: PillStyle.primary,
                            icon: Icons.work_outline_rounded,
                          ),
                          StatusPill(label: job.experience.label, icon: Icons.trending_up_rounded),
                          if (job.workingHours.isNotEmpty)
                            StatusPill(label: job.workingHours, icon: Icons.schedule_rounded),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Wrap(
                        spacing: AppSpacing.lg,
                        runSpacing: AppSpacing.xs,
                        children: [
                          MetaLine(icon: Icons.location_on_outlined, text: job.place.shortLabel),
                          MetaLine(icon: Icons.schedule_rounded, text: Formatters.relativeTime(job.publishedAt, now)),
                          MetaLine(
                            icon: Icons.visibility_outlined,
                            text: '${Formatters.compactCount(job.views)} ko‘rish',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (application != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  _ApplicationStatusBanner(application: application),
                ],
                DetailSection(title: 'Tavsif', child: ExpandableText(job.description)),
                if (job.responsibilities.isNotEmpty)
                  DetailSection(
                    title: 'Vazifalar',
                    child: _Bullets(items: job.responsibilities),
                  ),
                if (job.requirements.isNotEmpty)
                  DetailSection(
                    title: 'Talablar',
                    child: _Bullets(items: job.requirements),
                  ),
                DetailSection(
                  title: 'Ish joyi',
                  child: SurfaceCard(
                    child: Row(
                      children: [
                        const ToneIcon(icon: Icons.map_rounded, tone: AccentTone.teal, size: 40),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(child: Text(job.place.fullLabel)),
                      ],
                    ),
                  ),
                ),
                DetailSection(
                  title: 'Ish beruvchi',
                  child: SurfaceCard(
                    child: Row(
                      children: [
                        AppAvatar(name: job.employer.name, image: job.employer.avatar, isOnline: job.employer.isOnline),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(job.employer.name, style: text.titleSmall),
                              if (job.employer.verification.isVerified)
                                Text(
                                  job.employer.verification.label,
                                  style: text.labelSmall?.copyWith(color: palette.primary),
                                ),
                              Text(
                                Formatters.presence(
                                  isOnline: job.employer.isOnline,
                                  lastActiveAt: job.employer.lastActiveAt,
                                  now: now,
                                ),
                                style: text.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        VerifiedBadge(level: job.employer.verification, size: 20),
                      ],
                    ),
                  ),
                ),
                if (job.company.about != null)
                  DetailSection(
                    title: 'Kompaniya haqida',
                    child: Text(job.company.about!, style: text.bodyMedium),
                  ),
                const SizedBox(height: AppSpacing.xl),
                const SafetyTipsCard(
                  tips: [
                    'Ishga joylashish uchun pul to‘lamang.',
                    'Pasport va karta ma’lumotlarini chatda yubormang.',
                    'Suhbatni ish joyida yoki ofisda o‘tkazing.',
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: palette.danger),
                  onPressed: () => showReportSheet(context, type: ReportTargetType.job, targetId: job.id),
                  icon: const Icon(Icons.flag_outlined, size: AppIconSize.sm),
                  label: const Text('Vakansiya ustidan shikoyat qilish'),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: isMine
          ? null
          : StickyActionBar(
              children: [
                OutlinedButton.icon(
                  onPressed: () => startChat(
                    context,
                    ref,
                    peer: job.employer,
                    subject: ConversationContext(
                      subject: ConversationSubject.job,
                      refId: job.id,
                      title: job.title,
                      subtitle: Formatters.salaryRange(job.salaryMin, job.salaryMax, job.currency),
                    ),
                  ),
                  icon: const Icon(Icons.chat_bubble_outline_rounded),
                  label: const Text('Chat'),
                ),
                application != null
                    ? FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: palette.success),
                        onPressed: () => showContactSheet(
                          context,
                          person: job.employer,
                          loadPhone: () => ref.read(jobRepositoryProvider).revealJobPhone(job.id),
                        ),
                        icon: const Icon(Icons.call_rounded),
                        label: const Text('Qo‘ng‘iroq'),
                      )
                    : FilledButton.icon(
                        onPressed: () => _apply(context, ref),
                        icon: const Icon(Icons.send_rounded),
                        label: const Text('Ariza topshirish'),
                      ),
              ],
            ),
    );
  }
}

class _Bullets extends StatelessWidget {
  const _Bullets({required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: AppSpacing.sm),
                  child: Icon(Icons.check_circle_rounded, size: AppIconSize.sm, color: palette.success),
                ),
                Expanded(child: Text(item, style: Theme.of(context).textTheme.bodyMedium)),
              ],
            ),
          ),
      ],
    );
  }
}

class _ApplicationStatusBanner extends ConsumerWidget {
  const _ApplicationStatusBanner({required this.application});

  final JobApplication application;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final now = ref.watch(clockProvider)();
    final (color, bg) = switch (application.status) {
      ApplicationStatus.shortlisted || ApplicationStatus.accepted => (palette.success, palette.successSoft),
      ApplicationStatus.rejected => (palette.danger, palette.dangerSoft),
      _ => (palette.primary, palette.primarySoft),
    };
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: bg, borderRadius: AppRadii.mdAll),
      child: Row(
        children: [
          Icon(Icons.assignment_turned_in_rounded, color: color),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'Ariza: ${application.status.label} · ${Formatters.relativeTime(application.appliedAt, now)}',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _ApplySheet extends ConsumerStatefulWidget {
  const _ApplySheet({required this.job});

  final Job job;

  @override
  ConsumerState<_ApplySheet> createState() => _ApplySheetState();
}

class _ApplySheetState extends ConsumerState<_ApplySheet> {
  final _message = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _sending = true);
    try {
      await ref
          .read(myApplicationsProvider.notifier)
          .apply(widget.job.id, message: _message.text.trim().isEmpty ? null : _message.text.trim());
      if (!mounted) return;
      Navigator.pop(context);
      showAppSnack(context, 'Arizangiz yuborildi! Ish beruvchi javobini kuting.', icon: Icons.check_circle_rounded);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _sending = false);
      showAppSnack(context, error.asFailure().message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionProvider);
    final text = Theme.of(context).textTheme;
    return SheetScaffold(
      title: 'Ariza topshirish',
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${widget.job.title} · ${widget.job.company.name}', style: text.bodySmall),
            const SizedBox(height: AppSpacing.lg),
            if (user != null)
              SurfaceCard(
                child: Row(
                  children: [
                    AppAvatar(name: user.name, image: user.avatar),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(user.name, style: text.titleSmall),
                          Text(Formatters.phone(user.phone), style: text.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _message,
              minLines: 3,
              maxLines: 6,
              maxLength: 800,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'O‘zingiz haqingizda qisqacha: tajriba, qachondan ishlay olasiz…',
              ),
            ),
            Text('Ish beruvchi ismingiz va telefon raqamingizni ko‘radi.', style: text.bodySmall),
          ],
        ),
      ),
      actions: FilledButton(
        onPressed: _sending ? null : _submit,
        child: _sending
            ? const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
              )
            : const Text('Yuborish'),
      ),
    );
  }
}
