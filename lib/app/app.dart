import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/design/app_theme.dart';
import '../core/l10n/l10n.dart';
import '../core/push/push_registration.dart';
import '../features/settings/application/settings_controller.dart';
import 'router/app_router.dart';

class BozorApp extends ConsumerWidget {
  const BozorApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(appConfigProvider).isMisconfigured) return const _MisconfiguredApp();
    final router = ref.watch(appRouterProvider);
    final language = ref.watch(languageProvider);
    // Keeps push token registration in sync with the signed-in account.
    ref.watch(pushRegistrationProvider);
    return MaterialApp.router(
      title: 'Bozor.uz',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      themeAnimationDuration: const Duration(milliseconds: 220),
      routerConfig: router,
      locale: language.locale,
      supportedLocales: const [Locale('uz'), Locale('ru'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) {
        // Cap extreme text scaling at 2× — beyond that fixed-height controls
        // (bottom bar, chips) cannot stay usable; 2× still covers WCAG 200%.
        final mediaQuery = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQuery.copyWith(textScaler: mediaQuery.textScaler.clamp(maxScaleFactor: 2)),
          // Strings are resolved when widgets build; a new key rebuilds every screen in the new language.
          child: KeyedSubtree(key: ValueKey(language), child: child ?? const SizedBox.shrink()),
        );
      },
    );
  }
}

/// Release build without `API_BASE_URL`: refuse to run on fake data.
class _MisconfiguredApp extends StatelessWidget {
  const _MisconfiguredApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(),
    home: Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              tr('Ilova server manzilisiz yig‘ilgan (API_BASE_URL). Iltimos, ilovaning rasmiy versiyasini o‘rnating.'),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    ),
  );
}
