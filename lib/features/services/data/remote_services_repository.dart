import '../../../core/errors/app_failure.dart';
import '../../../core/network/api_client.dart';
import '../domain/service_provider.dart';

/// `/providers`, `/service-categories`, `/me/provider` REST implementation.
class RemoteServicesRepository implements ServicesRepository {
  RemoteServicesRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<ServiceCategory>> categories() async => [
    for (final item in await _api.get<List<dynamic>>('/service-categories')) ServiceCategory.fromJson(item as JsonMap),
  ];

  @override
  Future<List<ServiceProvider>> recommended({String? regionId}) async => (await _api.getPage(
    '/providers',
    ServiceProvider.fromJson,
    query: {'region': regionId, 'sort': 'rating', 'limit': 20},
  )).items;

  @override
  Future<List<ServiceProvider>> search(ProviderQuery query) async => (await _api.getPage(
    '/providers',
    ServiceProvider.fromJson,
    query: {
      'q': query.text.trim(),
      'category': query.categoryId,
      'region': query.regionId,
      'filter': query.filter.name,
      'limit': 50,
    },
  )).items;

  @override
  Future<ServiceProvider> getProvider(String id) async =>
      ServiceProvider.fromJson(await _api.get<JsonMap>('/providers/$id'));

  @override
  Future<String> revealPhone(String providerId) async =>
      (await _api.post<JsonMap>('/providers/$providerId/contact'))['phone'] as String;

  @override
  Future<ServiceProvider?> myProvider() async {
    try {
      final json = await _api.get<Object?>('/me/provider');
      return json is JsonMap ? ServiceProvider.fromJson(json) : null;
    } on NotFoundFailure {
      return null;
    }
  }

  @override
  Future<ServiceProvider> saveProvider(ProviderDraft draft) async =>
      ServiceProvider.fromJson(await _api.put<JsonMap>('/me/provider', body: draft.toJson()));

  @override
  Future<void> addOffering(OfferingDraft draft) async {
    await _api.post<Object?>('/me/provider/offerings', body: draft.toJson());
  }

  @override
  Future<void> deleteOffering(String offeringId) => _api.delete('/me/provider/offerings/$offeringId');

  @override
  Future<void> submitReview(String providerId, {required int rating, String? text}) async {
    await _api.put<Object?>(
      '/providers/$providerId/reviews/mine',
      body: {'rating': rating, if (text != null && text.trim().isNotEmpty) 'text': text.trim()},
    );
  }
}
