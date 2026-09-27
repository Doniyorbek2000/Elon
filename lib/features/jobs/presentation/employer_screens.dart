import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/config/feature_flags.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/avatar.dart';
import '../../../core/widgets/badges.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/contact_sheet.dart';
import '../../../core/widgets/state_views.dart';
import '../../chat/domain/chat.dart';
import '../../chat/presentation/start_chat.dart';
import '../../location/application/location_controller.dart';
import '../../monetization/domain/monetization.dart';
import '../../monetization/presentation/promote_sheet.dart';
import '../application/job_providers.dart';
import '../domain/job.dart';

// ─────────────────────────────────────────────────────────── my vacancies

class EmployerJobsScreen extends ConsumerWidget {
  const EmployerJobsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final now = ref.watch(clockProvider)();
    return Scaffold(
      appBar: AppBar(title: const Text('Mening vakansiyalarim')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppRoutes.createIn('jobs')),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Vakansiya'),
      ),
      body: ref
          .watch(myJobsProvider)
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => FailureView(error: error, onRetry: () => ref.invalidate(myJobsProvider)),
            data: (jobs) => jobs.isEmpty
                ? EmptyState(
                    icon: Icons.work_outline_rounded,
                    title: 'Vakansiyalar yo‘q',
                    message: 'Xodim kerak bo‘lsa, vakansiya joylang — arizalar shu yerda ko‘rinadi.',
                    actionLabel: 'Vakansiya joylash',
                    onAction: () => context.push(AppRoutes.createIn('jobs')),
                  )
                : RefreshIndicator.adaptive(
                    onRefresh: () => ref.refresh(myJobsProvider.future),
                    child: ContentWidth(
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 96),
                        itemCount: jobs.length,
                        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
                        itemBuilder: (_, index) {
                          final job = jobs[index];
                          return SurfaceCard(
                            onTap: () => context.push(AppRoutes.applicants(job.id)),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(job.title, style: text.titleSmall),
                                      Text(job.place.shortLabel, style: text.bodySmall),
                                      const SizedBox(height: AppSpacing.xs),
                                      Text(
                                        '${job.applicationCount ?? 0} ta ariza · '
                                        '${Formatters.relativeTime(job.publishedAt, now)}',
                                        style: text.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    StatusPill(
                                      label: job.status.label,
                                      dense: true,
                                      style: switch (job.status) {
                                        JobStatus.active => PillStyle.success,
                                        JobStatus.paused || JobStatus.draft => PillStyle.warning,
                                        JobStatus.rejected || JobStatus.expired => PillStyle.danger,
                                        _ => PillStyle.neutral,
                                      },
                                    ),
                                    _JobMenu(job: job),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
          ),
    );
  }
}

class _JobMenu extends ConsumerWidget {
  const _JobMenu({required this.job});

  final Job job;

  Future<void> _set(BuildContext context, WidgetRef ref, JobStatus status) async {
    try {
      await ref.read(jobRepositoryProvider).setJobStatus(job.id, status);
      ref.invalidate(myJobsProvider);
      if (context.mounted) showAppSnack(context, 'Holat yangilandi: ${status.label}');
    } on Object catch (error) {
      if (context.mounted) showAppSnack(context, error.asFailure().message, icon: Icons.error_outline_rounded);
    }
  }

