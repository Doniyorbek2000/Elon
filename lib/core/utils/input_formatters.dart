import 'package:flutter/services.dart';

/// Groups digits with spaces while typing ("120 000 000") and keeps the caret
/// stable. Parse with [ThousandsInputFormatter.parse].
class ThousandsInputFormatter extends TextInputFormatter {
  const ThousandsInputFormatter({this.maxDigits = 13});

  final int maxDigits;

  static int? parse(String text) {
    final digits = text.replaceAll(RegExp(r'\D'), '');
    return digits.isEmpty ? null : int.tryParse(digits);
  }

  static String format(int? value) {
    if (value == null) return '';
    final digits = '$value';
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > maxDigits) digits = digits.substring(0, maxDigits);
    digits = digits.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    final formatted = digits.isEmpty ? '' : format(int.parse(digits));

    // Keep the caret after the same number of digits as before formatting.
    final caret = newValue.selection.end.clamp(0, newValue.text.length);
    final digitsBeforeCaret = newValue.text.substring(0, caret).replaceAll(RegExp(r'\D'), '').length;
    var offset = 0;
    var seen = 0;
    while (offset < formatted.length && seen < digitsBeforeCaret) {
      if (formatted[offset] != ' ') seen++;
      offset++;
    }
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}

/// "+998 90 123 45 67" mask for Uzbek mobile numbers (9 national digits).
class UzPhoneInputFormatter extends TextInputFormatter {
  const UzPhoneInputFormatter();

  static String digitsOf(String text) {
    final digits = text.replaceAll(RegExp(r'\D'), '');
    return digits.startsWith('998') && digits.length > 9 ? digits.substring(3) : digits;
  }

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 9) digits = digits.substring(0, 9);
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i == 2 || i == 5 || i == 7) buffer.write(' ');
      buffer.write(digits[i]);
    }
    final text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
