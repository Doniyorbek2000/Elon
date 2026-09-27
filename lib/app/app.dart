import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/design/app_theme.dart';
import '../features/settings/application/settings_controller.dart';
import 'router/app_router.dart';

class BozorApp extends ConsumerWidget {
  const BozorApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'Bozor.uz',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      themeAnimationDuration: const Duration(milliseconds: 220),
      routerConfig: router,
      locale: const Locale('uz'),
      supportedLocales: const [Locale('uz'), Locale('ru'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) {
        // Cap extreme text scaling at 2× — beyond that fixed-height controls
        // (bottom bar, chips) cannot stay usable; 2× still covers WCAG 200%.
        final mediaQuery = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQuery.copyWith(textScaler: mediaQuery.textScaler.clamp(maxScaleFactor: 2)),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
