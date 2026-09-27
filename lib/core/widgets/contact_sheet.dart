import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/app_colors.dart';
import '../design/app_tokens.dart';
import '../domain/public_profile.dart';
import '../utils/external_actions.dart';
import '../utils/formatters.dart';
import 'avatar.dart';
import 'badges.dart';
import 'common.dart';
import 'sheets.dart';
import 'state_views.dart';

/// Reveals a contact number on explicit request (server-side rate limited)
/// and lets the user place the call.
Future<void> showContactSheet(
  BuildContext context, {
  required PublicProfile person,
  required Future<String> Function() loadPhone,
}) {
  return showAppSheet<void>(
    context,
    builder: (_) => _ContactSheet(person: person, loadPhone: loadPhone),
  );
}

class _ContactSheet extends ConsumerStatefulWidget {
  const _ContactSheet({required this.person, required this.loadPhone});

  final PublicProfile person;
  final Future<String> Function() loadPhone;

  @override
  ConsumerState<_ContactSheet> createState() => _ContactSheetState();
}

class _ContactSheetState extends ConsumerState<_ContactSheet> {
  late Future<String> _phone = widget.loadPhone();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final palette = context.palette;
    return SheetScaffold(
      title: 'Bog‘lanish',
      body: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.lg),
        child: FutureBuilder<String>(
          future: _phone,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return FailureView(
                error: snapshot.error!,
                compact: true,
                onRetry: () => setState(() => _phone = widget.loadPhone()),
              );
            }
            final phone = snapshot.data;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    AppAvatar(
                      name: widget.person.name,
                      image: widget.person.avatar,
                      size: 48,
                      isOnline: widget.person.isOnline,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  widget.person.name,
                                  style: text.titleSmall,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              VerifiedBadge(level: widget.person.verification),
                            ],
                          ),
                          const SizedBox(height: 2),
                          AnimatedSwitcher(
                            duration: AppMotion.of(context, AppMotion.fast),
                            child: Text(
                              phone == null ? 'Raqam yuklanmoqda…' : Formatters.phone(phone),
                              key: ValueKey(phone),
                              style: text.titleMedium?.copyWith(
                                fontFeatures: const [FontFeature.tabularFigures()],
                                color: phone == null ? palette.textTertiary : palette.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: palette.success),
                  onPressed: phone == null
                      ? null
                      : () async {
                          final ok = await ref.read(externalActionsProvider).call(phone);
                          if (!context.mounted) return;
                          if (ok) {
                            Navigator.pop(context);
                          } else {
                            showAppSnack(context, 'Qo‘ng‘iroq qilib bo‘lmadi');
                          }
                        },
                  icon: const Icon(Icons.call_rounded),
                  label: const Text('Qo‘ng‘iroq qilish'),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Qo‘ng‘iroq qilganingizda «Bozor.uz’dagi e’lon bo‘yicha» deb ayting. Oldindan to‘lov so‘ralsa — ehtiyot bo‘ling.',
                  textAlign: TextAlign.center,
                  style: text.bodySmall,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
