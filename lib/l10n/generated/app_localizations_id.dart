// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Indonesian (`id`).
class AppLocalizationsId extends AppLocalizations {
  AppLocalizationsId([String locale = 'id']) : super(locale);

  @override
  String get appTitle => 'Mekuru';

  @override
  String get navLibrary => 'Pustaka';

  @override
  String get navDictionary => 'Kamus';

  @override
  String get navVocabulary => 'Kosakata';

  @override
  String get navSettings => 'Pengaturan';

  @override
  String get commonHelp => 'Bantuan';

  @override
  String get commonImport => 'Impor';

  @override
  String get commonOpenNow => 'Buka sekarang';

  @override
  String get commonCancel => 'Batal';

  @override
  String get commonClose => 'Tutup';

  @override
  String get commonSave => 'Simpan';

  @override
  String get commonDelete => 'Hapus';

  @override
  String get commonDownload => 'Unduh';

  @override
  String get commonOpenDictionary => 'Buka Kamus';

  @override
  String get commonManageDictionaries => 'Kelola Kamus';

  @override
  String get commonClearAll => 'Bersihkan semua';

  @override
  String get commonClearSearch => 'Hapus pencarian';

  @override
  String get commonSearch => 'Cari';

  @override
  String get commonBack => 'Kembali';

  @override
  String get commonRetry => 'Coba lagi';

  @override
  String get commonOk => 'OK';

  @override
  String get commonDone => 'Selesai';

  @override
  String get commonUndo => 'Batalkan';

  @override
  String get commonUnlock => 'Buka kunci';

  @override
  String get commonOpenSettings => 'Buka Pengaturan';

  @override
  String get commonGotIt => 'Mengerti';

  @override
  String commonErrorWithDetails({required String details}) {
    return 'Kesalahan: $details';
  }

  @override
  String librarySortTooltip({required String label}) {
    return 'Urutkan: $label';
  }

  @override
  String get libraryEmptyTitle => 'Perpustakaan Anda siap untuk buku pertama';

  @override
  String get libraryEmptySubtitle =>
      'Impor sesuatu untuk dibaca, pasang kamus, dan Anda akan siap menyimpan kata dalam beberapa menit.';

  @override
  String get libraryImportEpub => 'Impor EPUB';

  @override
  String get libraryImportManga => 'Impor Manga';

  @override
  String get libraryGetDictionaries => 'Dapatkan Kamus';

  @override
  String get libraryRestoreBackup => 'Pulihkan Cadangan';

  @override
  String get librarySupportedMediaTitle => 'Media yang Didukung';

  @override
  String get libraryEpubBooksTitle => 'Buku EPUB';

  @override
  String get libraryEpubBooksDescription =>
      'File .epub standar didukung. Ketuk tombol + lalu pilih \"Impor EPUB\" untuk menambahkannya dari perangkat Anda.';

  @override
  String get libraryMokuroTitle => 'Manga Mokuro';

  @override
  String get libraryMokuroDescription =>
      'Impor manga dengan memilih sebuah folder, lalu pilih file .mokuro atau .html. Gambar halaman akan dimuat dari folder saudara dengan nama yang sama.';

  @override
  String get libraryMokuroFormatDescription =>
      'File .mokuro dihasilkan oleh alat mokuro, yang menjalankan OCR pada halaman manga untuk mengekstrak teks Jepang.';

  @override
  String get libraryLearnHowToCreateMokuroFiles =>
      'Pelajari cara membuat file .mokuro';

  @override
  String get librarySortBy => 'Urutkan berdasarkan';

  @override
  String get librarySortDateImported => 'Tanggal diimpor';

  @override
  String get librarySortRecentlyRead => 'Baru saja dibaca';

  @override
  String get librarySortAlphabetical => 'Alfabetis';

  @override
  String get libraryImportTitle => 'Impor';

  @override
  String get libraryImportEpubSubtitle => 'Impor file EPUB';

  @override
  String get libraryImportMangaSubtitle => 'Pilih arsip CBZ atau folder Mokuro';

  @override
  String get libraryImportMangaTitle => 'Impor Manga';

  @override
  String get libraryImportMangaDescription =>
      'Pilih apakah Anda ingin mengimpor arsip CBZ atau folder hasil ekspor Mokuro.';

  @override
  String get libraryImportMokuroFolder => 'Folder Mokuro';

  @override
  String get libraryImportMokuroFolderSubtitle =>
      'Pilih folder yang berisi file .mokuro atau .html beserta folder gambar.';

  @override
  String get libraryWhatIsMokuro => 'Apa itu Mokuro?';

  @override
  String get libraryImportCbzArchive => 'Arsip CBZ';

  @override
  String get libraryImportCbzArchiveSubtitle => 'Impor arsip komik .cbz';

  @override
  String get libraryImportedWithoutOcrMessage =>
      'Diimpor tanpa OCR. Untuk mendapatkan overlay teks, impor hasil OCR eksternal (misal: .mokuro).';

  @override
  String get libraryCouldNotOpenMokuroProjectPage =>
      'Tidak dapat membuka halaman proyek Mokuro.';

  @override
  String get libraryNoMangaManifestFound =>
      'Tidak ditemukan file .mokuro atau .html di folder yang dipilih.';

  @override
  String get librarySelectMangaFolder => 'Pilih folder manga';

  @override
  String get librarySelectedFolder => 'Folder dipilih';

  @override
  String libraryMangaFilesFound({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '# file manga ditemukan',
      one: '# file manga ditemukan',
    );
    return '$_temp0';
  }

  @override
  String get dictionarySearchHint => 'Cari dengan kanji, kana, atau romaji...';

  @override
  String get dictionaryNoDictionariesTitle => 'Belum ada kamus diimpor';

  @override
  String get dictionaryNoDictionariesSubtitle =>
      'Pasang starter pack atau impor kamus Yomitan Anda sendiri untuk mulai mencari.';

  @override
  String get dictionaryRecommendedStarterPack =>
      'Starter pack yang direkomendasikan';

  @override
  String get dictionaryNoEnabledTitle => 'Kamus Anda dinonaktifkan';

  @override
  String get dictionaryNoEnabledSubtitle =>
      'Aktifkan setidaknya satu kamus agar pencarian berfungsi, atau instal starter pack yang direkomendasikan.';

  @override
  String get dictionaryEnableDictionaries => 'Aktifkan kamus';

