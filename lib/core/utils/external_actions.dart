import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Phone calls / external URLs behind an interface so widgets stay testable.
abstract interface class ExternalActions {
  Future<bool> call(String phoneDigits);
  Future<bool> openUrl(Uri url);
}

class UrlLauncherActions implements ExternalActions {
  const UrlLauncherActions();

  @override
  Future<bool> call(String phoneDigits) {
    final digits = phoneDigits.replaceAll(RegExp(r'\D'), '');
    return launchUrl(Uri(scheme: 'tel', path: '+$digits'));
  }

  @override
  Future<bool> openUrl(Uri url) => launchUrl(url, mode: LaunchMode.externalApplication);
}

final externalActionsProvider = Provider<ExternalActions>((ref) => const UrlLauncherActions());
