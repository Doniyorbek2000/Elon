import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/config/app_config.dart';
import '../../../core/config/feature_flags.dart';
import '../domain/media_upload.dart';

/// Demo uploader: reports realistic progress and returns a `local:` id that
/// the demo listing repository resolves back to the on-device file.
class DemoMediaUploadService implements MediaUploadService {
  const DemoMediaUploadService({required this.duration});

  final Duration duration;

  @override
  Stream<UploadProgress> upload(String localPath) async* {
    const steps = 8;
    for (var i = 1; i <= steps; i++) {
      if (duration > Duration.zero) await Future<void>.delayed(duration ~/ steps);
      yield UploadProgress(fraction: i / steps);
    }
    yield UploadProgress(fraction: 1, remoteId: 'local:$localPath');
  }
}

final mediaUploadServiceProvider = Provider<MediaUploadService>((ref) {
  return DemoMediaUploadService(duration: ref.watch(appConfigProvider).demoLatency * 3);
});

final listingAssistServiceProvider = Provider<ListingAssistService>((ref) {
  // A model-backed implementation is registered here when the flag is on.
  ref.watch(featureFlagsProvider);
  return const DisabledListingAssist();
});

/// Photo source abstraction; compression happens at pick time
/// (max 2048 px long edge, JPEG q≈82) so uploads stay small on 3G/4G.
abstract interface class PhotoPicker {
  Future<List<String>> pickFromGallery({required int limit});
  Future<String?> takePhoto();
}

class ImagePickerPhotoPicker implements PhotoPicker {
  ImagePickerPhotoPicker([ImagePicker? picker]) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  static const _maxDimension = 2048.0;
  static const _quality = 82;

  @override
  Future<List<String>> pickFromGallery({required int limit}) async {
    if (limit <= 0) return const [];
    final files = await _picker.pickMultiImage(
      maxWidth: _maxDimension,
      maxHeight: _maxDimension,
      imageQuality: _quality,
      limit: limit > 1 ? limit : null,
    );
    return [for (final file in files.take(limit)) file.path];
  }

  @override
  Future<String?> takePhoto() async {
    final file = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: _maxDimension,
      maxHeight: _maxDimension,
      imageQuality: _quality,
    );
    return file?.path;
  }
}

final photoPickerProvider = Provider<PhotoPicker>((ref) => ImagePickerPhotoPicker());