  @override
  String get dictionaryStarterPack => 'Starter pack';

  @override
  String get dictionaryNoResultsFound => 'Tidak ada hasil.';

  @override
  String get dictionarySearchForAWord => 'Cari sebuah kata';

  @override
  String get dictionarySearchForAWordSubtitle =>
      'Ketik dalam kanji, hiragana, katakana, atau romaji';

  @override
  String get dictionaryRecent => 'Terbaru';

  @override
  String dictionarySavedWord({required String expression}) {
    return 'Disimpan \"$expression\"';
  }

  @override
  String get dictionaryWordAlreadyExistsInVocab =>
      'Kata sudah ada di daftar kosakata';

  @override
  String dictionaryCopiedWord({required String expression}) {
    return 'Disalin \"$expression\"';
  }

  @override
  String get dictionaryWordAlreadyExistsInAnki =>
      'Kata sudah ada di dek default';

  @override
  String dictionaryAddedToAnki({required String expression}) {
    return '\"$expression\" ditambahkan ke Anki';
  }

  @override
  String get dictionaryCopyTooltip => 'Salin';

  @override
  String get dictionaryAlreadyInAnkiTooltip =>
      'Sudah ada di dek Anki default. Tekan lama untuk tetap menambahkannya';

  @override
  String get dictionaryCheckingAnkiTooltip => 'Memeriksa dek Anki default';

  @override
  String get dictionarySendToAnkiTooltip => 'Kirim ke AnkiDroid';

  @override
  String get dictionaryAlreadyInVocabTooltip => 'Sudah ada di daftar kosakata';

  @override
  String get dictionarySaveToVocabularyTooltip => 'Simpan ke Kosakata';

  @override
  String get dictionaryVeryCommon => 'Sangat Umum';

  @override
  String get dictionaryOnyomiLabel => 'Onyomi: ';

  @override
  String get dictionaryKunyomiLabel => 'Kunyomi: ';

  @override
  String dictionaryKanjiStrokeCount({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '# guratan',
      one: '# guratan',
    );
    return '$_temp0';
  }

  @override
  String get dictionaryAnimateStrokeOrderTooltip => 'Animasi urutan guratan';

  @override
  String get vocabularySearchSavedWordsHint => 'Cari kata tersimpan';

  @override
  String get vocabularyExportCsvTooltip => 'Ekspor CSV';

  @override
  String get vocabularyEmptyTitle => 'Belum ada kata tersimpan';

  @override
  String get vocabularyEmptySubtitle =>
      'Simpan kata dari pencarian kamus atau saat membaca, dan akan muncul di sini beserta konteksnya.';

  @override
  String vocabularyNoMatches({required String query}) {
    return 'Tidak ada kecocokan untuk \"$query\"';
  }

  @override
  String get vocabularyNoMatchesSubtitle =>
      'Coba masukkan ekspresi, bacaan, atau sebagian definisi.';

  @override
  String vocabularySelectedCount({required int count}) {
    return '$count dipilih';
  }

  @override
  String get vocabularyDeselectAllTooltip => 'Batal pilih semua';

  @override
  String get vocabularySelectAllTooltip => 'Pilih semua';

  @override
  String get vocabularyExportSelectedTooltip => 'Ekspor yang dipilih';

  @override
  String get vocabularyNoDefinition => 'Tidak ada definisi';

  @override
  String get vocabularyContextLabel => 'Konteks:';

  @override
  String vocabularyAddedOn({required String date}) {
    return 'Ditambahkan: $date';
  }

  @override
  String vocabularyDeletedWord({required String expression}) {
    return 'Menghapus \"$expression\"';
  }

  @override
  String ocrPagesProgress({required int completed, required int total}) {
    return '$completed/$total halaman';
  }

  @override
  String ocrEtaSecondsRemaining({required int seconds}) {
    return '~$seconds detik tersisa';
  }

  @override
  String ocrEtaMinutesRemaining({required int minutes}) {
    return '~$minutes menit tersisa';
  }

  @override
  String ocrEtaHoursMinutesRemaining({
    required int hours,
    required int minutes,
  }) {
    return '~${hours}j ${minutes}m tersisa';
  }

  @override
  String get ocrPaused => 'OCR Dijeda';

  @override
  String get ocrComplete => 'OCR Selesai';

  @override
  String get ocrFailed => 'OCR Gagal';

  @override
  String get ocrTapForDetails => 'Ketuk untuk detail';

  @override
  String get ocrCustomServerRequiredTitle => 'Server OCR Kustom Diperlukan';

  @override
  String get ocrCustomServerRequiredBody =>
      'OCR manga jarak jauh sekarang menggunakan server milik Anda. Buka Pengaturan dan tambahkan URL server OCR kustom beserta shared key yang sesuai.';

  @override
  String get ocrCustomServerKeyRequiredTitle =>
      'Pengaturan Server Kustom Diperlukan';

  @override
  String get ocrCustomServerKeyRequiredBody =>
      'Server OCR kustom memerlukan shared key. Buka pengaturan Server OCR Kustom dan masukkan nilai AUTH_API_KEY yang sama seperti di server Anda.';

  @override
  String get proTitle => 'Pro';

  @override
  String get proPurchaseConfirmed => 'Pembelian Anda telah dikonfirmasi!';

  @override
  String get proUnlockOnceTitle => 'Buka Pro sekali';

  @override
  String get proStatusUnlocked => 'Terbuka';

  @override
  String get proStatusLocked => 'Terkunci';

  @override
  String get proUnlockDescription =>
      'Pembelian satu kali untuk fitur pembaca tingkat lanjut.';

  @override
  String get proRestorePurchase => 'Pulihkan Pembelian';

  @override
  String get proFeatureAutoCropTitle => 'Pangkas Otomatis';

  @override
  String get proFeatureAutoCropDescription =>
      'Pangkas margin kosong halaman manga setelah pengaturan satu kali per buku.';

  @override
  String get proFeatureHighlightsTitle => 'Sorotan Buku';

  @override
  String get proFeatureHighlightsDescription =>
      'Simpan dan tinjau kembali bagian-bagian yang disorot saat membaca buku EPUB.';

  @override
  String get proFeatureCustomOcrTitle => 'Server OCR Kustom';

  @override
  String get proFeatureCustomOcrDescription =>
      'Jalankan OCR manga jarak jauh dengan server dan kunci bersama milik Anda sendiri.';

