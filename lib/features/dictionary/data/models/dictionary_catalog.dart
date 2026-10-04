import 'package:mekuru/core/database/database_provider.dart'
    show DictionaryMeta;

enum CatalogSection { japaneseEnglish, japaneseJapanese, names, otherLanguages }

/// Where yomidevs/jmdict-yomitan publishes JMdict, JMnedict and KANJIDIC.
const jmdictYomitanReleases =
    'https://github.com/yomidevs/jmdict-yomitan/releases/latest/download';
const edrdgJmdictUrl =
    'https://www.edrdg.org/wiki/index.php/JMdict-EDICT_Dictionary_Project';
const edrdgKanjidicUrl =
    'https://www.edrdg.org/wiki/index.php/KANJIDIC_Project';
const _wiktionaryReleases =
    'https://huggingface.co/datasets/daxida/wty-release/resolve/main/latest';

/// Openly licensed Yomitan dictionaries Mekuru downloads from their own
/// hosts. Dictionaries with unclear licensing are never listed here; the
/// catalog only links the community guides to them ([dictionaryGuides]).
///
/// [title] is the index.json title without its trailing " [revision]".
/// Sizes were measured on 2026-10-04: [downloadMb] is the zip, [installedMb]
/// what the import adds to the database.
enum CatalogDictionary {
  jitendex(
    displayName: 'Jitendex',
    section: CatalogSection.japaneseEnglish,
    url:
        'https://github.com/stephenmk/stephenmk.github.io/releases/latest/download/jitendex-yomitan.zip',
    indexUrl: 'https://jitendex.org/static/yomitan.json',
    title: 'Jitendex.org',
    downloadMb: 39,
    installedMb: 774,
    sourceUrl: 'https://jitendex.org',
  ),
  wiktionaryEnglish.wiktionary(
    'en',
    'Wiktionary (English)',
    CatalogSection.japaneseEnglish,
    16,
    194,
  ),
  wiktionaryJapanese.wiktionary(
    'ja',
    'Wiktionary (日本語)',
    CatalogSection.japaneseJapanese,
    14,
    202,
  ),
  jmnedict(
    displayName: 'JMnedict',
    section: CatalogSection.names,
    url: '$jmdictYomitanReleases/JMnedict.zip',
    indexUrl: '$jmdictYomitanReleases/JMnedict.json',
    title: 'JMnedict',
    downloadMb: 11,
    installedMb: 117,
    sourceUrl: 'https://www.edrdg.org/enamdict/enamdict_doc.html',
  ),
  jmdictSpanish.jmdict('spanish', 'Spanish', 'Español', 1.3, 13),
  jmdictGerman.jmdict('german', 'German', 'Deutsch', 6.3, 63),
  jmdictFrench.jmdict('french', 'French', 'Français', 0.6, 5.3),
  jmdictRussian.jmdict('russian', 'Russian', 'Русский', 3.5, 38),
  jmdictDutch.jmdict('dutch', 'Dutch', 'Nederlands', 3.1, 34),
  jmdictHungarian.jmdict('hungarian', 'Hungarian', 'Magyar', 1.8, 17),
  jmdictSwedish.jmdict('swedish', 'Swedish', 'Svenska', 0.4, 3.8),
  jmdictSlovenian.jmdict('slovenian', 'Slovenian', 'Slovenščina', 0.3, 3),
  kanjidicSpanish.kanjidic('spanish', 'Spanish', 'Español', 0.3, 0.8),
  kanjidicFrench.kanjidic('french', 'French', 'Français', 0.3, 0.7),
  kanjidicPortuguese.kanjidic(
    'portuguese',
    'Portuguese',
    'Português',
    0.3,
    0.6,
  ),
  wiktionaryChinese.wiktionary(
    'zh',
    'Wiktionary (中文)',
    CatalogSection.otherLanguages,
    6.9,
    116,
  );

  const CatalogDictionary({
    required this.displayName,
    required this.section,
    required this.url,
    required this.indexUrl,
    required this.title,
    required this.downloadMb,
    required this.installedMb,
    required this.sourceUrl,
  });

