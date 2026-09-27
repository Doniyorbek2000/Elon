import 'package:bozor/app/app.dart';
import 'package:bozor/app/router/app_router.dart';
import 'package:bozor/core/config/app_config.dart';
import 'package:bozor/core/domain/public_profile.dart';
import 'package:bozor/core/sharing/share_service.dart';
import 'package:bozor/core/storage/key_value_store.dart';
import 'package:bozor/core/utils/clock.dart';
import 'package:bozor/core/utils/external_actions.dart';
import 'package:bozor/core/widgets/app_image.dart';
import 'package:bozor/features/create_listing/data/media_services.dart';
import 'package:bozor/features/location/application/location_controller.dart';
import 'package:bozor/features/location/domain/location.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// Fixed "now" so relative timestamps are deterministic.
final testNow = DateTime(2026, 9, 26, 12);

class FakePhotoPicker implements PhotoPicker {
  List<String> nextGallery = ['/tmp/photo_1.jpg', '/tmp/photo_2.jpg'];
  String? nextCamera = '/tmp/camera.jpg';

  @override
  Future<List<String>> pickFromGallery({required int limit}) async =>
      nextGallery.take(limit).toList();

  @override
  Future<String?> takePhoto() async => nextCamera;
}

class FakeLocationService implements DeviceLocationService {
  GeoPoint point = const GeoPoint(41.004, 71.24);
  bool deny = false;

  @override
  Future<GeoPoint> currentPosition() async {
    if (deny) throw StateError('denied');
    return point;
  }

  @override
  Future<void> openSettings() async {}

  @override
  Future<LocationPermissionState> permissionState() async =>
      deny ? LocationPermissionState.denied : LocationPermissionState.granted;
}

class RecordingShareService implements ShareService {
  final List<SharePayload> shared = [];

  @override
  Future<void> copyLink(SharePayload payload) async => shared.add(payload);

  @override
  Future<void> shareSystem(SharePayload payload, {Rect? origin}) async =>
      shared.add(payload);

  @override
  Future<void> shareToTelegram(SharePayload payload) async =>
      shared.add(payload);
}

class RecordingExternalActions implements ExternalActions {
  final List<String> calls = [];
  final List<Uri> urls = [];

  @override
  Future<bool> call(String phoneDigits) async {
    calls.add(phoneDigits);
    return true;
  }

  @override
  Future<bool> openUrl(Uri url) async {
    urls.add(url);
    return true;
  }
}

/// Everything a test needs to drive the real app on demo data, offline.
class TestHarness {
  TestHarness._(this.store);

  final KeyValueStore store;
  final photoPicker = FakePhotoPicker();
  final locationService = FakeLocationService();
  final share = RecordingShareService();
  final external = RecordingExternalActions();
  late ProviderContainer container;

  static Future<TestHarness> create({
    bool onboarded = true,
    Map<String, Object> prefs = const {},
  }) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({
          if (onboarded) StoreKeys.onboardingCompleted: true,
          ...prefs,
        });
    return TestHarness._(await KeyValueStore.open());
  }

  List<Override> get overrides => [
    keyValueStoreProvider.overrideWithValue(store),
    appConfigProvider.overrideWithValue(
      AppConfig.fromEnvironment().copyWith(demoLatency: Duration.zero),
    ),
    clockProvider.overrideWithValue(() => testNow),
    networkImagesEnabledProvider.overrideWithValue(false),
    photoPickerProvider.overrideWithValue(photoPicker),
    deviceLocationServiceProvider.overrideWithValue(locationService),
    shareServiceProvider.overrideWithValue(share),
    externalActionsProvider.overrideWithValue(external),
  ];

  ProviderContainer createContainer() => container = ProviderContainer(
    overrides: overrides,
    retry: (_, _) => null,
  );

  GoRouter get router => container.read(appRouterProvider);
}

/// Sets a device size + text scale for the duration of a test.
void setDevice(
  WidgetTester tester,
  Size logicalSize, {
  double pixelRatio = 3,
  double textScale = 1,
}) {
  tester.view.physicalSize = logicalSize * pixelRatio;
  tester.view.devicePixelRatio = pixelRatio;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// Pumps the full app (router, theme, shell) and optionally navigates.
Future<TestHarness> pumpBozorApp(
  WidgetTester tester, {
  bool onboarded = true,
  String? location,
  Size size = const Size(390, 844),
  double textScale = 1,
  ThemeMode? themeMode,
}) async {
  setDevice(tester, size, textScale: textScale);
  final harness = await TestHarness.create(
    onboarded: onboarded,
    prefs: {if (themeMode != null) StoreKeys.themeMode: themeMode.name},
  );
  final container = harness.createContainer();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const BozorApp()),
  );
  await settle(tester);
  if (location != null) {
    harness.router.go(location);
    await settle(tester);
  }
  return harness;
}

/// pumpAndSettle bounded so infinite animations (shimmer) cannot hang tests.
Future<void> settle(WidgetTester tester, {int frames = 40}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (!tester.binding.hasScheduledFrame) break;
  }
}

PublicProfile testProfile(String id, {String name = 'Test'}) =>
    PublicProfile(id: id, name: name, memberSince: DateTime(2024));