  @override
  String get proServerRepo => 'Repositori Server';

  @override
  String get proAlreadyUnlocked => 'Sudah Dibuka';

  @override
  String get proUnlock => 'Buka Pro';

  @override
  String proUnlockWithPrice({required String price}) {
    return 'Buka Pro $price';
  }

  @override
  String get downloadsTitle => 'Unduhan';

  @override
  String get downloadsRecommendedStarterPackTitle =>
      'Paket awal yang direkomendasikan';

  @override
  String get downloadsRecommendedStarterPackSubtitle =>
      'Instal JMdict English dan data frekuensi kata secara bersamaan untuk penyiapan tercepat.';

  @override
  String get downloadsStarterPackJmdict => 'JMdict English';

  @override
  String get downloadsStarterPackWordFrequency => 'Frekuensi Kata';

  @override
  String get downloadsInstallStarterPack => 'Instal Paket Awal';

  @override
  String get downloadsSectionDictionaries => 'Kamus';

  @override
  String get downloadsSectionAssets => 'Aset';

  @override
  String get downloadsFetchingLatestRelease => 'Mengambil rilis terbaru...';

  @override
  String downloadsDownloadingPercent({required int percent}) {
    return 'Mengunduh... $percent%';
  }

  @override
  String get downloadsImporting => 'Mengimpor...';

  @override
  String get downloadsExtractingFiles => 'Mengekstrak file...';

  @override
  String get downloadsJpdbAttribution =>
      'Data frekuensi kata dari JPDB (jpdb.io), didistribusikan oleh Kuuuube.';

  @override
  String get downloadsKanjiStrokeOrderTitle => 'Urutan Guratan Kanji';

  @override
  String downloadsKanjiStrokeOrderDownloaded({required int count}) {
    return '$count file urutan guratan telah diunduh';
  }

  @override
  String get downloadsKanjiStrokeOrderDescription =>
      'Unduh data urutan guratan kanji dari KanjiVG';

  @override
  String get downloadsDeleteKanjiDataTooltip => 'Hapus data kanji';

  @override
  String get downloadsDeleteKanjiDataTitle => 'Hapus Data Kanji';

  @override
  String get downloadsDeleteKanjiDataBody =>
      'Hapus semua file urutan goresan kanji yang sudah diunduh? Anda dapat mengunduhnya lagi nanti.';

  @override
  String get downloadsWordFrequencyDownloaded =>
      'Data frekuensi kata berhasil diunduh';

  @override
  String get downloadsWordFrequencyDescription =>
      'Unduh data frekuensi kata untuk peringkat hasil pencarian';

  @override
  String get downloadsDeleteFrequencyDataTooltip => 'Hapus data frekuensi';

  @override
  String get downloadsDeleteFrequencyDataTitle => 'Hapus Data Frekuensi';

  @override
  String get downloadsDeleteFrequencyDataBody =>
      'Hapus data frekuensi kata? Hasil pencarian tidak lagi diurutkan berdasarkan frekuensi. Anda bisa mengunduhnya lagi nanti.';

  @override
  String get downloadsJmdictDownloaded =>
      'Kamus Jepang-Inggris berhasil diunduh';

  @override
  String get downloadsJmdictDescription => 'Unduh kamus Jepang-Inggris';

  @override
  String get downloadsDeleteJmdictTooltip => 'Hapus JMdict';

  @override
  String get downloadsChooseJmdictVariant => 'Pilih varian JMdict';

  @override
  String get downloadsJmdictStandardSubtitle => 'Kamus standar (~15 MB)';

  @override
  String get downloadsJmdictExamplesTitle =>
      'JMdict Inggris dengan Contoh Kalimat';

  @override
  String get downloadsJmdictExamplesSubtitle =>
      'Termasuk contoh kalimat (~18 MB)';

  @override
  String get downloadsDeleteJmdictTitle => 'Hapus JMdict';

  @override
  String get downloadsDeleteJmdictBody =>
      'Hapus JMdict beserta seluruh entri di dalamnya? Anda dapat mengunduhnya lagi nanti.';

  @override
  String get downloadsKanjidicDownloaded => 'Kamus kanji berhasil diunduh';

  @override
  String get downloadsKanjidicDescription => 'Unduh kamus kanji';

  @override
  String get downloadsDeleteKanjidicTooltip => 'Hapus KANJIDIC';

  @override
  String get downloadsDeleteKanjidicTitle => 'Hapus KANJIDIC';

  @override
  String get downloadsDeleteKanjidicBody =>
      'Hapus KANJIDIC dan semua entri di dalamnya? Anda bisa mengunduhnya lagi nanti.';

  @override
  String get commonClear => 'Bersihkan';

  @override
  String get commonSubmit => 'Kirim';

  @override
  String get commonLoading => 'Memuat...';

  @override
  String get commonError => 'Kesalahan';

  @override
  String get commonRestore => 'Pulihkan';

  @override
  String get settingsTitle => 'Pengaturan';

  @override
  String get settingsSectionGeneral => 'Umum';

  @override
  String get settingsAppLanguageTitle => 'Bahasa Aplikasi';

  @override
  String settingsAppLanguageSystemValue({required String language}) {
    return 'Default sistem ($language)';
  }

  @override
  String get settingsAppLanguageEnglish => 'English';

  @override
  String get settingsAppLanguageSpanish => 'Español';

  @override
  String get settingsAppLanguageIndonesian => 'Bahasa Indonesia';

  @override
  String get settingsAppLanguageSimplifiedChinese => '简体中文';

  @override
  String get settingsSectionAppearance => 'Tampilan';

  @override
  String get settingsSectionReadingDefaults => 'Pengaturan Baca Default';

  @override
  String get settingsSectionDictionary => 'Kamus';

  @override
  String get settingsSectionVocabularyExport => 'Kosakata & Ekspor';

  @override
  String get settingsSectionPro => 'Pro';

  @override
  String get settingsSectionMangaAutoCrop => 'Otomatis Pangkas Manga';

  @override
  String get settingsSectionMangaOcr => 'OCR Manga';

  @override
  String get settingsSectionDownloads => 'Unduhan';

  @override
  String get settingsSectionBackupRestore => 'Cadangan & Pulihkan';

  @override
  String get settingsSectionAboutFeedback => 'Tentang & Masukan';

  @override
  String get settingsStartupScreenTitle => 'Layar Awal';

