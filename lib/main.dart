import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/logging/app_logger.dart';
import 'core/storage/key_value_store.dart';

Future<void> main() async {
  const logger = DeveloperLogger();
  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        logger.error(
          'Flutter error',
          error: details.exception,
          stackTrace: details.stack,
          tag: 'ui',
        );
      };
      PlatformDispatcher.instance.onError = (error, stack) {
        logger.error(
          'Uncaught platform error',
          error: error,
          stackTrace: stack,
        );
        return true;
      };
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));

      final store = await KeyValueStore.open();
      runApp(
        ProviderScope(
          overrides: [keyValueStoreProvider.overrideWithValue(store)],
          // Screens expose explicit retry actions; silent auto-retry would
          // hide offline state from the user.
          retry: (_, _) => null,
          child: const BozorApp(),
        ),
      );
    },
    (error, stack) =>
        logger.error('Uncaught zone error', error: error, stackTrace: stack),
  );
}
