/// Facts about a channel that playlists spell many different ways: country,
/// language, categories, picture quality and the little markers lists put
/// in names ("[Geo-blocked]", "Ⓖ", "(1080p)").
///
/// Everything here is pure and cheap so the app can derive it for channels
/// stored before these fields existed, without a refresh.
library;

import 'sources.dart';

/// Picture quality buckets, best first. Names say more than numbers would
/// on a badge, so each has a short [label].
enum ChannelQuality {
  uhd('4K'),
  fhd('1080p'),
  hd('720p'),
  sd('SD'),
  unknown('Unknown');

  const ChannelQuality(this.label);
  final String label;

  static ChannelQuality? byName(String? name) {
    for (final q in values) {
      if (q.name == name) return q;
    }
    return null;
  }

  /// [name], or null for [unknown] (nothing worth storing).
  String? get nameOrNull => this == unknown ? null : name;
}

final _uhdRe = RegExp(r'(\b(2160p|4k|uhd|8k|4320p)\b)', caseSensitive: false);
final _fhdRe = RegExp(r'\b(1080[pi]|fhd|full ?hd)\b', caseSensitive: false);
final _hdRe = RegExp(r'\b(720p|hd)\b', caseSensitive: false);
final _sdRe = RegExp(
  r'\b(576[pi]|480[pi]|360p|240p|sd)\b',
  caseSensitive: false,
);

/// The quality bucket a stream name or a catalogue quality ("1080p") names.
/// The catalogue value wins: it was measured, the name is a promise.
ChannelQuality qualityOf(String name, [String? catalogueQuality]) {
  final cat = catalogueQuality?.trim();
  if (cat != null && cat.isNotEmpty) {
    final q = _qualityIn(cat);
    if (q != ChannelQuality.unknown) return q;
  }
  return _qualityIn(name);
}

// Any quality word at all; most names have none, so one scan settles them.
final _anyQualityRe = RegExp(
  r'\b(2160p|4k|uhd|8k|4320p|1080[pi]|fhd|full ?hd|720p|hd|576[pi]|480[pi]|'
  r'360p|240p|sd)\b',
  caseSensitive: false,
);

ChannelQuality _qualityIn(String s) {
  if (!_anyQualityRe.hasMatch(s)) return ChannelQuality.unknown;
  if (_uhdRe.hasMatch(s)) return ChannelQuality.uhd;
  if (_fhdRe.hasMatch(s)) return ChannelQuality.fhd;
  if (_hdRe.hasMatch(s)) return ChannelQuality.hd;
  if (_sdRe.hasMatch(s)) return ChannelQuality.sd;
  return ChannelQuality.unknown;
}

final _geoRe = RegExp(r'\[\s*geo[- ]?blocked\s*\]|Ⓖ', caseSensitive: false);
final _not247Re = RegExp(r'\[\s*not 24/7\s*\]', caseSensitive: false);
// "[Geo-blocked]", "[Not 24/7]" and any other bracketed note; "(1080p)" style
// quality tags; the circled-letter markers Free-TV uses (U+24B6 to U+24E9).
final _bracketRe = RegExp(r'\[[^\]]*\]');
final _qualityTagRe = RegExp(
  r'\(\s*(2160p|1080[pi]|720p|576[pi]|480[pi]|360p|240p|4k|uhd|fhd|hd|sd)\s*\)',
  caseSensitive: false,
);
final _circledRe = RegExp('[Ⓐ-ⓩ]');
final _spacesRe = RegExp(r'\s{2,}');

/// True when the name carries a geo-blocked marker.
bool isGeoBlocked(String name) =>
    (name.contains('[') || name.contains('Ⓖ')) && _geoRe.hasMatch(name);

/// True when the name says the stream is not on all day.
bool isNot247(String name) => name.contains('[') && _not247Re.hasMatch(name);