  @override
  String get settingsStartupScreenLibrary => 'Perpustakaan';

  @override
  String get settingsStartupScreenDictionary => 'Kamus';

  @override
  String get settingsStartupScreenLastRead => 'Buku Terakhir Dibaca';

  @override
  String get settingsThemeTitle => 'Tema';

  @override
  String get settingsThemeLight => 'Terang';

  @override
  String get settingsThemeDark => 'Gelap';

  @override
  String get settingsThemeSystemDefault => 'Default sistem';

  @override
  String get settingsColorThemeTitle => 'Tema Warna';

  @override
  String get settingsColorThemeMekuruRed => 'Mekuru Merah';

  @override
  String get settingsColorThemeIndigo => 'Indigo';

  @override
  String get settingsColorThemeTeal => 'Teal';

  @override
  String get settingsColorThemeDeepPurple => 'Ungu Tua';

  @override
  String get settingsColorThemeBlue => 'Biru';

  @override
  String get settingsColorThemeGreen => 'Hijau';

  @override
  String get settingsColorThemeOrange => 'Oranye';

  @override
  String get settingsColorThemePink => 'Merah Muda';

  @override
  String get settingsColorThemeBlueGrey => 'Abu-abu Kebiruan';

  @override
  String get settingsFontSizeTitle => 'Ukuran Font';

  @override
  String settingsPointsValue({required int points}) {
    return '$points pt';
  }

  @override
  String get settingsColorModeTitle => 'Mode Warna';

  @override
  String get settingsColorModeNormal => 'Normal';

  @override
  String get settingsColorModeSepia => 'Sepia';

  @override
  String get settingsColorModeDark => 'Gelap';

  @override
  String get settingsSepiaIntensityTitle => 'Intensitas Sepia';

  @override
  String get settingsKeepScreenOnTitle => 'Layar Selalu Aktif';

  @override
  String get settingsKeepScreenOnSubtitle => 'Cegah layar mati saat membaca';

  @override
  String settingsHorizontalMarginValue({required int pixels}) {
    return 'Margin Horizontal: ${pixels}px';
  }

  @override
  String settingsVerticalMarginValue({required int pixels}) {
    return 'Margin Vertikal: ${pixels}px';
  }

  @override
  String get settingsSwipeSensitivityTitle => 'Sensitivitas Geser';

  @override
  String settingsPercentValue({required int percent}) {
    return '$percent%';
  }

  @override
  String get settingsSwipeSensitivityHint =>
      'Lebih rendah = butuh gerakan jari lebih sedikit untuk menggeser';

  @override
  String get settingsManageDictionariesSubtitle =>
      'Impor, urutkan ulang, aktif/nonaktifkan';

  @override
  String get settingsLookupFontSizeTitle => 'Ukuran Font Pencarian';

  @override
  String get settingsFilterRomanLetterEntriesTitle =>
      'Saring Entri Huruf Romawi';

  @override
  String get settingsFilterRomanLetterEntriesSubtitle =>
      'Sembunyikan entri yang menggunakan huruf Inggris di judul';

  @override
  String get settingsAutoFocusSearchTitle => 'Pencarian Autofokus';

  @override
  String get settingsAutoFocusSearchSubtitle =>
      'Buka keyboard saat tab kamus dipilih';

  @override
  String get settingsAnkiDroidIntegrationTitle => 'Integrasi AnkiDroid';

  @override
  String get settingsAnkiDroidIntegrationSubtitle =>
      'Atur tipe catatan, dek, dan pemetaan kolom';

  @override
  String get settingsProUnavailableSubtitle =>
      'Layanan Pro sedang tidak tersedia sementara.';

  @override
  String get settingsProSubtitle =>
      'Buka fitur auto-crop, sorotan buku, dan OCR kustom';

  @override
  String get settingsWhiteThresholdTitle => 'Ambang Putih';

  @override
  String settingsWhiteThresholdSubtitle({required int threshold}) {
    return '$threshold (nilai lebih rendah mengabaikan lebih banyak artefak mendekati putih)';
  }

  @override
  String get settingsCustomOcrServerTitle => 'Server OCR Kustom';

  @override
  String get settingsCustomOcrServerUnavailableSubtitle =>
      'Layanan OCR sedang tidak tersedia sementara.';

  @override
  String get settingsCustomOcrServerNotConfigured =>
      'Belum dikonfigurasi. Tambahkan URL server dan shared key milik Anda sendiri.';

  @override
  String settingsCustomOcrServerConfigured({required String url}) {
    return '$url\nGunakan shared key yang sama seperti di server Anda.';
  }

  @override
  String get settingsCustomOcrServerUrlLabel => 'URL Server';

  @override
  String get settingsCustomOcrServerUrlHint => 'http://192.168.1.100:8000';

  @override
  String get settingsCustomOcrServerLearnHow =>
      'Pelajari cara menjalankan server sendiri';

  @override
  String get settingsCustomOcrServerKeyLabel => 'Shared key kustom';

  @override
  String get settingsCustomOcrServerKeyHint => 'Diperlukan AUTH_API_KEY';

  @override
  String get settingsCustomOcrServerDescription =>
      'Masukkan AUTH_API_KEY bersama yang sama dengan server OCR Anda. Mekuru akan mengirim sebagai Authorization: Bearer <key> untuk permintaan OCR manga jarak jauh.';

  @override
  String get settingsCustomOcrServerUrlRequired => 'Masukkan URL server Anda.';

  @override
  String get settingsCustomOcrServerUrlInvalid =>
      'Masukkan URL server lengkap http:// atau https://.';

  @override
  String get settingsCustomOcrServerKeyRequired =>
      'Shared key diperlukan untuk server kustom.';

  @override
  String get settingsDownloadsSubtitle => 'Kamus, data kanji, dan lainnya';

  @override
  String get settingsBackupRestoreTitle => 'Cadangkan & Pulihkan';

  @override
  String get settingsBackupRestoreSubtitle =>
      'Cadangkan dan pulihkan data Anda';

  @override
  String get settingsSendFeedbackSubtitle => 'Laporkan bug atau sarankan fitur';

  @override
  String get settingsFeedbackThanks => 'Terima kasih atas masukan Anda!';

  @override
  String get settingsFeedbackFailed =>
      'Gagal mengirim masukan. Silakan coba lagi.';

  @override
  String get settingsDocumentationTitle => 'Dokumentasi';

