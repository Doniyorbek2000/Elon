import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/key_value_store.dart';

class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    final stored = ref.watch(keyValueStoreProvider).getString(StoreKeys.themeMode);
    return ThemeMode.values.where((mode) => mode.name == stored).firstOrNull ?? ThemeMode.system;
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    await ref.read(keyValueStoreProvider).setString(StoreKeys.themeMode, mode.name);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

class NotificationsPreferenceController extends Notifier<bool> {
  @override
  bool build() => ref.watch(keyValueStoreProvider).getBool(StoreKeys.notificationsEnabled) ?? true;

  Future<void> set({required bool enabled}) async {
    state = enabled;
    await ref.read(keyValueStoreProvider).setBool(StoreKeys.notificationsEnabled, value: enabled);
  }
}

final notificationsPreferenceProvider = NotifierProvider<NotificationsPreferenceController, bool>(
  NotificationsPreferenceController.new,
);

class OnboardingController extends Notifier<bool> {
  @override
  bool build() => ref.watch(keyValueStoreProvider).getBool(StoreKeys.onboardingCompleted) ?? false;

  Future<void> complete() async {
    state = true;
    await ref.read(keyValueStoreProvider).setBool(StoreKeys.onboardingCompleted, value: true);
  }

  Future<void> reset() async {
    state = false;
    await ref.read(keyValueStoreProvider).remove(StoreKeys.onboardingCompleted);
  }
}

final onboardingCompletedProvider = NotifierProvider<OnboardingController, bool>(OnboardingController.new);