/// [name] without list markers and quality tags; the original when nothing
/// would be left.
String cleanChannelName(String name) {
  if (!_mayNeedCleaning(name)) return name.trim();
  final s = name
      .replaceAll(_bracketRe, ' ')
      .replaceAll(_qualityTagRe, ' ')
      .replaceAll(_circledRe, ' ')
      .replaceAll(_spacesRe, ' ')
      .trim();
  return s.isEmpty ? name.trim() : s;
}

/// False when [name] has no bracket, no parenthesis, no circled letter and
/// no double space, so [cleanChannelName] has nothing to strip.
bool _mayNeedCleaning(String name) {
  if (name.contains('[') || name.contains('(') || name.contains('  ')) {
    return true;
  }
  for (final u in name.codeUnits) {
    if (u >= 0x24B6 && u <= 0x24E9) return true;
  }
  return false;
}

/// The ISO 3166 alpha-2 code (upper case) in a `tvg-country` value: "AL",
/// "al;xk" (first wins), "UK" (means GB) or a country name ("Albania").
String? normalizeCountry(String? raw) {
  if (raw == null) return null;
  for (final part in raw.split(RegExp('[;,|]'))) {
    final p = part.trim();
    if (p.isEmpty) continue;
    final up = p.toUpperCase();
    if (up == 'UK') return 'GB';
    if (up.length == 2 && countryNames.containsKey(up)) return up;
    final byName = countryCodeForName(p);
    if (byName != null) return byName;
  }
  return null;
}

/// The country in an iptv-org style tvg-id: "Kanali7.al" or
/// "StingrayClassicRock.us@SD" give AL and US.
String? countryFromTvgId(String? tvgId) {
  if (tvgId == null) return null;
  var id = tvgId.trim();
  final at = id.indexOf('@');
  if (at >= 0) id = id.substring(0, at);
  final dot = id.lastIndexOf('.');
  if (dot < 0 || dot == id.length - 1) return null;
  final suffix = id.substring(dot + 1).toUpperCase();
  if (suffix == 'UK') return 'GB';
  return suffix.length == 2 && countryNames.containsKey(suffix) ? suffix : null;
}

Map<String, String>? _codeByName;

/// The ISO code of a country spelled out in English ("Albania", "united
/// states"), or null.
String? countryCodeForName(String name) {
  final m = _codeByName ??= {
    for (final e in countryNames.entries) e.value.toLowerCase(): e.key,
    ..._countryAliases,
  };
  return m[name.trim().toLowerCase()];
}

/// The categories a `group-title` names: "Animation;Kids" gives both. A group
/// that is just a country name (Free-TV groups by country) is not a category.
List<String> categoriesFromGroup(String? group) {
  if (group == null) return const [];
  final out = <String>[];
  for (final part in group.split(';')) {
    final p = part.trim();
    if (p.isEmpty || countryCodeForName(p) != null) continue;
    final t = _tidyCase(p);
    if (t.toLowerCase() == 'undefined' || out.contains(t)) continue;
    out.add(t);
  }
  return out;
}

/// "NEWS" and "news" read as "News"; mixed case is left as the list wrote it.
String _tidyCase(String s) {
  if (s != s.toUpperCase() && s != s.toLowerCase()) return s;
  return s
      .toLowerCase()
      .split(' ')
      .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
      .join(' ');
}

/// Language names from a `tvg-language` value ("English;Hindi", "eng", "hi")
/// or a catalogue's ISO 639 codes. Codes become names; unknown words are kept
/// with tidy case.
List<String> normalizeLanguages(Iterable<String> raw) {
  final out = <String>[];
  for (final r in raw) {
    for (final part in r.split(RegExp('[;,|/]'))) {
      final p = part.trim();
      if (p.isEmpty) continue;
      final name = languageNames[p.toLowerCase()] ?? _tidyCase(p);
      if (name.toLowerCase() == 'undefined' || out.contains(name)) continue;
      out.add(name);
    }
  }
  return out;
}

/// Splits a `tvg-language` attribute; see [normalizeLanguages].
List<String> languagesFromAttribute(String? raw) =>
    raw == null ? const [] : normalizeLanguages([raw]);

