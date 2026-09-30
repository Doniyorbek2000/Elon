import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n.dart';
import '../design/app_colors.dart';
import '../design/app_tokens.dart';
import '../widgets/app_image.dart';
import '../widgets/common.dart';
import '../widgets/sheets.dart';
import 'share_service.dart';

/// Share sheet with a preview of what recipients (e.g. in Telegram) will see:
/// image, title, price/salary, location and the deep link.
Future<void> showShareSheet(BuildContext context, SharePayload payload) {
  return showAppSheet<void>(context, builder: (_) => _ShareSheet(payload: payload));
}

class _ShareSheet extends ConsumerWidget {
  const _ShareSheet({required this.payload});

  final SharePayload payload;

  Future<void> _run(BuildContext context, Future<void> Function() action, {String? done}) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    Navigator.pop(context);
    try {
      await action();
      if (done != null) {
        messenger?.showSnackBar(SnackBar(content: Text(done)));
      }
    } on Object {
      messenger?.showSnackBar(SnackBar(content: Text(tr('Ulashib bo‘lmadi. Qayta urinib ko‘ring.'))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final share = ref.watch(shareServiceProvider);
    final palette = context.palette;
    final text = Theme.of(context).textTheme;
    final origin = context.findRenderObject() is RenderBox
        ? (context.findRenderObject()! as RenderBox).localToGlobal(Offset.zero) & const Size(1, 1)
        : null;

    return SheetScaffold(
      title: tr('Ulashish'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              label: tr('Havola ko‘rinishi: {title}', {'title': payload.title}),
              child: Container(
                decoration: BoxDecoration(
                  color: palette.surfaceMuted,
                  borderRadius: AppRadii.lgAll,
                  border: Border(left: BorderSide(color: palette.primary, width: 3)),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (payload.image != null) AspectRatio(aspectRatio: 1.91, child: AppImage(image: payload.image)),
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(payload.url.host, style: text.labelSmall?.copyWith(color: palette.primary)),
                          const SizedBox(height: AppSpacing.xxs),
                          Text(payload.title, style: text.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                          if (payload.subtitle != null)
                            Text(
                              payload.subtitle!,
                              style: text.titleSmall?.copyWith(color: palette.price, fontWeight: FontWeight.w800),
                            ),
                          if (payload.location != null)
                            MetaLine(icon: Icons.location_on_outlined, text: payload.location!),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF229ED9), foregroundColor: Colors.white),
              onPressed: () => _run(context, () => share.shareToTelegram(payload)),
              icon: const Icon(Icons.send_rounded),
              label: Text(tr('Telegram’da ulashish')),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _run(context, () => share.copyLink(payload), done: tr('Havola nusxalandi')),
                    icon: const Icon(Icons.link_rounded),
                    label: Text(tr('Nusxalash')),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _run(context, () => share.shareSystem(payload, origin: origin)),
                    icon: const Icon(Icons.ios_share_rounded),
                    label: Text(tr('Boshqa')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