  Future<void> _promote(BuildContext context, WidgetRef ref) async {
    final activated = await showPromoteSheet(
      context,
      target: PromotionTarget.job,
      targetId: job.id,
      itemTitle: job.title,
    );
    if (activated) ref.invalidate(myJobsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => PopupMenuButton<Object>(
    tooltip: 'Amallar',
    onSelected: (value) => value is JobStatus ? _set(context, ref, value) : _promote(context, ref),
    itemBuilder: (_) => [
      if (job.status == JobStatus.active && ref.read(featureFlagsProvider).canPromoteJobs)
        const PopupMenuItem<Object>(value: 'promote', child: Text('TOP / Shoshilinch')),
      if (job.status == JobStatus.active) const PopupMenuItem(value: JobStatus.paused, child: Text('To‘xtatish')),
      if (job.status == JobStatus.paused || job.status == JobStatus.expired)
        const PopupMenuItem(value: JobStatus.active, child: Text('Faollashtirish')),
      if (job.status == JobStatus.active || job.status == JobStatus.paused)
        const PopupMenuItem(value: JobStatus.filled, child: Text('Xodim topildi')),
      if (job.status != JobStatus.archived) const PopupMenuItem(value: JobStatus.archived, child: Text('Arxivlash')),
    ],
  );
}

// ─────────────────────────────────────────────────────────── applicants

class ApplicantsScreen extends ConsumerWidget {
  const ApplicantsScreen({super.key, required this.jobId});

  final String jobId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final job = ref.watch(jobDetailProvider(jobId)).value;
    return Scaffold(
      appBar: AppBar(title: Text(job == null ? 'Arizalar' : 'Arizalar · ${job.title}')),
      body: ref
          .watch(applicantsProvider(jobId))
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => FailureView(error: error, onRetry: () => ref.invalidate(applicantsProvider(jobId))),
            data: (applicants) => applicants.isEmpty
                ? const EmptyState(
                    icon: Icons.inbox_outlined,
                    title: 'Hali ariza yo‘q',
                    message: 'Nomzodlar ariza yuborganda shu yerda ko‘rasiz va sizga bildirishnoma keladi.',
                  )
                : RefreshIndicator.adaptive(
                    onRefresh: () => ref.refresh(applicantsProvider(jobId).future),
                    child: ContentWidth(
                      child: ListView.separated(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        itemCount: applicants.length,
                        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
                        itemBuilder: (_, index) => _ApplicantCard(jobId: jobId, applicant: applicants[index]),
                      ),
                    ),
                  ),
          ),
    );
  }
}

class _ApplicantCard extends ConsumerWidget {
  const _ApplicantCard({required this.jobId, required this.applicant});

  final String jobId;
  final Applicant applicant;

  static const _decisions = [ApplicationStatus.shortlisted, ApplicationStatus.accepted, ApplicationStatus.rejected];

