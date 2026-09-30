import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/app_colors.dart';
import '../../../../core/design/app_tokens.dart';
import '../../../../core/domain/media_image.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/widgets/app_image.dart';
import '../../../../core/widgets/common.dart';
import '../../../../core/widgets/sheets.dart';
import '../../application/create_listing_controller.dart';
import '../../data/media_services.dart';
import '../../domain/listing_draft.dart';

/// Step 2: add (gallery/camera), reorder by long-press drag, choose cover,
/// remove, watch per-photo upload progress, retry failures.
class PhotosStep extends ConsumerWidget {
  const PhotosStep({super.key, required this.errors});

  final Map<String, String> errors;

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(createListingProvider.notifier);
    final remaining = controller.remainingPhotoSlots;
    if (remaining <= 0) {
      showAppSnack(
        context,
        tr('Ko‘pi bilan {maxPhotos} ta rasm qo‘shish mumkin', {'maxPhotos': ListingDraft.maxPhotos}),
      );
      return;
    }
    final source = await showAppSheet<_Source>(
      context,
      builder: (context) => SheetScaffold(
        title: tr('Rasm qo‘shish'),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const ToneIcon(icon: Icons.photo_library_rounded, tone: AccentTone.blue, size: 40),
                title: Text(tr('Galereyadan tanlash')),
                subtitle: Text(tr('Bir nechta rasm tanlash mumkin ({remaining} ta qoldi)', {'remaining': remaining})),
                onTap: () => Navigator.pop(context, _Source.gallery),
              ),
              ListTile(
                leading: const ToneIcon(icon: Icons.photo_camera_rounded, tone: AccentTone.green, size: 40),
                title: Text(tr('Kamera bilan olish')),
                onTap: () => Navigator.pop(context, _Source.camera),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null) return;
    final picker = ref.read(photoPickerProvider);
    try {
      final paths = switch (source) {
        _Source.gallery => await picker.pickFromGallery(limit: remaining),
        _Source.camera => [?await picker.takePhoto()],
      };
      controller.addPhotos(paths);
    } on PlatformException catch (error) {
      if (!context.mounted) return;
      final denied = error.code.contains('denied') || error.code.contains('access');
      showAppSnack(
        context,
        denied ? tr('Rasmlarga ruxsat berilmagan. Sozlamalardan ruxsat bering.') : tr('Rasm tanlab bo‘lmadi'),
        icon: Icons.no_photography_outlined,
      );
    }
  }