  @override
  String get settingsDocumentationSubtitle => 'Panduan dan artikel cara pakai';

  @override
  String get settingsAboutMekuruTitle => 'Tentang Mekuru';

  @override
  String get settingsAboutMekuruSubtitle => 'Versi, lisensi, dan lainnya';

  @override
  String get feedbackTitle => 'Kirim Masukan';

  @override
  String get feedbackNameLabel => 'Nama';

  @override
  String get feedbackNameHint => 'Nama Anda';

  @override
  String get feedbackEmailLabel => 'Email';

  @override
  String get feedbackEmailHint => 'your@email.com';

  @override
  String get feedbackMessageLabel => 'Pesan';

  @override
  String get feedbackRequired => '(wajib diisi)';

  @override
  String get feedbackMessageHint =>
      'Jelaskan bug atau permintaan fitur Anda...';

  @override
  String get feedbackMessageRequiredError => 'Silakan masukkan pesan';

  @override
  String get backupTitle => 'Cadangkan & Pulihkan';

  @override
  String get backupSectionBackup => 'Cadangkan';

  @override
  String get backupCreateNowTitle => 'Buat Cadangan Sekarang';

  @override
  String get backupCreateNowSubtitle =>
      'Simpan pengaturan dan data pengguna Anda, seperti bookmark, sorotan, dan daftar kosakata. File EPUB dan manga tidak disertakan.';

  @override
  String get backupExportTitle => 'Ekspor Cadangan';

  @override
  String get backupExportSubtitle =>
      'Simpan cadangan terbaru untuk pengaturan dan data pengguna Anda ke file. File EPUB dan manga tidak disertakan.';

  @override
  String get backupSaveFileDialogTitle => 'Simpan Cadangan';

  @override
  String get backupScopeNoteTitle => 'Apa yang dicadangkan?';

  @override
  String get backupScopeNoteBody =>
      'Cadangan mencakup pengaturan dan data yang Anda buat di Mekuru, seperti bookmark, sorotan, dan daftar kosakata. Cadangan tidak mencakup file EPUB atau manga yang sebenarnya.';

  @override
  String get backupScopeNoteRestore =>
      'Setelah memulihkan, impor ulang konten EPUB atau manga yang sama. Jika kontennya sama persis, riwayat Anda akan kembali.';

  @override
  String get backupSectionAutoBackup => 'Cadangan Otomatis';

  @override
  String get backupAutoBackupIntervalTitle => 'Interval Cadangan Otomatis';

  @override
  String get backupIntervalOff => 'Mati';

  @override
  String get backupIntervalDaily => 'Harian';

  @override
  String get backupIntervalWeekly => 'Mingguan';

  @override
  String get backupSectionRestore => 'Pulihkan';

  @override
  String get backupImportFileTitle => 'Impor File Cadangan';

  @override
  String get backupImportFileSubtitle =>
      'Pulihkan pengaturan dan data pengguna dari file .mekuru. Impor ulang konten EPUB atau manga yang sama untuk mengembalikan riwayatnya.';

  @override
  String get backupSectionHistory => 'Riwayat Cadangan';

  @override
  String get backupNoBackupsYet => 'Belum ada cadangan';

  @override
  String backupErrorLoadingHistory({required String details}) {
    return 'Galat memuat cadangan: $details';
  }

  @override
  String get backupCreatedSuccess => 'Cadangan berhasil dibuat';

  @override
  String backupFailed({required String details}) {
    return 'Cadangan gagal: $details';
  }

  @override
  String get backupNoBackupsToExport =>
      'Tidak ada cadangan untuk diekspor. Buat satu terlebih dahulu.';

  @override
  String get backupExportedSuccess => 'Cadangan berhasil diekspor';

  @override
  String backupExportFailed({required String details}) {
    return 'Ekspor gagal: $details';
  }

  @override
  String get backupInvalidFile => 'Silakan pilih file cadangan .mekuru.';

  @override
  String backupCouldNotOpenFile({required String details}) {
    return 'Tidak dapat membuka file: $details';
  }

  @override
  String backupRestoreFailed({required String details}) {
    return 'Pemulihan gagal: $details';
  }

  @override
  String backupBooksUpdatedFromBackup({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '# buku diperbarui dari cadangan',
      one: '# buku diperbarui dari cadangan',
    );
    return '$_temp0';
  }

  @override
  String backupApplyBookDataFailed({required String details}) {
    return 'Gagal menerapkan data buku: $details';
  }

  @override
  String get backupConflictDialogTitle => 'Buku Konflik';

  @override
  String get backupConflictDialogBody =>
      'Buku-buku berikut sudah memiliki data bacaan. Pilih yang ingin ditimpa dengan data cadangan:';

  @override
  String backupConflictEntrySubtitle({
    required String bookType,
    required int progress,
  }) {
    return '$bookType - $progress% dalam cadangan';
  }

  @override
  String get backupConflictSkipAll => 'Lewati Semua';

  @override
  String backupConflictOverwriteSelected({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Timpa #',
      one: 'Timpa #',
    );
    return '$_temp0';
  }

  @override
  String get backupBookTypeEpub => 'EPUB';

  @override
  String get backupBookTypeManga => 'Manga';

  @override
  String get backupRestoreSummarySettingsRestored =>
      'Pengaturan berhasil dipulihkan';

  @override
  String get backupRestoreSummarySettingsPartial =>
      'Sebagian pengaturan tidak dapat dipulihkan';

  @override
  String backupRestoreSummaryWords({required int added, required int skipped}) {
    return '$added kata ditambahkan, $skipped dilewati';
  }

  @override
  String backupRestoreSummaryBooksRestored({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '# buku berhasil dipulihkan',
      one: '# buku berhasil dipulihkan',
    );
    return '$_temp0';
  }

  @override
  String backupRestoreSummaryBooksPending({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '# buku menunggu konten EPUB atau manga yang sama untuk diimpor ulang',
      one:
          '# buku menunggu konten EPUB atau manga yang sama untuk diimpor ulang',
    );
    return '$_temp0';
  }

  @override
  String get backupRestoreComplete => 'Pemulihan selesai';

  @override
  String get backupRestoreDialogTitle => 'Pulihkan Cadangan?';

