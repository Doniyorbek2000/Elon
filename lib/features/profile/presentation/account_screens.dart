import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/config/app_config.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/domain/media_image.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/external_actions.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/avatar.dart';
import '../../../core/widgets/badges.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/detail_widgets.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/application/session_controller.dart';
import '../../create_listing/data/media_services.dart';
import '../../jobs/application/job_providers.dart';
import '../../jobs/domain/job.dart';
import '../../search/application/search_providers.dart';
import '../../settings/application/settings_controller.dart';
import '../../trust_safety/application/trust_safety_providers.dart';
import '../application/profile_providers.dart';

// ------------------------------------------------------------ applications

class MyApplicationsScreen extends ConsumerWidget {
  const MyApplicationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider)();
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Mening arizalarim'))),
      body: ref
          .watch(myApplicationsProvider)
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => FailureView(error: error, onRetry: () => ref.invalidate(myApplicationsProvider)),
            data: (applications) => applications.isEmpty
                ? EmptyState(
                    icon: Icons.assignment_outlined,
                    title: tr('Hali ariza topshirmagansiz'),
                    message: tr('Yaqin atrofdagi vakansiyalarni ko‘ring va bir tugma bilan ariza yuboring.'),
                    actionLabel: tr('Vakansiyalar'),
                    onAction: () => context.push(AppRoutes.jobs),
                  )
                : ContentWidth(
                    child: ListView.separated(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      itemCount: applications.length,
                      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
                      itemBuilder: (_, index) {
                        final application = applications[index];
                        return SurfaceCard(
                          onTap: () => context.push(AppRoutes.job(application.job.id)),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(application.job.title, style: text.titleSmall),
                                    Text(application.job.company.name, style: text.bodySmall),
                                    const SizedBox(height: AppSpacing.xs),
                                    Text(
                                      tr('Yuborilgan: {p0}', {
                                        'p0': Formatters.relativeTime(application.appliedAt, now),
                                      }),
                                      style: text.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              StatusPill(
                                label: application.status.label,
                                style: switch (application.status) {
                                  ApplicationStatus.submitted || ApplicationStatus.withdrawn => PillStyle.neutral,
                                  ApplicationStatus.viewed => PillStyle.primary,
                                  ApplicationStatus.shortlisted || ApplicationStatus.accepted => PillStyle.success,
                                  ApplicationStatus.rejected => PillStyle.danger,
                                },
                              ),
                              if (application.status.isOpen)
                                IconButton(
                                  tooltip: tr('Arizani qaytarib olish'),
                                  icon: const Icon(Icons.undo_rounded),
                                  onPressed: () async {
                                    final confirmed = await confirmDialog(
                                      context,
                                      title: tr('Arizani qaytarib olasizmi?'),
                                      message: tr('Ish beruvchi arizangizni boshqa ko‘rmaydi.'),
                                      confirmLabel: tr('Qaytarib olish'),
                                    );
                                    if (!confirmed) return;
                                    try {
                                      await ref.read(myApplicationsProvider.notifier).withdraw(application.id);
                                    } on Object catch (error) {
                                      if (context.mounted) showAppSnack(context, error.asFailure().message);
                                    }
                                  },
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
          ),
    );
  }
}

// ---------------------------------------------------------------- settings

Future<void> _pickLanguage(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: RadioGroup<AppLanguage>(
        groupValue: ref.read(languageProvider),
        onChanged: (language) {
          if (language != null) ref.read(languageProvider.notifier).set(language);
          Navigator.of(sheetContext).pop();
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final language in AppLanguage.values)
              RadioListTile<AppLanguage>(value: language, title: Text(language.nativeName)),
          ],
        ),
      ),
    ),
  );
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final notifications = ref.watch(notificationsPreferenceProvider);
    final config = ref.watch(appConfigProvider);
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: Text(tr('Sozlamalar'))),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text(tr('Ko‘rinish'), style: text.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<ThemeMode>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: ThemeMode.system,
                    icon: const Icon(Icons.brightness_auto_rounded),
                    label: Text(tr('Tizim')),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    icon: const Icon(Icons.light_mode_rounded),
                    label: Text(tr('Yorug‘')),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    icon: const Icon(Icons.dark_mode_rounded),
                    label: Text(tr('Qorong‘i')),
                  ),
                ],
                selected: {themeMode},
                onSelectionChanged: (value) => ref.read(themeModeProvider.notifier).set(value.first),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            SurfaceCard(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Column(
                children: [
                  SwitchListTile.adaptive(
                    secondary: const Icon(Icons.notifications_active_outlined),
                    title: Text(tr('Bildirishnomalar')),
                    subtitle: Text(tr('Yangi xabarlar, narx tushishi, arizalar')),
                    value: notifications,
                    onChanged: (value) => ref.read(notificationsPreferenceProvider.notifier).set(enabled: value),
                  ),
                  ListTile(
                    leading: const Icon(Icons.language_rounded),
                    title: Text(tr('Til')),
                    subtitle: Text(ref.watch(languageProvider).nativeName),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _pickLanguage(context, ref),
                  ),
                  ListTile(
                    leading: const Icon(Icons.block_rounded),
                    title: Text(tr('Bloklangan foydalanuvchilar')),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.push(AppRoutes.blockedUsers),
                  ),
                  ListTile(
                    leading: const Icon(Icons.history_rounded),
                    title: Text(tr('Qidiruv tarixini tozalash')),
                    onTap: () {
                      ref.read(recentSearchesProvider.notifier).clear();
                      showAppSnack(context, tr('Qidiruv tarixi tozalandi'), icon: Icons.check_rounded);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            SurfaceCard(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.privacy_tip_outlined),
                    title: Text(tr('Maxfiylik siyosati')),
                    trailing: const Icon(Icons.open_in_new_rounded, size: AppIconSize.sm),
                    onTap: () => ref.read(externalActionsProvider).openUrl(Uri.parse('${config.webBaseUrl}/privacy')),
                  ),
                  ListTile(
                    leading: const Icon(Icons.gavel_rounded),
                    title: Text(tr('Foydalanish shartlari')),
                    trailing: const Icon(Icons.open_in_new_rounded, size: AppIconSize.sm),
                    onTap: () => ref.read(externalActionsProvider).openUrl(Uri.parse('${config.webBaseUrl}/terms')),
                  ),
                  ListTile(
                    leading: const Icon(Icons.info_outline_rounded),
                    title: Text(tr('Ilova versiyasi')),
                    trailing: Text(config.useDemoData ? tr('0.1.0 · demo') : '0.1.0', style: text.bodySmall),
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

class BlockedUsersScreen extends ConsumerWidget {
  const BlockedUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Bloklanganlar'))),
      body: ref
          .watch(blockedUsersProvider)
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => FailureView(error: error),
            data: (ids) => ids.isEmpty
                ? EmptyState(icon: Icons.block_rounded, title: tr('Bloklangan foydalanuvchilar yo‘q'))
                : ListView(
                    children: [
                      for (final id in ids)
                        Consumer(
                          builder: (context, ref, _) {
                            final profile = ref.watch(publicProfileProvider(id)).value;
                            return ListTile(
                              leading: AppAvatar(name: profile?.name ?? '?', image: profile?.avatar),
                              title: Text(profile?.name ?? '…'),
                              trailing: TextButton(
                                onPressed: () => ref.read(blockedUsersProvider.notifier).unblock(id),
                                child: Text(tr('Blokdan chiqarish')),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
          ),
    );
  }
}

// -------------------------------------------------------------------- help

class HelpScreen extends ConsumerWidget {
  const HelpScreen({super.key});

  static List<(String, String)> get _faq => [
    (tr('E’lon joylash pullikmi?'), tr('Yo‘q. Hozir barcha e’lonlar, vakansiyalar va xizmatlar bepul joylanadi.')),
    (
      tr('E’lonim nega «Tekshiruvda»?'),
      tr('Matnda telefon raqami, havola yoki oldindan to‘lov so‘rovi bo‘lsa, moderator tekshiradi. Odatda 15 daqiqa.'),
    ),
    (
      tr('Telefon raqamim hammaga ko‘rinadimi?'),
      tr('Yo‘q. Raqamingiz faqat xaridor «Qo‘ng‘iroq» tugmasini bosganda ko‘rsatiladi.'),
    ),
    (
      tr('Firibgarni qanday aniqlash mumkin?'),
      tr('Oldindan to‘lov so‘rash, karta raqami yoki SMS kodni talab qilish — firibgarlik belgilari. Shikoyat qiling.'),
    ),
    (tr('E’lonni qanday o‘chiraman?'), tr('Profil → Mening e’lonlarim → e’lon yonidagi ⋮ tugmasi → O‘chirish.')),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Yordam'))),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text(tr('Ko‘p so‘raladigan savollar'), style: text.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            SurfaceCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final (question, answer) in _faq)
                    ExpansionTile(
                      shape: const Border(),
                      title: Text(question, style: text.titleSmall),
                      childrenPadding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
                      expandedAlignment: Alignment.centerLeft,
                      children: [Text(answer, style: text.bodyMedium)],
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            const SafetyTipsCard(),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF229ED9)),
              onPressed: () => ref.read(externalActionsProvider).openUrl(Uri.parse(config.supportTelegramUrl)),
              icon: const Icon(Icons.support_agent_rounded),
              label: Text(tr('Qo‘llab-quvvatlash (Telegram)')),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ edit profile

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  late final _name = TextEditingController(text: ref.read(sessionProvider)?.name ?? '');
  MediaImage? _avatar;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    try {
      final paths = await ref.read(photoPickerProvider).pickFromGallery(limit: 1);
      if (paths.isNotEmpty) setState(() => _avatar = MediaImage.local('avatar', paths.first));
    } on Object {
      if (mounted) showAppSnack(context, tr('Rasm tanlab bo‘lmadi'));
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.length < 2) {
      setState(() => _error = tr('Ism kamida 2 ta harfdan iborat bo‘lsin'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider.notifier).updateProfile(name: name, avatar: _avatar);
      if (!mounted) return;
      context.pop();
      showAppSnack(context, tr('Profil yangilandi'), icon: Icons.check_rounded);
    } on Object {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppSnack(context, tr('Saqlab bo‘lmadi'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionProvider);
    final palette = context.palette;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Profilni tahrirlash'))),
      body: ContentWidth(
        maxWidth: AppBreakpoints.formMaxWidth,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            Center(
              child: Stack(
                children: [
                  AppAvatar(name: _name.text, image: _avatar ?? user?.avatar, size: 104),
                  PositionedDirectional(
                    end: 0,
                    bottom: 0,
                    child: IconButton.filled(
                      tooltip: tr('Rasmni o‘zgartirish'),
                      style: IconButton.styleFrom(backgroundColor: palette.primary),
                      onPressed: _pickAvatar,
                      icon: const Icon(Icons.photo_camera_rounded, color: Colors.white, size: AppIconSize.sm),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: tr('Ism'), errorText: _error),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (user != null)
              InputDecorator(
                decoration: InputDecoration(
                  labelText: tr('Telefon raqami'),
                  helperText: tr('Raqam boshqa foydalanuvchilarga faqat so‘ralganda ko‘rsatiladi'),
                  enabled: false,
                ),
                child: Text(Formatters.phone(user.phone)),
              ),
            const SizedBox(height: AppSpacing.xxl),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                    )
                  : Text(tr('Saqlash')),
            ),
          ],
        ),
      ),
    );
  }
}
