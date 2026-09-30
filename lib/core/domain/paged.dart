import 'package:flutter/foundation.dart';

import '../errors/app_failure.dart';

/// One page from a cursor-paginated endpoint.
@immutable
class PageResult<T> {
  const PageResult({required this.items, required this.nextCursor, this.total, this.fromCache = false});

  final List<T> items;

  /// Null when there are no more pages.
  final String? nextCursor;
  final int? total;

  /// True when the page comes from the on-device cache because the network is unavailable.
  final bool fromCache;

  bool get hasMore => nextCursor != null;
}

/// UI state for an infinite list. Initial load/error is represented by the
/// surrounding `AsyncValue`; this tracks follow-up pages.
@immutable
class PagedState<T> {
  const PagedState({
    required this.items,
    required this.nextCursor,
    this.isLoadingMore = false,
    this.loadMoreError,
    this.total,
    this.fromCache = false,
  });

  factory PagedState.fromPage(PageResult<T> page) =>
      PagedState(items: page.items, nextCursor: page.nextCursor, total: page.total, fromCache: page.fromCache);

  final List<T> items;
  final String? nextCursor;
  final bool isLoadingMore;
  final AppFailure? loadMoreError;
  final int? total;
  final bool fromCache;

  bool get hasMore => nextCursor != null;
  bool get isEmpty => items.isEmpty;

  PagedState<T> appending(PageResult<T> page) =>
      PagedState(items: [...items, ...page.items], nextCursor: page.nextCursor, total: page.total ?? total);

  PagedState<T> copyWith({List<T>? items, bool? isLoadingMore, AppFailure? loadMoreError, bool clearError = false}) =>
      PagedState(
        items: items ?? this.items,
        nextCursor: nextCursor,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        loadMoreError: clearError ? null : loadMoreError ?? this.loadMoreError,
        total: total,
        fromCache: fromCache,
      );
}
