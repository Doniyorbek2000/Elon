import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../domain/media_image.dart';

enum ShareTarget { listing, job, provider, seller }

/// Everything needed to render a share preview card and a Telegram-friendly
/// message. The web landing page at [url] renders the same data as Open
/// Graph tags so Telegram shows a rich preview.
class SharePayload {
  const SharePayload({
    required this.target,
    required this.id,
    required this.title,
    required this.url,
    this.subtitle,
    this.location,
    this.image,
  });

  final ShareTarget target;
  final String id;
  final String title;

  /// Price or salary line.
  final String? subtitle;
  final String? location;
  final MediaImage? image;
  final Uri url;

  String get message => [
    title,
    ?subtitle,
    if (location != null) '📍 $location',
    '',
    url.toString(),
  ].join('\n');
}

/// Builds canonical links. Paths mirror in-app routes so the same URL works
/// as an Android App Link, iOS Universal Link and web landing page.
class DeepLinks {
  const DeepLinks(this._config);

  final AppConfig _config;

  static String pathFor(ShareTarget target, String id) => switch (target) {
    ShareTarget.listing => '/listing/$id',
    ShareTarget.job => '/job/$id',
    ShareTarget.provider => '/provider/$id',
    ShareTarget.seller => '/seller/$id',
  };

  Uri web(ShareTarget target, String id) =>
      Uri.parse('${_config.webBaseUrl}${pathFor(target, id)}');

  /// `bozor://app/listing/42` — custom-scheme fallback for in-app handoff.
  Uri app(ShareTarget target, String id) =>
      Uri.parse('${_config.appScheme}://app${pathFor(target, id)}');
}

final deepLinksProvider = Provider<DeepLinks>(
  (ref) => DeepLinks(ref.watch(appConfigProvider)),
);

abstract interface class ShareService {
  Future<void> shareToTelegram(SharePayload payload);
  Future<void> shareSystem(SharePayload payload, {Rect? origin});
  Future<void> copyLink(SharePayload payload);
}

class PlatformShareService implements ShareService {
  const PlatformShareService();

  @override
  Future<void> shareToTelegram(SharePayload payload) async {
    final text = payload.message.replaceAll(payload.url.toString(), '').trim();
    final query =
        'url=${Uri.encodeComponent(payload.url.toString())}&text=${Uri.encodeComponent(text)}';
    final appUri = Uri.parse('tg://msg_url?$query');
    if (await canLaunchUrl(appUri) && await launchUrl(appUri)) return;
    await launchUrl(
      Uri.parse('https://t.me/share/url?$query'),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Future<void> shareSystem(SharePayload payload, {Rect? origin}) async {
    await SharePlus.instance.share(
      ShareParams(
        text: payload.message,
        subject: payload.title,
        sharePositionOrigin: origin,
      ),
    );
  }

  @override
  Future<void> copyLink(SharePayload payload) =>
      Clipboard.setData(ClipboardData(text: payload.url.toString()));
}

final shareServiceProvider = Provider<ShareService>(
  (ref) => const PlatformShareService(),
);
