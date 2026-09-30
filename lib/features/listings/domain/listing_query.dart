import 'package:flutter/foundation.dart';

import '../../../core/l10n/l10n.dart';
import 'listing.dart';

enum ListingSort {
  newest('Eng yangi'),
  priceAsc('Narxi arzon'),
  priceDesc('Narxi qimmat'),
  popular('Eng mashhur'),
  nearest('Yaqin');

  const ListingSort(this._label);

  final String _label;

  String get label => tr(_label);
}

/// Radius options. `null` radius on a query means "whole selected area".
const listingRadiusOptionsKm = [1, 5, 10, 25, 50];

/// Immutable query value; used as a Riverpod family key so it implements ==.
@immutable
class ListingQuery {
  const ListingQuery({
    this.text = '',
    this.categoryId,
    this.regionId,
    this.districtId,
    this.radiusKm,
    this.minPrice,
    this.maxPrice,
    this.condition,
    this.sort = ListingSort.newest,
    this.sellerId,
    this.pageSize = 20,
  });

  final String text;
  final String? categoryId;
  final String? regionId;
  final String? districtId;
  final int? radiusKm;
  final int? minPrice;
  final int? maxPrice;
  final ItemCondition? condition;
  final ListingSort sort;
  final String? sellerId;
  final int pageSize;

  /// Number of user-applied refinements (drives the filter badge).
  int get activeFilterCount => [
    minPrice != null || maxPrice != null,
    condition != null,
    sort != ListingSort.newest,
    radiusKm != null,
  ].where((active) => active).length;

  ListingQuery copyWith({
    String? text,
    String? Function()? categoryId,
    String? Function()? regionId,
    String? Function()? districtId,
    int? Function()? radiusKm,
    int? Function()? minPrice,
    int? Function()? maxPrice,
    ItemCondition? Function()? condition,
    ListingSort? sort,
    String? Function()? sellerId,
  }) => ListingQuery(
    text: text ?? this.text,
    categoryId: categoryId != null ? categoryId() : this.categoryId,
    regionId: regionId != null ? regionId() : this.regionId,
    districtId: districtId != null ? districtId() : this.districtId,
    radiusKm: radiusKm != null ? radiusKm() : this.radiusKm,
    minPrice: minPrice != null ? minPrice() : this.minPrice,
    maxPrice: maxPrice != null ? maxPrice() : this.maxPrice,
    condition: condition != null ? condition() : this.condition,
    sort: sort ?? this.sort,
    sellerId: sellerId != null ? sellerId() : this.sellerId,
    pageSize: pageSize,
  );

  ListingQuery clearedRefinements() => ListingQuery(
    text: text,
    categoryId: categoryId,
    regionId: regionId,
    districtId: districtId,
    sellerId: sellerId,
    pageSize: pageSize,
  );

  Map<String, Object?> toQueryParameters({String? cursor}) => {
    'q': text,
    'category': categoryId,
    'region': regionId,
    'district': districtId,
    'radius': radiusKm,
    'priceMin': minPrice,
    'priceMax': maxPrice,
    'condition': condition?.apiValue,
    'sort': sort.name,
    'seller': sellerId,
    'limit': pageSize,
    'cursor': cursor,
  };

  @override
  bool operator ==(Object other) =>
      other is ListingQuery &&
      other.text == text &&
      other.categoryId == categoryId &&
      other.regionId == regionId &&
      other.districtId == districtId &&
      other.radiusKm == radiusKm &&
      other.minPrice == minPrice &&
      other.maxPrice == maxPrice &&
      other.condition == condition &&
      other.sort == sort &&
      other.sellerId == sellerId &&
      other.pageSize == pageSize;

  @override
  int get hashCode => Object.hash(
    text,
    categoryId,
    regionId,
    districtId,
    radiusKm,
    minPrice,
    maxPrice,
    condition,
    sort,
    sellerId,
    pageSize,
  );
}
