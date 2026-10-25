/// Undoes the common `eval(function(p,a,c,k,e,d){...})` script packer that
/// video embed pages use to hide their player setup. Text only: the script
/// is never run.
library;

final _packed = RegExp(
  r"""\}\s*\(\s*'((?:\\.|[^'\\])*)'\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*'((?:\\.|[^'\\])*)'\.split\(\s*'\|'\s*\)""",
  dotAll: true,
);
final _word = RegExp(r'\b\w+\b');
const _digits = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';

/// The unpacked source of every packed script in [text]; empty when there is
/// none or a script is malformed.
List<String> unpackAll(String text) => [
      for (final m in _packed.allMatches(text))
        ?_unpack(_unescape(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!), _unescape(m.group(4)!)),
    ];

String? _unpack(String payload, int radix, int count, String keywords) {
  if (radix < 2 || radix > _digits.length) return null;
  final words = keywords.split('|');
  if (words.length < count) words.addAll(List.filled(count - words.length, ''));
  return payload.replaceAllMapped(_word, (m) {
    final w = m.group(0)!;
    final i = _decode(w, radix);
    return (i != null && i < words.length && words[i].isNotEmpty) ? words[i] : w;
  });
}

int? _decode(String word, int radix) {
  var n = 0;
  for (final ch in word.split('')) {
    final d = _digits.indexOf(ch);
    if (d < 0 || d >= radix) return null;
    n = n * radix + d;
  }
  return n;
}

String _unescape(String s) => s.replaceAllMapped(RegExp(r"\\(['\\])"), (m) => m.group(1)!);