/// What the app shows and filters on for one channel: stored fields first,
/// then what the name, group and tvg-id give away.
class ChannelMeta {
  const ChannelMeta({
    required this.displayName,
    required this.country,
    required this.categories,
    required this.languages,
    required this.languagesInferred,
    required this.quality,
    required this.geoBlocked,
    required this.not247,
    this.number,
  });

  final String displayName;

  /// ISO 3166 alpha-2, upper case.
  final String? country;
  final List<String> categories;
  final List<String> languages;

  /// [languages] is a guess from [country], not something the list said.
  final bool languagesInferred;
  final ChannelQuality quality;
  final bool geoBlocked;
  final bool not247;
  final int? number;

  String? get countryName => country == null ? null : countryNames[country];

  factory ChannelMeta.of(StoredChannel c) {
    final country =
        c.country ?? countryFromTvgId(c.tvgId) ?? _countryFromGroup(c.group);
    // Catalogue ids ("news") get the same tidy case as playlist groups.
    final cats = _categoriesCached(
      c.categories.isNotEmpty ? c.categories.join(';') : c.group,
    );
    var langs = c.languages;
    var inferred = false;
    if (langs.isEmpty && country != null) {
      final l = countryLanguage[country];
      if (l != null) {
        langs = [l];
        inferred = true;
      }
    }
    return ChannelMeta(
      displayName: cleanChannelName(c.name),
      country: country,
      categories: cats,
      languages: langs,
      languagesInferred: inferred,
      quality: ChannelQuality.byName(c.quality) ?? _qualityWithFeed(c),
      geoBlocked: isGeoBlocked(c.name),
      not247: isNot247(c.name),
      number: c.number,
    );
  }

  /// The name first; then an iptv-org feed suffix ("Name.us@SD", "@HD").
  static ChannelQuality _qualityWithFeed(StoredChannel c) {
    final q = qualityOf(c.name);
    if (q != ChannelQuality.unknown) return q;
    final id = c.tvgId;
    final at = id?.indexOf('@') ?? -1;
    return at < 0 ? q : qualityOf(id!.substring(at + 1));
  }

  /// Free-TV groups by country name: "Albania" says where the channel is.
  static String? _countryFromGroup(String? group) {
    if (group == null || group.contains(';')) return null;
    return countryCodeForName(group);
  }

  // A playlist repeats a few dozen groups over thousands of channels, so the
  // parsed categories are kept per group string. The lists are shared and
  // must not be changed; the cache starts over if it grows past a cap.
  static final _catsByGroup = <String, List<String>>{};

  static List<String> _categoriesCached(String? group) {
    if (group == null) return const [];
    final hit = _catsByGroup[group];
    if (hit != null) return hit;
    if (_catsByGroup.length >= 4096) _catsByGroup.clear();
    return _catsByGroup[group] = List.unmodifiable(categoriesFromGroup(group));
  }
}

const _countryAliases = <String, String>{
  'usa': 'US',
  'united states of america': 'US',
  'uk': 'GB',
  'great britain': 'GB',
  'england': 'GB',
  'scotland': 'GB',
  'wales': 'GB',
  'south korea': 'KR',
  'korea': 'KR',
  'north korea': 'KP',
  'russia': 'RU',
  'czech republic': 'CZ',
  'vietnam': 'VN',
  'iran': 'IR',
  'syria': 'SY',
  'laos': 'LA',
  'bolivia': 'BO',
  'venezuela': 'VE',
  'tanzania': 'TZ',
  'moldova': 'MD',
  'taiwan': 'TW',
  'palestine': 'PS',
  'kosovo': 'XK',
  'ivory coast': 'CI',
  'macedonia': 'MK',
  'turkiye': 'TR',
  'türkiye': 'TR',
  'uae': 'AE',
  'dr congo': 'CD',
  'bosnia': 'BA',
  'bosnia & herzegovina': 'BA',
  'brunei': 'BN',
  'cape verde': 'CV',
  'micronesia': 'FM',
  'vatican': 'VA',
};