  @override
  String backupRestoreDialogBody({required String fileName}) {
    return 'Ini akan memulihkan pengaturan dan data pengguna dari $fileName, seperti bookmark, sorotan, dan daftar kosakata. Ini tidak memulihkan file EPUB atau manga yang sebenarnya. Setelah memulihkan, impor ulang konten EPUB atau manga yang sama untuk mengembalikan riwayatnya. Pengaturan Anda saat ini akan ditimpa.';
  }

  @override
  String get backupDeleteDialogTitle => 'Hapus Cadangan?';

  @override
  String backupDeleteDialogBody({required String fileName}) {
    return 'Hapus $fileName? Tindakan ini tidak dapat dibatalkan.';
  }

  @override
  String get backupHistoryTypeAuto => 'Cadangan otomatis';

  @override
  String get backupHistoryTypeManual => 'Cadangan manual';

  @override
  String get readerDismiss => 'Tutup';

  @override
  String readerFailedToLoadContent({required String details}) {
    return 'Gagal memuat konten EPUB.\n$details';
  }

  @override
  String readerFailedToLoad({required String details}) {
    return 'Gagal memuat EPUB.\n$details';
  }

  @override
  String get readerVerticalTextNonNativeWarning =>
      'Buku ini awalnya tidak diformat untuk teks vertikal. Beberapa tampilan mungkin bermasalah.';

  @override
  String get readerHorizontalTextNonNativeWarning =>
      'Buku ini awalnya diformat untuk teks vertikal. Beberapa tampilan mungkin bermasalah dalam mode horizontal.';

  @override
  String get readerBookmarkRemoved => 'Bookmark dihapus';

  @override
  String get readerPageBookmarked => 'Halaman ditandai';

  @override
  String get readerTableOfContents => 'Daftar Isi';

  @override
  String get readerRemoveBookmarkTooltip => 'Hapus Bookmark';

  @override
  String get readerBookmarkPageTooltip => 'Tandai Halaman';

  @override
  String get readerViewBookmarksTooltip => 'Lihat Bookmark';

  @override
  String get readerHighlightsTooltip => 'Sorotan';

  @override
  String get readerNextPageTooltip => 'Halaman Berikutnya';

  @override
  String get readerPreviousPageTooltip => 'Halaman Sebelumnya';

  @override
  String get readerUnknownError => 'Kesalahan pembaca tidak diketahui.';

  @override
  String get readerQuickSettings => 'Pengaturan Cepat';

  @override
  String get readerVerticalTextTitle => 'Teks Vertikal';

  @override
  String get readerThisBook => 'Buku ini';

  @override
  String get readerVerticalTextUnavailable =>
      'Tidak tersedia untuk bahasa buku ini';

  @override
  String get readerReadingDirectionTitle => 'Arah Membaca';

  @override
  String get readerReadingDirectionRtl => 'Kanan ke Kiri';

  @override
  String get readerReadingDirectionLtr => 'Kiri ke Kanan';

  @override
  String get readerDisableLinksTitle => 'Nonaktifkan Tautan';

  @override
  String get readerDisableLinksSubtitle =>
      'Ketuk teks terhubung untuk mencari kata, bukan untuk navigasi';

  @override
  String get readerHighlightSelectionTooltip => 'Sorot pilihan';

  @override
  String get commonCopy => 'Salin';

  @override
  String get commonShare => 'Bagikan';

  @override
  String get commonContinue => 'Lanjutkan';

  @override
  String get commonNotSelected => 'Belum dipilih';

  @override
  String get commonUnknown => 'Tidak diketahui';

  @override
  String get commonRename => 'Ganti nama';

  @override
  String get commonTitleLabel => 'Judul';

  @override
  String libraryCouldNotReadFolder({required String details}) {
    return 'Tidak dapat membaca folder:\n$details';
  }

  @override
  String get libraryBookmarksTitle => 'Penanda Halaman';

  @override
  String get libraryChangeCoverAction => 'Ubah Sampul';

  @override
  String get libraryRenameBookTitle => 'Ganti Nama Buku';

  @override
  String get libraryDeleteBookTitle => 'Hapus Buku';

  @override
  String libraryDeleteBookBody({required String title}) {
    return 'Hapus \"$title\" dari perpustakaan Anda?';
  }

  @override
  String libraryChangeCoverFailed({required String details}) {
    return 'Gagal mengubah sampul: $details';
  }

  @override
  String get dictionaryManagerTitle => 'Pengelola Kamus';

  @override
  String get dictionaryManagerImportTooltip => 'Impor Kamus';

  @override
  String get dictionaryManagerEmptySubtitle =>
      'Ketuk + untuk mengimpor kamus Yomitan (.zip)\natau koleksi (.json)';

  @override
  String get dictionaryManagerBrowseDownloads => 'Jelajahi Unduhan';

  @override
  String get dictionaryManagerBrowseDownloadsCaption =>
      'Unduh kamus dan aset lainnya';

  @override
  String dictionaryManagerImportedOn({required String date}) {
    return 'Diimpor pada $date';
  }

  @override
  String get dictionaryManagerSupportedFormatsTitle => 'Format yang Didukung';

  @override
  String get dictionaryManagerSupportedFormatsYomitan =>
      'Kamus Yomitan (.zip)\nSemua kamus yang dapat diimpor ke Yomitan didukung. Ini adalah file .zip yang berisi file JSON bank istilah.';

  @override
  String get dictionaryManagerSupportedFormatsCollection =>
      'Koleksi Yomitan (.json)\nEkspor basis data Dexie yang berisi beberapa kamus dalam satu file. Anda dapat mengekspor ini dari pengaturan Yomitan di bagian Cadangan.';

  @override
  String get dictionaryManagerOrderTitle => 'Urutan Kamus';

  @override
  String get dictionaryManagerOrderBody =>
      'Seret kamus menggunakan pegangan di kiri untuk mengatur ulang urutannya. Urutan di sini menentukan urutan definisi yang muncul saat Anda mengetuk kata ketika membaca.';

  @override
  String get dictionaryManagerEnablingTitle => 'Aktivasi & Nonaktifkan';

  @override
  String get dictionaryManagerEnablingBody =>
      'Gunakan tombol sakelar untuk mengaktifkan atau menonaktifkan kamus. Kamus yang dinonaktifkan tidak akan dicari saat melakukan penelusuran kata.';

  @override
  String get dictionaryManagerFindingTitle => 'Mencari Kamus';

  @override
  String get dictionaryManagerFindingPrefix =>
      'Jelajahi kamus yang kompatibel di ';

