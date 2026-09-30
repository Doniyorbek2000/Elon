import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/l10n/l10n.dart';
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
      appBar: AppBar(title: Text(tr('Mening vakansiyalarim'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppRoutes.createIn('jobs')),
        icon: const Icon(Icons.add_rounded),
        label: Text(tr('Vakansiya')),
      ),
      body: ref
          .watch(myJobsProvider)
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => FailureView(error: error, onRetry: () => ref.invalidate(myJobsProvider)),
            data: (jobs) => jobs.isEmpty
                ? EmptyState(
                    icon: Icons.work_outline_rounded,
                    title: tr('Vakansiyalar yo‘q'),
                    message: tr('Xodim kerak bo‘lsa, vakansiya joylang — arizalar shu yerda ko‘rinadi.'),
                    actionLabel: tr('Vakansiya joylash'),
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
                                        tr('{p0} ta ariza · {p1}', {
                                          'p0': job.applicationCount ?? 0,
                                          'p1': Formatters.relativeTime(job.publishedAt, now),
                                        }),
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
      if (context.mounted) showAppSnack(context, tr('Holat yangilandi: {label}', {'label': status.label}));
    } on Object catch (error) {
      if (context.mounted) showAppSnack(context, error.asFailure().message, icon: Icons.error_outline_rounded);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => PopupMenuButton<JobStatus>(
    tooltip: tr('Amallar'),
    onSelected: (value) => _set(context, ref, value),
    itemBuilder: (_) => [
      if (job.status == JobStatus.active) PopupMenuItem(value: JobStatus.paused, child: Text(tr('To‘xtatish'))),
      if (job.status == JobStatus.paused || job.status == JobStatus.expired)
        PopupMenuItem(value: JobStatus.active, child: Text(tr('Faollashtirish'))),
      if (job.status == JobStatus.active || job.status == JobStatus.paused)
        PopupMenuItem(value: JobStatus.filled, child: Text(tr('Xodim topildi'))),
      if (job.status != JobStatus.archived) PopupMenuItem(value: JobStatus.archived, child: Text(tr('Arxivlash'))),
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
      appBar: AppBar(title: Text(job == null ? tr('Arizalar') : tr('Arizalar · {title}', {'title': job.title}))),
      body: ref
          .watch(applicantsProvider(jobId))
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => FailureView(error: error, onRetry: () => ref.invalidate(applicantsProvider(jobId))),
            data: (applicants) => applicants.isEmpty
                ? EmptyState(
                    icon: Icons.inbox_outlined,
                    title: tr('Hali ariza yo‘q'),
                    message: tr('Nomzodlar ariza yuborganda shu yerda ko‘rasiz va sizga bildirishnoma keladi.'),
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
      if (context.mounted) showAppSnack(context, tr('Nomzodga xabar yuborildi: {label}', {'label': status.label}));
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
                          ? tr('Rezyume yashirilgan')
                          : tr('{desiredPosition} · {experienceYears} yil tajriba', {
                              'desiredPosition': resume.desiredPosition,
                              'experienceYears': resume.experienceYears,
                            }),
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
                  label: Text(tr('Qo‘ng‘iroq')),
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
                  label: Text(tr('Chat')),
                ),
              if (applicant.status.isOpen)
                PopupMenuButton<ApplicationStatus>(
                  tooltip: tr('Qaror'),
                  onSelected: (status) => _decide(context, ref, status),
                  itemBuilder: (_) => [
                    for (final status in _decisions)
                      if (status != applicant.status) PopupMenuItem(value: status, child: Text(status.label)),
                  ],
                  child: Chip(
                    avatar: Icon(Icons.how_to_reg_rounded, size: 18, color: palette.primary),
                    label: Text(tr('Qaror')),
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
      if (_title.text.trim().length < 2) 'title': tr('Lavozimni kiriting'),
      if (int.tryParse(_experience.text) == null) 'experience': tr('Raqam kiriting'),
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
        showAppSnack(context, tr('Rezyume saqlandi'));
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
      appBar: AppBar(title: Text(tr('Mening rezyumem'))),
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
                Text(tr('Ish qidiraman'), style: text.titleMedium),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _title,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(labelText: tr('Lavozim'), errorText: _errors['title']),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _experience,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: tr('Tajriba (yil)'), errorText: _errors['experience']),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _skills,
                  decoration: InputDecoration(labelText: tr('Ko‘nikmalar'), hintText: tr('Masalan: savdo, 1C, Excel')),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _salary,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: tr('Kutilayotgan maosh (so‘m)')),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _about,
                  minLines: 3,
                  maxLines: 8,
                  maxLength: 2000,
                  decoration: InputDecoration(labelText: tr('O‘zingiz haqingizda')),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(tr('Bandlik turi'), style: text.titleSmall),
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
                Text(tr('Kim ko‘ra oladi'), style: text.titleSmall),
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
                      : Text(tr('Saqlash')),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
