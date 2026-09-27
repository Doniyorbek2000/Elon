import 'package:flutter/foundation.dart';

/// Rendition sizes the backend/CDN is expected to generate for every upload.
enum ImageVariant {
  /// ~160 px: avatars, chat context, list thumbnails.
  thumbnail(160),

  /// ~480 px: feed/grid cards.
  feed(480),

  /// ~1080 px: detail gallery.
  detail(1080),

  /// Untouched upload: full-screen zoom only.
  original(4096);

  const ImageVariant(this.maxPixels);

  final int maxPixels;

  /// Smallest variant that satisfies the physical pixel width being rendered.
  static ImageVariant forPixelWidth(double pixels) =>
      values.firstWhere((variant) => variant.maxPixels >= pixels, orElse: () => original);
}

/// A remote image with multiple renditions. Feed cards request `feed`,
/// never the multi-megabyte `original`.
@immutable
class MediaImage {
  const MediaImage({required this.id, required this.variants, this.blurHash, this.aspectRatio, this.localPath});

  /// Convenience for CDNs that resize via a width query parameter.
  factory MediaImage.resizable(String id, String baseUrl, {double? aspectRatio}) {
    String sized(int width) => '$baseUrl${baseUrl.contains('?') ? '&' : '?'}w=$width&q=75&auto=format&fit=crop';
    return MediaImage(
      id: id,
      aspectRatio: aspectRatio,
      variants: {
        ImageVariant.thumbnail: sized(ImageVariant.thumbnail.maxPixels),
        ImageVariant.feed: sized(ImageVariant.feed.maxPixels),
        ImageVariant.detail: sized(ImageVariant.detail.maxPixels),
        ImageVariant.original: sized(2048),
      },
    );
  }

  /// Image picked on device and not yet uploaded.
  factory MediaImage.local(String id, String path) => MediaImage(id: id, variants: const {}, localPath: path);

  final String id;
  final Map<ImageVariant, String> variants;
  final String? blurHash;
  final double? aspectRatio;
  final String? localPath;

  bool get isLocal => localPath != null;

  /// Falls back to the next larger (then smaller) variant if one is missing.
  String? url(ImageVariant preferred) {
    final ordered = [
      ...ImageVariant.values.where((v) => v.index >= preferred.index),
      ...ImageVariant.values.where((v) => v.index < preferred.index).toList().reversed,
    ];
    for (final variant in ordered) {
      final url = variants[variant];
      if (url != null) return url;
    }
    return null;
  }

  factory MediaImage.fromJson(Map<String, dynamic> json) => MediaImage(
    id: json['id'] as String,
    blurHash: json['blurHash'] as String?,
    aspectRatio: (json['aspectRatio'] as num?)?.toDouble(),
    variants: {
      for (final variant in ImageVariant.values)
        if ((json['variants'] as Map<String, dynamic>?)?[variant.name] case final String url) variant: url,
    },
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    if (blurHash != null) 'blurHash': blurHash,
    if (aspectRatio != null) 'aspectRatio': aspectRatio,
    'variants': {for (final entry in variants.entries) entry.key.name: entry.value},
    if (localPath != null) 'localPath': localPath,
  };

  @override
  bool operator ==(Object other) => other is MediaImage && other.id == id && other.localPath == localPath;

  @override
  int get hashCode => Object.hash(id, localPath);
}