/// ISO 3166-1 alpha-2 codes and English short names (plus XK, Kosovo, which
/// playlists use though it has no official code).
const countryNames = <String, String>{
  'AD': 'Andorra',
  'AE': 'United Arab Emirates',
  'AF': 'Afghanistan',
  'AG': 'Antigua and Barbuda',
  'AI': 'Anguilla',
  'AL': 'Albania',
  'AM': 'Armenia',
  'AO': 'Angola',
  'AQ': 'Antarctica',
  'AR': 'Argentina',
  'AS': 'American Samoa',
  'AT': 'Austria',
  'AU': 'Australia',
  'AW': 'Aruba',
  'AX': 'Aland Islands',
  'AZ': 'Azerbaijan',
  'BA': 'Bosnia and Herzegovina',
  'BB': 'Barbados',
  'BD': 'Bangladesh',
  'BE': 'Belgium',
  'BF': 'Burkina Faso',
  'BG': 'Bulgaria',
  'BH': 'Bahrain',
  'BI': 'Burundi',
  'BJ': 'Benin',
  'BL': 'Saint Barthelemy',
  'BM': 'Bermuda',
  'BN': 'Brunei Darussalam',
  'BO': 'Bolivia',
  'BQ': 'Caribbean Netherlands',
  'BR': 'Brazil',
  'BS': 'Bahamas',
  'BT': 'Bhutan',
  'BW': 'Botswana',
  'BY': 'Belarus',
  'BZ': 'Belize',
  'CA': 'Canada',
  'CD': 'Congo (DRC)',
  'CF': 'Central African Republic',
  'CG': 'Congo',
  'CH': 'Switzerland',
  'CI': "Cote d'Ivoire",
  'CK': 'Cook Islands',
  'CL': 'Chile',
  'CM': 'Cameroon',
  'CN': 'China',
  'CO': 'Colombia',
  'CR': 'Costa Rica',
  'CU': 'Cuba',
  'CV': 'Cabo Verde',
  'CW': 'Curacao',
  'CY': 'Cyprus',
  'CZ': 'Czechia',
  'DE': 'Germany',
  'DJ': 'Djibouti',
  'DK': 'Denmark',
  'DM': 'Dominica',
  'DO': 'Dominican Republic',
  'DZ': 'Algeria',
  'EC': 'Ecuador',
  'EE': 'Estonia',
  'EG': 'Egypt',
  'EH': 'Western Sahara',
  'ER': 'Eritrea',
  'ES': 'Spain',
  'ET': 'Ethiopia',
  'FI': 'Finland',
  'FJ': 'Fiji',
  'FK': 'Falkland Islands',
  'FM': 'Micronesia',
  'FO': 'Faroe Islands',
  'FR': 'France',
  'GA': 'Gabon',
  'GB': 'United Kingdom',
  'GD': 'Grenada',
  'GE': 'Georgia',
  'GF': 'French Guiana',
  'GG': 'Guernsey',
  'GH': 'Ghana',
  'GI': 'Gibraltar',
  'GL': 'Greenland',
  'GM': 'Gambia',
  'GN': 'Guinea',
  'GP': 'Guadeloupe',
  'GQ': 'Equatorial Guinea',
  'GR': 'Greece',
  'GT': 'Guatemala',
  'GU': 'Guam',
  'GW': 'Guinea-Bissau',
  'GY': 'Guyana',
  'HK': 'Hong Kong',
  'HN': 'Honduras',
  'HR': 'Croatia',
  'HT': 'Haiti',
  'HU': 'Hungary',
  'ID': 'Indonesia',
  'IE': 'Ireland',
  'IL': 'Israel',
  'IM': 'Isle of Man',
  'IN': 'India',
  'IQ': 'Iraq',
  'IR': 'Iran',
  'IS': 'Iceland',
  'IT': 'Italy',
  'JE': 'Jersey',
  'JM': 'Jamaica',
  'JO': 'Jordan',
  'JP': 'Japan',
  'KE': 'Kenya',
  'KG': 'Kyrgyzstan',
  'KH': 'Cambodia',
  'KI': 'Kiribati',
  'KM': 'Comoros',
  'KN': 'Saint Kitts and Nevis',
  'KP': 'North Korea',
  'KR': 'South Korea',
  'KW': 'Kuwait',
  'KY': 'Cayman Islands',
  'KZ': 'Kazakhstan',
  'LA': 'Laos',
  'LB': 'Lebanon',
  'LC': 'Saint Lucia',
  'LI': 'Liechtenstein',
  'LK': 'Sri Lanka',
  'LR': 'Liberia',
  'LS': 'Lesotho',
  'LT': 'Lithuania',
  'LU': 'Luxembourg',
  'LV': 'Latvia',
  'LY': 'Libya',
  'MA': 'Morocco',
  'MC': 'Monaco',
  'MD': 'Moldova',
  'ME': 'Montenegro',
  'MF': 'Saint Martin',
  'MG': 'Madagascar',
  'MH': 'Marshall Islands',
  'MK': 'North Macedonia',
  'ML': 'Mali',
  'MM': 'Myanmar',
  'MN': 'Mongolia',
  'MO': 'Macao',
  'MP': 'Northern Mariana Islands',
  'MQ': 'Martinique',
  'MR': 'Mauritania',
  'MS': 'Montserrat',
  'MT': 'Malta',
  'MU': 'Mauritius',
  'MV': 'Maldives',
  'MW': 'Malawi',
  'MX': 'Mexico',
  'MY': 'Malaysia',
  'MZ': 'Mozambique',
  'NA': 'Namibia',
  'NC': 'New Caledonia',
  'NE': 'Niger',
  'NG': 'Nigeria',
  'NI': 'Nicaragua',
  'NL': 'Netherlands',
  'NO': 'Norway',
  'NP': 'Nepal',
  'NR': 'Nauru',
  'NZ': 'New Zealand',
  'OM': 'Oman',
  'PA': 'Panama',
  'PE': 'Peru',
  'PF': 'French Polynesia',
  'PG': 'Papua New Guinea',
  'PH': 'Philippines',
  'PK': 'Pakistan',
  'PL': 'Poland',
  'PM': 'Saint Pierre and Miquelon',
  'PR': 'Puerto Rico',
  'PS': 'Palestine',
  'PT': 'Portugal',
  'PW': 'Palau',
  'PY': 'Paraguay',
  'QA': 'Qatar',
  'RE': 'Reunion',
  'RO': 'Romania',
  'RS': 'Serbia',
  'RU': 'Russia',
  'RW': 'Rwanda',
  'SA': 'Saudi Arabia',
  'SB': 'Solomon Islands',
  'SC': 'Seychelles',
  'SD': 'Sudan',
  'SE': 'Sweden',
  'SG': 'Singapore',
  'SI': 'Slovenia',
  'SK': 'Slovakia',
  'SL': 'Sierra Leone',
  'SM': 'San Marino',
  'SN': 'Senegal',
  'SO': 'Somalia',
  'SR': 'Suriname',
  'SS': 'South Sudan',
  'ST': 'Sao Tome and Principe',
  'SV': 'El Salvador',
  'SX': 'Sint Maarten',
  'SY': 'Syria',
  'SZ': 'Eswatini',
  'TC': 'Turks and Caicos Islands',
  'TD': 'Chad',
  'TG': 'Togo',
  'TH': 'Thailand',
  'TJ': 'Tajikistan',
  'TL': 'Timor-Leste',
  'TM': 'Turkmenistan',
  'TN': 'Tunisia',
  'TO': 'Tonga',
  'TR': 'Turkey',
  'TT': 'Trinidad and Tobago',
  'TV': 'Tuvalu',
  'TW': 'Taiwan',
  'TZ': 'Tanzania',
  'UA': 'Ukraine',
  'UG': 'Uganda',
  'US': 'United States',
  'UY': 'Uruguay',
  'UZ': 'Uzbekistan',
  'VA': 'Vatican City',
  'VC': 'Saint Vincent and the Grenadines',
  'VE': 'Venezuela',
  'VG': 'British Virgin Islands',
  'VI': 'U.S. Virgin Islands',
  'VN': 'Viet Nam',
  'VU': 'Vanuatu',
  'WF': 'Wallis and Futuna',
  'WS': 'Samoa',
  'XK': 'Kosovo',
  'YE': 'Yemen',
  'YT': 'Mayotte',
  'ZA': 'South Africa',
  'ZM': 'Zambia',
  'ZW': 'Zimbabwe',
};

