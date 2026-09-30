import 'dart:io';

import 'package:bozor/core/domain/money.dart';
import 'package:bozor/core/domain/place.dart';
import 'package:bozor/core/l10n/l10n.dart';
import 'package:bozor/core/l10n/ru.dart';
import 'package:bozor/core/utils/formatters.dart';
import 'package:bozor/features/create_listing/domain/listing_draft.dart';
import 'package:bozor/features/jobs/domain/job.dart';
import 'package:bozor/features/listings/domain/listing_query.dart';
import 'package:bozor/features/location/data/uzbekistan_locations.dart';
import 'package:bozor/features/search/domain/search.dart';
import 'package:bozor/features/services/domain/service_provider.dart';
import 'package:bozor/features/trust_safety/domain/trust_safety.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  valueTests();
  tearDown(() => currentLanguage = AppLanguage.uz);

  group('tr', () {
    test('returns the Uzbek source and fills placeholders in Uzbek', () {
      expect(tr('Hammasi ({length})', {'length': 12}), 'Hammasi (12)');
      expect(tr('Hech qanday tarjima yo‘q'), 'Hech qanday tarjima yo‘q');
    });

    test('translates to Russian and keeps every placeholder', () {
      currentLanguage = AppLanguage.ru;
      expect(tr('Hammasi ({length})', {'length': 12}), 'Все (12)');
      expect(tr('Hech qanday tarjima yo‘q'), 'Hech qanday tarjima yo‘q', reason: 'unknown text falls back to source');
    });

    test('russian plural forms', () {
      String hours(int n) => pluralRu(n, 'час', 'часа', 'часов');
      expect([1, 2, 4, 5, 11, 12, 14, 21, 22, 25, 101, 111].map(hours), [
        'час',
        'часа',
        'часа',
        'часов',
        'часов',
        'часов',
        'часов',
        'час',
        'часа',
        'часов',
        'час',
        'часов',
      ]);
    });
  });

  group('translation table', () {
    test('every tr() call in lib/ has a Russian entry with the same placeholders', () {
      final call = RegExp(r"\btr\('((?:[^'\\]|\\.)*)'");
      final placeholder = RegExp(r'\{\w+\}');
      final missing = <String>[];
      final mismatched = <String>[];
      for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart') || file.path.contains('core/l10n/')) continue;
        for (final match in call.allMatches(file.readAsStringSync())) {
          final key = match.group(1)!.replaceAll(r'\n', '\n').replaceAll(r"\'", "'");
          final value = russianStrings[key];
          if (value == null) {
            missing.add('${file.path}: $key');
          } else if (!_sameSet(
            placeholder.allMatches(key).map((m) => m[0]!),
            placeholder.allMatches(value).map((m) => m[0]!),
          )) {
            mismatched.add('$key → $value');
          }
        }
      }
      expect(missing, isEmpty, reason: 'add these to tool/l10n/*.txt and run tool/l10n/build.py');
      expect(mismatched, isEmpty);
    });

    test('russian values are not accidentally Uzbek (Latin) text', () {
      final latin = RegExp(r'[A-Za-z]{4,}');
      const allowed = {
        'Bozor',
        'Business',
        'Google Play',
        'App Store',
        'Telegram',
        'iPhone',
        'Excel',
        'Cobalt',
        'Chevrolet',
        'WebP',
        'HEIC',
        'JPEG',
        'API_BASE_URL',
        'Deep Purple',
      };
      final offenders = [
        for (final e in russianStrings.entries)
          if (latin.hasMatch(e.value.replaceAll(RegExp(r'\{\w+\}'), '')) &&
              !allowed.any(e.value.contains) &&
              !e.value.contains(RegExp(r'[0-9]')))
            '${e.key} → ${e.value}',
      ];
      expect(offenders, isEmpty);
    });

    test('enum labels are translated', () {
      currentLanguage = AppLanguage.ru;
      final labels = <String>[
        for (final v in CreateStep.values) v.label,
        for (final v in EmploymentType.values) v.label,
        for (final v in ExperienceLevel.values) v.label,
        for (final v in JobStatus.values) v.label,
        for (final v in ApplicationStatus.values) v.label,
        for (final v in ResumeVisibility.values) v.label,
        for (final v in ListingSort.values) v.label,
        for (final v in SearchScope.values) v.label,
        for (final v in PricingType.values) v.label,
        for (final v in ProviderFilter.values) v.label,
        for (final v in ReportReason.values) v.label,
      ];
      final untranslated = labels.where((l) => l.contains(RegExp(r'[A-Za-z]{4,}')) && l != 'TOP' && l != 'VIP');
      expect(untranslated, isEmpty);
    });

    test('every region, district and locality name has a Russian name', () {
      final names = <String>[
        for (final region in UzbekistanLocations.tree.regions) ...[
          region.name,
          for (final district in region.districts) ...[district.name, for (final l in district.localities) l.name],
        ],
      ];
      expect(names.where((n) => !russianStrings.containsKey(n)), isEmpty);
    });
  });

  group('formatting in Russian', () {
    final now = DateTime(2026, 9, 30, 12);

    test('relative time uses correct plural forms', () {
      currentLanguage = AppLanguage.ru;
      expect(Formatters.relativeTime(now.subtract(const Duration(minutes: 1)), now), '1 минуту назад');
      expect(Formatters.relativeTime(now.subtract(const Duration(minutes: 5)), now), '5 минут назад');
      expect(Formatters.relativeTime(now.subtract(const Duration(hours: 2)), now), '2 часа назад');
      expect(Formatters.relativeTime(now.subtract(const Duration(hours: 21)), now), '21 час назад');
      expect(Formatters.relativeTime(now.subtract(const Duration(days: 1)), now), 'вчера');
      expect(Formatters.relativeTime(now.subtract(const Duration(days: 3)), now), '3 дня назад');
      expect(Formatters.relativeTime(now.subtract(const Duration(days: 14)), now), '2 недели назад');
      expect(Formatters.relativeTime(now.subtract(const Duration(seconds: 10)), now), 'только что');
    });

    test('dates and months', () {
      currentLanguage = AppLanguage.ru;
      expect(Formatters.date(DateTime(2026, 3, 12), now: now), '12 марта');
      expect(Formatters.date(DateTime(2024, 1, 5), now: now), '5 января 2024');
      expect(Formatters.monthYear(DateTime(2026, 9)), 'сентябрь 2026');
    });

    test('unchanged in Uzbek', () {
      expect(Formatters.relativeTime(now.subtract(const Duration(hours: 2)), now), '2 soat oldin');
      expect(Formatters.date(DateTime(2026, 3, 12), now: now), '12 mart');
    });

    test('money and salary ranges', () {
      currentLanguage = AppLanguage.ru;
      expect(Formatters.salaryRange(3000000, null, Currency.uzs), endsWith('сум'));
      expect(Formatters.salaryRange(3000000, null, Currency.uzs), startsWith('от '));
      expect(Formatters.salaryRange(null, 5000000, Currency.uzs), startsWith('до '));
    });

    test('places read naturally in Russian', () {
      currentLanguage = AppLanguage.ru;
      const place = Place(
        regionId: 'namangan',
        regionName: 'Namangan viloyati',
        districtId: 'chust',
        districtName: 'Chust tumani',
        localityName: 'Karkidon',
      );
      expect(place.shortLabel, 'Чустский, Наманганская');
      expect(place.fullLabel, 'Каркидон, Чустский район, Наманганская область');
      currentLanguage = AppLanguage.uz;
      expect(place.shortLabel, 'Chust, Namangan');
    });
  });
}

bool _sameSet(Iterable<String> a, Iterable<String> b) {
  final x = a.toList()..sort();
  final y = b.toList()..sort();
  return x.join('|') == y.join('|');
}

void valueTests() {
  group('trValue', () {
    tearDown(() => currentLanguage = AppLanguage.uz);

    test('translates composite attribute values in Russian only', () {
      expect(trValue('Benzin/Metan'), 'Benzin/Metan');
      currentLanguage = AppLanguage.ru;
      expect(trValue('Benzin/Metan'), 'Бензин/Метан');
      expect(trValue('Kia, Yevro ta’mir'), 'Kia, Евроремонт');
      expect(trValue('35 000 km'), '35 000 км');
      expect(trValue('2023'), '2023');
    });
  });
}