  Future<void> _decide(BuildContext context, WidgetRef ref, ApplicationStatus status) async {
    try {
      await ref.read(jobRepositoryProvider).setApplicationStatus(applicant.applicationId, status);
      ref.invalidate(applicantsProvider(jobId));
      if (context.mounted) showAppSnack(context, 'Nomzodga xabar yuborildi: ${status.label}');
    } on Object catch (error) {
      if (context.mounted) showAppSnack(context, error.asFailure().message, icon: Icons.error_outline_rounded);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final palette = context.palette;
    final now = ref.watch(clockProvider)();
    final resume = applicant.resume;
    final phone = applicant.phone;
    return SurfaceCard(
      onTap: resume == null ? null : () => context.push(AppRoutes.candidate(resume.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppAvatar(name: applicant.profile.name, image: applicant.profile.avatar, size: 44),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(applicant.profile.name, style: text.titleSmall),
                    Text(
                      resume == null
                          ? 'Rezyume yashirilgan'
                          : '${resume.desiredPosition} · ${resume.experienceYears} yil tajriba',
                      style: text.bodySmall,
                    ),
                    Text(Formatters.relativeTime(applicant.appliedAt, now), style: text.labelSmall),
                  ],
                ),
              ),
              StatusPill(
                label: applicant.status.label,
                dense: true,
                style: switch (applicant.status) {
                  ApplicationStatus.shortlisted || ApplicationStatus.accepted => PillStyle.success,
                  ApplicationStatus.rejected => PillStyle.danger,
                  ApplicationStatus.withdrawn => PillStyle.neutral,
                  _ => PillStyle.primary,
                },
              ),
            ],
          ),
          if (applicant.message != null && applicant.message!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(applicant.message!, style: text.bodyMedium?.copyWith(color: palette.textSecondary)),
          ],
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              if (phone != null)
                OutlinedButton.icon(
                  onPressed: () => showContactSheet(context, person: applicant.profile, loadPhone: () async => phone),
                  icon: const Icon(Icons.call_rounded, size: 18),
                  label: const Text('Qo‘ng‘iroq'),
                ),
              if (resume != null)
                OutlinedButton.icon(
                  onPressed: () => startChat(
                    context,
                    ref,
                    peer: applicant.profile,
                    subject: ConversationContext(
                      subject: ConversationSubject.candidate,
                      refId: resume.id,
                      title: resume.desiredPosition,
                    ),
                  ),
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                  label: const Text('Chat'),
                ),
              if (applicant.status.isOpen)
                PopupMenuButton<ApplicationStatus>(
                  tooltip: 'Qaror',
                  onSelected: (status) => _decide(context, ref, status),
                  itemBuilder: (_) => [
                    for (final status in _decisions)
                      if (status != applicant.status) PopupMenuItem(value: status, child: Text(status.label)),
                  ],
                  child: Chip(
                    avatar: Icon(Icons.how_to_reg_rounded, size: 18, color: palette.primary),
                    label: const Text('Qaror'),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────── CV editor

class ResumeEditScreen extends ConsumerStatefulWidget {
  const ResumeEditScreen({super.key});

  @override
  ConsumerState<ResumeEditScreen> createState() => _ResumeEditScreenState();
}

class _ResumeEditScreenState extends ConsumerState<ResumeEditScreen> {
  final _title = TextEditingController();
  final _about = TextEditingController();
  final _skills = TextEditingController();
  final _experience = TextEditingController(text: '0');
  final _salary = TextEditingController();
  Set<EmploymentType> _types = {EmploymentType.fullTime};
  ResumeVisibility _visibility = ResumeVisibility.public;
  bool _loaded = false;
  bool _saving = false;
  Map<String, String> _errors = const {};

  @override
  void dispose() {
    for (final controller in [_title, _about, _skills, _experience, _salary]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _fill(CandidateProfile? resume) {
    if (_loaded) return;
    _loaded = true;
    if (resume == null) return;
    _title.text = resume.desiredPosition;
    _about.text = resume.about;
    _skills.text = resume.skills.join(', ');
    _experience.text = '${resume.experienceYears}';
    _salary.text = resume.expectedSalary == null ? '' : '${resume.expectedSalary!.amount}';
    _types = resume.employmentTypes.isEmpty ? {EmploymentType.fullTime} : {...resume.employmentTypes};
    _visibility = resume.visibility;
  }

  Future<void> _save() async {
    final errors = <String, String>{
      if (_title.text.trim().length < 2) 'title': 'Lavozimni kiriting',
      if (int.tryParse(_experience.text) == null) 'experience': 'Raqam kiriting',
    };
    setState(() => _errors = errors);
    if (errors.isNotEmpty) return;
    setState(() => _saving = true);
    final location = ref.read(locationProvider);
    try {
      await ref
          .read(jobRepositoryProvider)
          .saveResume(
            ResumeDraft(
              title: _title.text.trim(),
              about: _about.text.trim(),
              experienceYears: int.parse(_experience.text),
              skills: [
                for (final skill in _skills.text.split(','))
                  if (skill.trim().isNotEmpty) skill.trim(),
              ],
              employmentTypes: _types,
              regionId: location.regionId,
              districtId: location.districtId,
              salaryExpectation: int.tryParse(_salary.text.replaceAll(' ', '')),
              visibility: _visibility,
            ),
          );
      ref.invalidate(myResumeProvider);
      if (mounted) {
        showAppSnack(context, 'Rezyume saqlandi');
        context.pop();
      }
    } on Object catch (error) {
      final failure = error.asFailure();
      if (!mounted) return;
      setState(() {
        _saving = false;
        if (failure is ValidationFailure) _errors = failure.fieldErrors;
      });
      showAppSnack(context, failure.message, icon: Icons.error_outline_rounded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final resume = ref.watch(myResumeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Mening rezyumem')),
      body: resume.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => FailureView(error: error, onRetry: () => ref.invalidate(myResumeProvider)),
        data: (existing) {
          _fill(existing);
          return ContentWidth(
            maxWidth: AppBreakpoints.formMaxWidth,
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                Text('Ish qidiraman', style: text.titleMedium),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _title,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(labelText: 'Lavozim', errorText: _errors['title']),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _experience,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: 'Tajriba (yil)', errorText: _errors['experience']),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _skills,
                  decoration: const InputDecoration(labelText: 'Ko‘nikmalar', hintText: 'Masalan: savdo, 1C, Excel'),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _salary,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Kutilayotgan maosh (so‘m)'),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _about,
                  minLines: 3,
                  maxLines: 8,
                  maxLength: 2000,
                  decoration: const InputDecoration(labelText: 'O‘zingiz haqingizda'),
                ),
                const SizedBox(height: AppSpacing.md),
                Text('Bandlik turi', style: text.titleSmall),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final type in EmploymentType.values.where((t) => t != EmploymentType.remote))
                      FilterChip(
                        label: Text(type.label),
                        selected: _types.contains(type),
                        onSelected: (value) =>
                            setState(() => _types = value ? {..._types, type} : ({..._types}..remove(type))),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Text('Kim ko‘ra oladi', style: text.titleSmall),
                RadioGroup<ResumeVisibility>(
                  groupValue: _visibility,
                  onChanged: (value) => setState(() => _visibility = value ?? _visibility),
                  child: Column(
                    children: [
                      for (final visibility in ResumeVisibility.values)
                        RadioListTile<ResumeVisibility>(
                          value: visibility,
                          contentPadding: EdgeInsets.zero,
                          title: Text(visibility.label),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Saqlash'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
