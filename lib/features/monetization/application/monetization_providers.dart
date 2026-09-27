import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/config/feature_flags.dart';
import '../../../core/domain/paged.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/external_actions.dart';
import '../../auth/application/session_controller.dart';
import '../data/monetization_repository.dart';
import '../data/store_billing.dart';
import '../domain/monetization.dart';

final monetizationRepositoryProvider = Provider<MonetizationRepository>((ref) {
  if (ref.watch(appConfigProvider).useDemoData) return const UnavailableMonetizationRepository();
  return RemoteMonetizationRepository(ref.watch(apiClientProvider));
});

/// `ios` / `android` / `web`: the server picks allowed payment routes from it.
String checkoutPlatform([TargetPlatform? platform]) {
  if (kIsWeb) return 'web';
  return switch (platform ?? defaultTargetPlatform) {
    TargetPlatform.iOS || TargetPlatform.macOS => 'ios',
    TargetPlatform.android => 'android',
    _ => 'web',
  };
}

final checkoutPlatformProvider = Provider<String>((ref) => checkoutPlatform());

/// Random, URL-safe key per checkout attempt (reused on retry of that attempt).
String newIdempotencyKey([Random? random]) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-';
  final rng = random ?? Random.secure();
  return List.generate(32, (_) => alphabet[rng.nextInt(alphabet.length)]).join();
}

typedef OfferKey = ({PromotionTarget target, String targetId});

/// Products, prices and eligibility for one of the user's items.
final promotionOfferProvider = FutureProvider.autoDispose.family<PromotionOffer, OfferKey>((ref, key) {
  return ref
      .watch(monetizationRepositoryProvider)
      .offer(key.target, key.targetId, platform: ref.watch(checkoutPlatformProvider));
});

final plansProvider = FutureProvider.autoDispose<List<Plan>>((ref) {
  if (!ref.watch(featureFlagsProvider).canBuyPlans) return const [];
  return ref.watch(monetizationRepositoryProvider).plans();
});

final myEntitlementsProvider = FutureProvider.autoDispose<MyEntitlements?>((ref) async {
  if (ref.watch(sessionProvider) == null || ref.watch(appConfigProvider).useDemoData) return null;
  return ref.watch(monetizationRepositoryProvider).entitlements();
});

final mySubscriptionsProvider = FutureProvider.autoDispose<List<Subscription>>((ref) {
  if (ref.watch(sessionProvider) == null) return const [];
  return ref.watch(monetizationRepositoryProvider).subscriptions();
});

final myCreditsProvider = FutureProvider.autoDispose<({int balance, List<CreditEntry> entries})>((ref) {
  if (ref.watch(sessionProvider) == null) return (balance: 0, entries: const <CreditEntry>[]);
  return ref.watch(monetizationRepositoryProvider).credits();
});

final purchaseDetailProvider = FutureProvider.autoDispose.family<Purchase, String>((ref, id) {
  return ref.watch(monetizationRepositoryProvider).purchase(id);
});

/// Payment history ("To‘lovlar tarixi"), newest first, paginated.
final purchaseHistoryProvider = AsyncNotifierProvider.autoDispose<PurchaseHistory, PagedState<Purchase>>(
  PurchaseHistory.new,
);

class PurchaseHistory extends AsyncNotifier<PagedState<Purchase>> {
  @override
  Future<PagedState<Purchase>> build() async {
    if (ref.watch(sessionProvider) == null) return const PagedState(items: [], nextCursor: null);
    return PagedState.fromPage(await ref.watch(monetizationRepositoryProvider).purchases());
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.isLoadingMore) return;
    state = AsyncData(current.copyWith(isLoadingMore: true, clearError: true));
    try {
      final page = await ref.read(monetizationRepositoryProvider).purchases(cursor: current.nextCursor);
      if (!ref.mounted) return;
      state = AsyncData(current.appending(page));
    } on Object catch (error) {
      if (!ref.mounted) return;
      state = AsyncData(current.copyWith(isLoadingMore: false, loadMoreError: error.asFailure()));
    }
  }
}

// ───────────────────────────────────────────────────────────── checkout flow

enum CheckoutPhase {
  idle,
  starting,

  /// The provider page is open; waiting for the server to confirm.
  awaitingPayment,
  succeeded,

  /// Paid, but the server flagged it for manual review (no activation yet).
  review,
  failed,
  cancelled,

  /// No payment route for this platform (e.g. store billing not configured).
  unavailable,
}

@immutable
class CheckoutState {
  const CheckoutState({this.phase = CheckoutPhase.idle, this.purchase, this.failure, this.redirect});

  final CheckoutPhase phase;
  final Purchase? purchase;
  final AppFailure? failure;

  /// Provider page to (re)open while awaiting payment.
  final Uri? redirect;

  bool get busy => phase == CheckoutPhase.starting;

  CheckoutState copyWith({CheckoutPhase? phase, Purchase? purchase, AppFailure? failure, Uri? redirect}) =>
      CheckoutState(
        phase: phase ?? this.phase,
        purchase: purchase ?? this.purchase,
        failure: failure,
        redirect: redirect ?? this.redirect,
      );
}

/// Timing knobs (overridden in tests).
class CheckoutTiming {
  const CheckoutTiming({
    this.pollInterval = const Duration(seconds: 3),
    this.pollTimeout = const Duration(minutes: 15),
  });

  final Duration pollInterval;
  final Duration pollTimeout;
}

final checkoutTimingProvider = Provider<CheckoutTiming>((ref) => const CheckoutTiming());

/// Drives one purchase: create → pay at the provider → wait for the
/// server's verified result. The client never marks anything as paid; it
/// only reflects the purchase status the server reports.
final checkoutControllerProvider = NotifierProvider.autoDispose<CheckoutController, CheckoutState>(
  CheckoutController.new,
);

