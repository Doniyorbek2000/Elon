/// Query normalization shared by client-side matching: case folding, Uzbek
/// apostrophe variants, Cyrillic→Latin transliteration, common synonyms and
/// small-edit-distance typo tolerance.
abstract final class SearchNormalizer {
  static const _cyrillic = {
    'а': 'a',
    'б': 'b',
    'в': 'v',
    'г': 'g',
    'д': 'd',
    'е': 'e',
    'ё': 'yo',
    'ж': 'j',
    'з': 'z',
    'и': 'i',
    'й': 'y',
    'к': 'k',
    'л': 'l',
    'м': 'm',
    'н': 'n',
    'о': 'o',
    'п': 'p',
    'р': 'r',
    'с': 's',
    'т': 't',
    'у': 'u',
    'ф': 'f',
    'х': 'x',
    'ц': 's',
    'ч': 'ch',
    'ш': 'sh',
    'щ': 'sh',
    'ъ': '',
    'ы': 'i',
    'ь': '',
    'э': 'e',
    'ю': 'yu',
    'я': 'ya',
    'ў': 'o',
    'қ': 'q',
    'ғ': 'g',
    'ҳ': 'h',
  };

  /// Colloquial spellings → canonical token.
  static const _synonyms = {
    'ayfon': 'iphone',
    'aifon': 'iphone',
    'iphon': 'iphone',
    'samsng': 'samsung',
    'kobalt': 'cobalt',
    'jentra': 'gentra',
    'neksiya': 'nexia',
    'nexiya': 'nexia',
    'malibo': 'malibu',
    'noutbook': 'noutbuk',
    'notebook': 'noutbuk',
    'laptop': 'noutbuk',
    'kvartira': 'kvartira',
    'xonadon': 'kvartira',
    'santexnika': 'santexnik',
    'elektrika': 'elektrik',
    'shofyor': 'haydovchi',
    'voditel': 'haydovchi',
    'telefon': 'telefon',
  };

  static String normalize(String input) {
    final lower = input.toLowerCase();
    final buffer = StringBuffer();
    for (final rune in lower.runes) {
      final char = String.fromCharCode(rune);
      buffer.write(_cyrillic[char] ?? char);
    }
    return buffer
        .toString()
        .replaceAll(RegExp('[‘’ʻʼ`\']'), '')
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static List<String> tokens(String input) => [
    for (final token in normalize(input).split(' '))
      if (token.isNotEmpty) _synonyms[token] ?? token,
  ];

  /// True when every query token matches some token in [haystack]
  /// (prefix match, or edit distance ≤ 1 for tokens ≥ 4 chars).
  static bool matches(List<String> queryTokens, String haystack) {
    if (queryTokens.isEmpty) return true;
    final targetTokens = tokens(haystack);
    return queryTokens.every(
      (q) => targetTokens.any((t) => tokenMatches(q, t)),
    );
  }

  /// Relevance score: exact token > prefix > fuzzy. 0 = no match.
  static int score(List<String> queryTokens, String haystack) {
    final targetTokens = tokens(haystack);
    var total = 0;
    for (final q in queryTokens) {
      var best = 0;
      for (final t in targetTokens) {
        if (t == q) {
          best = 3;
          break;
        }
        if (t.startsWith(q)) {
          best = best < 2 ? 2 : best;
        } else if (tokenMatches(q, t)) {
          best = best < 1 ? 1 : best;
        }
      }
      if (best == 0) return 0;
      total += best;
    }
    return total;
  }

  static bool tokenMatches(String query, String target) {
    if (target.startsWith(query)) return true;
    if (query.length < 4) return false;
    final comparable = target.length > query.length + 1
        ? target.substring(0, query.length)
        : target;
    return editDistance(query, comparable) <= 1;
  }

  /// Canonical form of the query when synonyms changed it, for "Did you mean".
  static String? correction(String input) {
    final raw = normalize(input).split(' ').where((t) => t.isNotEmpty).toList();
    final canonical = tokens(input);
    if (raw.join(' ') == canonical.join(' ')) return null;
    return canonical.join(' ');
  }

  static int editDistance(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    var previous = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final current = List<int>.filled(b.length + 1, 0)..[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        current[j] = [
          previous[j] + 1,
          current[j - 1] + 1,
          previous[j - 1] + cost,
        ].reduce((x, y) => x < y ? x : y);
      }
      previous = current;
    }
    return previous[b.length];
  }
}
