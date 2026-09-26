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

final class UnauthorizedFailure extends AppFailure {
  const UnauthorizedFailure([super.message = 'Tizimga qayta kiring']);
}

final class ValidationFailure extends AppFailure {
  const ValidationFailure(super.message, {this.fieldErrors = const {}});

  final Map<String, String> fieldErrors;
}

final class RateLimitFailure extends AppFailure {
  const RateLimitFailure([super.message = 'Juda ko‘p so‘rov. Birozdan so‘ng urinib ko‘ring']);
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