  /// A JMdict edition, e.g. `JMdict_spanish.zip` titled "JMdict (Spanish)".
  const CatalogDictionary.jmdict(
    String file,
    String english,
    String native,
    double downloadMb,
    double installedMb,
  ) : this(
        displayName: 'JMdict ($native)',
        section: CatalogSection.otherLanguages,
        url: '$jmdictYomitanReleases/JMdict_$file.zip',
        indexUrl: '$jmdictYomitanReleases/JMdict_$file.json',
        title: 'JMdict ($english)',
        downloadMb: downloadMb,
        installedMb: installedMb,
        sourceUrl: edrdgJmdictUrl,
      );

  /// A KANJIDIC edition, e.g. `KANJIDIC_french.zip` titled "KANJIDIC (French)".
  const CatalogDictionary.kanjidic(
    String file,
    String english,
    String native,
    double downloadMb,
    double installedMb,
  ) : this(
        displayName: 'KANJIDIC ($native)',
        section: CatalogSection.otherLanguages,
        url: '$jmdictYomitanReleases/KANJIDIC_$file.zip',
        indexUrl: '$jmdictYomitanReleases/KANJIDIC_$file.json',
        title: 'KANJIDIC ($english)',
        downloadMb: downloadMb,
        installedMb: installedMb,
        sourceUrl: edrdgKanjidicUrl,
      );

  /// A Wiktionary dictionary for Japanese with definitions in [language],
  /// titled `wty-ja-$language`.
  const CatalogDictionary.wiktionary(
    String language,
    String displayName,
    CatalogSection section,
    double downloadMb,
    double installedMb,
  ) : this(
        displayName: displayName,
        section: section,
        url: '$_wiktionaryReleases/dict/ja/$language/wty-ja-$language.zip',
        indexUrl: '$_wiktionaryReleases/index/wty-ja-$language-index.json',
        title: 'wty-ja-$language',
        downloadMb: downloadMb,
        installedMb: installedMb,
        sourceUrl: 'https://yomidevs.github.io/wiktionary-to-yomitan/',
      );

  /// Shown in the app; a proper name, so not translated.
  final String displayName;
  final CatalogSection section;
  final String url;

  /// The published index.json, checked for updates.
  final String indexUrl;
  final String title;
  final double downloadMb;
  final double installedMb;

  /// The project page, which states the license (CC BY-SA 4.0 for all).
  final String sourceUrl;

  /// Whether [storedTitle], a dictionary's index.json title, is this
  /// dictionary, at any revision.
  bool matchesTitle(String storedTitle) =>
      storedTitle == title || storedTitle.startsWith('$title [');

  /// The catalog entry an installed dictionary came from, if any.
  static CatalogDictionary? forTitle(String storedTitle) {
    for (final entry in values) {
      if (entry.matchesTitle(storedTitle)) return entry;
    }
    return null;
  }

  bool isInstalledIn(Iterable<DictionaryMeta> dictionaries) =>
      dictionaries.any((d) => matchesTitle(d.name));

  /// Free storage an install needs: the zip, the database's growth, and as
  /// much again for the import's journal until it commits.
  double get requiredMb => downloadMb + 2 * installedMb;
}

/// The name the app shows for a dictionary: the catalog's name for a
/// catalog dictionary ("Jitendex.org [2026-10-03]" → "Jitendex"), otherwise
/// its title without a trailing revision ("JMdict [2026-10-03]" → "JMdict").
/// Stored titles stay as imported: matching depends on them.
String dictionaryDisplayName(String storedTitle) =>
    CatalogDictionary.forTitle(storedTitle)?.displayName ??
    storedTitle.replaceFirst(_trailingRevision, '');

/// The version [dictionaryDisplayName] leaves out: the title's trailing
/// revision, else the one index.json gave; null when neither is known.
String? dictionaryVersion(DictionaryMeta meta) =>
    _trailingRevision.firstMatch(meta.name)?.group(1) ?? meta.revision;

final _trailingRevision = RegExp(r'\s\[(\d{4}[\d.\-]*)\]$');

/// Community guides that list many more Yomitan dictionaries, including
/// ones Mekuru does not download itself.
const List<({String name, String url})> dictionaryGuides = [
  (name: 'yomitan.wiki', url: 'https://yomitan.wiki/dictionaries/'),
  (name: 'learnjapanese.moe', url: 'https://learnjapanese.moe/yomichan/'),
  (
    name: 'MarvNC/yomitan-dictionaries',
    url: 'https://github.com/MarvNC/yomitan-dictionaries',
  ),
];