/// The language most channels of a country broadcast in. Only a guess for
/// lists that say nothing, so it is shown as inferred. Countries with no
/// clear majority language (India, Switzerland, Belgium...) are left out on
/// purpose: a wrong guess is worse than none.
const countryLanguage = <String, String>{
  'AD': 'Catalan',
  'AE': 'Arabic',
  'AF': 'Pashto',
  'AL': 'Albanian',
  'AM': 'Armenian',
  'AO': 'Portuguese',
  'AR': 'Spanish',
  'AT': 'German',
  'AU': 'English',
  'AZ': 'Azerbaijani',
  'BA': 'Bosnian',
  'BD': 'Bengali',
  'BG': 'Bulgarian',
  'BH': 'Arabic',
  'BO': 'Spanish',
  'BR': 'Portuguese',
  'BY': 'Belarusian',
  'CL': 'Spanish',
  'CN': 'Chinese',
  'CO': 'Spanish',
  'CR': 'Spanish',
  'CU': 'Spanish',
  'CY': 'Greek',
  'CZ': 'Czech',
  'DE': 'German',
  'DK': 'Danish',
  'DO': 'Spanish',
  'DZ': 'Arabic',
  'EC': 'Spanish',
  'EE': 'Estonian',
  'EG': 'Arabic',
  'ES': 'Spanish',
  'FI': 'Finnish',
  'FR': 'French',
  'GB': 'English',
  'GE': 'Georgian',
  'GR': 'Greek',
  'GT': 'Spanish',
  'HK': 'Chinese',
  'HN': 'Spanish',
  'HR': 'Croatian',
  'HU': 'Hungarian',
  'ID': 'Indonesian',
  'IE': 'English',
  'IL': 'Hebrew',
  'IQ': 'Arabic',
  'IR': 'Persian',
  'IS': 'Icelandic',
  'IT': 'Italian',
  'JM': 'English',
  'JO': 'Arabic',
  'JP': 'Japanese',
  'KR': 'Korean',
  'KP': 'Korean',
  'KW': 'Arabic',
  'KZ': 'Kazakh',
  'LB': 'Arabic',
  'LK': 'Sinhala',
  'LT': 'Lithuanian',
  'LV': 'Latvian',
  'LY': 'Arabic',
  'MA': 'Arabic',
  'MD': 'Romanian',
  'ME': 'Montenegrin',
  'MK': 'Macedonian',
  'MN': 'Mongolian',
  'MT': 'Maltese',
  'MX': 'Spanish',
  'MY': 'Malay',
  'NI': 'Spanish',
  'NL': 'Dutch',
  'NO': 'Norwegian',
  'NP': 'Nepali',
  'NZ': 'English',
  'OM': 'Arabic',
  'PA': 'Spanish',
  'PE': 'Spanish',
  'PH': 'Filipino',
  'PK': 'Urdu',
  'PL': 'Polish',
  'PR': 'Spanish',
  'PS': 'Arabic',
  'PT': 'Portuguese',
  'PY': 'Spanish',
  'QA': 'Arabic',
  'RO': 'Romanian',
  'RS': 'Serbian',
  'RU': 'Russian',
  'SA': 'Arabic',
  'SD': 'Arabic',
  'SE': 'Swedish',
  'SI': 'Slovenian',
  'SK': 'Slovak',
  'SO': 'Somali',
  'SV': 'Spanish',
  'SY': 'Arabic',
  'TH': 'Thai',
  'TN': 'Arabic',
  'TR': 'Turkish',
  'TW': 'Chinese',
  'UA': 'Ukrainian',
  'US': 'English',
  'UY': 'Spanish',
  'UZ': 'Uzbek',
  'VE': 'Spanish',
  'VN': 'Vietnamese',
  'XK': 'Albanian',
  'YE': 'Arabic',
};