  Future<void> _photoActions(BuildContext context, WidgetRef ref, DraftPhoto photo, int index) async {
    final controller = ref.read(createListingProvider.notifier);
    await showAppSheet<void>(
      context,
      builder: (context) => SheetScaffold(
        title: tr('Rasm'),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (index > 0)
                ListTile(
                  leading: const Icon(Icons.star_rounded),
                  title: Text(tr('Muqova qilish')),
                  onTap: () {
                    controller.makeCover(photo.id);
                    Navigator.pop(context);
                  },
                ),
              if (photo.failed)
                ListTile(
                  leading: const Icon(Icons.refresh_rounded),
                  title: Text(tr('Qayta yuklash')),
                  onTap: () {
                    controller.retryUpload(photo.id);
                    Navigator.pop(context);
                  },
                ),
              ListTile(
                leading: Icon(Icons.delete_outline_rounded, color: context.palette.danger),
                title: Text(tr('O‘chirish'), style: TextStyle(color: context.palette.danger)),
                onTap: () {
                  controller.removePhoto(photo.id);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(createListingProvider);
    final controller = ref.read(createListingProvider.notifier);
    final assist = ref.watch(listingAssistServiceProvider);
    final palette = context.palette;
    final text = Theme.of(context).textTheme;
    final error = errors[DraftField.photos];
    final required = controller.schema.photosRequired;

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xxxl),
      children: [
        Row(
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  text: tr('Rasmlar'),
                  children: [
                    if (required)
                      TextSpan(
                        text: ' *',
                        style: TextStyle(color: palette.danger),
                      ),
                    TextSpan(text: '  ${draft.photos.length}/${ListingDraft.maxPhotos}', style: text.bodySmall),
                  ],
                ),
                style: text.titleMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          tr('Birinchi rasm — muqova. Tartibni o‘zgartirish uchun rasmni bosib turing va suring.'),
          style: text.bodySmall,
        ),
        const SizedBox(height: AppSpacing.lg),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= AppBreakpoints.medium ? 5 : 3;
            final size = (constraints.maxWidth - AppSpacing.sm * (columns - 1)) / columns;
            return Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final (index, photo) in draft.photos.indexed)
                  _DraggablePhoto(
                    key: ValueKey(photo.id),
                    photo: photo,
                    index: index,
                    size: size,
                    onMove: controller.movePhoto,
                    onTap: () => _photoActions(context, ref, photo, index),
                    onRemove: () => controller.removePhoto(photo.id),
                  ),
                if (draft.photos.length < ListingDraft.maxPhotos)
                  _AddPhotoTile(size: size, hasError: error != null, onTap: () => _add(context, ref)),
              ],
            );
          },
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: Text(error, style: text.bodySmall?.copyWith(color: palette.danger)),
          ),
        if (assist.isAvailable && draft.photos.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          SurfaceCard(
            color: palette.primarySoft,
            borderColor: Colors.transparent,
            child: Row(
              children: [
                Icon(Icons.auto_awesome_rounded, color: palette.primary),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: Text(tr('Rasmlar asosida sarlavha va tavsifni avtomatik to‘ldirish'))),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        SurfaceCard(
          color: palette.surfaceMuted,
          borderColor: Colors.transparent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('Yaxshi rasm uchun maslahatlar'), style: text.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              for (final tip in [
                'Kunduzi, yorug‘ joyda suratga oling',
                tr('Mahsulotni turli tomondan ko‘rsating'),
                tr('Kamchiliklarni yashirmang — ishonch oshadi'),
              ])
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: MetaLine(
                    icon: Icons.check_circle_outline_rounded,
                    text: tip,
                    color: palette.textSecondary,
                    maxLines: 2,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

enum _Source { gallery, camera }

class _DraggablePhoto extends StatelessWidget {
  const _DraggablePhoto({
    super.key,
    required this.photo,
    required this.index,
    required this.size,
    required this.onMove,
    required this.onTap,
    required this.onRemove,
  });

  final DraftPhoto photo;
  final int index;
  final double size;
  final void Function(int from, int to) onMove;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final tile = _PhotoTile(photo: photo, isCover: index == 0, size: size, onRemove: onRemove);
    return DragTarget<int>(
      onWillAcceptWithDetails: (details) => details.data != index,
      onAcceptWithDetails: (details) {
        HapticFeedback.selectionClick();
        onMove(details.data, index);
      },
      builder: (context, candidates, _) => LongPressDraggable<int>(
        data: index,
        feedback: Material(
          color: Colors.transparent,
          child: Transform.scale(scale: 1.06, child: Opacity(opacity: 0.9, child: tile)),
        ),
        childWhenDragging: Opacity(opacity: 0.3, child: tile),
        child: Semantics(
          label: tr('{p0}-rasm{p1}. Amallar uchun bosing', {'p0': index + 1, 'p1': index == 0 ? tr(', muqova') : ''}),
          button: true,
          customSemanticsActions: {
            if (index > 0) CustomSemanticsAction(label: tr('Oldinga surish')): () => onMove(index, index - 1),
            CustomSemanticsAction(label: tr('O‘chirish')): onRemove,
          },
          child: GestureDetector(
            onTap: onTap,
            child: AnimatedScale(duration: AppMotion.fast, scale: candidates.isNotEmpty ? 0.94 : 1, child: tile),
          ),
        ),
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.photo, required this.isCover, required this.size, required this.onRemove});

  final DraftPhoto photo;
  final bool isCover;
  final double size;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SizedBox.square(
      dimension: size,
      child: ClipRRect(
        borderRadius: AppRadii.mdAll,
        child: Stack(
          fit: StackFit.expand,
          children: [
            AppImage(image: MediaImage.local(photo.id, photo.localPath)),
            if (!photo.isUploaded)
              ColoredBox(
                color: Colors.black.withValues(alpha: 0.45),
                child: Center(
                  child: photo.failed
                      ? Icon(Icons.refresh_rounded, color: Colors.white, semanticLabel: tr('Yuklanmadi'))
                      : SizedBox.square(
                          dimension: 34,
                          child: CircularProgressIndicator(
                            value: photo.progress == 0 ? null : photo.progress,
                            strokeWidth: 3,
                            color: Colors.white,
                            backgroundColor: Colors.white24,
                            semanticsLabel: tr('Yuklanmoqda'),
                            semanticsValue: '${(photo.progress * 100).round()}%',
                          ),
                        ),
                ),
              ),
            if (isCover)
              PositionedDirectional(
                start: AppSpacing.xs,
                bottom: AppSpacing.xs,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
                  decoration: BoxDecoration(color: palette.primary, borderRadius: AppRadii.pillAll),
                  child: Text(
                    tr('Muqova'),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white),
                  ),
                ),
              ),
            PositionedDirectional(
              top: 0,
              end: 0,
              child: IconButton(
                tooltip: tr('O‘chirish'),
                onPressed: onRemove,
                icon: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), shape: BoxShape.circle),
                  child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddPhotoTile extends StatelessWidget {
  const _AddPhotoTile({required this.size, required this.onTap, required this.hasError});

  final double size;
  final VoidCallback onTap;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      button: true,
      label: tr('Rasm qo‘shish'),
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: Material(
          color: palette.primarySoft,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadii.mdAll,
            side: BorderSide(color: hasError ? palette.danger : palette.primary.withValues(alpha: 0.35), width: 1.2),
          ),
          child: InkWell(
            borderRadius: AppRadii.mdAll,
            onTap: onTap,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_a_photo_rounded, color: palette.primary),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  tr('Rasm qo‘shish'),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: palette.primary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