  @override
  String get dictionaryManagerDeleteTitle => 'Hapus Kamus';

  @override
  String dictionaryManagerDeleteBody({required String name}) {
    return 'Hapus \"$name\" beserta semua entri di dalamnya?\nTindakan ini tidak dapat dibatalkan.';
  }

  @override
  String get ankidroidDataSourceExpression => 'Ekspresi';

  @override
  String get ankidroidDataSourceReading => 'Pembacaan';

  @override
  String get ankidroidDataSourceFurigana => 'Furigana (format Anki)';

  @override
  String get ankidroidDataSourceGlossary => 'Glosarium / Makna';

  @override
  String get ankidroidDataSourceSentenceContext => 'Konteks Kalimat';

  @override
  String get ankidroidDataSourceFrequency => 'Peringkat Frekuensi';

  @override
  String get ankidroidDataSourceDictionaryName => 'Nama Kamus';

  @override
  String get ankidroidDataSourcePitchAccent => 'Aksen Nada';

  @override
  String get ankidroidDataSourceEmpty => '(Kosong)';

  @override
  String get ankidroidPermissionNotGrantedLong =>
      'Izin AnkiDroid belum diberikan. Pastikan AnkiDroid sudah terpasang dan coba lagi.';

  @override
  String get ankidroidCouldNotConnectLong =>
      'Tidak dapat terhubung ke AnkiDroid. Pastikan AnkiDroid sudah diinstal dan dijalankan.';

  @override
  String get ankidroidPermissionNotGrantedShort =>
      'Izin AnkiDroid tidak diberikan.';

  @override
  String get ankidroidCouldNotConnectShort =>
      'Tidak dapat terhubung ke AnkiDroid.';

  @override
  String get ankidroidFailedToAddNote =>
      'Gagal menambahkan catatan. Pastikan AnkiDroid sedang berjalan dan tipe catatan serta dek yang dipilih masih ada.';

  @override
  String get ankidroidSettingsNoteTypeSection => 'Tipe Catatan';

  @override
  String get ankidroidSettingsNoteTypeTitle => 'Tipe Catatan Anki';

  @override
  String get ankidroidSettingsDefaultDeckSection => 'Dek Default';

  @override
  String get ankidroidSettingsTargetDeckTitle => 'Dek Tujuan';

  @override
  String get ankidroidSettingsFieldMappingSection => 'Pemetaan Kolom';

  @override
  String get ankidroidSettingsFieldMappingHelp =>
      'Petakan setiap kolom Anki ke sumber data dari aplikasi.';

  @override
  String get ankidroidSettingsDefaultTagsSection => 'Tag Default';

  @override
  String get ankidroidSettingsDefaultTagsHelp =>
      'Tag yang dipisahkan koma dan akan diterapkan pada setiap catatan yang diekspor.';

  @override
  String get ankidroidTagsHint => 'mekuru, japanese';

  @override
  String get ankidroidSettingsSelectNoteType => 'Pilih Tipe Catatan';

  @override
  String get ankidroidSettingsSelectDeck => 'Pilih Dek';

  @override
  String ankidroidSettingsMapFieldTo({required String ankiFieldName}) {
    return 'Petakan \"$ankiFieldName\" ke:';
  }

  @override
  String get ankidroidCardSettingsTooltip => 'Pengaturan AnkiDroid';

  @override
  String get ankidroidCardDeckTitle => 'Dek';

  @override
  String get ankidroidCardTagsTitle => 'Tag';

  @override
  String get ankidroidCardAddToAnki => 'Tambah ke Anki';

  @override
  String get mangaReaderSettingsTitle => 'Pengaturan Pembaca';

  @override
  String get mangaViewModeSingle => 'Tunggal';

  @override
  String get mangaViewModeSpread => 'Dua Halaman';

  @override
  String get mangaViewModeScroll => 'Gulir';

  @override
  String get mangaAutoCropSubtitle => 'Hapus margin kosong';

  @override
  String get mangaAutoCropRerunTitle => 'Jalankan Ulang Pemotongan Otomatis';

  @override
  String get mangaAutoCropRerunSubtitle =>
      'Pindai ulang setiap gambar halaman untuk buku ini';

  @override
  String get mangaTransparentLookupTitle => 'Pencarian Transparan';

  @override
  String get mangaTransparentLookupSubtitle => 'Lembar kamus tembus pandang';

  @override
  String get mangaDebugWordOverlayTitle => 'Debug Overlay Kata';

  @override
  String get mangaDebugWordOverlaySubtitle => 'Tampilkan kotak pembatas kata';

  @override
  String get mangaAutoCropComputeTitle => 'Hitung Pemotongan Otomatis?';

  @override
  String get mangaAutoCropComputeBody =>
      'Pemotongan otomatis harus memindai setiap gambar halaman pada buku ini sebelum dapat diaktifkan. Ini mungkin memerlukan waktu satu menit.';

  @override
  String get mangaAutoCropRerunDialogTitle =>
      'Jalankan Ulang Pemotongan Otomatis?';

  @override
  String get mangaAutoCropRerunDialogBody =>
      'Pemotongan otomatis akan memindai ulang setiap gambar halaman untuk buku ini dan menggantikan batas potongan yang tersimpan. Ini mungkin memerlukan waktu satu menit.';

  @override
  String get mangaAutoCropComputingProgress =>
      'Menghitung batas pemotongan otomatis. Ini mungkin memerlukan waktu satu menit.';

  @override
  String get mangaAutoCropRecomputingProgress =>
      'Menghitung ulang batas pemotongan otomatis. Ini mungkin memerlukan waktu satu menit.';

  @override
  String get mangaAutoCropBoundsRefreshed =>
      'Batas pemotongan otomatis telah diperbarui.';

  @override
  String mangaAutoCropSetupFailed({required String details}) {
    return 'Pengaturan pemotongan otomatis gagal: $details';
  }

  @override
  String get ocrNoPagesCacheFound =>
      'Cache halaman tidak ditemukan untuk buku ini';

  @override
  String get ocrAlreadyCompleteResetHint =>
      'OCR sudah selesai. Gunakan \"Hapus OCR\" untuk mereset.';

  @override
  String get ocrMangaImageDirectoryNotFound =>
      'Direktori gambar manga tidak ditemukan';

  @override
  String get ocrBuildWordOverlaysTitle => 'Bangun Overlay Kata';

