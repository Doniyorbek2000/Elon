import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/app_colors.dart';
import '../../../core/design/app_tokens.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/sheets.dart';
import '../application/trust_safety_providers.dart';
import '../domain/trust_safety.dart';

Future<void> showReportSheet(BuildContext context, {required ReportTargetType type, required String targetId}) {
  return showAppSheet<void>(
    context,
    builder: (_) => ReportSheet(type: type, targetId: targetId),
  );
}

class ReportSheet extends ConsumerStatefulWidget {
  const ReportSheet({super.key, required this.type, required this.targetId});

  final ReportTargetType type;
  final String targetId;

  @override
  ConsumerState<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<ReportSheet> {
  ReportReason? _reason;
  final _comment = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _reason;
    if (reason == null) return;
    setState(() => _sending = true);
    try {
      await ref
          .read(trustSafetyRepositoryProvider)
          .report(
            ReportRequest(
              targetType: widget.type,
              targetId: widget.targetId,
              reason: reason,
              comment: _comment.text.trim().isEmpty ? null : _comment.text.trim(),
            ),
          );
      if (!mounted) return;
      Navigator.pop(context);
      showAppSnack(context, 'Rahmat! Shikoyatingiz moderatorlarga yuborildi.', icon: Icons.check_circle_rounded);
    } on Object {
      if (!mounted) return;
      setState(() => _sending = false);
      showAppSnack(context, 'Yuborib bo‘lmadi. Qayta urinib ko‘ring.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SheetScaffold(
      title: 'Shikoyat qilish',
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.sm, 0, AppSpacing.xl, AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.md, bottom: AppSpacing.sm),
              child: Text('Sababni tanlang. Shikoyatlar anonim ko‘rib chiqiladi.', style: text.bodySmall),
            ),
            RadioGroup<ReportReason>(
              groupValue: _reason,
              onChanged: (value) => setState(() => _reason = value),
              child: Column(
                children: [
                  for (final reason in ReportReason.values)
                    RadioListTile<ReportReason>(
                      value: reason,
                      dense: true,
                      title: Text(reason.label, style: text.bodyMedium),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.md, top: AppSpacing.sm),
              child: TextField(
                controller: _comment,
                maxLines: 3,
                maxLength: 500,
                decoration: const InputDecoration(hintText: 'Qo‘shimcha izoh (ixtiyoriy)'),
              ),
            ),
          ],
        ),
      ),
      actions: FilledButton(
        style: FilledButton.styleFrom(backgroundColor: context.palette.danger),
        onPressed: _reason == null || _sending ? null : _submit,
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

/// Confirm + block. Returns true when the user was blocked.
Future<bool> confirmAndBlock(
  BuildContext context,
  WidgetRef ref, {
  required String userId,
  required String name,
}) async {
  final confirmed = await confirmDialog(
    context,
    title: '$name bloklansinmi?',
    message:
        'U sizga yoza olmaydi va uning e’lonlari sizga ko‘rsatilmaydi. Istalgan vaqtda blokdan chiqarishingiz mumkin.',
    confirmLabel: 'Bloklash',
    destructive: true,
  );
  if (!confirmed || !context.mounted) return false;
  try {
    await ref.read(blockedUsersProvider.notifier).block(userId);
    if (context.mounted) showAppSnack(context, '$name bloklandi', icon: Icons.block_rounded);
    return true;
  } on Object {
    if (context.mounted) showAppSnack(context, 'Bloklab bo‘lmadi. Qayta urinib ko‘ring.');
    return false;
  }
}
