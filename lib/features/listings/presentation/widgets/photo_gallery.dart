import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/design/app_colors.dart';
import '../../../../core/design/app_tokens.dart';
import '../../../../core/domain/media_image.dart';
import '../../../../core/widgets/app_image.dart';

/// Swipeable photo pager with counter; tap opens the zoomable viewer.
class PhotoGallery extends StatefulWidget {
  const PhotoGallery({
    super.key,
    required this.images,
    required this.heroTag,
    required this.placeholderIcon,
    required this.tone,
    this.semanticTitle = '',
  });

  final List<MediaImage> images;
  final String heroTag;
  final IconData placeholderIcon;
  final AccentTone tone;
  final String semanticTitle;

  @override
  State<PhotoGallery> createState() => _PhotoGalleryState();
}

class _PhotoGalleryState extends State<PhotoGallery> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _openViewer() {
    if (widget.images.isEmpty) return;
    Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: AppMotion.of(context, AppMotion.medium),
        reverseTransitionDuration: AppMotion.of(context, AppMotion.fast),
        pageBuilder: (_, _, _) => PhotoViewer(
          images: widget.images,
          initialIndex: _index,
          onPageChanged: (index) {
            if (_controller.hasClients) _controller.jumpToPage(index);
          },
        ),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.images;
    final count = images.length;
    return Semantics(
      label: '${widget.semanticTitle} rasmlari, ${count == 0 ? 0 : _index + 1} / $count. Kattalashtirish uchun bosing',
      button: count > 0,
      child: GestureDetector(
        onTap: _openViewer,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (count == 0)
              AppImage(image: null, placeholderIcon: widget.placeholderIcon, tone: widget.tone)
            else
              PageView.builder(
                controller: _controller,
                itemCount: count,
                onPageChanged: (index) {
                  HapticFeedback.selectionClick();
                  setState(() => _index = index);
                },
                itemBuilder: (_, index) {
                  final image = AppImage(
                    image: images[index],
                    variant: ImageVariant.detail,
                    placeholderIcon: widget.placeholderIcon,
                    tone: widget.tone,
                  );
                  return index == 0 ? Hero(tag: widget.heroTag, child: image) : image;
                },
              ),
            if (count > 1)
              PositionedDirectional(
                end: AppSpacing.md,
                bottom: AppSpacing.md,
                child: ExcludeSemantics(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm + 2, vertical: AppSpacing.xs),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: AppRadii.pillAll,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.photo_camera_outlined, size: 14, color: Colors.white),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          '${_index + 1}/$count',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (count > 1)
              Positioned(
                bottom: AppSpacing.md + 4,
                left: 0,
                right: 0,
                child: ExcludeSemantics(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < count && i < 10; i++)
                        AnimatedContainer(
                          duration: AppMotion.of(context, AppMotion.fast),
                          margin: const EdgeInsets.symmetric(horizontal: 2.5),
                          width: i == _index ? 16 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: i == _index ? 1 : 0.6),
                            borderRadius: AppRadii.pillAll,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Full-screen, pinch-to-zoom viewer on black.
class PhotoViewer extends StatefulWidget {
  const PhotoViewer({super.key, required this.images, required this.initialIndex, this.onPageChanged});

  final List<MediaImage> images;
  final int initialIndex;
  final ValueChanged<int>? onPageChanged;

  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer> {
  late final _controller = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            PageView.builder(
              controller: _controller,
              itemCount: widget.images.length,
              onPageChanged: (index) {
                setState(() => _index = index);
                widget.onPageChanged?.call(index);
              },
              itemBuilder: (_, index) => InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(
                  child: AppImage(image: widget.images[index], fit: BoxFit.contain, variant: ImageVariant.original),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Yopish',
                      color: Colors.white,
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                    const Spacer(),
                    Text(
                      '${_index + 1} / ${widget.images.length}',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Colors.white),
                    ),
                    const SizedBox(width: AppSpacing.lg),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