class CheckoutController extends Notifier<CheckoutState> {
  Timer? _poll;
  DateTime? _pollDeadline;
  CheckoutRequest? _lastRequest;

  @override
  CheckoutState build() {
    ref.onDispose(() => _poll?.cancel());
    return const CheckoutState();
  }

  MonetizationRepository get _repository => ref.read(monetizationRepositoryProvider);

  /// Builds a request for the current platform with a fresh idempotency key.
  CheckoutRequest request({
    required PaymentMethod method,
    String? productId,
    String? planPriceId,
    String? targetId,
    String? couponCode,
  }) => CheckoutRequest(
    method: method,
    productId: productId,
    planPriceId: planPriceId,
    targetId: targetId,
    couponCode: couponCode,
    platform: ref.read(checkoutPlatformProvider),
    idempotencyKey: newIdempotencyKey(),
  );

  Future<void> start(CheckoutRequest request) async {
    if (state.busy || state.phase == CheckoutPhase.awaitingPayment) return;
    // A retry of the same attempt keeps its key, so the server returns the
    // same purchase instead of charging twice.
    final same =
        _lastRequest != null &&
        _lastRequest!.productId == request.productId &&
        _lastRequest!.planPriceId == request.planPriceId &&
        _lastRequest!.targetId == request.targetId &&
        _lastRequest!.method == request.method &&
        state.phase == CheckoutPhase.failed &&
        state.purchase == null;
    final effective = same ? _lastRequest! : request;
    _lastRequest = effective;
    state = const CheckoutState(phase: CheckoutPhase.starting);
    try {
      final purchase = await _repository.checkout(effective);
      if (!ref.mounted) return;
      await _handle(purchase);
    } on PaymentUnavailableFailure catch (failure) {
      if (!ref.mounted) return;
      state = CheckoutState(phase: CheckoutPhase.unavailable, failure: failure);
    } on Object catch (error) {
      if (!ref.mounted) return;
      state = CheckoutState(phase: CheckoutPhase.failed, failure: error.asFailure());
    }
  }

  Future<void> _handle(Purchase purchase) async {
    switch (purchase.action) {
      case RedirectAction(:final url):
        state = CheckoutState(phase: CheckoutPhase.awaitingPayment, purchase: purchase, redirect: url);
        await ref.read(externalActionsProvider).openUrl(url);
        _startPolling(purchase.id);
      case StoreAction():
        // Store billing is not configured: nothing is charged, offer is withdrawn.
        final billing = ref.read(storeBillingProvider);
        if (!billing.available) {
          await _repository.cancelPurchase(purchase.id).then<void>((_) {}, onError: (Object _) {});
          state = CheckoutState(phase: CheckoutPhase.unavailable, purchase: purchase);
          return;
        }
        state = CheckoutState(phase: CheckoutPhase.awaitingPayment, purchase: purchase);
        _startPolling(purchase.id);
      case NoAction() || null:
        _apply(purchase);
        if (state.phase == CheckoutPhase.awaitingPayment) _startPolling(purchase.id);
    }
  }

  void _apply(Purchase purchase) {
    final phase = switch (purchase.status) {
      PurchaseStatus.fulfilled => CheckoutPhase.succeeded,
      PurchaseStatus.needsReview => CheckoutPhase.review,
      PurchaseStatus.failed => CheckoutPhase.failed,
      PurchaseStatus.cancelled || PurchaseStatus.refunded => CheckoutPhase.cancelled,
      PurchaseStatus.awaitingPayment => CheckoutPhase.awaitingPayment,
    };
    state = CheckoutState(phase: phase, purchase: purchase, redirect: state.redirect);
    if (phase != CheckoutPhase.awaitingPayment) _poll?.cancel();
  }

  void _startPolling(String purchaseId) {
    _poll?.cancel();
    final timing = ref.read(checkoutTimingProvider);
    _pollDeadline = DateTime.now().add(timing.pollTimeout);
    _poll = Timer.periodic(timing.pollInterval, (_) => refresh());
  }

  /// Re-reads the server status (also called when the app returns to foreground).
  Future<void> refresh() async {
    final purchase = state.purchase;
    if (purchase == null || state.phase != CheckoutPhase.awaitingPayment) return;
    if (_pollDeadline != null && DateTime.now().isAfter(_pollDeadline!)) _poll?.cancel();
    try {
      final fresh = await _repository.purchase(purchase.id);
      if (!ref.mounted || state.phase != CheckoutPhase.awaitingPayment) return;
      _apply(fresh);
    } on Object {
      // Transient network errors: keep waiting; the next tick retries.
    }
  }

  Future<void> reopenPayment() async {
    final url = state.redirect;
    if (url != null) await ref.read(externalActionsProvider).openUrl(url);
  }

  /// User abandons a pending payment; the server cancels it (a late provider
  /// success is still honoured and reviewed server-side).
  Future<void> cancel() async {
    final purchase = state.purchase;
    _poll?.cancel();
    if (purchase == null || state.phase != CheckoutPhase.awaitingPayment) {
      state = const CheckoutState();
      return;
    }
    try {
      final fresh = await _repository.cancelPurchase(purchase.id);
      if (!ref.mounted) return;
      _apply(fresh);
    } on Object catch (error) {
      if (!ref.mounted) return;
      // Already settled meanwhile: show the real result.
      final fresh = await _repository.purchase(purchase.id).then<Purchase?>((p) => p, onError: (Object _) => null);
      if (!ref.mounted) return;
      if (fresh != null) {
        _apply(fresh);
      } else {
        state = state.copyWith(failure: error.asFailure());
      }
    }
  }

  void reset() {
    _poll?.cancel();
    _lastRequest = null;
    state = const CheckoutState();
  }
}
