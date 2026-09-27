import 'package:flutter/foundation.dart';

import '../../../core/errors/app_failure.dart';

@immutable
class UploadProgress {
  const UploadProgress({required this.fraction, this.remoteId, this.failure});

  final double fraction;

  /// Set once the server has accepted the file.
  final String? remoteId;
  final AppFailure? failure;

  bool get isDone => remoteId != null;
  bool get isFailed => failure != null;
}

/// Uploads a (client-compressed) photo. The server generates thumbnail/
/// feed/detail renditions; the client only ever uploads once.
abstract interface class MediaUploadService {
  /// [purpose]: `listing` | `avatar` | `chat` | `portfolio` | `offering`.
  Stream<UploadProgress> upload(String localPath, {String purpose = 'listing'});
}

@immutable
class ListingSuggestion {
  const ListingSuggestion({this.categoryId, this.title, this.description, this.attributes = const {}});

  final String? categoryId;
  final String? title;
  final String? description;
  final Map<String, String> attributes;
}

/// Future AI assist: photos → suggested category/title/description/attributes.
/// The create flow works fully without it.
abstract interface class ListingAssistService {
  bool get isAvailable;
  Future<ListingSuggestion?> suggestFromPhotos(List<String> localPaths);
}

class DisabledListingAssist implements ListingAssistService {
  const DisabledListingAssist();

  @override
  bool get isAvailable => false;

  @override
  Future<ListingSuggestion?> suggestFromPhotos(List<String> localPaths) async => null;
}
