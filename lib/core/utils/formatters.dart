import '../../core/l10n/l10n.dart';
import '../domain/money.dart';

/// Uzbek-locale formatting helpers. Pure functions → trivially testable.
abstract final class Formatters {
  static const _nbsp = ' ';

  static const _monthsRuGenitive = [
    'января',
    'февраля',
    'марта',
    'апреля',
    'мая',
    'июня',
    'июля',
    'августа',
    'сентября',
    'октября',
    'ноября',
    'декабря',
  ];

  static const _monthsRuNominative = [
    'январь',
    'февраль',
    'март',
    'апрель',
    'май',
    'июнь',
    'июль',
    'август',
    'сентябрь',
    'октябрь',
    'ноябрь',
    'декабрь',
  ];

  static bool get _ru => currentLanguage == AppLanguage.ru;

  static const _months = [
    'yanvar',
    'fevral',
    'mart',
    'aprel',
    'may',
    'iyun',
    'iyul',
    'avgust',
    'sentabr',
    'oktabr',
    'noyabr',
    'dekabr',
  ];

  /// 120000000 → "120 000 000" (non-breaking spaces so prices never wrap mid-number).
  static String groupDigits(num value) {
    final digits = value.round().abs().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(_nbsp);
      buffer.write(digits[i]);
    }
    return value < 0 ? '-$buffer' : buffer.toString();
  }

  static String money(Money money) => switch (money.currency) {
    Currency.uzs => '${groupDigits(money.amount)}$_nbsp${tr('so‘m')}',
    Currency.usd => '\$${groupDigits(money.amount)}',
  };

  static String moneyOrNegotiable(Money? value, {bool negotiable = false}) {
    if (value == null) return tr('Kelishiladi');
    return money(value);
  }

  /// "3 000 000 – 5 000 000 so‘m", "5 000 000 so‘m dan", "Suhbat asosida".
  static String salaryRange(int? min, int? max, Currency currency) {
    if (min == null && max == null) return tr('Suhbat asosida');
    final suffix = currency == Currency.uzs ? '$_nbsp${tr('so‘m')}' : '';
    final prefix = currency == Currency.usd ? '\$' : '';
    if (min != null && max != null) return '$prefix${groupDigits(min)} – $prefix${groupDigits(max)}$suffix';
    if (min != null) return tr('{p0} dan', {'p0': '$prefix${groupDigits(min)}$suffix'});
    return tr('{p0} gacha', {'p0': '$prefix${groupDigits(max!)}$suffix'});
  }

  /// Compact counts: 950 → "950", 2400 → "2.4K", 1250000 → "1.3M".
  static String compactCount(int value) {
    if (value < 1000) return '$value';
    if (value < 1000000) return '${_trim(value / 1000)}K';
    return '${_trim(value / 1000000)}M';
  }

  static String _trim(double value) {
    final fixed = value.toStringAsFixed(1);
    return fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
  }

  /// "hozirgina", "5 daqiqa oldin", "2 soat oldin", "kecha", "3 kun oldin", "12 mart".
  static String relativeTime(DateTime time, DateTime now) {
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return tr('hozirgina');
    if (diff.inMinutes < 60) return _ago(diff.inMinutes, 'daqiqa', ('минуту', 'минуты', 'минут'));
    if (diff.inHours < 24) return _ago(diff.inHours, 'soat', ('час', 'часа', 'часов'));
    if (diff.inDays == 1) return tr('kecha');
    if (diff.inDays < 7) return _ago(diff.inDays, 'kun', ('день', 'дня', 'дней'));
    if (diff.inDays < 30) return _ago(diff.inDays ~/ 7, 'hafta', ('неделю', 'недели', 'недель'));
    return date(time, now: now);
  }

  static String _ago(int n, String uzUnit, (String, String, String) ru) =>
      _ru ? '$n ${pluralRu(n, ru.$1, ru.$2, ru.$3)} назад' : '$n $uzUnit oldin';

  /// "12 mart" in the current year, "12 mart 2024" otherwise.
  static String date(DateTime time, {required DateTime now}) {
    final month = (_ru ? _monthsRuGenitive : _months)[time.month - 1];
    final base = '${time.day} $month';
    return time.year == now.year ? base : '$base ${time.year}';
  }

  static String monthYear(DateTime time) => '${(_ru ? _monthsRuNominative : _months)[time.month - 1]} ${time.year}';

  /// "10:24"
  static String clock(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  /// Chat list stamp: time today, "kecha", or date.
  static String chatStamp(DateTime time, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(time.year, time.month, time.day);
    final days = today.difference(day).inDays;
    if (days == 0) return clock(time);
    if (days == 1) return tr('kecha');
    return date(time, now: now);
  }

  /// Day separator in conversations.
  static String dayLabel(DateTime time, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(time.year, time.month, time.day);
    final days = today.difference(day).inDays;
    if (days == 0) return tr('Bugun');
    if (days == 1) return tr('Kecha');
    return date(time, now: now);
  }

  /// "Onlayn" / "5 daqiqa oldin faol edi".
  static String presence({required bool isOnline, DateTime? lastActiveAt, required DateTime now}) {
    if (isOnline) return tr('Onlayn');
    if (lastActiveAt == null) return tr('Yaqinda faol edi');
    return tr('{p0} faol edi', {'p0': relativeTime(lastActiveAt, now)});
  }

  /// "+998 90 123 45 67"
  static String phone(String digits) {
    final d = digits.replaceAll(RegExp(r'\D'), '');
    if (d.length != 12 || !d.startsWith('998')) return digits;
    return '+998 ${d.substring(3, 5)} ${d.substring(5, 8)} ${d.substring(8, 10)} ${d.substring(10)}';
  }

  /// "+998 90 *** ** 67" — never show full numbers until the user explicitly asks.
  static String maskedPhone(String digits) {
    final d = digits.replaceAll(RegExp(r'\D'), '');
    if (d.length != 12) return '+998 ** *** ** **';
    return '+998 ${d.substring(3, 5)} *** ** ${d.substring(10)}';
  }

  static String distance(double km) =>
      km < 1 ? '${(km * 1000).round()} m' : tr('{p0} km', {'p0': km < 10 ? km.toStringAsFixed(1) : km.round()});
}