  @override
  String get ocrBuildWordOverlaysBody =>
      'Teks OCR sudah ada. Ini akan membangun ulang target ketukan kata agar overlay pencarian tampil dengan benar.';

  @override
  String get ocrRunActionTitle => 'Jalankan OCR';

  @override
  String ocrProcessPagesBody({required int count}) {
    return 'Ini akan memproses $count halaman. OCR akan berjalan di latar belakang dan tetap berjalan meskipun Anda menutup aplikasi.';
  }

  @override
  String get ocrProcessAction => 'Proses';

  @override
  String get ocrStartAction => 'Mulai';

  @override
  String ocrPrepareFailed({required String details}) {
    return 'Tidak dapat menyiapkan OCR: $details';
  }

  @override
  String ocrStartFailed({required String details}) {
    return 'Gagal memulai OCR: $details';
  }

  @override
  String get ocrWordOverlayStartedBackground =>
      'Proses overlay kata dimulai di latar belakang';

  @override
  String get ocrStartedBackground => 'OCR dimulai di latar belakang';

  @override
  String get ocrCancelActionTitle => 'Batalkan OCR';

  @override
  String get ocrCancelSavedProgress => 'OCR dibatalkan. Progres disimpan.';

  @override
  String get ocrReplaceActionTitle => 'Ganti OCR';

  @override
  String get ocrReplaceMokuroBody =>
      'Ini akan menimpa data OCR yang diimpor dari file Mokuro/HTML dan menjalankan ulang OCR pada SEMUA halaman menggunakan server kustom Anda.\n\nUntuk mengembalikan OCR asli, impor ulang bukunya.';

  @override
  String get ocrReplaceStartedBackground =>
      'Penggantian OCR dimulai di latar belakang';

  @override
  String get ocrRemoveActionTitle => 'Hapus OCR';

  @override
  String get ocrRemoveBody =>
      'Hapus teks OCR dan overlay kata dari manga ini? Anda dapat menjalankan OCR lagi nanti.';

  @override
  String get ocrRemoveSubtitle => 'Hapus teks OCR dari semua halaman';

  @override
  String get ocrRemovedFromBook => 'OCR dihapus dari buku ini';

  @override
  String ocrRemoveFailed({required String details}) {
    return 'Gagal menghapus OCR: $details';
  }

  @override
  String get ocrUnlockProSubtitle =>
      'Buka Pro untuk menggunakan server OCR kustom Anda';

  @override
  String get ocrStopAndSaveProgressSubtitle =>
      'Hentikan proses dan simpan progres';

  @override
  String get ocrReplaceMokuroSubtitle =>
      'Ganti OCR Mokuro dengan server OCR kustom Anda';

  @override
  String get ocrBuildWordTargetsSubtitle =>
      'Buat target ketukan kata dari OCR yang disimpan';

  @override
  String ocrResumeSubtitle({required int completed, required int total}) {
    return 'Lanjutkan OCR ($completed/$total selesai)';
  }

  @override
  String get ocrRecognizeAllPagesSubtitle => 'Kenali teks pada semua halaman';

  @override
  String get readerEditNoteTitle => 'Edit Catatan';

  @override
  String get readerAddNoteHint => 'Tambah catatan...';

  @override
  String get readerCopiedToClipboard => 'Disalin ke clipboard';

  @override
  String get aboutPrivacyPolicyTitle => 'Kebijakan Privasi';

  @override
  String get aboutPrivacyPolicySubtitle =>
      'Lihat bagaimana Mekuru menangani data lokal dan OCR';

  @override
  String get aboutOpenSourceLicensesTitle => 'Lisensi Open Source';

  @override
  String get aboutOpenSourceLicensesSubtitle =>
      'Lihat lisensi untuk dependensi';

  @override
  String get aboutTagline => '\"untuk membalik halaman\"';

  @override
  String get aboutEpubJsLicenseTitle => 'Lisensi epub.js';

  @override
  String get downloadsKanjidicTitle => 'KANJIDIC';

  @override
  String get readerBookmarksTitle => 'Penanda Halaman';

  @override
  String get readerNoBookmarksYet =>
      'Belum ada penanda halaman.\nKetuk ikon penanda saat membaca untuk menambahkannya.';

  @override
  String readerBookmarkProgressDate({
    required String progress,
    required String date,
  }) {
    return '$progress - $date';
  }

  @override
  String aboutVersion({required String version}) {
    return 'Versi $version';
  }

  @override
  String get aboutDescription =>
      'Pembaca EPUB berfokus pada bahasa Jepang dengan teks vertikal, kamus offline, dan manajemen kosakata.';

  @override
  String get aboutAttributionTitle => 'Atribusi';

  @override
  String get aboutKanjiVgTitle => 'KanjiVG';

  @override
  String get aboutKanjiVgDescription =>
      'Data urutan goresan kanji disediakan oleh proyek KanjiVG, dibuat oleh Ulrich Apel.';

  @override
  String get aboutLicensedUnderPrefix => 'Dilindungi di bawah lisensi ';

  @override
  String get aboutLicenseSuffix => ' .';

  @override
  String get aboutProjectLabel => 'Proyek: ';

  @override
  String get aboutSourceLabel => 'Sumber: ';

  @override
  String get aboutJpdbTitle => 'Kamus Frekuensi JPDB';

  @override
  String get aboutJpdbDescription =>
      'Data frekuensi kata disediakan oleh kamus frekuensi JPDB, didistribusikan melalui yomitan-dictionaries oleh Kuuuube.';

  @override
  String get aboutDataSourceLabel => 'Sumber data: ';

  @override
  String get aboutDictionaryLabel => 'Kamus: ';

  @override
  String get aboutJmdictKanjidicTitle => 'JMdict & KANJIDIC';

  @override
  String get aboutJmdictKanjidicDescriptionPrefix =>
      'Data kamus multibahasa Jepang disediakan oleh proyek JMdict/EDICT dan data kamus kanji oleh proyek KANJIDIC, keduanya dibuat oleh Jim Breen dan ';

  @override
  String get aboutJmdictLabel => 'JMdict: ';

  @override
  String get aboutKanjidicLabel => 'KANJIDIC: ';

  @override
  String get aboutEpubJsTitle => 'epub.js';

  @override
  String get aboutEpubJsDescription =>
      'Rendering EPUB didukung oleh epub.js, pustaka pembaca EPUB JavaScript sumber terbuka.';
}
