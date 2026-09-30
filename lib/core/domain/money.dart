import 'package:flutter/foundation.dart';

import '../../core/l10n/l10n.dart';

enum Currency {
  uzs,
  usd;

  static Currency parse(Object? value) => value == 'usd' || value == 'USD' ? Currency.usd : Currency.uzs;

  String get label => switch (this) {
    Currency.uzs => tr('so‘m'),
    Currency.usd => 'y.e.',
  };
}

/// Integer amount in whole currency units (so‘m has no minor unit in practice).
@immutable
class Money implements Comparable<Money> {
  const Money(this.amount, [this.currency = Currency.uzs]);

  const Money.uzs(this.amount) : currency = Currency.uzs;
  const Money.usd(this.amount) : currency = Currency.usd;

  final int amount;
  final Currency currency;

  /// Rough UZS normalization so mixed-currency results can be sorted by price.
  /// The backend should own real exchange rates; this is a display-order fallback.
  int get approxUzs => currency == Currency.usd ? amount * _usdRate : amount;
  static const _usdRate = 12600;

  factory Money.fromJson(Map<String, dynamic> json) =>
      Money((json['amount'] as num).round(), Currency.parse(json['currency']));

  Map<String, dynamic> toJson() => {'amount': amount, 'currency': currency.name};

  @override
  int compareTo(Money other) => approxUzs.compareTo(other.approxUzs);

  @override
  bool operator ==(Object other) => other is Money && other.amount == amount && other.currency == currency;

  @override
  int get hashCode => Object.hash(amount, currency);
}
