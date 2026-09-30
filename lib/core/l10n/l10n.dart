import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/session_controller.dart';
import '../config/app_config.dart';
import '../errors/app_failure.dart';
import '../network/api_client.dart';
import '../storage/key_value_store.dart';
import 'ru.dart';

/// Interface languages. Uzbek (Latin) is the source language of every string
/// in the code base; other languages are looked up by that source text.
enum AppLanguage {
  uz('uz', 'O‘zbekcha'),
  ru('ru', 'Русский');

  const AppLanguage(this.code, this.nativeName);

  final String code;
  final String nativeName;

  Locale get locale => Locale(code);

  static AppLanguage parse(String? code) => values.where((l) => l.code == code).firstOrNull ?? AppLanguage.uz;

  /// First launch: follow the device language when we support it.
  static AppLanguage fromDevice([ui.Locale? device]) =>
      (device ?? ui.PlatformDispatcher.instance.locale).languageCode == 'ru' ? AppLanguage.ru : AppLanguage.uz;
}

/// The language `tr` renders. Set by [LanguageController] before widgets
/// rebuild; a plain global keeps call sites free of `BuildContext`.
AppLanguage currentLanguage = AppLanguage.uz;

/// Translates [source] (the Uzbek text) into the current language and fills
/// `{name}` placeholders from [args]. Unknown strings fall back to the source.
String tr(String source, [Map<String, Object?>? args]) {
  var text = currentLanguage == AppLanguage.uz ? source : (russianStrings[source] ?? source);
  if (args != null) {
    for (final entry in args.entries) {
      text = text.replaceAll('{${entry.key}}', '${entry.value}');
    }
  }
  return text;
}

/// Translates a stored attribute value such as "Benzin/Metan", "Kia, Hyundai" or "35 000 km":
/// each part is looked up on its own and trailing units are translated.
String trValue(String value) {
  if (currentLanguage == AppLanguage.uz) return value;
  final whole = russianStrings[value];
  if (whole != null) return whole;
  return value.replaceAllMapped(RegExp(r'[^/,|]+'), (match) {
    final part = match[0]!;
    final trimmed = part.trim();
    if (trimmed.isEmpty) return part;
    final withUnit = RegExp(r'^(.*\d)\s+(\S+)$').firstMatch(trimmed);
    final translated = withUnit != null && russianStrings.containsKey(withUnit[2])
        ? '${withUnit[1]} ${tr(withUnit[2]!)}'
        : tr(trimmed);
    return part.replaceFirst(trimmed, translated);
  });
}

/// Russian plural form: 1 → [one] (час), 2–4 → [few] (часа), 5+ → [many] (часов).
String pluralRu(int n, String one, String few, String many) {
  final mod100 = n.abs() % 100;
  final mod10 = n.abs() % 10;
  if (mod100 >= 11 && mod100 <= 14) return many;
  if (mod10 == 1) return one;
  if (mod10 >= 2 && mod10 <= 4) return few;
  return many;
}

class LanguageController extends Notifier<AppLanguage> {
  @override
  AppLanguage build() {
    final stored = ref.watch(keyValueStoreProvider).getString(StoreKeys.language);
    final language = stored == null ? AppLanguage.fromDevice() : AppLanguage.parse(stored);
    currentLanguage = language;
    return language;
  }

  Future<void> set(AppLanguage language) async {
    currentLanguage = language;
    state = language;
    await ref.read(keyValueStoreProvider).setString(StoreKeys.language, language.code);
  }
}

final languageProvider = NotifierProvider<LanguageController, AppLanguage>(LanguageController.new);

/// Tells the server which language to use for notifications and push, whenever
/// the signed-in user or the chosen language changes. Best effort: failures are
/// ignored because the next change (or sign-in) retries.
class LanguageSync extends Notifier<void> {
  @override
  void build() {
    final language = ref.watch(languageProvider);
    final userId = ref.watch(sessionProvider.select((user) => user?.id));
    if (userId == null || ref.watch(appConfigProvider).useDemoData) return;
    unawaited(_push(language));
  }

  Future<void> _push(AppLanguage language) async {
    try {
      await ref.read(apiClientProvider).patch<Object?>('/me', body: {'language': language.code});
    } on AppFailure {
      // Retried on the next change or sign-in.
    }
  }
}

final languageSyncProvider = NotifierProvider<LanguageSync, void>(LanguageSync.new);
