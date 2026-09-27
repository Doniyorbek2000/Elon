/// Typed failures surfaced from the data layer. UI maps these to copy/icons;
/// repositories never leak transport exceptions (Dio, platform) upward.
sealed class AppFailure implements Exception {
  const AppFailure(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

final class NetworkFailure extends AppFailure {
  const NetworkFailure([super.message = 'Internet aloqasi yo‘q']);
}

final class TimeoutFailure extends AppFailure {
  const TimeoutFailure([super.message = 'Server javob bermadi']);
}

final class ServerFailure extends AppFailure {
  const ServerFailure(super.message, {this.statusCode});

  final int? statusCode;
}

final class NotFoundFailure extends AppFailure {
  const NotFoundFailure([super.message = 'Topilmadi']);
}

/// 401: missing/expired credentials. The session layer signs the user out.
final class UnauthorizedFailure extends AppFailure {
  const UnauthorizedFailure([super.message = 'Tizimga qayta kiring']);
}

/// 403: authenticated but not allowed (roles, inactive account).
final class ForbiddenFailure extends AppFailure {
  const ForbiddenFailure([super.message = 'Bu amal uchun ruxsat yo‘q']);
}

/// 403 BLOCKED: one of the users blocked the other.
final class BlockedFailure extends AppFailure {
  const BlockedFailure([super.message = 'Bu foydalanuvchi bilan yozishib bo‘lmaydi']);
}

/// 409: state conflict (duplicate, invalid status transition).
final class ConflictFailure extends AppFailure {
  const ConflictFailure(super.message, {this.code});

  final String? code;
}

final class ValidationFailure extends AppFailure {
  const ValidationFailure(super.message, {this.fieldErrors = const {}, this.code});

  final Map<String, String> fieldErrors;

  /// Server error code, e.g. `OTP_INVALID`, `NOT_ELIGIBLE`.
  final String? code;
}

final class RateLimitFailure extends AppFailure {
  const RateLimitFailure([super.message = 'Juda ko‘p so‘rov. Birozdan so‘ng urinib ko‘ring', this.retryAfter]);

  final Duration? retryAfter;
}

final class PermissionFailure extends AppFailure {
  const PermissionFailure(super.message, {this.permanentlyDenied = false});

  final bool permanentlyDenied;
}

final class UnknownFailure extends AppFailure {
  const UnknownFailure([super.message = 'Kutilmagan xatolik yuz berdi']);
}

extension AppFailureX on Object {
  AppFailure asFailure() => this is AppFailure ? this as AppFailure : const UnknownFailure();
}
