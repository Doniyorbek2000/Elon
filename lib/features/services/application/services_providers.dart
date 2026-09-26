import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/demo/demo_database.dart';
import '../data/demo_services_repository.dart';
import '../domain/service_provider.dart';

/// Services backend is not specified yet; the demo implementation serves the
/// interface until a `RemoteServicesRepository` is added.
final servicesRepositoryProvider = Provider<ServicesRepository>((ref) {
  return DemoServicesRepository(ref.watch(demoDatabaseProvider));
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
