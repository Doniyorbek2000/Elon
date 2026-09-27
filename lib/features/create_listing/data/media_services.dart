import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/config/app_config.dart';
import '../../../core/config/feature_flags.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/network/api_client.dart';
import '../domain/media_upload.dart';

/// Demo uploader: reports realistic progress and returns a `local:` id that
/// the demo listing repository resolves back to the on-device file.
class DemoMediaUploadService implements MediaUploadService {
  const DemoMediaUploadService({required this.duration});

  final Duration duration;

  @override
  Stream<UploadProgress> upload(String localPath, {String purpose = 'listing'}) async* {
    const steps = 8;
    for (var i = 1; i <= steps; i++) {
      if (duration > Duration.zero) await Future<void>.delayed(duration ~/ steps);
      yield UploadProgress(fraction: i / steps);
    }
    yield UploadProgress(fraction: 1, remoteId: 'local:$localPath');
  }
}

/// Multipart upload to `POST /media`, then waits (bounded) for the worker to
/// produce renditions. Failures are reported, never swallowed: the draft shows
/// a failed tile with retry.
class RemoteMediaUploadService implements MediaUploadService {
  const RemoteMediaUploadService(this._api, {this.pollInterval = const Duration(milliseconds: 700)});

  final ApiClient _api;
  final Duration pollInterval;

  static const _processingTimeout = Duration(seconds: 45);

  @override
  Stream<UploadProgress> upload(String localPath, {String purpose = 'listing'}) async* {
    final controller = StreamController<UploadProgress>();
    final form = FormData.fromMap({
      'purpose': purpose,
      'file': await MultipartFile.fromFile(localPath, filename: localPath.split(Platform.pathSeparator).last),
    });
    final upload = _api
        .upload(
          '/media',
          data: form,
          onProgress: (sent, total) {
            if (total > 0 && !controller.isClosed) controller.add(UploadProgress(fraction: 0.9 * sent / total));
          },
        )
        .whenComplete(controller.close);
    yield* controller.stream;
    final media = await upload;
    final id = media['id'] as String;

    // Renditions are generated asynchronously; wait briefly so the preview
    // and feed card have real images. Processing failures surface here.
    var status = media['status'] as String?;
    final deadline = DateTime.now().add(_processingTimeout);
    while (status == 'processing' && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(pollInterval);
      status = (await _api.get<JsonMap>('/media/$id'))['status'] as String?;
    }
    if (status == 'failed') throw const ValidationFailure('Rasmni qayta ishlab bo‘lmadi. Boshqa rasm tanlang');
    yield UploadProgress(fraction: 1, remoteId: id);
  }
}

final mediaUploadServiceProvider = Provider<MediaUploadService>((ref) {
  final config = ref.watch(appConfigProvider);
  if (config.useDemoData) return DemoMediaUploadService(duration: config.demoLatency * 3);
  return RemoteMediaUploadService(ref.watch(apiClientProvider));
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
