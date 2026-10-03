abstract final class AppLinks {
  static final Uri website = Uri.https('mekuru.matthew.moe');
  static final Uri documentation = Uri.https(
    'mekuru.matthew.moe',
    '/documentation/',
  );
  static final Uri privacyPolicy = Uri.https('mekuru.matthew.moe', '/privacy');

  /// Aozora Bunko works converted to EPUB (Aozora itself serves only HTML
  /// and text), linked from the empty library's free-books tip.
  static final Uri freeJapaneseBooks = Uri.https(
    'kyukyunyorituryo.github.io',
    '/bookshelf/',
  );
}
