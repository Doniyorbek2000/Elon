import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../data/demo/demo_database.dart';
import '../data/demo_services_repository.dart';
import '../data/remote_services_repository.dart';
import '../domain/service_provider.dart';

final servicesRepositoryProvider = Provider<ServicesRepository>((ref) {
  if (ref.watch(appConfigProvider).useDemoData) return DemoServicesRepository(ref.watch(demoDatabaseProvider));
  return RemoteServicesRepository(ref.watch(apiClientProvider));
});

/// The signed-in user's provider profile (null = not a provider yet).
final myProviderProvider = FutureProvider.autoDispose<ServiceProvider?>((ref) {
  return ref.watch(servicesRepositoryProvider).myProvider();
});

final recommendedProvidersProvider = FutureProvider.autoDispose.family<List<ServiceProvider>, String?>((ref, regionId) {
  return ref.watch(servicesRepositoryProvider).recommended(regionId: regionId);
});

final providerSearchProvider = FutureProvider.autoDispose.family<List<ServiceProvider>, ProviderQuery>((ref, query) {
  return ref.watch(servicesRepositoryProvider).search(query);
});

final providerDetailProvider = FutureProvider.autoDispose.family<ServiceProvider, String>((ref, id) {
  return ref.watch(servicesRepositoryProvider).getProvider(id);
});
