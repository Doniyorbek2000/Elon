import 'package:bozor/core/domain/money.dart';
import 'package:bozor/core/utils/formatters.dart';
import 'package:bozor/core/utils/input_formatters.dart';
import 'package:bozor/features/catalog/data/bundled_categories.dart';
import 'package:bozor/features/catalog/domain/category.dart';
import 'package:bozor/features/location/data/uzbekistan_locations.dart';
import 'package:bozor/features/location/domain/location.dart';
import 'package:bozor/features/search/domain/search_normalizer.dart';
import 'package:bozor/features/trust_safety/domain/trust_safety.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Formatters', () {
    test('formats so‘m with non-breaking thousand separators', () {
      expect(Formatters.money(const Money.uzs(120000000)), '120 000 000 so‘m');
      expect(Formatters.money(const Money.usd(38000)), '\$38 000');
    });

    test('salary ranges cover min/max/negotiable', () {
      expect(
        Formatters.salaryRange(3000000, 5000000, Currency.uzs),
        '3 000 000 – 5 000 000 so‘m',
      );
      expect(
        Formatters.salaryRange(3500000, null, Currency.uzs),
        '3 500 000 so‘m dan',
      );
      expect(
        Formatters.salaryRange(null, null, Currency.uzs),
        'Suhbat asosida',
      );
    });

    test('relative time in Uzbek', () {
      final now = DateTime(2026, 9, 26, 12);
      expect(
        Formatters.relativeTime(now.subtract(const Duration(seconds: 20)), now),
        'hozirgina',
      );
      expect(
        Formatters.relativeTime(now.subtract(const Duration(minutes: 5)), now),
        '5 daqiqa oldin',
      );
      expect(
        Formatters.relativeTime(now.subtract(const Duration(hours: 1)), now),
        '1 soat oldin',
      );
      expect(
        Formatters.relativeTime(now.subtract(const Duration(days: 1)), now),
        'kecha',
      );
      expect(
        Formatters.relativeTime(now.subtract(const Duration(days: 3)), now),
        '3 kun oldin',
      );
      expect(
        Formatters.relativeTime(DateTime(2025, 3, 12), now),
        '12 mart 2025',
      );
    });

    test('compact counts and masked phones', () {
      expect(Formatters.compactCount(950), '950');
      expect(Formatters.compactCount(2400), '2.4K');
      expect(Formatters.compactCount(1250000), '1.3M');
      expect(Formatters.phone('998901234567'), '+998 90 123 45 67');
      expect(Formatters.maskedPhone('998901234567'), '+998 90 *** ** 67');
    });
  });

  group('ThousandsInputFormatter', () {
    const formatter = ThousandsInputFormatter();

    test('groups digits while typing and keeps caret at end', () {
      final result = formatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(
          text: '120000000',
          selection: TextSelection.collapsed(offset: 9),
        ),
      );
      expect(result.text, '120 000 000');
      expect(result.selection.baseOffset, result.text.length);
      expect(ThousandsInputFormatter.parse(result.text), 120000000);
    });

    test('strips leading zeros and non-digits', () {
      final result = formatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(
          text: '00a45',
          selection: TextSelection.collapsed(offset: 5),
        ),
      );
      expect(result.text, '45');
    });
  });

  group('SearchNormalizer', () {
    test('normalizes apostrophes, case and Cyrillic', () {
      expect(SearchNormalizer.normalize('Qo‘ng‘iroq'), 'qongiroq');
      expect(SearchNormalizer.normalize('Кобальт'), 'kobalt');
    });

    test('maps colloquial spellings to canonical tokens', () {
      expect(SearchNormalizer.tokens('ayfon 14'), ['iphone', '14']);
      expect(SearchNormalizer.correction('ayfon'), 'iphone');
      expect(SearchNormalizer.correction('iphone'), isNull);
    });

    test('tolerates one typo in longer tokens', () {
      expect(
        SearchNormalizer.matches(
          SearchNormalizer.tokens('santexnk'),
          'Santexnik xizmatlari',
        ),
        isTrue,
      );
      expect(
        SearchNormalizer.matches(
          SearchNormalizer.tokens('iphone'),
          'Samsung Galaxy',
        ),
        isFalse,
      );
    });

    test('scores exact matches above prefix matches', () {
      final tokens = SearchNormalizer.tokens('cobalt');
      expect(
        SearchNormalizer.score(tokens, 'Cobalt 2023'),
        greaterThan(SearchNormalizer.score(tokens, 'Cobalts')),
      );
    });
  });

  group('Trust & safety', () {
    test('flags card numbers as blocking and phone numbers as warnings', () {
      final signals = ListingRiskAssessor.assess(
        title: 'iPhone 14',
        description: 'Pulni 8600 1234 5678 9012 kartaga tashlang. Tel: +998 90 123 45 67',
      );
      final codes = signals.map((s) => s.code).toSet();
      expect(
        codes,
        containsAll(['card_number', 'phone_in_text', 'prepayment']),
      );
      expect(
        signals.firstWhere((s) => s.code == 'card_number').severity,
        RiskSeverity.blocking,
      );
      expect(ListingRiskAssessor.requiresModeration(signals), isTrue);
    });

    test('clean listings do not require moderation', () {
      final signals = ListingRiskAssessor.assess(
        title: 'Cobalt 2023',
        description: 'Holati a’lo, hech qanday ishi yo‘q.',
        price: const Money.uzs(120000000),
        referencePrice: const Money.uzs(120000000),
      );
      expect(signals, isEmpty);
    });

    test('suspiciously low price is flagged', () {
      final signals = ListingRiskAssessor.assess(
        title: 'Cobalt',
        description: 'Tez sotiladi',
        price: const Money.uzs(10000000),
        referencePrice: const Money.uzs(120000000),
      );
      expect(signals.map((s) => s.code), contains('price_outlier'));
    });

    test('message guard throttles bursts and warns about prepayment', () {
      final guard = MessageGuard(
        maxMessages: 3,
        window: const Duration(seconds: 10),
      );
      final now = DateTime(2026);
      for (var i = 0; i < 3; i++) {
        expect(guard.check('salom', now).verdict, MessageVerdict.allow);
        guard.recordSent(now);
      }
      expect(guard.check('salom', now).verdict, MessageVerdict.throttle);
      expect(
        guard.check('salom', now.add(const Duration(seconds: 11))).verdict,
        MessageVerdict.allow,
      );
      expect(
        guard
            .check(
              'Oldindan to‘lov qiling',
              now.add(const Duration(seconds: 11)),
            )
            .verdict,
        MessageVerdict.warn,
      );
    });
  });

  group('Catalog & locations', () {
    final tree = BundledCategories.tree;

    test('nested categories resolve parents, roots and schemas', () {
      expect(tree.parentOf('cars')?.id, 'transport');
      expect(tree.rootOf('phones')?.id, 'electronics');
      expect(tree.isWithin('cars', 'transport'), isTrue);
      expect(tree.isWithin('phones', 'transport'), isFalse);
      expect(
        tree.schemaFor('cars').fields.map((f) => f.key),
        containsAll(['year', 'mileage', 'transmission']),
      );
      expect(tree.schemaFor('jobs').priceMode, PriceMode.salary);
    });

    test('attribute validation enforces ranges and options', () {
      final year = tree
          .schemaFor('cars')
          .fields
          .firstWhere((f) => f.key == 'year');
      expect(year.validate(''), isNotNull);
      expect(year.validate('1800'), isNotNull);
      expect(year.validate('2023'), isNull);
      final transmission = tree
          .schemaFor('cars')
          .fields
          .firstWhere((f) => f.key == 'transmission');
      expect(transmission.validate('Avtomat'), isNull);
      expect(transmission.validate('Nomaʼlum'), isNotNull);
    });

    test('reverse geocoding picks the nearest district', () {
      final nearest = UzbekistanLocations.tree.nearestDistrict(
        const GeoPoint(41.0, 71.24),
      );
      expect(nearest?.district.id, 'chust');
      expect(nearest?.region.id, 'namangan');
    });

    test('covers all 14 top-level administrative units', () {
      expect(UzbekistanLocations.tree.regions, hasLength(14));
    });
  });
}
