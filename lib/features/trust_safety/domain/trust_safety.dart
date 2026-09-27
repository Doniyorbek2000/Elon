import 'package:flutter/foundation.dart';

import '../../../core/domain/money.dart';

enum ReportTargetType { listing, user, job, provider, conversation }

enum ReportReason {
  fraud('Firibgarlik yoki aldov'),
  prohibited('Taqiqlangan mahsulot yoki xizmat'),
  wrongInfo('Noto‘g‘ri narx yoki ma’lumot'),
  wrongCategory('Noto‘g‘ri kategoriya'),
  duplicate('Takroriy e’lon'),
  spam('Spam yoki reklama'),
  offensive('Haqoratli kontent'),
  other('Boshqa sabab');

  const ReportReason(this.label);

  final String label;
}

@immutable
class ReportRequest {
  const ReportRequest({
    required this.targetType,
    required this.targetId,
    required this.reason,
    this.comment,
  });

  final ReportTargetType targetType;
  final String targetId;
  final ReportReason reason;
  final String? comment;
}

abstract interface class TrustSafetyRepository {
  Future<void> report(ReportRequest request);
  Future<void> block(String userId);
  Future<void> unblock(String userId);
  Future<Set<String>> blockedUserIds();
}

enum RiskSeverity { info, warning, blocking }

@immutable
class RiskSignal {
  const RiskSignal(this.code, this.message, this.severity);

  final String code;
  final String message;
  final RiskSeverity severity;
}

/// Client-side heuristics that nudge honest users and route suspicious
/// content to moderation. The server re-checks everything; this is UX, not
/// the security boundary.
abstract final class ContentRiskRules {
  static final _phone = RegExp(
    r'(\+?998[\s-]?)?\(?\d{2}\)?[\s-]?\d{3}[\s-]?\d{2}[\s-]?\d{2}',
  );
  static final _card = RegExp(
    r'\b(?:8600|9860|5614|4\d{3}|5[1-5]\d{2})[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b',
  );
  static final _link = RegExp(
    r'(https?://|www\.|t\.me/|@[a-z0-9_]{5,})',
    caseSensitive: false,
  );
  static final _prepayment = RegExp(
    r'(oldindan\s+to.?lov|avans\s+to.?la|predoplat|предоплат|kartaga\s+tashla|zakalat)',
    caseSensitive: false,
  );

  static bool containsPhone(String text) => _phone.hasMatch(text);
  static bool containsCard(String text) => _card.hasMatch(text);
  static bool containsLink(String text) => _link.hasMatch(text);
  static bool asksPrepayment(String text) => _prepayment.hasMatch(text);
}

/// Scores a listing before publishing.
abstract final class ListingRiskAssessor {
  /// [referencePrice] is a typical price for the category (from backend stats).
  static List<RiskSignal> assess({
    required String title,
    required String description,
    Money? price,
    Money? referencePrice,
  }) {
    final text = '$title\n$description';
    final signals = <RiskSignal>[];
    if (ContentRiskRules.containsCard(text)) {
      signals.add(
        const RiskSignal(
          'card_number',
          'Karta raqamini e’londa ko‘rsatmang — firibgarlar undan foydalanishi mumkin.',
          RiskSeverity.blocking,
        ),
      );
    }
    if (ContentRiskRules.containsPhone(text)) {
      signals.add(
        const RiskSignal(
          'phone_in_text',
          'Telefon raqamini matnga yozish shart emas — xaridorlar «Qo‘ng‘iroq» tugmasi orqali bog‘lanadi.',
          RiskSeverity.warning,
        ),
      );
    }
    if (ContentRiskRules.containsLink(text)) {
      signals.add(
        const RiskSignal(
          'external_link',
          'Tashqi havolalar va Telegram manzillari e’lonni tekshiruvga yuboradi.',
          RiskSeverity.warning,
        ),
      );
    }
    if (ContentRiskRules.asksPrepayment(text)) {
      signals.add(
        const RiskSignal(
          'prepayment',
          'Oldindan to‘lov talab qilish qoidalarga zid. E’lon moderatsiyadan o‘tadi.',
          RiskSeverity.warning,
        ),
      );
    }
    final letters = title.replaceAll(RegExp(r'[^A-Za-zА-Яа-я]'), '');
    if (letters.length >= 8 && letters == letters.toUpperCase()) {
      signals.add(
        const RiskSignal(
          'caps_title',
          'Sarlavhani katta harflar bilan yozmang — bu o‘qishni qiyinlashtiradi.',
          RiskSeverity.info,
        ),
      );
    }
    if (price != null &&
        referencePrice != null &&
        price.approxUzs > 0 &&
        price.approxUzs < referencePrice.approxUzs * 0.25) {
      signals.add(
        const RiskSignal(
          'price_outlier',
          'Narx shu turdagi e’lonlardan juda past. Narxni tekshiring.',
          RiskSeverity.warning,
        ),
      );
    }
    return signals;
  }

  /// Anything above [RiskSeverity.info] is published as "pending review".
  static bool requiresModeration(List<RiskSignal> signals) =>
      signals.any((signal) => signal.severity != RiskSeverity.info);
}

enum MessageVerdict { allow, warn, throttle }

@immutable
class MessageCheck {
  const MessageCheck(this.verdict, [this.message]);

  final MessageVerdict verdict;
  final String? message;
}

/// Anti-spam guard for outgoing chat messages: throttles bursts and warns
/// about sharing card numbers or prepayment requests.
class MessageGuard {
  MessageGuard({
    this.maxMessages = 6,
    this.window = const Duration(seconds: 10),
  });

  final int maxMessages;
  final Duration window;
  final List<DateTime> _recent = [];

  MessageCheck check(String text, DateTime now) {
    _recent.removeWhere((sentAt) => now.difference(sentAt) > window);
    if (_recent.length >= maxMessages) {
      return const MessageCheck(
        MessageVerdict.throttle,
        'Juda tez yozyapsiz. Bir necha soniya kuting.',
      );
    }
    if (ContentRiskRules.containsCard(text)) {
      return const MessageCheck(
        MessageVerdict.warn,
        'Karta ma’lumotlarini begonalarga yubormang. Pulni faqat mahsulotni ko‘rgandan keyin to‘lang.',
      );
    }
    if (ContentRiskRules.asksPrepayment(text)) {
      return const MessageCheck(
        MessageVerdict.warn,
        'Oldindan to‘lov — firibgarlikning eng keng tarqalgan usuli. Ehtiyot bo‘ling.',
      );
    }
    return const MessageCheck(MessageVerdict.allow);
  }

  void recordSent(DateTime now) => _recent.add(now);
}