/// ISO 639-1 and 639-3 codes (and a few common English variants) to names.
const languageNames = <String, String>{
  'en': 'English',
  'eng': 'English',
  'hi': 'Hindi',
  'hin': 'Hindi',
  'ml': 'Malayalam',
  'mal': 'Malayalam',
  'ta': 'Tamil',
  'tam': 'Tamil',
  'te': 'Telugu',
  'tel': 'Telugu',
  'kn': 'Kannada',
  'kan': 'Kannada',
  'mr': 'Marathi',
  'mar': 'Marathi',
  'bn': 'Bengali',
  'ben': 'Bengali',
  'bangla': 'Bengali',
  'gu': 'Gujarati',
  'guj': 'Gujarati',
  'pa': 'Punjabi',
  'pan': 'Punjabi',
  'or': 'Odia',
  'ori': 'Odia',
  'ory': 'Odia',
  'as': 'Assamese',
  'asm': 'Assamese',
  'ur': 'Urdu',
  'urd': 'Urdu',
  'ne': 'Nepali',
  'nep': 'Nepali',
  'npi': 'Nepali',
  'si': 'Sinhala',
  'sin': 'Sinhala',
  'es': 'Spanish',
  'spa': 'Spanish',
  'fr': 'French',
  'fra': 'French',
  'fre': 'French',
  'de': 'German',
  'deu': 'German',
  'ger': 'German',
  'it': 'Italian',
  'ita': 'Italian',
  'pt': 'Portuguese',
  'por': 'Portuguese',
  'nl': 'Dutch',
  'nld': 'Dutch',
  'dut': 'Dutch',
  'ru': 'Russian',
  'rus': 'Russian',
  'uk': 'Ukrainian',
  'ukr': 'Ukrainian',
  'pl': 'Polish',
  'pol': 'Polish',
  'cs': 'Czech',
  'ces': 'Czech',
  'cze': 'Czech',
  'sk': 'Slovak',
  'slk': 'Slovak',
  'sl': 'Slovenian',
  'slv': 'Slovenian',
  'hr': 'Croatian',
  'hrv': 'Croatian',
  'sr': 'Serbian',
  'srp': 'Serbian',
  'bs': 'Bosnian',
  'bos': 'Bosnian',
  'mk': 'Macedonian',
  'mkd': 'Macedonian',
  'cnr': 'Montenegrin',
  'bg': 'Bulgarian',
  'bul': 'Bulgarian',
  'ro': 'Romanian',
  'ron': 'Romanian',
  'rum': 'Romanian',
  'hu': 'Hungarian',
  'hun': 'Hungarian',
  'el': 'Greek',
  'ell': 'Greek',
  'gre': 'Greek',
  'tr': 'Turkish',
  'tur': 'Turkish',
  'sq': 'Albanian',
  'sqi': 'Albanian',
  'alb': 'Albanian',
  'hy': 'Armenian',
  'hye': 'Armenian',
  'ka': 'Georgian',
  'kat': 'Georgian',
  'az': 'Azerbaijani',
  'aze': 'Azerbaijani',
  'kk': 'Kazakh',
  'kaz': 'Kazakh',
  'uz': 'Uzbek',
  'uzb': 'Uzbek',
  'be': 'Belarusian',
  'bel': 'Belarusian',
  'lt': 'Lithuanian',
  'lit': 'Lithuanian',
  'lv': 'Latvian',
  'lav': 'Latvian',
  'et': 'Estonian',
  'est': 'Estonian',
  'fi': 'Finnish',
  'fin': 'Finnish',
  'sv': 'Swedish',
  'swe': 'Swedish',
  'no': 'Norwegian',
  'nor': 'Norwegian',
  'nb': 'Norwegian',
  'nob': 'Norwegian',
  'da': 'Danish',
  'dan': 'Danish',
  'is': 'Icelandic',
  'isl': 'Icelandic',
  'ga': 'Irish',
  'gle': 'Irish',
  'cy': 'Welsh',
  'cym': 'Welsh',
  'ca': 'Catalan',
  'cat': 'Catalan',
  'eu': 'Basque',
  'eus': 'Basque',
  'gl': 'Galician',
  'glg': 'Galician',
  'mt': 'Maltese',
  'mlt': 'Maltese',
  'ar': 'Arabic',
  'ara': 'Arabic',
  'he': 'Hebrew',
  'heb': 'Hebrew',
  'fa': 'Persian',
  'fas': 'Persian',
  'per': 'Persian',
  'farsi': 'Persian',
  'ps': 'Pashto',
  'pus': 'Pashto',
  'ku': 'Kurdish',
  'kur': 'Kurdish',
  'ckb': 'Kurdish',
  'kmr': 'Kurdish',
  'zh': 'Chinese',
  'zho': 'Chinese',
  'chi': 'Chinese',
  'cmn': 'Chinese',
  'yue': 'Cantonese',
  'ja': 'Japanese',
  'jpn': 'Japanese',
  'ko': 'Korean',
  'kor': 'Korean',
  'th': 'Thai',
  'tha': 'Thai',
  'vi': 'Vietnamese',
  'vie': 'Vietnamese',
  'id': 'Indonesian',
  'ind': 'Indonesian',
  'ms': 'Malay',
  'msa': 'Malay',
  'zsm': 'Malay',
  'may': 'Malay',
  'tl': 'Filipino',
  'tgl': 'Filipino',
  'fil': 'Filipino',
  'tagalog': 'Filipino',
  'km': 'Khmer',
  'khm': 'Khmer',
  'lo': 'Lao',
  'lao': 'Lao',
  'my': 'Burmese',
  'mya': 'Burmese',
  'mn': 'Mongolian',
  'mon': 'Mongolian',
  'khk': 'Mongolian',
  'sw': 'Swahili',
  'swa': 'Swahili',
  'swh': 'Swahili',
  'am': 'Amharic',
  'amh': 'Amharic',
  'so': 'Somali',
  'som': 'Somali',
  'ha': 'Hausa',
  'hau': 'Hausa',
  'yo': 'Yoruba',
  'yor': 'Yoruba',
  'ig': 'Igbo',
  'ibo': 'Igbo',
  'zu': 'Zulu',
  'zul': 'Zulu',
  'af': 'Afrikaans',
  'afr': 'Afrikaans',
  'tg': 'Tajik',
  'tgk': 'Tajik',
  'ky': 'Kyrgyz',
  'kir': 'Kyrgyz',
  'tk': 'Turkmen',
  'tuk': 'Turkmen',
  'lb': 'Luxembourgish',
  'ltz': 'Luxembourgish',
  'fo': 'Faroese',
  'fao': 'Faroese',
  'ht': 'Haitian Creole',
  'hat': 'Haitian Creole',
  'qu': 'Quechua',
  'que': 'Quechua',
  'gn': 'Guarani',
  'grn': 'Guarani',
  'sa': 'Sanskrit',
  'san': 'Sanskrit',
  'bho': 'Bhojpuri',
  'mai': 'Maithili',
  'kok': 'Konkani',
  'gom': 'Konkani',
  'tcy': 'Tulu',
  'sd': 'Sindhi',
  'snd': 'Sindhi',
  'ks': 'Kashmiri',
  'kas': 'Kashmiri',
  'dv': 'Dhivehi',
  'div': 'Dhivehi',
  'bo': 'Tibetan',
  'bod': 'Tibetan',
  'ug': 'Uyghur',
  'uig': 'Uyghur',
  'la': 'Latin',
  'lat': 'Latin',
};
