// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get appTitle => 'Mekuru';

  @override
  String get navLibrary => 'ライブラリ';

  @override
  String get navDictionary => '辞書';

  @override
  String get navVocabulary => '単語帳';

  @override
  String get navYou => 'マイページ';

  @override
  String get navRecent => '最近';

  @override
  String get navStats => '統計';

  @override
  String get navFreeBooks => '無料の本';

  @override
  String get recentlyReadTitle => '最近読んだ本';

  @override
  String get recentlyReadEmpty => '開いた本がここに表示されます。';

  @override
  String recentlyReadDaysAgo({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count日前',
      one: '昨日',
      zero: '今日',
    );
    return '$_temp0';
  }

  @override
  String get settingsNavBarTitle => 'ナビゲーションバー';

  @override
  String get navBarEditorHint =>
      'ドラッグで並べ替えできます。タブは5つまでです。ライブラリは常に表示されます。非表示のタブは設定から開けます。';

  @override
  String get navBarLibraryNote => '常に表示';

  @override
  String get navBarYouNote => 'マイページと設定を両方とも非表示にすると、設定はライブラリの上部バーに表示されます。';

  @override
  String get settingsSectionHiddenTabs => '非表示のタブ';

  @override
  String get commonHelp => 'ヘルプ';

  @override
  String get commonImport => 'インポート';

  @override
  String get commonOpenNow => '今すぐ開く';

  @override
  String get commonCancel => 'キャンセル';

  @override
  String get commonClose => '閉じる';

  @override
  String get commonSave => '保存';

  @override
  String get commonDelete => '削除';

  @override
  String get commonDownload => 'ダウンロード';

  @override
  String get commonOpenDictionary => '辞書を開く';

  @override
  String get commonManageDictionaries => '辞書を管理';

  @override
  String get commonClearAll => 'すべて消去';

  @override
  String get commonClearSearch => '検索をクリア';

  @override
  String get commonSearch => '検索';

  @override
  String get commonBack => '戻る';

  @override
  String get commonRetry => '再試行';

  @override
  String get commonOk => 'OK';

  @override
  String get commonDone => '完了';

  @override
  String get commonUndo => '元に戻す';

  @override
  String get commonUnlock => 'アンロック';

  @override
  String get commonOpenSettings => '設定を開く';

  @override
  String get commonOpenDownloads => 'ダウンロードを開く';

  @override
  String get commonGotIt => 'わかりました';

  @override
  String commonErrorWithDetails({required String details}) {
    return 'エラー：$details';
  }

  @override
  String ankidroidAlreadyInDeck({required String deck}) {
    return '「$deck」に登録済み';
  }

  @override
  String libraryBatchImportProgress({
    required int current,
    required int total,
  }) {
    return '$total件中$current件をインポート中…';
  }

  @override
  String libraryImportedBooks({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count冊の本をインポートしました',
      one: '$count冊の本をインポートしました',
    );
    return '$_temp0';
  }

  @override
  String libraryImportPartial({required int succeeded, required int total}) {
    return '$total件中$succeeded件をインポートしました。';
  }

  @override
  String libraryImportFailedFile({
    required String file,
    required String reason,
  }) {
    return '$fileをインポートできませんでした：$reason';
  }

  @override
  String get libraryImportReasonPasswordProtected => 'このファイルはパスワードで保護されています。';

  @override
  String get libraryImportReasonSolidRar =>
      'このRARファイルは古いバージョンのRARのソリッド圧縮を使っているため、Mekuruでは開けません。ページをCBZ（ZIP）ファイルにまとめ直してからインポートしてください。';

  @override
  String get libraryImportReasonDamaged => 'ファイルが破損しているか、想定された形式ではありません。';

  @override
  String get libraryImportReasonNoPages => 'ページや画像が見つかりませんでした。';

  @override
  String get libraryImportReasonUnsupported => 'このファイル形式には対応していません。';

  @override
  String get libraryImportReasonUnreadable => 'ファイルを読み込めませんでした。';

  @override
  String get libraryImportReasonUnknown => '問題が発生しました。';

  @override
  String librarySortTooltip({required String label}) {
    return '並べ替え：$label';
  }

  @override
  String get libraryEmptyTitle => 'ライブラリに最初の本を追加しましょう';

  @override
  String get libraryEmptySubtitle =>
      '読みたいものをインポートして辞書をインストールすれば、数分で単語を保存できるようになります。';

  @override
  String get libraryFreeBooksLink => '無料の本を探す';

  @override
  String get libraryImportEpub => 'EPUBをインポート';

  @override
  String get libraryImportManga => 'マンガをインポート';

  @override
  String get libraryGetDictionaries => '辞書を入手';

  @override
  String get libraryContinueReading => '続きを読む';

  @override
  String get libraryRestoreBackup => 'バックアップを復元';

  @override
  String get librarySupportedMediaTitle => '対応形式';

  @override
  String get libraryEpubBooksTitle => 'EPUBの本';

  @override
  String get libraryEpubBooksDescription =>
      '標準的な.epubファイルに対応しています。+ボタンをタップして「EPUBをインポート」を選ぶと、端末から追加できます。';

  @override
  String get libraryMokuroTitle => 'Mokuroマンガ';

  @override
  String get libraryMokuroDescription =>
      'フォルダを選択してから.mokuroまたは.htmlファイルを選ぶと、マンガをインポートできます。ページ画像は、同じ階層にある同名のフォルダから読み込まれます。';

  @override
  String get libraryMokuroFormatDescription =>
      '.mokuroファイルはmokuroというツールで作成します。このツールはマンガのページに文字認識（OCR）をかけて、日本語のテキストを抽出します。';

  @override
  String get libraryLearnHowToCreateMokuroFiles => '.mokuroファイルの作り方';

  @override
  String get librarySortBy => '並べ替え';

  @override
  String get librarySortDateImported => 'インポート日';

  @override
  String get librarySortRecentlyRead => '最近読んだ順';

  @override
  String get librarySortAlphabetical => 'タイトル順';

  @override
  String get libraryImportTitle => 'インポート';

  @override
  String get libraryImportEpubSubtitle => 'EPUBファイルをインポート';

  @override
  String get libraryLargeImportWarnTitle => '大きな本';

  @override
  String libraryLargeImportWarnBody({required int sizeMb}) {
    return '選択した本のうち最も大きいものは$sizeMb MBです。この端末はメモリが少ないため、非常に大きな本はリーダーで開けない場合があります。このままインポートしますか？';
  }

  @override
  String get libraryLargeImportWarnAction => 'このままインポート';

  @override
  String get libraryImportMangaSubtitle => 'マンガのアーカイブかMokuroフォルダを選択';

  @override
  String get libraryImportPdf => 'PDFをインポート';

  @override
  String get libraryImportPdfSubtitle => 'PDFファイルをインポート';

  @override
  String get pdfScannedTitle => 'このPDFはスキャンしたもののようです';

  @override
  String pdfScannedBody({required String title}) {
    return 'Mekuruは「$title」から読み取れるテキストを見つけられませんでした。ページがスキャンのような画像になっているため、今のところ単語をタップできません。ページ単位で読むことはできます。\n\n多くの電子書籍のように、テキストから作られたPDFはすぐに使えます。スキャンしたPDFの場合は、OCR（Pro機能）で文字を認識すると、単語をタップできるようになります。';
  }

  @override
  String libraryImportFromServer({required String serverName}) {
    return '$serverNameからダウンロード';
  }

  @override
  String get libraryImportMangaTitle => 'マンガをインポート';

  @override
  String get libraryImportMangaDescription =>
      'マンガのアーカイブ（CBZ、CBR、ZIP、RAR）と、Mokuroで書き出したフォルダのどちらをインポートするか選んでください。';

  @override
  String get libraryImportMokuroFolder => 'Mokuroフォルダ';

  @override
  String get libraryImportMokuroFolderSubtitle =>
      '画像フォルダと同じ場所に.mokuroまたは.htmlファイルがあるフォルダを選択してください。';

  @override
  String get libraryWhatIsMokuro => 'Mokuroとは？';

  @override
  String get libraryImportCbzArchive => 'マンガのアーカイブ';

  @override
  String get libraryImportCbzArchiveSubtitle =>
      'マンガのページをまとめた.cbz、.cbr、.zip、.rarファイルをインポート';

  @override
  String get libraryImportedWithoutOcrMessage =>
      'OCRなしでインポートしました。テキストを重ねて表示するには、外部のOCR結果（.mokuroなど）をインポートしてください。';

  @override
  String get libraryCouldNotOpenMokuroProjectPage =>
      'Mokuroのプロジェクトページを開けませんでした。';

  @override
  String get libraryNoMangaManifestFound =>
      '選択したフォルダに.mokuroまたは.htmlファイルが見つかりません。';

  @override
  String get librarySelectedFolder => '選択したフォルダ';

  @override
  String libraryMangaFilesFound({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のマンガファイルが見つかりました',
      one: '$count件のマンガファイルが見つかりました',
    );
    return '$_temp0';
  }

  @override
  String get dictionarySearchHint => '漢字・かな・ローマ字で検索…';

  @override
  String get dictionaryNoDictionariesTitle => '辞書がインポートされていません';

  @override
  String get dictionaryNoDictionariesSubtitle =>
      'スターターパックをインストールするか、Yomitan形式の辞書をインポートすると検索できるようになります。';

  @override
  String get dictionaryRecommendedStarterPack => 'おすすめのスターターパック';

  @override
  String get dictionaryNoEnabledTitle => '辞書がすべてオフになっています';

  @override
  String get dictionaryNoEnabledSubtitle =>
      '辞書検索を使うには、少なくとも1つの辞書をオンにするか、おすすめのスターターパックをインストールしてください。';

  @override
  String get dictionaryEnableDictionaries => '辞書をオンにする';

  @override
  String get dictionaryStarterPack => 'スターターパック';

  @override
  String get dictionaryNoResultsFound => '結果が見つかりませんでした。';

  @override
  String get dictionarySearchForAWord => '単語を検索';

  @override
  String get dictionarySearchForAWordSubtitle => '漢字、ひらがな、カタカナ、ローマ字で入力';

  @override
  String get dictionaryRecent => '最近の検索';

  @override
  String dictionarySavedWord({required String expression}) {
    return '「$expression」を保存しました';
  }

  @override
  String get dictionaryWordAlreadyExistsInVocab => 'この単語はすでに単語帳にあります';

  @override
  String dictionaryCopiedWord({required String expression}) {
    return '「$expression」をコピーしました';
  }

  @override
  String get dictionaryWordAlreadyExistsInAnki => 'この単語はすでにデフォルトのデッキにあります';

  @override
  String dictionaryAddedToAnki({required String expression}) {
    return '「$expression」をAnkiに追加しました';
  }

  @override
  String dictionarySentToAnkiMobile({required String expression}) {
    return '「$expression」をAnkiMobileに送信しました';
  }

  @override
  String get dictionaryCopyTooltip => 'コピー';

  @override
  String get dictionaryAlreadyInAnkiTooltip => 'Ankiのデフォルトデッキに登録済み。長押しでそのまま追加';

  @override
  String get dictionaryCheckingAnkiTooltip => 'Ankiのデフォルトデッキを確認中';

  @override
  String dictionarySendToAnkiTooltip({required String app}) {
    return '$appに送信';
  }

  @override
  String get dictionaryAlreadyInVocabTooltip => '単語帳に保存済み';

  @override
  String get dictionarySaveToVocabularyTooltip => '単語帳に保存';

  @override
  String get dictionaryVeryCommon => '最頻出';

  @override
  String get dictionaryCommon => '頻出';

  @override
  String get dictionaryUncommon => '低頻度';

  @override
  String get dictionaryRare => 'まれ';

  @override
  String get dictionaryOnyomiLabel => '音読み：';

  @override
  String get dictionaryKunyomiLabel => '訓読み：';

  @override
  String dictionaryKanjiStrokeCount({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count画',
      one: '$count画',
    );
    return '$_temp0';
  }

  @override
  String get dictionaryAnimateStrokeOrderTooltip => '書き順を再生';

  @override
  String get vocabularySearchSavedWordsHint => '保存した単語を検索';

  @override
  String get vocabularyExportCsvTooltip => 'CSVをエクスポート';

  @override
  String get vocabularyEmptyTitle => '保存した単語はまだありません';

  @override
  String get vocabularyEmptySubtitle => '辞書検索や読書中に単語を保存すると、文脈と一緒にここに表示されます。';

  @override
  String vocabularyNoMatches({required String query}) {
    return '「$query」に一致する単語はありません';
  }

  @override
  String get vocabularyNoMatchesSubtitle => '見出し語、読み、意味の一部で検索してみてください。';

  @override
  String vocabularySelectedCount({required int count}) {
    return '$count件を選択中';
  }

  @override
  String get vocabularyDeselectAllTooltip => 'すべての選択を解除';

  @override
  String get vocabularySelectAllTooltip => 'すべて選択';

  @override
  String get vocabularyExportSelectedTooltip => '選択した単語をエクスポート';

  @override
  String get vocabularyCsvExported => 'CSVをエクスポートしました';

  @override
  String get vocabularyNoDefinition => '意味なし';

  @override
  String get vocabularyContextLabel => '文脈：';

  @override
  String vocabularyAddedOn({required String date}) {
    return '追加日：$date';
  }

  @override
  String vocabularyDeletedWord({required String expression}) {
    return '「$expression」を削除しました';
  }

  @override
  String ocrPagesProgress({required int completed, required int total}) {
    return '$completed/$totalページ';
  }

  @override
  String ocrEtaSecondsRemaining({required int seconds}) {
    return '残り約$seconds秒';
  }

  @override
  String ocrEtaMinutesRemaining({required int minutes}) {
    return '残り約$minutes分';
  }

  @override
  String ocrEtaHoursMinutesRemaining({
    required int hours,
    required int minutes,
  }) {
    return '残り約$hours時間$minutes分';
  }

  @override
  String get ocrPaused => 'OCR一時停止中';

  @override
  String get ocrComplete => 'OCR完了';

  @override
  String get ocrFailed => 'OCR失敗';

  @override
  String get ocrTapForDetails => 'タップして詳細を表示';

  @override
  String get ocrCustomServerRequiredTitle => 'カスタムOCRサーバーが必要';

  @override
  String get ocrCustomServerRequiredBody =>
      'リモートでのマンガOCRは、ご自身のサーバーを使う方式になりました。設定を開き、カスタムOCRサーバーのURLと対応する共有キーを追加してください。';

  @override
  String get ocrCustomServerKeyRequiredTitle => 'カスタムサーバーの設定が必要';

  @override
  String get ocrCustomServerKeyRequiredBody =>
      'カスタムOCRサーバーには共有キーが必要です。「カスタムOCRサーバー」の設定を開き、サーバーに設定したものと同じAUTH_API_KEYの値を入力してください。';

  @override
  String get proTitle => 'Pro';

  @override
  String get proPurchaseConfirmed => '購入が確認されました！';

  @override
  String get proUnlockOnceTitle => '買い切りでProをアンロック';

  @override
  String get proStatusUnlocked => 'アンロック済み';

  @override
  String get proStatusLocked => 'ロック中';

  @override
  String get proUnlockDescription => '読書をもっと便利にする機能を、一度の購入で使えるようになります。';

  @override
  String get proRestorePurchase => '購入を復元';

  @override
  String get proFeatureAutoCropTitle => '自動トリミング';

  @override
  String get proFeatureAutoCropDescription =>
      '本ごとに一度設定するだけで、マンガのページの余白を自動でトリミングします。';

  @override
  String get proFeatureHighlightsTitle => '本のハイライト';

  @override
  String get proFeatureHighlightsDescription =>
      'EPUBの本を読みながら気になった箇所をハイライトして保存し、あとで見返せます。';

  @override
  String get proFeatureLocalOcrTitle => '端末内OCR';

  @override
  String get proFeatureLocalOcrDescription =>
      'kha-whiteのmanga-ocrモデルとComic Text Detectorを使い、スマートフォン上でオフラインでマンガの文字を認識します。処理の負荷が高いため、速度はスマートフォンによって大きく異なり、バッテリーも消費します。購入前にお使いの端末でテストしてください。';

  @override
  String get proFeatureLocalOcrDescriptionIos =>
      'Appleの文字認識を使い、端末上でオフラインでマンガの文字を認識します。Mekuruを離れてもスキャンは続き、iOSに停止された場合は一時停止します。';

  @override
  String get proFeatureCustomOcrTitle => 'OCRサーバー連携';

  @override
  String get proFeatureCustomOcrDescription =>
      'ご自身のサーバーと共有キーで、リモートでマンガOCRを実行します。';

  @override
  String get proServerRepo => 'リポジトリ';

  @override
  String get proAlreadyUnlocked => 'アンロック済み';

  @override
  String get proActiveTitle => 'Mekuru Proをご利用中';

  @override
  String get proActiveSubtitle => 'この端末で購入が有効になっています。すべてのPro機能をご利用いただけます。';

  @override
  String get proUnlock => 'Proをアンロック';

  @override
  String proUnlockWithPrice({required String price}) {
    return '$priceでProをアンロック';
  }

  @override
  String get downloadsTitle => 'ダウンロード';

  @override
  String get downloadsRecommendedStarterPackTitle => 'おすすめのスターターパック';

  @override
  String get downloadsRecommendedStarterPackSubtitle =>
      'Jitendexと単語の頻度データをまとめてインストールすれば、すぐに使い始められます。';

  @override
  String get downloadsStarterPackJmdict => 'JMdict（英語）';

  @override
  String get downloadsStarterPackWordFrequency => '単語の頻度';

  @override
  String downloadsStarterPackMobileDataBody({required String size}) {
    return '辞書のサイズは約$sizeです。モバイルデータ通信またはテザリングを使用中のため、ダウンロードするとデータ通信量を消費する場合があります。';
  }

  @override
  String get downloadsInstallStarterPack => 'スターターパックをインストール';

  @override
  String get downloadsSectionDictionaries => '辞書';

  @override
  String get downloadsSectionAssets => '追加データ';

  @override
  String downloadsDownloadingPercent({required int percent}) {
    return 'ダウンロード中… $percent%';
  }

  @override
  String get downloadsImporting => 'インポート中…';

  @override
  String get downloadsExtractingFiles => 'ファイルを展開中…';

  @override
  String get downloadsJpdbAttribution =>
      '単語の頻度データはJPDB（jpdb.io）のもので、Kuuuubeが配布しています。';

  @override
  String get commonListSeparator => '、';

  @override
  String get downloadsEdrdgAttributionSuffix =>
      '：電子辞書研究開発グループ（EDRDG）作成、CC BY-SA 4.0ライセンス。';

  @override
  String get downloadsKanjiVgAttributionPrefix => '漢字の書き順データ：';

  @override
  String get downloadsKanjiVgAttributionSuffix =>
      '（Ulrich Apel）、CC BY-SA 3.0ライセンス。';

  @override
  String get downloadsUniDicAttributionPrefix => '形態素解析：';

  @override
  String get downloadsUniDicAttributionSuffix =>
      '（国立国語研究所）、BSD/GPL/LGPLのトリプルライセンスで配布。';

  @override
  String get downloadsKanjiStrokeOrderTitle => '漢字の書き順';

  @override
  String downloadsKanjiStrokeOrderDownloaded({required int count}) {
    return '$count件の書き順ファイルをダウンロード済み';
  }

  @override
  String get downloadsKanjiStrokeOrderDescription =>
      'KanjiVGから漢字の書き順データをダウンロード';

  @override
  String downloadsKanjiStrokeOrderMobileDataBody({required String size}) {
    return '書き順データのサイズは約$sizeです。モバイルデータ通信またはテザリングを使用中のため、ダウンロードするとデータ通信量を消費する場合があります。';
  }

  @override
  String get downloadsDeleteKanjiDataTooltip => '漢字データを削除';

  @override
  String get downloadsDeleteKanjiDataTitle => '漢字データを削除';

  @override
  String get downloadsDeleteKanjiDataBody =>
      'ダウンロードした漢字の書き順ファイルをすべて削除しますか？あとで再ダウンロードできます。';

  @override
  String get downloadsWordFrequencyDownloaded => '頻度データをダウンロード済み';

  @override
  String get downloadsWordFrequencyDescription => '検索結果の並べ替えに使う単語の頻度データをダウンロード';

  @override
  String get downloadsDeleteFrequencyDataTooltip => '頻度データを削除';

  @override
  String get downloadsDeleteFrequencyDataTitle => '頻度データを削除';

  @override
  String get downloadsDeleteFrequencyDataBody =>
      '単語の頻度データを削除しますか？検索結果が頻度順に並ばなくなります。あとで再ダウンロードできます。';

  @override
  String get downloadsJmdictDownloaded => '和英辞書をダウンロード済み';

  @override
  String get downloadsJmdictDescription => '和英辞書をダウンロード';

  @override
  String get downloadsDeleteJmdictTooltip => 'JMdictを削除';

  @override
  String get downloadsChooseJmdictVariant => 'JMdictの種類を選択';

  @override
  String get downloadsJmdictStandardSubtitle => '標準の辞書（約15 MB）';

  @override
  String get downloadsJmdictExamplesTitle => 'JMdict 英語版（例文付き）';

  @override
  String get downloadsJmdictExamplesSubtitle => '例文を収録（約18 MB）';

  @override
  String get downloadsDeleteJmdictTitle => 'JMdictを削除';

  @override
  String get downloadsDeleteJmdictBody =>
      'JMdictとそのすべての項目を削除しますか？後で再ダウンロードできます。';

  @override
  String get downloadsKanjidicDownloaded => '漢字辞書をダウンロード済み';

  @override
  String get downloadsKanjidicDescription => '漢字辞書をダウンロード';

  @override
  String get downloadsDeleteKanjidicTooltip => 'KANJIDICを削除';

  @override
  String get downloadsDeleteKanjidicTitle => 'KANJIDICを削除';

  @override
  String get downloadsDeleteKanjidicBody =>
      'KANJIDICとそのすべての項目を削除しますか？後で再ダウンロードできます。';

  @override
  String get downloadsEnhancedFuriganaTitle => '拡張ふりがな辞書';

  @override
  String get downloadsEnhancedFuriganaInstalled =>
      '有効です。変更が反映されない場合はアプリを再起動してください。';

  @override
  String get downloadsEnhancedFuriganaUseTitle => '強化辞書を使用';

  @override
  String get downloadsEnhancedFuriganaUseSubtitle =>
      '読みの精度にのみ影響し、ふりがなの表示・非表示は変わりません。単語をタップしても反応しなくなった場合はオフにしてください。ダウンロードしたデータは残るので、いつでも再びオンにできます。適用するにはアプリを再起動してください。';

  @override
  String get downloadsEnhancedFuriganaDescription =>
      '自動生成されるふりがなと辞書検索の読みの精度を高めます（約10,000語を追加）。ふりがなのオン/オフは切り替わりません。ダウンロード45 MB、保存容量250 MB。';

  @override
  String get downloadsEnhancedFuriganaRemoveTooltip => '強化辞書を削除';

  @override
  String downloadsEnhancedFuriganaDownloadingPercent({required int percent}) {
    return '強化辞書をダウンロード中… $percent%';
  }

  @override
  String get downloadsEnhancedFuriganaExtracting => '展開中…';

  @override
  String get downloadsEnhancedFuriganaConfirmRemoveTitle => '強化辞書を削除しますか？';

  @override
  String get downloadsEnhancedFuriganaConfirmRemoveBody =>
      '約250 MBのストレージが空きます。次回の起動からは内蔵の辞書が使われます。この画面から後で再ダウンロードできます。';

  @override
  String get commonClear => 'クリア';

  @override
  String get commonShow => '表示';

  @override
  String get commonHide => '非表示';

  @override
  String get commonSubmit => '送信';

  @override
  String get commonLoading => '読み込み中…';

  @override
  String get commonError => 'エラー';

  @override
  String get commonRestore => '復元';

  @override
  String get settingsTitle => '設定';

  @override
  String get settingsSectionGeneral => '一般';

  @override
  String get settingsAppLanguageTitle => 'アプリの言語';

  @override
  String settingsAppLanguageSystemValue({required String language}) {
    return 'システム設定に従う（$language）';
  }

  @override
  String get settingsAppLanguageEnglish => 'English';

  @override
  String get settingsAppLanguageSpanish => 'Español';

  @override
  String get settingsAppLanguageIndonesian => 'Bahasa Indonesia';

  @override
  String get settingsAppLanguageJapanese => '日本語';

  @override
  String get settingsAppLanguageSimplifiedChinese => '简体中文';

  @override
  String get settingsSectionAppearance => '外観';

  @override
  String get settingsSectionDictionary => '辞書';

  @override
  String get settingsSectionVocabularyExport => '単語帳とエクスポート';

  @override
  String get settingsSectionServerSync => 'サーバー同期';

  @override
  String get settingsServerSyncTitle => '書籍サーバー';

  @override
  String get settingsServerSyncSubtitle => 'KomgaまたはKavitaを閲覧・同期';

  @override
  String get settingsSectionPro => 'Pro';

  @override
  String get settingsSectionDownloads => 'ダウンロード';

  @override
  String get settingsSectionBackupRestore => 'バックアップと復元';

  @override
  String get settingsSectionAboutFeedback => 'アプリ情報とフィードバック';

  @override
  String get settingsStartupScreenTitle => '起動時の画面';

  @override
  String get settingsStartupScreenLastRead => '最後に読んだ本';

  @override
  String get settingsThemeTitle => 'テーマ';

  @override
  String get settingsThemeLight => 'ライト';

  @override
  String get settingsThemeDark => 'ダーク';

  @override
  String get settingsThemeSystemDefault => 'システム設定に従う';

  @override
  String get settingsColorThemeTitle => 'カラーテーマ';

  @override
  String get settingsPureBlackTitle => 'ダークテーマを純黒にする';

  @override
  String get settingsPureBlackSubtitle =>
      'AMOLED画面向け：ダークモードとリーダーのダーク表示で背景を真っ黒にします';

  @override
  String get settingsColorThemeMekuruRed => 'Mekuruレッド';

  @override
  String get settingsColorThemeIndigo => 'インディゴ';

  @override
  String get settingsColorThemeTeal => 'ティール';

  @override
  String get settingsColorThemeDeepPurple => 'ディープパープル';

  @override
  String get settingsColorThemeBlue => 'ブルー';

  @override
  String get settingsColorThemeGreen => 'グリーン';

  @override
  String get settingsColorThemeOrange => 'オレンジ';

  @override
  String get settingsColorThemePink => 'ピンク';

  @override
  String get settingsColorThemeBlueGrey => 'ブルーグレー';

  @override
  String get settingsFontSizeTitle => '文字サイズ';

  @override
  String settingsPointsValue({required int points}) {
    return '$points pt';
  }

  @override
  String get settingsColorModeTitle => 'カラーモード';

  @override
  String get settingsColorModeNormal => '標準';

  @override
  String get settingsColorModeSepia => 'セピア';

  @override
  String get settingsColorModeDark => 'ダーク';

  @override
  String get settingsFontFamilyTitle => 'フォント';

  @override
  String get settingsFontFamilyBook => '本の指定フォント';

  @override
  String get settingsFontFamilyMincho => '明朝体';

  @override
  String get settingsFontFamilyGothic => 'ゴシック体';

  @override
  String get settingsFontAdd => 'フォントを追加…';

  @override
  String get settingsFontAddNotAFont => 'このファイルはフォントではありません。';

  @override
  String get settingsFontAddCollection =>
      'フォントコレクション（.ttc）には対応していません。.ttfまたは.otfファイルを選択してください。';

  @override
  String get settingsFontAddTooLarge => 'このフォントはサイズが大きすぎます（29.99 MB超）。';

  @override
  String get settingsFontAddFailed => 'このフォントを追加できませんでした。';

  @override
  String get settingsFontRemoveTooltip => 'フォントを削除';

  @override
  String get settingsFontRemoveTitle => 'フォントを削除しますか？';

  @override
  String settingsFontRemoveBody({required String name}) {
    return '「$name」をMekuruから削除します。追加元のファイルには影響しません。';
  }

  @override
  String get settingsSepiaIntensityTitle => 'セピアの濃さ';

  @override
  String get settingsKeepScreenOnTitle => '画面をオンのままにする';

  @override
  String get settingsKeepScreenOnSubtitle => '読書中は画面をスリープさせない';

  @override
  String settingsHorizontalMarginValue({required int pixels}) {
    return '左右の余白：${pixels}px';
  }

  @override
  String settingsVerticalMarginValue({required int pixels}) {
    return '上下の余白：${pixels}px';
  }

  @override
  String get settingsSwipeSensitivityTitle => 'スワイプの感度';

  @override
  String settingsPercentValue({required int percent}) {
    return '$percent%';
  }

  @override
  String get settingsSwipeSensitivityHint => '低いほど、少ない指の動きでスワイプできます';

  @override
  String get settingsManageDictionariesSubtitle => 'インポート、並べ替え、オン/オフ';

  @override
  String get settingsLookupFontSizeTitle => '辞書検索の文字サイズ';

  @override
  String get settingsFilterRomanLetterEntriesTitle => 'アルファベットの項目を除外';

  @override
  String get settingsFilterRomanLetterEntriesSubtitle => '見出し語にアルファベットを含む項目を隠す';

  @override
  String get settingsAutoFocusSearchTitle => '検索欄に自動フォーカス';

  @override
  String get settingsAutoFocusSearchSubtitle => '辞書タブを選んだときにキーボードを表示します';

  @override
  String settingsAnkiDroidIntegrationTitle({required String app}) {
    return '$app連携';
  }

  @override
  String get settingsAnkiDroidIntegrationSubtitle => 'ノートタイプ、デッキ、フィールドを設定';

  @override
  String get settingsProUnavailableSubtitle => 'Proサービスは一時的に利用できません。';

  @override
  String get settingsProSubtitle => '自動トリミング、本のハイライト、マンガのOCRをアンロック';

  @override
  String get settingsWhiteThresholdTitle => '白のしきい値';

  @override
  String settingsWhiteThresholdSubtitle({required int threshold}) {
    return '$threshold（低いほど白に近いノイズを多く無視します）';
  }

  @override
  String get settingsCustomOcrServerTitle => 'カスタムOCRサーバー';

  @override
  String get settingsCustomOcrServerUnavailableSubtitle =>
      'OCRサービスは一時的に利用できません。';

  @override
  String get settingsCustomOcrServerNotConfigured =>
      '未設定です。独自のサーバーURLと共有キーを追加してください。';

  @override
  String settingsCustomOcrServerConfigured({required String url}) {
    return '$url\nサーバーで設定したものと同じ共有キーを使用してください。';
  }

  @override
  String get settingsCustomOcrServerUrlLabel => 'サーバーURL';

  @override
  String get settingsCustomOcrServerUrlHint => 'http://192.168.1.100:8000';

  @override
  String get settingsCustomOcrServerLearnHow => '独自のサーバーを立てる方法';

  @override
  String get settingsCustomOcrServerTestAction => '接続をテスト';

  @override
  String get settingsCustomOcrServerTesting => '接続をテスト中…';

  @override
  String settingsCustomOcrServerHealthy({required String status}) {
    return '接続しました。/healthの応答ステータス：$status。';
  }

  @override
  String get settingsCustomOcrServerKeyLabel => 'カスタム共有キー';

  @override
  String get settingsCustomOcrServerKeyHint => 'AUTH_API_KEY（必須）';

  @override
  String get settingsCustomOcrServerDescription =>
      'OCRサーバーで使用しているものと同じ共有AUTH_API_KEYを入力してください。Mekuruはリモートでのマンガ OCRリクエストの際に、これをAuthorization: Bearer <key>として送信します。';

  @override
  String get settingsCustomOcrServerUrlRequired => 'サーバーURLを入力してください。';

  @override
  String get settingsCustomOcrServerUrlInvalid =>
      'http://またはhttps://で始まる完全なサーバーURLを入力してください。';

  @override
  String get settingsCustomOcrServerUrlSpacesOrSymbols =>
      'サーバーのアドレスからスペースや< >などの記号を削除してください。';

  @override
  String get settingsCustomOcrServerAllowSelfSigned => '自己署名証明書を許可';

  @override
  String get settingsCustomOcrServerAllowSelfSignedSubtitle =>
      '独自の証明書を使うhttps://サーバー向けです。オンにすると、Mekuruはこのサーバーが提示するすべての証明書を受け入れます。';

  @override
  String get settingsCustomOcrServerKeyRequired => 'カスタムサーバーには共有キーが必要です。';

  @override
  String get settingsDownloadsSubtitle => '辞書、漢字データなど';

  @override
  String get settingsBackupRestoreTitle => 'バックアップと復元';

  @override
  String get settingsBackupRestoreSubtitle => 'データのバックアップと復元';

  @override
  String get settingsSendFeedbackSubtitle => '不具合の報告や機能の提案';

  @override
  String get settingsFeedbackThanks => 'フィードバックをありがとうございます！';

  @override
  String get settingsFeedbackFailed => 'フィードバックを送信できませんでした。もう一度お試しください。';

  @override
  String get settingsRateMekuruTitle => 'Mekuruを評価';

  @override
  String get settingsRateMekuruSubtitle => '気に入ったらレビューをお願いします';

  @override
  String get settingsDocumentationTitle => 'ドキュメント';

  @override
  String get settingsDocumentationSubtitle => 'ガイドと使い方の記事';

  @override
  String get settingsAboutMekuruTitle => 'Mekuruについて';

  @override
  String get settingsAboutMekuruSubtitle => 'バージョン、ライセンスなど';

  @override
  String get feedbackTitle => 'フィードバックを送信';

  @override
  String get feedbackNameLabel => '名前';

  @override
  String get feedbackNameHint => 'お名前';

  @override
  String get feedbackEmailLabel => 'メールアドレス';

  @override
  String get feedbackEmailHint => 'your@email.com';

  @override
  String get feedbackMessageLabel => 'メッセージ';

  @override
  String get feedbackRequired => '（必須）';

  @override
  String get feedbackMessageHint => '不具合の内容や機能のご要望を入力してください…';

  @override
  String get feedbackMessageRequiredError => 'メッセージを入力してください';

  @override
  String get backupTitle => 'バックアップと復元';

  @override
  String get backupSectionBackup => '読書データのバックアップ';

  @override
  String get backupCreateNowTitle => '読書データのバックアップを作成';

  @override
  String get backupCreateNowSubtitle =>
      '設定、読書の進捗、ブックマーク、ハイライト、単語帳、統計を小さな.mekuruファイルに保存します。本、マンガ、辞書は含まれません。';

  @override
  String get backupExportTitle => 'バックアップをエクスポート（.mekuru）';

  @override
  String get backupExportSubtitle => '最新の読書データのバックアップを、選んだ場所にファイルとして保存します。';

  @override
  String get backupSaveFileDialogTitle => '読書データのバックアップを保存';

  @override
  String get backupScopeNoteTitle => '2種類のバックアップ';

  @override
  String get backupScopeNoteBody =>
      '読書データのバックアップ（.mekuru）：設定、辞書の並び順、ブックマーク、ハイライト、単語帳、読書統計を含む小さなファイルです。インポートすると、Mekuruにある既存のデータに統合されます。完全バックアップ（.zip）：本、マンガ、辞書を含むすべてのデータです。復元すると、この端末のMekuruのデータがすべて置き換えられます。';

  @override
  String get backupScopeNoteRestore =>
      '読書データをインポートした後、同じEPUBやマンガを再インポートすると、その履歴が戻ります。読書時間の履歴は、この端末にまだ履歴がない場合にのみ復元されます。単語の統計は統合されます。一致する辞書の設定は、後で「辞書の管理」から適用できます。';

  @override
  String get backupSectionAutoBackup => '読書データの自動バックアップ';

  @override
  String get backupAutoBackupIntervalTitle => '自動バックアップの間隔';

  @override
  String get backupIntervalOff => 'オフ';

  @override
  String get backupIntervalDaily => '毎日';

  @override
  String get backupIntervalWeekly => '毎週';

  @override
  String get backupSectionRestore => '読書データの復元';

  @override
  String get backupImportFileTitle => '読書データをインポート（.mekuru）';

  @override
  String get backupImportFileSubtitle =>
      '.mekuruファイルの設定、進捗、ブックマーク、ハイライト、単語帳をMekuruに統合します。同じEPUBやマンガを再インポートすると、その履歴が戻ります。';

  @override
  String get backupSectionHistory => '読書データのバックアップ履歴';

  @override
  String get backupNoBackupsYet => '読書データのバックアップはまだありません';

  @override
  String backupErrorLoadingHistory({required String details}) {
    return 'バックアップを読み込めませんでした：$details';
  }

  @override
  String get backupCreatedSuccess => '読書データのバックアップを作成しました';

  @override
  String backupFailed({required String details}) {
    return 'バックアップに失敗しました：$details';
  }

  @override
  String get backupNoBackupsToExport =>
      'エクスポートできる読書データのバックアップがありません。先に作成してください。';

  @override
  String get backupExportedSuccess => '読書データのバックアップをエクスポートしました';

  @override
  String backupExportFailed({required String details}) {
    return 'エクスポートに失敗しました：$details';
  }

  @override
  String get backupInvalidFile => '.mekuru形式の読書データのバックアップファイルを選択してください。';

  @override
  String backupCouldNotOpenFile({required String details}) {
    return 'ファイルを開けませんでした：$details';
  }

  @override
  String backupRestoreFailed({required String details}) {
    return '復元に失敗しました：$details';
  }

  @override
  String backupBooksUpdatedFromBackup({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count冊の本をバックアップから更新しました',
      one: '$count冊の本をバックアップから更新しました',
    );
    return '$_temp0';
  }

  @override
  String backupApplyBookDataFailed({required String details}) {
    return '本のデータを適用できませんでした：$details';
  }

  @override
  String get backupConflictDialogTitle => '競合する本';

  @override
  String get backupConflictDialogBody =>
      '次の本にはすでに読書データがあります。バックアップのデータで上書きする本を選択してください：';

  @override
  String backupConflictEntrySubtitle({
    required String bookType,
    required int progress,
  }) {
    return '$bookType - バックアップの進捗 $progress%';
  }

  @override
  String get backupConflictSkipAll => 'すべてスキップ';

  @override
  String backupConflictOverwriteSelected({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count冊を上書き',
      one: '$count冊を上書き',
    );
    return '$_temp0';
  }

  @override
  String get backupBookTypeEpub => 'EPUB';

  @override
  String get backupBookTypeManga => 'マンガ';

  @override
  String get backupRestoreSummarySettingsRestored => '設定を復元しました';

  @override
  String get backupRestoreSummarySettingsPartial => '一部の設定を復元できませんでした';

  @override
  String backupRestoreSummaryWords({required int added, required int skipped}) {
    return '$added語を追加、$skipped語をスキップ';
  }

  @override
  String backupRestoreSummaryBooksRestored({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count冊の本を復元しました',
      one: '$count冊の本を復元しました',
    );
    return '$_temp0';
  }

  @override
  String backupRestoreSummaryBooksPending({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count冊の本が、同じEPUBまたはマンガの再インポート待ちです',
      one: '$count冊の本が、同じEPUBまたはマンガの再インポート待ちです',
    );
    return '$_temp0';
  }

  @override
  String get backupRestoreComplete => '復元が完了しました';

  @override
  String get backupRestoreDialogTitle => '読書データをインポートしますか？';

  @override
  String backupRestoreDialogBody({required String fileName}) {
    return '$fileNameの設定と読書データ（ブックマーク、ハイライト、単語帳、進捗）をMekuruに統合します。本、マンガ、辞書ファイルは復元されません。インポート後、同じEPUBやマンガを再インポートすると、その履歴が戻ります。読書時間の履歴は、この端末にまだ履歴がない場合にのみ復元されます。単語の統計は統合されます。現在の設定は上書きされます。';
  }

  @override
  String get backupQueueDictionaryPreferencesTitle => 'このバックアップの辞書設定を保存して後で適用';

  @override
  String get backupQueueDictionaryPreferencesBody =>
      '一致する辞書の並び順と有効/無効の状態を、後で「辞書の管理」から適用できます。';

  @override
  String backupRestoreSummaryDictionaryPreferencesQueued({
    required int matching,
    required int missing,
  }) {
    return '辞書設定を保存しました：$matching件は適用可能、$missing件は見つからないためスキップされます';
  }

  @override
  String get backupRestoreSummaryDictionaryPreferencesSkipped =>
      '辞書設定は保存されませんでした';

  @override
  String get backupDeleteDialogTitle => 'バックアップを削除しますか？';

  @override
  String backupDeleteDialogBody({required String fileName}) {
    return '$fileNameを削除しますか？この操作は取り消せません。';
  }

  @override
  String get backupHistoryTypeAuto => '自動バックアップ';

  @override
  String get backupHistoryTypeManual => '手動バックアップ';

  @override
  String get readerDismiss => '閉じる';

  @override
  String readerFailedToLoadContent({required String details}) {
    return 'EPUBの内容を読み込めませんでした。\n$details';
  }

  @override
  String readerFailedToLoad({required String details}) {
    return 'EPUBを読み込めませんでした。\n$details';
  }

  @override
  String get readerLoadTimeout =>
      'リーダーの読み込みに時間がかかっています。「再試行」をタップしてもう一度お試しください。';

  @override
  String get readerUserFontFailed => 'このフォントを読み込めなかったため、本のフォントで表示しています。';

  @override
  String get readerVerticalTextNonNativeWarning =>
      'この本は元々縦書き用に作られていません。表示が崩れる場合があります。';

  @override
  String get readerHorizontalTextNonNativeWarning =>
      'この本は元々縦書き用に作られています。横書きでは表示が崩れる場合があります。';

  @override
  String get readerBookmarkRemoved => 'ブックマークを削除しました';

  @override
  String get readerDictionaryLoading => '辞書を読み込み中です。しばらくしてからもう一度お試しください。';

  @override
  String get readerDictionaryUnavailable =>
      '辞書を読み込めませんでした。アプリを再起動してもう一度お試しください。';

  @override
  String get readerPageBookmarked => 'ページをブックマークしました';

  @override
  String get readerTableOfContents => '目次';

  @override
  String get readerRemoveBookmarkTooltip => 'ブックマークを削除';

  @override
  String get readerBookmarkPageTooltip => 'ページをブックマーク';

  @override
  String get readerViewBookmarksTooltip => 'ブックマーク一覧';

  @override
  String get readerHighlightsTooltip => 'ハイライト';

  @override
  String get readerUnknownError => 'リーダーで不明なエラーが発生しました。';

  @override
  String get readerQuickSettings => 'クイック設定';

  @override
  String get readerBrightnessFollowSystem => 'システムの明るさに合わせる';

  @override
  String get readerBrightnessTitle => '明るさ';

  @override
  String get readerSettingsSectionDisplay => '表示';

  @override
  String get readerSettingsSectionBehavior => '動作';

  @override
  String get readerFuriganaTitle => 'ふりがな';

  @override
  String get readerFuriganaOff => 'オフ';

  @override
  String get readerFuriganaBook => '本のまま';

  @override
  String get readerFuriganaAllKanji => 'すべての漢字';

  @override
  String get readerFuriganaAboveLevel => 'JLPT';

  @override
  String get readerFuriganaJlptLevelTitle => 'このレベルより上の漢字にふりがな';

  @override
  String get readerAllSettingsTooltip => 'すべての設定';

  @override
  String get mangaSettingsSectionReading => '読書';

  @override
  String get mangaSettingsSectionImage => '画像';

  @override
  String get mangaSettingsSectionLookup => '辞書検索';

  @override
  String get mangaViewModeTitle => '表示モード';

  @override
  String get readerAnimationsTitle => 'アニメーション';

  @override
  String get readerAnimationsSubtitle => '電子ペーパー端末ではオフを推奨';

  @override
  String get settingsReadingTitle => 'リーダー設定';

  @override
  String get settingsSectionReading => '読書';

  @override
  String get settingsReadingSubtitle => '文字サイズ、色、余白、マンガ設定';

  @override
  String get settingsReadingSectionShared => 'すべての本';

  @override
  String get settingsReadingSectionEpub => 'EPUB';

  @override
  String get settingsReadingSectionManga => 'マンガ';

  @override
  String get readerVerticalTextTitle => '縦書き';

  @override
  String get readerSplitVerticalTextTitle => '縦書きを分割';

  @override
  String get readerSplitVerticalTextSubtitle => '1ページを上下2段に分けて表示';

  @override
  String get readerScrollViewTitle => 'スクロール表示';

  @override
  String get readerScrollViewSubtitle => 'ページをめくらず、章をスクロールして読む';

  @override
  String get readerThisBook => 'この本';

  @override
  String get readerVerticalTextUnavailable => 'この本の言語では使用できません';

  @override
  String get readerReadingDirectionTitle => '読む方向';

  @override
  String get readerReadingDirectionRtl => '右から左';

  @override
  String get readerReadingDirectionLtr => '左から右';

  @override
  String get readerDisableLinksTitle => 'リンクを無効化';

  @override
  String get readerDisableLinksSubtitle => 'リンク先に移動せず、タップした単語を調べる';

  @override
  String get readerHighlightSelectionTooltip => '選択範囲をハイライト';

  @override
  String get commonCopy => 'コピー';

  @override
  String get commonShare => '共有';

  @override
  String get commonContinue => '続ける';

  @override
  String get commonNotSelected => '未選択';

  @override
  String get commonUnknown => '不明';

  @override
  String get commonRename => '名前を変更';

  @override
  String get commonTitleLabel => 'タイトル';

  @override
  String libraryCouldNotReadFolder({required String details}) {
    return 'フォルダを読み込めませんでした：\n$details';
  }

  @override
  String get libraryBookmarksTitle => 'ブックマーク';

  @override
  String get libraryChangeCoverAction => '表紙を変更';

  @override
  String get libraryExportFuriganaTitle => 'EPUBとしてエクスポート';

  @override
  String get libraryExportFuriganaDialogTitle => 'エクスポートする本のふりがな';

  @override
  String get libraryExportFuriganaMatchBook => '出版時のまま';

  @override
  String get libraryExportFuriganaAboveLevel => 'JLPTレベルより上の漢字';

  @override
  String get libraryExportFuriganaNone => 'なし（既存のふりがなも削除）';

  @override
  String get libraryExportFuriganaAction => 'エクスポート';

  @override
  String get libraryExportFuriganaProgress => 'EPUBを準備中…';

  @override
  String get libraryExportFuriganaSaveTitle => 'EPUBを保存';

  @override
  String get libraryExportFuriganaDone => 'EPUBをエクスポートしました';

  @override
  String get libraryExportFuriganaUnavailable =>
      'ふりがなエンジンを使用できません。しばらくしてからもう一度お試しください。';

  @override
  String get libraryConvertToMangaTitle => 'マンガに変換';

  @override
  String get libraryConvertToMangaSubtitle => '全ページが画像のマンガEPUB向け';

  @override
  String get libraryConvertToMangaConfirmTitle => 'マンガに変換しますか？';

  @override
  String get libraryConvertToMangaConfirmBody =>
      '変換後はマンガリーダーで開きますが、ページにOCRを実行するまでタップでの辞書検索は使えません。本のメニューからMekuru Proのセルフホストサーバーを使ってOCRを実行するか、本をCBZとしてエクスポートしてmokuroで処理してください。アプリ内に保存されているEPUBは削除され、読書位置はリセットされます。元に戻すには、元のファイルをもう一度インポートしてください。';

  @override
  String get libraryConvertToMangaAction => '変換';

  @override
  String get libraryConvertToMangaProgress => '変換中…';

  @override
  String get libraryConvertToMangaDone => 'マンガに変換しました';

  @override
  String get libraryConvertToMangaNotEligible =>
      'このEPUBはマンガではないようです。各ページが1枚の画像になっていません';

  @override
  String get libraryExportCbzTitle => 'CBZとしてエクスポート';

  @override
  String get libraryExportCbzSubtitle => 'ページ画像をコミックアーカイブとして共有';

  @override
  String get libraryExportCbzProgress => 'CBZを準備中…';

  @override
  String get libraryExportCbzDone => 'CBZをエクスポートしました';

  @override
  String get libraryExportCbzEmpty => 'エクスポートするページがありません';

  @override
  String get libraryExportCbzSafUnsupported =>
      'この本の画像はアプリの外に保存されているため、エクスポートできません';

  @override
  String get libraryFolderEmpty =>
      'まだ本がありません。ライブラリで本を長押しして「コレクションに追加」を選んでください。';

  @override
  String get librarySelectTooltip => '選択';

  @override
  String librarySelectedCount({required int count}) {
    return '$count冊を選択中';
  }

  @override
  String get librarySelectAllTooltip => 'すべて選択';

  @override
  String get libraryDeselectAllTooltip => '選択をすべて解除';

  @override
  String get libraryRemoveFromFolderAction => 'このフォルダから外す';

  @override
  String get commonAdd => '追加';

  @override
  String get libraryAddToCollectionAction => 'コレクションに追加';

  @override
  String get libraryNewCollectionAction => '新しいコレクション';

  @override
  String get libraryCollectionNameLabel => '名前';

  @override
  String get libraryRenameCollectionTitle => 'コレクション名を変更';

  @override
  String get libraryDeleteCollectionConfirmTitle => 'コレクションを削除しますか？';

  @override
  String libraryDeleteCollectionConfirmBody({required String name}) {
    return '「$name」を削除します。本はライブラリに残ります。';
  }

  @override
  String libraryRemoveFromFolderConfirmTitle({required int count}) {
    return '$count冊の本をこのフォルダから外しますか？';
  }

  @override
  String get libraryRemoveFromFolderConfirmBody => '本はライブラリに残ります。';

  @override
  String get commonRemove => '外す';

  @override
  String get libraryRenameBookTitle => '本の名前を変更';

  @override
  String get libraryDeleteBookTitle => '本を削除';

  @override
  String libraryDeleteBookBody({required String title}) {
    return '「$title」をライブラリから削除しますか？';
  }

  @override
  String libraryChangeCoverFailed({required String details}) {
    return '表紙を変更できませんでした：$details';
  }

  @override
  String get dictionaryManagerTitle => '辞書の管理';

  @override
  String get dictionaryManagerImportTooltip => '辞書をインポート';

  @override
  String get dictionaryManagerEmptySubtitle =>
      '+をタップしてYomitan辞書（.zip）\nまたはコレクション（.json）をインポート';

  @override
  String get dictionaryManagerBrowseDownloads => 'ダウンロードを見る';

  @override
  String get dictionaryManagerBrowseDownloadsCaption => '辞書やその他のデータをダウンロード';

  @override
  String dictionaryManagerImportedOn({required String date}) {
    return '$dateにインポート';
  }

  @override
  String get dictionaryManagerSupportedFormatsTitle => '対応形式';

  @override
  String get dictionaryManagerSupportedFormatsYomitan =>
      'Yomitan辞書（.zip）\nYomitanにインポートできる辞書はすべて使用できます。term bankのJSONファイルを含む.zipファイルです。';

  @override
  String get dictionaryManagerSupportedFormatsCollection =>
      'Yomitanコレクション（.json）\n複数の辞書を1つのファイルにまとめたDexieデータベースのエクスポートです。Yomitanの設定の「Backup」（バックアップ）からエクスポートできます。';

  @override
  String get dictionaryManagerOrderTitle => '辞書の順番';

  @override
  String get dictionaryManagerOrderBody =>
      '左側のハンドルをドラッグして辞書を並べ替えます。ここでの順番が、読書中に単語をタップしたときに意味が表示される順番になります。';

  @override
  String get dictionaryManagerPendingBackupTitle => 'バックアップの辞書設定を適用できます';

  @override
  String get dictionaryManagerPendingBackupBody =>
      '復元したバックアップに保存されている辞書の順番と有効・無効の状態を適用します。インストールされていない辞書はスキップされます。';

  @override
  String dictionaryManagerPendingBackupMatching({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '一致する辞書が$count件インストールされています',
      one: '一致する辞書が1件インストールされています',
      zero: '一致する辞書はインストールされていません',
    );
    return '$_temp0';
  }

  @override
  String dictionaryManagerPendingBackupMissing({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '未インストールの辞書$count件はスキップされます',
      one: '未インストールの辞書1件はスキップされます',
      zero: '未インストールの辞書はありません',
    );
    return '$_temp0';
  }

  @override
  String get dictionaryManagerPendingBackupNoMatches =>
      'このバックアップ設定を適用するには、一致する辞書を1つ以上インストールしてください。';

  @override
  String get dictionaryManagerPendingBackupApplyButton => 'バックアップ設定を適用';

  @override
  String get dictionaryManagerPendingBackupWarningTitle => '現在の辞書設定を上書きしますか？';

  @override
  String get dictionaryManagerPendingBackupWarningBody =>
      '一致する辞書の現在の順番と有効・無効の状態を上書きします。インストールされていない辞書はスキップされます。';

  @override
  String dictionaryManagerPendingBackupApplied({
    required int applied,
    required int missing,
  }) {
    return '$applied件の辞書にバックアップ設定を適用しました。インストールされていない$missing件の辞書をスキップしました。';
  }

  @override
  String get dictionaryManagerEnablingTitle => '有効化と無効化';

  @override
  String get dictionaryManagerEnablingBody =>
      'スイッチで辞書のオン・オフを切り替えます。無効にした辞書は、単語を調べるときに検索されません。';

  @override
  String get dictionaryManagerFindingTitle => '辞書を探す';

  @override
  String get dictionaryManagerFindingPrefix => '対応する辞書の一覧：';

  @override
  String get dictionaryManagerDeleteTitle => '辞書を削除';

  @override
  String dictionaryManagerDeleteBody({required String name}) {
    return '「$name」とそのすべての項目を削除しますか？\nこの操作は元に戻せません。';
  }

  @override
  String get ankidroidDataSourceExpression => '見出し語';

  @override
  String get ankidroidDataSourceReading => '読み';

  @override
  String get ankidroidDataSourceFurigana => 'ふりがな（Anki形式）';

  @override
  String get ankidroidDataSourceGlossary => '意味';

  @override
  String get ankidroidDataSourceSentenceContext => '文（文脈）';

  @override
  String get ankidroidDataSourceFrequency => '頻度順位';

  @override
  String get ankidroidDataSourceDictionaryName => '辞書名';

  @override
  String get ankidroidDataSourcePitchAccent => 'ピッチアクセント';

  @override
  String get ankidroidDataSourceEmpty => '（空）';

  @override
  String get ankidroidPermissionNotGrantedLong =>
      'AnkiDroidへのアクセスが許可されていません。AnkiDroidがインストールされていることを確認して、もう一度お試しください。';

  @override
  String get ankidroidCouldNotConnectLong =>
      'AnkiDroidに接続できませんでした。AnkiDroidがインストールされ、起動していることを確認してください。';

  @override
  String get ankidroidPermissionNotGrantedShort => 'AnkiDroidへのアクセスが許可されていません。';

  @override
  String ankidroidCouldNotConnectShort({required String app}) {
    return '$appに接続できませんでした。';
  }

  @override
  String ankidroidFailedToAddNote({required String app}) {
    return 'ノートを追加できませんでした。$appが起動していて、選択したノートタイプとデッキが存在することを確認してください。';
  }

  @override
  String get ankidroidSettingsNoteTypeSection => 'ノートタイプ';

  @override
  String get ankidroidSettingsNoteTypeTitle => 'Ankiのノートタイプ';

  @override
  String get ankidroidSettingsDefaultDeckSection => 'デフォルトのデッキ';

  @override
  String get ankidroidSettingsTargetDeckTitle => '追加先のデッキ';

  @override
  String get ankidroidSettingsFieldMappingSection => 'フィールドの割り当て';

  @override
  String get ankidroidSettingsFieldMappingHelp =>
      'Ankiのノートタイプにあるフィールドです。タップして、Mekuruが入力する内容を選んでください。';

  @override
  String get ankidroidSettingsDefaultTagsSection => 'デフォルトのタグ';

  @override
  String get ankidroidSettingsDefaultTagsHelp =>
      'エクスポートするすべてのノートに付けるタグを、カンマ区切りで入力します。';

  @override
  String get ankidroidTagsHint => 'mekuru, 日本語';

  @override
  String get ankidroidSettingsSelectNoteType => 'ノートタイプを選択';

  @override
  String get ankidroidSettingsSelectDeck => 'デッキを選択';

  @override
  String ankidroidSettingsMapFieldTo({required String ankiFieldName}) {
    return '「$ankiFieldName」に割り当てる項目：';
  }

  @override
  String ankidroidSettingsMapPreviewLookedUp({required String word}) {
    return 'プレビューには、調べた単語「$word」を使用しています。';
  }

  @override
  String ankidroidSettingsMapPreviewExample({required String word}) {
    return 'プレビューには、例として「$word」を使用しています。';
  }

  @override
  String ankidroidCardSettingsTooltip({required String app}) {
    return 'Mekuruの$app設定';
  }

  @override
  String get ankidroidCardDeckTitle => 'デッキ';

  @override
  String get ankidroidCardTagsTitle => 'タグ';

  @override
  String get ankidroidCardAddToAnki => 'Ankiに追加';

  @override
  String ankidroidNoteTypeMissing({required String app}) {
    return '設定したノートタイプがAnkiに存在しません。Mekuruの$app設定で新しいノートタイプを選んでください。';
  }

  @override
  String ankidroidStaleMappingBanner({required String fields}) {
    return '割り当てたフィールドの一部がAnkiに存在しません：$fields。タップしてフィールドの割り当てを修正してください。';
  }

  @override
  String ankidroidMissingInAnki({required String name}) {
    return '$name（Ankiに存在しません）';
  }

  @override
  String ankidroidStaleFieldSubtitle({required String source}) {
    return 'Ankiに存在しません（割り当て：$source）';
  }

  @override
  String ankidroidReassignFieldTo({required String source}) {
    return '「$source」の移動先：';
  }

  @override
  String get mangaReaderSettingsTitle => 'リーダー設定';

  @override
  String get mangaViewModeSingle => '単ページ';

  @override
  String get mangaViewModeSpread => '見開き';

  @override
  String get mangaViewModeScroll => '縦読み';

  @override
  String get mangaAutoCropSubtitle => '余白を取り除く';

  @override
  String get mangaAutoCropRerunTitle => '自動トリミングを再実行';

  @override
  String get mangaAutoCropRerunSubtitle => 'この本のすべてのページ画像を再解析';

  @override
  String get mangaTransparentLookupTitle => '辞書検索の透過表示';

  @override
  String get mangaTransparentLookupSubtitle => '辞書シートを半透明にする';

  @override
  String get mangaPageTurnEdgeZoneTitle => 'ページめくりエリア';

  @override
  String get mangaPageTurnEdgeZoneSubtitle => '画面の各端のうち、ページめくりに使う範囲の広さです。';

  @override
  String get mangaDebugWordOverlayTitle => '単語枠をデバッグ表示';

  @override
  String get mangaDebugWordOverlaySubtitle => '単語の検出枠を表示';

  @override
  String get mangaAutoCropComputeTitle => '自動トリミングを計算しますか？';

  @override
  String get mangaAutoCropComputeBody =>
      '自動トリミングを有効にするには、この本のすべてのページ画像を解析する必要があります。1分ほどかかる場合があります。';

  @override
  String get mangaAutoCropRerunDialogTitle => '自動トリミングを再実行しますか？';

  @override
  String get mangaAutoCropRerunDialogBody =>
      'この本のすべてのページ画像を再解析し、保存済みのトリミング範囲を置き換えます。1分ほどかかる場合があります。';

  @override
  String get mangaAutoCropComputingProgress =>
      'トリミング範囲を計算しています。1分ほどかかる場合があります。';

  @override
  String get mangaAutoCropRecomputingProgress =>
      'トリミング範囲を再計算しています。1分ほどかかる場合があります。';

  @override
  String get mangaAutoCropBoundsRefreshed => 'トリミング範囲を更新しました。';

  @override
  String mangaAutoCropSetupFailed({required String details}) {
    return '自動トリミングの設定に失敗しました：$details';
  }

  @override
  String get ocrNoPagesCacheFound => 'この本のページキャッシュが見つかりません';

  @override
  String get ocrAlreadyCompleteResetHint =>
      'OCRはすでに完了しています。リセットするには「OCRを削除」を使用してください。';

  @override
  String get ocrMangaImageDirectoryNotFound => 'マンガの画像フォルダが見つかりません';

  @override
  String get ocrBuildWordOverlaysTitle => '単語オーバーレイを作成';

  @override
  String get ocrBuildWordOverlaysBody =>
      'OCRテキストはすでにあります。単語のタップ領域を作り直し、辞書検索のオーバーレイが正しく表示されるようにします。';

  @override
  String get ocrRunActionTitle => 'OCRを実行';

  @override
  String ocrProcessPagesBody({required int count}) {
    return '$countページを処理します。OCRはバックグラウンドで実行され、アプリを閉じても続行されます。';
  }

  @override
  String get ocrProcessAction => '処理';

  @override
  String get ocrStartAction => '開始';

  @override
  String ocrPrepareFailed({required String details}) {
    return 'OCRを準備できませんでした：$details';
  }

  @override
  String ocrStartFailed({required String details}) {
    return 'OCRを開始できませんでした：$details';
  }

  @override
  String get ocrWordOverlayStartedBackground => '単語オーバーレイの処理をバックグラウンドで開始しました';

  @override
  String get ocrStartedBackground => 'バックグラウンドでOCRを開始しました';

  @override
  String get ocrCancelActionTitle => 'OCRを一時停止';

  @override
  String get ocrCancelSavedProgress => 'OCRを一時停止しました。進捗は保存されています。';

  @override
  String get ocrReplaceActionTitle => 'OCRを置き換え';

  @override
  String get ocrReplaceMokuroBody =>
      'Mokuro/HTMLファイルからインポートしたOCRデータを上書きし、カスタムサーバーで全ページのOCRをやり直します。\n\n元のOCRは、後で「OCRを削除」から復元できます。';

  @override
  String get ocrReplaceStartedBackground => 'OCRの置き換えをバックグラウンドで開始しました';

  @override
  String get ocrRemoveActionTitle => 'OCRを削除';

  @override
  String get ocrRemoveBody =>
      'このマンガのOCRテキストと単語オーバーレイをすべて削除しますか？OCRは後でもう一度実行できます。';

  @override
  String get ocrRemoveSubtitle => 'この本のOCRテキストをすべて削除';

  @override
  String get ocrRemovedFromBook => 'この本のOCRを削除しました';

  @override
  String ocrRemoveFailed({required String details}) {
    return 'OCRを削除できませんでした：$details';
  }

  @override
  String get ocrUnlockProSubtitle => 'カスタムOCRサーバーを使うにはProが必要です';

  @override
  String get ocrStopAndSaveProgressSubtitle => '処理を一時停止して進捗を保存';

  @override
  String get ocrReplaceMokuroSubtitle => 'MokuroのOCRをカスタムOCRサーバーの結果に置き換え';

  @override
  String get ocrRestoreOriginalMokuroBody =>
      '現在のOCRを削除し、Mokuro/HTMLファイルからインポートした元のOCRを復元しますか？';

  @override
  String get ocrRestoreOriginalMokuroSubtitle =>
      '現在のOCRを削除し、元のMokuro/HTMLのOCRを復元';

  @override
  String get ocrRemovePdfSubtitle => 'このPDFに追加したOCRテキストを削除（PDF本来のテキストは残ります）';

  @override
  String get ocrRemovePdfBody => 'このPDFに追加したOCRテキストを削除しますか？PDFに元からあるテキストは残ります。';

  @override
  String get ocrOriginalMokuroRestored => '元のMokuro/HTMLのOCRを復元しました';

  @override
  String get ocrBuildWordTargetsSubtitle => '保存済みのOCRから単語のタップ領域を作成';

  @override
  String ocrResumeSubtitle({required int completed, required int total}) {
    return 'OCRを再開（$completed/$total完了）';
  }

  @override
  String get ocrRecognizeAllPagesSubtitle => '全ページの文字を認識';

  @override
  String get readerEditNoteTitle => 'メモを編集';

  @override
  String get readerAddNoteHint => 'メモを追加…';

  @override
  String get readerCopiedToClipboard => 'クリップボードにコピーしました';

  @override
  String get aboutPrivacyPolicyTitle => 'プライバシーポリシー';

  @override
  String get aboutPrivacyPolicySubtitle => 'MekuruによるローカルデータとOCRデータの取り扱い';

  @override
  String get aboutOpenSourceLicensesTitle => 'オープンソースライセンス';

  @override
  String get aboutOpenSourceLicensesSubtitle => '依存ライブラリのライセンスを表示';

  @override
  String get aboutTagline => '「ページをめくる」';

  @override
  String get aboutEpubJsLicenseTitle => 'epub.jsのライセンス';

  @override
  String get downloadsKanjidicTitle => 'KANJIDIC';

  @override
  String get readerBookmarksTitle => 'ブックマーク';

  @override
  String get readerNoBookmarksYet =>
      'ブックマークはまだありません。\n読書中にブックマークアイコンをタップすると追加できます。';

  @override
  String get readerNoHighlightsYet => 'ハイライトはまだありません。\n読書中にテキストを選択すると追加できます。';

  @override
  String readerBookmarkProgressDate({
    required String progress,
    required String date,
  }) {
    return '$progress - $date';
  }

  @override
  String aboutVersion({required String version}) {
    return 'バージョン $version';
  }

  @override
  String get aboutDescription =>
      '日本語に特化したEPUBリーダーです。縦書き表示、オフライン辞書、単語帳管理に対応しています。';

  @override
  String get attributionsTitle => 'クレジット';

  @override
  String get aboutAttributionsTitle => 'クレジット';

  @override
  String get aboutAttributionsSubtitle => 'データの出典、ライセンス、謝辞';

  @override
  String get attributionUniDicTitle => 'UniDic';

  @override
  String get attributionUniDicDescription =>
      '高精度なふりがなの形態素解析には、国立国語研究所（NINJAL）が管理するコーパス辞書UniDicを使用しています。';

  @override
  String get attributionUniDicLicense => 'BSD/GPL/LGPLのトリプルライセンスで配布されています。';

  @override
  String get aboutKanjiVgTitle => 'KanjiVG';

  @override
  String get aboutKanjiVgDescription =>
      '漢字の書き順データは、Ulrich Apel氏が作成したKanjiVGプロジェクトから提供されています。';

  @override
  String get aboutLicensedUnderPrefix => 'ライセンス：';

  @override
  String get aboutLicenseSuffix => '。';

  @override
  String get aboutProjectLabel => 'プロジェクト：';

  @override
  String get aboutSourceLabel => '出典：';

  @override
  String get aboutJpdbTitle => 'JPDB頻度辞書';

  @override
  String get aboutJpdbDescription =>
      '単語の頻度データは、Kuuuube氏のyomitan-dictionariesで配布されているJPDB頻度辞書から提供されています。';

  @override
  String get aboutDataSourceLabel => 'データの出典：';

  @override
  String get aboutDictionaryLabel => '辞書：';

  @override
  String get aboutJmdictKanjidicTitle => 'JMdict、JMnedict、KANJIDIC';

  @override
  String get aboutJmdictKanjidicDescriptionPrefix =>
      '日本語多言語辞書データはJMdict/EDICTプロジェクト、漢字辞書データはKANJIDICプロジェクトから提供されています。どちらも作成者はJim Breen氏と';

  @override
  String get aboutJmdictLabel => 'JMdict：';

  @override
  String get aboutKanjidicLabel => 'KANJIDIC：';

  @override
  String get aboutEpubJsTitle => 'epub.js';

  @override
  String get aboutEpubJsDescription =>
      'EPUBの表示には、オープンソースのJavaScript製EPUBリーダーライブラリepub.jsを使用しています。';

  @override
  String get dictionaryPartOfSpeechNoun => '名詞';

  @override
  String get dictionaryPartOfSpeechPronoun => '代名詞';

  @override
  String get dictionaryPartOfSpeechPrefix => '接頭辞';

  @override
  String get dictionaryPartOfSpeechSuffix => '接尾辞';

  @override
  String get dictionaryPartOfSpeechCounter => '助数詞';

  @override
  String get dictionaryPartOfSpeechNumeric => '数詞';

  @override
  String get dictionaryPartOfSpeechExpression => '表現';

  @override
  String get dictionaryPartOfSpeechInterjection => '感動詞';

  @override
  String get dictionaryPartOfSpeechConjunction => '接続詞';

  @override
  String get dictionaryPartOfSpeechParticle => '助詞';

  @override
  String get dictionaryPartOfSpeechCopula => 'コピュラ';

  @override
  String get dictionaryPartOfSpeechAuxiliary => '補助語';

  @override
  String get dictionaryPartOfSpeechAuxiliaryVerb => '助動詞';

  @override
  String get dictionaryPartOfSpeechAuxiliaryAdjective => '補助形容詞';

  @override
  String get dictionaryPartOfSpeechIAdjective => 'い形容詞';

  @override
  String get dictionaryPartOfSpeechNaAdjective => 'な形容詞';

  @override
  String get dictionaryPartOfSpeechNoAdjective => 'の形容詞';

  @override
  String get dictionaryPartOfSpeechPreNounAdjectival => '連体詞';

  @override
  String get dictionaryPartOfSpeechAdverb => '副詞';

  @override
  String get dictionaryPartOfSpeechToAdverb => 'と副詞';

  @override
  String get dictionaryPartOfSpeechAdverbialNoun => '副詞的名詞';

  @override
  String get dictionaryPartOfSpeechSuruVerb => 'する動詞';

  @override
  String get dictionaryPartOfSpeechKuruVerb => '来る動詞';

  @override
  String get dictionaryPartOfSpeechIchidanVerb => '一段動詞';

  @override
  String get dictionaryPartOfSpeechGodanVerb => '五段動詞';

  @override
  String get dictionaryPartOfSpeechZuruVerb => 'ずる動詞';

  @override
  String get dictionaryPartOfSpeechIntransitiveVerb => '自動詞';

  @override
  String get dictionaryPartOfSpeechTransitiveVerb => '他動詞';

  @override
  String get statsHeroReadingTime => '読書時間';

  @override
  String get statsHeroCharactersRead => '読んだ文字数';

  @override
  String get statsHeroWordsAdded => '追加した単語';

  @override
  String get statsFormatAll => 'すべて';

  @override
  String get statsFormatEpub => 'EPUB';

  @override
  String get statsFormatManga => 'マンガ';

  @override
  String get statsPeriodWeek => '1週間';

  @override
  String get statsPeriodMonth => '1か月';

  @override
  String get statsPeriodYear => '1年';

  @override
  String get statsPeriodAll => '全期間';

  @override
  String get statsUnavailable => '現在、読書の統計を表示できません。';

  @override
  String get statsHeatmapTitle => '読書アクティビティ';

  @override
  String get statsHeatmapLegendLess => '少ない';

  @override
  String get statsHeatmapLegendMore => '多い';

  @override
  String get statsHeatmapLookups => '辞書検索';

  @override
  String get statsBestDayMarker => '最長記録';

  @override
  String statsVolumePageCount({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countページ',
      one: '$countページ',
    );
    return '$_temp0';
  }

  @override
  String get statsLookupRateTitle => '辞書検索率';

  @override
  String get statsLookupRateSubtitle => '1,000文字あたりの辞書検索回数';

  @override
  String get statsVocabGrowthTitle => '単語帳の推移';

  @override
  String statsVocabWordCount({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count語',
      one: '$count語',
    );
    return '$_temp0';
  }

  @override
  String statsDurationHoursMinutes({required int hours, required int minutes}) {
    return '$hours時間$minutes分';
  }

  @override
  String statsDurationMinutes({required int minutes}) {
    return '$minutes分';
  }

  @override
  String get mangaReaderFailedToLoad => 'マンガを読み込めませんでした';

  @override
  String get mangaReaderNoPages => 'ページが見つかりません';

  @override
  String get serverSettingsSyncNow => '今すぐ同期';

  @override
  String serverSettingsConnectionSubtitle({
    required String serverType,
    required String baseUrl,
  }) {
    return '$serverType · $baseUrl';
  }

  @override
  String get serverSettingsDisabled => '無効';

  @override
  String get serverSettingsLinkExisting => '端末の本をリンク';

  @override
  String get serverSettingsEdit => '編集';

  @override
  String get serverSettingsEmptyHint =>
      'セルフホストのKomgaまたはKavitaサーバーに接続すると、本の閲覧やダウンロード、読書の進捗の同期ができます。';

  @override
  String get serverSettingsAddServer => 'サーバーを追加';

  @override
  String get serverSettingsMatching => 'ライブラリを照合中…';

  @override
  String get serverSettingsNoMatches =>
      '新たに一致する本はありませんでした。本はサーバーの閲覧画面からもリンクできます';

  @override
  String serverSettingsLinkedCount({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count冊の本をリンクし、進捗を同期しました',
      one: '1冊の本をリンクし、進捗を同期しました',
    );
    return '$_temp0';
  }

  @override
  String serverSettingsLinkFailed({required String error}) {
    return 'リンクできませんでした：$error';
  }

  @override
  String get serverSettingsSyncing => '同期中…';

  @override
  String serverSettingsSyncedWithFailures({
    required int pushed,
    required int failed,
  }) {
    return '$pushed冊を同期しました（$failed冊は失敗）';
  }

  @override
  String serverSettingsSynced({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count冊を同期しました',
      one: '1冊を同期しました',
    );
    return '$_temp0';
  }

  @override
  String get serverSettingsAlreadyInSync => 'すべて同期済みです';

  @override
  String get serverDialogEditTitle => 'サーバーを編集';

  @override
  String get serverDialogNameLabel => '名前';

  @override
  String get serverDialogNameHint => 'マイサーバー';

  @override
  String get serverDialogUrlLabel => 'サーバーURL';

  @override
  String get serverDialogUrlHint => 'https://server:port';

  @override
  String get serverDialogSecretLabel => 'APIキー';

  @override
  String get serverDialogSecretLabelKomga => 'APIキーまたはID:パスワード';

  @override
  String get serverDialogSecretKeepHint => '変更しない場合は空欄のまま';

  @override
  String get serverDialogEnabled => '有効';

  @override
  String get serverDialogAllowSelfSigned => '自己署名証明書を許可';

  @override
  String get serverDialogAllowSelfSignedSubtitle =>
      '独自の証明書を使うhttps://サーバー向けです。オンにすると、Mekuruはこのサーバーが提示する証明書をすべて受け入れます。';

  @override
  String get serverDialogConnectionOk => '接続に成功しました';

  @override
  String serverDialogConnectionFailed({required String error}) {
    return '失敗しました：$error';
  }

  @override
  String get serverDialogTest => 'テスト';

  @override
  String get serverDialogRemoveTitle => 'サーバーを削除しますか？';

  @override
  String get serverDialogRemoveBody =>
      'ダウンロード済みの本と読書の進捗はこの端末に残ります。削除されるのはサーバーとの接続だけです。';

  @override
  String get serverBrowseNoLibraries => 'このサーバーにはライブラリがありません';

  @override
  String get serverBrowseSearchHint => 'このサーバーを検索';

  @override
  String get serverBrowseNoSeries => 'シリーズが見つかりません';

  @override
  String serverBrowseBookCount({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count冊',
      one: '$count冊',
    );
    return '$_temp0';
  }

  @override
  String get serverBrowseAlreadyInLibraryTitle => 'この本はすでに端末にあります';

  @override
  String serverBrowseAlreadyInLibraryBody({required String title}) {
    return '「$title」をリンクして読書の進捗をサーバーと同期するか、別のコピーをダウンロードしてください。';
  }

  @override
  String get serverBrowseDownloadAnyway => '別途ダウンロード';

  @override
  String get serverBrowseLinkExistingCopy => '端末の本をリンク';

  @override
  String serverBrowseLinked({required String title}) {
    return '「$title」をリンクしました';
  }

  @override
  String serverBrowseAddedToLibrary({required String title}) {
    return '「$title」をライブラリに追加しました';
  }

  @override
  String serverBrowseDownloadFailed({required String error}) {
    return 'ダウンロードに失敗しました：$error';
  }

  @override
  String get serverBrowseDownloadStopped => 'ダウンロードが停止しました';

  @override
  String get serverCertificateUntrusted =>
      'サーバーの証明書が信頼されていません。独自の（自己署名）証明書を使っている場合は、「自己署名証明書を許可」をオンにしてください。';

  @override
  String get serverErrorSignInRejected => 'サーバーがAPIキーまたはパスワードを拒否しました。';

  @override
  String get serverErrorUnreachable => 'サーバーに接続できませんでした。URLとネットワーク接続を確認してください。';

  @override
  String serverErrorStatus({required int status}) {
    return 'サーバーがエラー$statusを返しました。';
  }

  @override
  String backgroundWorkDownloading({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count冊の本をダウンロード中',
      one: '1冊の本をダウンロード中',
    );
    return '$_temp0';
  }

  @override
  String backgroundWorkScanning({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count冊の本の文字を認識中',
      one: '1冊の本の文字を認識中',
    );
    return '$_temp0';
  }

  @override
  String backgroundWorkPercent({required int percent}) {
    return '$percent%完了';
  }

  @override
  String get serverBrowseBookGone => 'この本はもう端末にありません';

  @override
  String serverLinkDropped({required String title}) {
    return '「$title」はサーバー上に見つからなくなったため、同期を停止しました。サーバーの本の一覧からもう一度リンクしてください。';
  }

  @override
  String get serverBrowseNoBooks => 'このシリーズには本がありません';

  @override
  String serverBrowsePageCount({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countページ',
      one: '$countページ',
    );
    return '$_temp0';
  }

  @override
  String get backupReadingDataBadge => '.mekuru';

  @override
  String get backupFullBadge => '.zip';

  @override
  String get backupWrongKindFullBackup =>
      'これは.zipファイルで、読書データのバックアップではありません。Mekuruの完全バックアップの場合は、「完全バックアップを復元」を使用してください。';

  @override
  String get backupWrongKindReadingData =>
      'これは読書データのバックアップ（.mekuru）で、完全バックアップではありません。代わりに「読書データをインポート」を使用してください。';

  @override
  String get backupFullSectionTitle => '完全バックアップ';

  @override
  String get backupFullScopeBody =>
      '本、マンガ、辞書、フォント、設定、読書データをすべて1つの大きな.zipファイルにまとめます。復元すると、この端末のMekuruのデータがすべて置き換えられます。他のアプリやファイルには影響しません。手動でのみ作成できます。';

  @override
  String get backupFullNotIncluded =>
      '含まれないもの：ダウンロードしたKanjiVGの書き順データ、OCRモデル、翻訳モデル（設定から再ダウンロードしてください）、読書データのバックアップ履歴。';

  @override
  String get backupFullNotIncludedIos =>
      '含まれないもの：ダウンロードしたKanjiVGの書き順データとOCRモデル（設定から再ダウンロードしてください）、読書データのバックアップ履歴。';

  @override
  String get backupFullExportTitle => '完全バックアップをエクスポート（.zip）…';

  @override
  String get backupFullExportSubtitle =>
      'フォルダを選択してください。ファイルは数GBになることがあります。バックアップはバックグラウンドで実行され、進捗は通知に表示されます。';

  @override
  String get backupFullRestoreTitle => '完全バックアップを復元（.zip）…';

  @override
  String get backupFullRestoreSubtitle =>
      'この端末のMekuruのデータをすべて完全バックアップの内容に置き換えます。バックグラウンドで実行され、ファイルのコピーが終わるとMekuruは終了します。';

  @override
  String get backupFullReplacesChip => 'Mekuruのデータを置き換え';

  @override
  String get backupFullProgressPreparing => '準備中…';

  @override
  String backupFullProgressBytes({
    required String done,
    required String total,
  }) {
    return '$done / $total';
  }

  @override
  String backupFullExported({required String size}) {
    return '完全バックアップを保存しました（$size）';
  }

  @override
  String backupFullExportedWithSkipped({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '完全バックアップを保存しました。$count個のファイルを読み込めなかったため、スキップしました',
      one: '完全バックアップを保存しました。$count個のファイルを読み込めなかったため、スキップしました',
    );
    return '$_temp0';
  }

  @override
  String get backupFullCancelled => 'キャンセルしました。何も変更されていません。';

  @override
  String get backupFullBusy => '本のインポートがまだ実行中です。完了してから、もう一度お試しください。';

  @override
  String backupFullNotEnoughSpace({required String size}) {
    return 'この端末の空き容量が不足しています。あと約$size必要です。';
  }

  @override
  String backupFullTooNew({required String version}) {
    return 'この完全バックアップはMekuru $versionで作成されています。Mekuruをアップデートしてから、もう一度お試しください。';
  }

  @override
  String get backupFullInvalid => 'このファイルはMekuruの完全バックアップではありません。';

  @override
  String get backupFullPendingRestore =>
      '以前の完全復元がまだ完了していません。先にMekuruを完全に終了してから、もう一度開いてください。';

  @override
  String backupFullFailed({required String details}) {
    return '完全バックアップに失敗しました：$details';
  }

  @override
  String backupFullRestoreFailed({required String details}) {
    return '完全復元に失敗しました：$details';
  }

  @override
  String get backupFullReviewTitle => '完全バックアップの確認';

  @override
  String get backupFullReviewInFile => 'このファイルの内容';

  @override
  String backupFullReviewCreated({
    required String date,
    required String version,
  }) {
    return '$dateにMekuru $versionで作成';
  }

  @override
  String backupFullCountBooks({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '本$count冊',
      one: '本$count冊',
    );
    return '$_temp0';
  }

  @override
  String backupFullCountDictionaries({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '辞書$count個',
      one: '辞書$count個',
    );
    return '$_temp0';
  }

  @override
  String backupFullReviewExternalManga({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Mekuru外のフォルダにリンクされていたマンガが$count冊あります。そのページはこのバックアップに含まれており、Mekuru内に保存されます。',
      one:
          'Mekuru外のフォルダにリンクされていたマンガが$count冊あります。そのページはこのバックアップに含まれており、Mekuru内に保存されます。',
    );
    return '$_temp0';
  }

  @override
  String get backupFullReviewOnDevice => '現在このデバイスのMekuruにあるデータ';

  @override
  String get backupFullReviewContinue => '続行';

  @override
  String get backupFullReplaceTitle => 'Mekuruのデータを削除して置き換えますか？';

  @override
  String backupFullReplaceBody({
    required String books,
    required String dictionaries,
  }) {
    return 'このデバイスのMekuruにある現在のデータ（$books、$dictionaries、Mekuruのすべての設定と読書データ）はすべて削除されます。Mekuru以外のものには影響しません。この操作は取り消せません。Mekuruが終了するので、もう一度開いて完了してください。';
  }

  @override
  String get backupFullReplaceAcknowledge => 'このデバイスのMekuruのデータが削除されることを理解しました';

  @override
  String get backupFullReplaceConfirm => 'Mekuruのデータを削除して置き換える';

  @override
  String get backupFullRestartTitle => 'Mekuruを終了します';

  @override
  String get backupFullRestartBody =>
      '完全バックアップの準備ができました。復元を完了するためにMekuruが終了します。もう一度開くと、復元されたライブラリで続けられます。';

  @override
  String get backupFullRestartButton => 'Mekuruを終了';

  @override
  String get backupFullExportSubtitleIos =>
      'ファイルは数GBになることがあります。書き込みが終わるまでMekuruを開いたままにしてください。保存先は最後に選択します。';

  @override
  String get backupFullRestoreSubtitleIos =>
      'このデバイスのMekuruの内容をすべて完全バックアップの内容に置き換えます。ファイルのコピー中はMekuruを開いたままにしてください。最後にMekuruが再起動します。';

  @override
  String backupFullReplaceBodyIos({
    required String books,
    required String dictionaries,
  }) {
    return 'このデバイスのMekuruにある現在のデータ（$books、$dictionaries、Mekuruのすべての設定と読書データ）はすべて削除されます。Mekuru以外のものには影響しません。この操作は取り消せません。最後にMekuruが再起動して完了します。';
  }

  @override
  String get backupFullReloadTitle => 'Mekuruを再起動します';

  @override
  String get backupFullReloadBody =>
      '完全バックアップの準備ができました。復元を完了するためにMekuruが再起動し、復元されたライブラリを開きます。';

  @override
  String get backupFullReloadButton => 'Mekuruを再起動';

  @override
  String get backupFullRestoreComplete => '完全バックアップからの復元が完了しました';

  @override
  String backupFullRestoreBootFailed({required String details}) {
    return '完全バックアップからの復元を完了できなかったため、以前のデータを保持しました。（$details）';
  }

  @override
  String get backupFullJobExportTitle => 'バックアップ中';

  @override
  String get backupFullJobRestoreTitle => '復元中';

  @override
  String get backupFullJobPhaseWriting => 'バックアップを書き込み中…';

  @override
  String get backupFullJobPhaseChecking => 'コピー済みのファイルを確認中…';

  @override
  String get backupFullJobPhaseExtracting => 'ファイルをコピー中…';

  @override
  String get backupFullJobPhaseFinishing => '最終処理中…';

  @override
  String get backupFullJobPhaseResuming => '再開中…';

  @override
  String backupFullJobPaused({required String details}) {
    return '一時停止中：$details。Mekuruをもう一度開くと再試行します。';
  }

  @override
  String get backupFullJobBackgroundHint => 'Mekuruを離れても処理は続きます。進捗は通知にも表示されます。';

  @override
  String get backupFullJobBackgroundHintIos =>
      '完了するまでMekuruを画面に表示したままにしてください。処理中は画面が消灯しません。';

  @override
  String get backupFullJobCancelConfirmExport =>
      'バックアップを中止しますか？ここまでに書き込んだデータは削除されます。';

  @override
  String get backupFullJobCancelConfirmRestore =>
      '復元を中止しますか？Mekuruの内容はまだ変更されていません。コピーしたファイルは削除されます。';

  @override
  String get backupFullJobKeepGoing => '続ける';

  @override
  String get backupFullJobStop => '中止';

  @override
  String get backupFullJobDone => '完了';

  @override
  String get backupFullSaveButton => 'バックアップを保存…';

  @override
  String get backupFullJobClose => '閉じる';

  @override
  String get backupFullJobRenameFailed =>
      'ファイルは末尾が .partial の一時的な名前で保存されました。復元に使う前に、末尾が .zip になるよう名前を変更してください。';

  @override
  String get backupFullIncomplete =>
      'このファイルは不完全か破損しています。保存した場所からもう一度コピーしてください。';

  @override
  String get readerFuriganaWanikani => 'WaniKani';

  @override
  String get readerFuriganaWanikaniStageTitle => 'ふりがなを隠す段階';

  @override
  String get wanikaniStageApprentice => 'Apprentice以上';

  @override
  String get wanikaniStageGuru => 'Guru以上';

  @override
  String get wanikaniStageMaster => 'Master以上';

  @override
  String get wanikaniStageEnlightened => 'Enlightened以上';

  @override
  String get wanikaniStageBurned => 'Burnedのみ';

  @override
  String get readerFuriganaWanikaniLinkPrompt => 'WaniKaniアカウントを連携';

  @override
  String get settingsWanikaniSubtitle => '覚えた漢字のふりがなを隠す';

  @override
  String settingsWanikaniLinkedAs({required String username}) {
    return '$usernameとして連携中';
  }

  @override
  String get wanikaniSettingsIntro =>
      'WaniKaniのAPIトークンを貼り付けてください（読み取り専用のトークンで十分です）。Mekuruがすべての漢字のSRS段階をダウンロードし、覚えた漢字だけでできた単語のふりがなを隠します。';

  @override
  String get wanikaniSettingsTokenLabel => 'APIトークン';

  @override
  String get wanikaniSettingsGetToken => 'APIトークンを取得';

  @override
  String get wanikaniSettingsLink => 'アカウントを連携';

  @override
  String get wanikaniSettingsUnlink => '連携を解除';

  @override
  String get wanikaniSettingsUnlinkConfirm =>
      'WaniKaniとの連携を解除しますか？Mekuruはトークンと漢字リストを削除します。';

  @override
  String get wanikaniSettingsSyncNow => '今すぐ同期';

  @override
  String wanikaniSettingsStatus({required int level, required int count}) {
    return 'レベル$level・漢字$count字を同期済み';
  }

  @override
  String wanikaniSettingsLastSynced({required String time}) {
    return '最終同期：$time';
  }

  @override
  String get wanikaniSettingsRestoredNoToken =>
      '漢字リストはバックアップから復元されました。最新の状態を保つには、もう一度連携してください。';

  @override
  String get wanikaniSettingsThresholdCaption =>
      '隠す漢字を選ぶには、リーダー設定の「ふりがな」で「WaniKani」を選択してください。';

  @override
  String wanikaniSettingsSyncDone({required int count}) {
    return '漢字$count字を同期しました';
  }

  @override
  String get wanikaniErrorTokenInvalid =>
      'WaniKaniがこのトークンを拒否しました。新しいトークンを作成して、もう一度お試しください。';

  @override
  String get wanikaniErrorNetwork => 'WaniKaniに接続できませんでした。ネットワーク接続を確認してください。';

  @override
  String get wanikaniErrorRateLimited =>
      'WaniKaniへのリクエストが制限されています。1分ほど待ってから、もう一度お試しください。';

  @override
  String get wanikaniErrorGeneric =>
      'WaniKaniとの同期に失敗しました。しばらくしてから、もう一度お試しください。';

  @override
  String get libraryExportFuriganaWanikani => 'WaniKaniでまだ覚えていない漢字';

  @override
  String get readerFuriganaWanikaniStagePickerTitle => 'ふりがなを隠す漢字の段階';

  @override
  String get localOcrRecognize => '文字を認識';

  @override
  String get localOcrRecognizeQuick => 'このページの文字を認識。長押しでその他のオプション';

  @override
  String localOcrQuickStartedOnDevice({
    required int count,
    required String pages,
  }) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$pagesページをデバイス上で認識中',
      one: '$pagesページをデバイス上で認識中',
    );
    return '$_temp0';
  }

  @override
  String localOcrQuickStartedRemote({
    required int count,
    required String pages,
  }) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$pagesページをOCRサーバーで認識中',
      one: '$pagesページをOCRサーバーで認識中',
    );
    return '$_temp0';
  }

  @override
  String get localOcrOptions => 'オプション';

  @override
  String get localOcrAlreadyDone => 'このページはOCR済みです';

  @override
  String get localOcrOnDevice => 'オンデバイス';

  @override
  String get localOcrOnDeviceSubtitle => 'モデルのダウンロード後はオフラインで動作';

  @override
  String get localOcrOnDeviceSubtitleIos =>
      'Appleの文字認識を使ってオフラインで処理します。Mekuruを離れてもスキャンは続き、iOSに停止された場合は一時停止します。';

  @override
  String get localOcrRemote => 'リモート';

  @override
  String get localOcrRemoteSubtitle => 'お使いのOCRサーバーを使用（既存のアクセス要件が適用されます）';

  @override
  String get localOcrEntireManga => 'マンガ全体';

  @override
  String localOcrThisPage({required int page}) {
    return '$pageページ';
  }

  @override
  String localOcrCoverage({required int done, required int total}) {
    return '$totalページ中$doneページがOCR済み';
  }

  @override
  String get localOcrMissingOnly => 'OCRされていないページのみ';

  @override
  String get localOcrReplace => '既存のOCRを置き換える';

  @override
  String get localOcrReplaceDescription =>
      '既存の結果は、各ページの置き換えが成功するまで保持されます。キャンセルしても、完了した置き換えは保持されます。';

  @override
  String get localOcrChargingOnly => '充電中のみ';

  @override
  String localOcrStartPages({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countページを認識',
      one: '1ページを認識',
    );
    return '$_temp0';
  }

  @override
  String get localOcrNothingToDo =>
      '選択したページはすでにOCR済みです。もう一度スキャンするには「既存のOCRを置き換える」を選択してください。';

  @override
  String get localOcrModelTitle => '日本語マンガOCR — manga-ocr';

  @override
  String get localOcrModelDescription =>
      '日本語のマンガをオフラインで認識します。ページ画像はデバイスの外に送信されません。利用にはMekuru Proが必要ですが、事前にデバイスで試せるよう、モデルのダウンロードはどなたでも可能です。';

  @override
  String get localOcrModelDescriptionIos =>
      '任意のダウンロードです。なくてもAppleの文字認識でマンガの文字を検出して読み取れますが、入れるとmanga-ocrがより正確に読み取ります。ページ画像はデバイスの外に送信されません。';

  @override
  String localOcrDownloadSize({required String done, required String total}) {
    return '$done / $total ダウンロード済み';
  }

  @override
  String get localOcrDownloadRequired =>
      '「設定」→「ダウンロード」でOCRモデルをダウンロードしてから、ここに戻って開始してください。';

  @override
  String get localOcrModelsMissingBody =>
      'オンデバイスOCRを使うには、先にモデルをダウンロードする必要があります。「ダウンロード」を開いて入手してから、戻ってもう一度OCRをタップしてください。';

  @override
  String get localOcrModelReady => 'モデルはインストール済み・オフラインで動作';

  @override
  String get localOcrModelMissing => '追加のダウンロードが必要';

  @override
  String get localOcrModelVerifying => 'モデルファイルを検証中…';

  @override
  String get localOcrModelDownloading => 'モデルをダウンロード中…';

  @override
  String get localOcrUnsupported =>
      'オンデバイスOCRには、対応する64ビットARMのAndroidデバイスが必要です。リモートOCRは引き続き利用できます。';

  @override
  String get localOcrPause => '一時停止';

  @override
  String get localOcrResume => '再開';

  @override
  String get localOcrCancelJob => 'スキャンをキャンセル';

  @override
  String get localOcrCancelDescription =>
      'このスキャンを中止して、残りの処理を削除しますか？完了したOCRは保持されます。';

  @override
  String get localOcrPaused => '一時停止中';

  @override
  String get localOcrQueued => '待機中';

  @override
  String get localOcrPreparing => 'モデルを準備中…';

  @override
  String get localOcrDetecting => '文字を検出中…';

  @override
  String get localOcrRecognizing => '文字を認識中…';

  @override
  String get localOcrPausing => '一時停止しています…';

  @override
  String get localOcrCancelling => 'キャンセルしています…';

  @override
  String get localOcrCancelled => 'スキャンをキャンセルしました・完了したOCRは保持';

  @override
  String get localOcrCompleted => 'OCR完了';

  @override
  String get localOcrCompletedErrors => '完了（一部のページでエラー）';

  @override
  String get localOcrFailed => 'ページのエラーが繰り返されたため、OCRを停止しました';

  @override
  String localOcrProgress({required int processed, required int total}) {
    return '$processed / $totalページ処理済み';
  }

  @override
  String localOcrOutcomeCounts({
    required int succeeded,
    required int skipped,
    required int failed,
  }) {
    return '$succeeded件保存・$skipped件スキップ・$failed件失敗';
  }

  @override
  String get localOcrRetryFailed => '失敗したページを再試行';

  @override
  String get localOcrDismiss => '閉じる';

  @override
  String localOcrError({required String details}) {
    return 'OCRを続行できませんでした：$details';
  }

  @override
  String get localOcrInterrupted => 'スキャンが中断されました。再開すると、保存された進捗から続行します。';

  @override
  String get localOcrLowMemory =>
      'デバイスのメモリが不足しているため一時停止しました。再開する前に他のアプリを閉じてください。';

  @override
  String get localOcrTooHot => 'デバイスが高温になっているため一時停止しました。冷めてから再開してください。';

  @override
  String get localOcrLowBattery =>
      'バッテリー残量が15%を下回ったため一時停止しました。デバイスを充電してから再開してください。';

  @override
  String get localOcrChargingRequired => 'このスキャンを再開する前に充電器を接続してください。';

  @override
  String get localOcrBackgroundLimit =>
      'Androidがバックグラウンド処理を停止しました。Mekuruを開いてスキャンを再開してください。';

  @override
  String get localOcrRuntimeError => 'このデバイスではOCRランタイムを続行できませんでした。進捗は保存されています。';

  @override
  String get localOcrAccessLost =>
      'マンガの画像を読み込めませんでした。フォルダへのアクセスを復元してから再試行してください。';

  @override
  String get localOcrStorageFull => 'ストレージの空き容量が不足しているため続行できません。';

  @override
  String get localOcrBusy =>
      'このマンガにはすでにOCRジョブがあります。新しく開始する前に、一時停止またはキャンセルしてください。';

  @override
  String get localOcrModelBusy =>
      'インストール済みのモデルを変更する前に、実行中のOCRとダウンロードを停止してください。';

  @override
  String get localOcrLicenseTitle => 'マンガOCRのモデルとランタイム';

  @override
  String get localOcrLicenseRecognizer =>
      'manga-ocr（作者：kha-white）。文字認識に使用。Apache-2.0。';

  @override
  String get localOcrLicenseDetector =>
      'Comic Text Detector（作者：dmMazeおよびコントリビューター）。マンガの文字検出に使用。GPL-3.0のプロジェクトです。成果物の出所とソースに関する表記をご確認ください。';

  @override
  String get localOcrLicenseRuntime =>
      'ONNX Runtime（作者：Microsoftおよびコントリビューター）、OpenCV（作者：OpenCVコントリビューター）。ローカルでの推論と画像処理に使用。';

  @override
  String get localOcrLicenseOpen => 'ライセンスとソースに関する表記を表示';

  @override
  String get localOcrPageErrors => 'ページのエラー';

  @override
  String localOcrPageError({required int page, required String details}) {
    return '$pageページ：$details';
  }

  @override
  String get localOcrNotificationsOff =>
      '通知がオフでもOCRは続行できます。一時停止やキャンセルは、マンガの文字認識シートから行ってください。';

  @override
  String get localOcrModelCorrupt =>
      'モデルファイルの検証に失敗しました。OCRモデルを削除して、もう一度ダウンロードしてください。';

  @override
  String get localOcrMobileDownloadTitle => 'モバイルデータ通信でダウンロードしますか？';

  @override
  String localOcrMobileDownloadBody({required String size}) {
    return 'OCRモデルのサイズは$sizeです。モバイルデータ通信またはテザリングで接続しているため、ダウンロードでデータ通信量を消費する可能性があります。保存済みのダウンロード進捗は再利用されます。';
  }

  @override
  String get localOcrWifiLostIos =>
      'Wi-Fiが切断されたため、ダウンロードが停止しました。完了したファイルは保持されます。続けるには「ダウンロード」をタップしてください。';

  @override
  String get localOcrWaitingWifi =>
      'Wi-Fiを待機中。モバイルデータ通信を使うには、キャンセルしてから再開してください。';

  @override
  String get localOcrDownloadQueued => 'ダウンロード待機中…';

  @override
  String get mobileDataVpnTitle => 'VPN経由でダウンロードしますか？';

  @override
  String mobileDataVpnBody({required String size}) {
    return 'VPN経由で接続しているため、このダウンロード（$size）がモバイルデータ通信を使うかどうかをMekuruでは判断できません。';
  }

  @override
  String get localOcrEstimating => '残り時間を計算中…';

  @override
  String localOcrReadingRegions({required int done, required int total}) {
    return 'テキスト領域 $done / $total を読み取り済み';
  }

  @override
  String localOcrCurrentPage({required int page}) {
    return '$pageページを認識中';
  }

  @override
  String get localOcrCopyDiagnostics => 'OCR診断情報をコピー';

  @override
  String get localOcrDiagnosticsCopied => 'OCR診断情報をコピーしました';

  @override
  String get localOcrSpeedTest => 'デバイスの速度をテスト';

  @override
  String get localOcrSpeedTestRunning => 'オンデバイスOCRの速度をテスト中…';

  @override
  String localOcrSpeedTestResult({
    required String pageSeconds,
    required int minutes,
  }) {
    return '1ページあたり約$pageSeconds秒・200ページの巻で約$minutes分';
  }

  @override
  String get localOcrSpeedTestCancelled => '速度テストをキャンセルしました';

  @override
  String get ankiConnectAddressLabel => 'AnkiConnectのアドレス';

  @override
  String get ankiConnectSetupHelp =>
      'パソコンのAnkiにAnkiConnectアドオン（コード 2055492159）をインストールし、その設定で\"webBindAddress\": \"0.0.0.0\"を指定してAnkiを再起動してください。このデバイスとパソコンを同じネットワークに接続し、ローカルネットワークへのアクセスを求められたら許可してください。その後、パソコンのアドレス（例：http://192.168.1.20:8765）を入力してください。';

  @override
  String get ankiConnectInvalidAddress =>
      'http://192.168.1.20:8765 のような形式でアドレスを入力してください';

  @override
  String get ankiConnectConnect => '接続';

  @override
  String get ankiConnectCouldNotConnect =>
      'Ankiに接続できませんでした。アドレスが正しいこと、パソコンでAnkiが起動していることを確認してください。';

  @override
  String get ankiBackendLabel => 'カードの送信先';

  @override
  String get ankiBackendAnkiMobile => 'AnkiMobile（このデバイス）';

  @override
  String get ankiBackendAnkiConnect => 'パソコンのAnki（AnkiConnect）';

  @override
  String get ankiMobileSetupHelp =>
      'AnkiMobileはノートタイプ、デッキ、フィールドを他のアプリに知らせることができないため、ここに入力してください。名前はAnkiMobileのものと完全に一致させる必要があります。';

  @override
  String get ankiMobileNoteTypeLabel => 'ノートタイプ';

  @override
  String get ankiMobileDeckLabel => 'デッキ';

  @override
  String get ankiMobileFieldNamesLabel => 'フィールド名（カンマ区切り）';

  @override
  String get ankiMobileNamesRequired => 'ノートタイプ、デッキ、および1つ以上のフィールド名を入力してください。';

  @override
  String get ankiMobileCouldNotOpen =>
      'AnkiMobileを開けませんでした。このデバイスにインストールされていることを確認してください。';

  @override
  String get catalogTitle => 'その他の辞書';

  @override
  String get catalogEntrySubtitle => '固有名詞、国語辞典、他の言語など';

  @override
  String get catalogSectionJapaneseEnglish => '和英辞典';

  @override
  String get catalogSectionJapaneseJapanese => '国語辞典';

  @override
  String get catalogSectionNames => '固有名詞';

  @override
  String get catalogSectionOtherLanguages => 'その他の言語';

  @override
  String get catalogJitendexDescription =>
      'JMdictをもとにした新しい和英辞典。例文付きで、より見やすいレイアウトです。';

  @override
  String get catalogWiktionaryEnglishDescription =>
      '英語版Wiktionaryに収録された日本語の単語。語源、文法の解説、用例付きです。';

  @override
  String get catalogWiktionaryJapaneseDescription =>
      '日本語版Wiktionaryをもとにした国語辞典。意味は日本語で書かれています。';

  @override
  String get catalogWiktionaryChineseDescription =>
      '中国語版Wiktionaryに収録された日本語の単語。意味は中国語で書かれています。';

  @override
  String get catalogJmnedictDescription => '日本の固有名詞の読み。人名、地名、会社名などを収録しています。';

  @override
  String get catalogJmdictLanguageDescription => '意味がこの言語で書かれたJMdictです。';

  @override
  String get catalogKanjidicLanguageDescription =>
      'この言語による漢字の意味と、音読み・訓読みを収録しています。';

  @override
  String catalogSizes({required String download, required String installed}) {
    return 'ダウンロード $download・デバイス上で約$installed';
  }

  @override
  String catalogMobileDataBody({required String size}) {
    return 'この辞書のサイズは約$sizeです。モバイルデータ通信またはテザリングで接続しているため、ダウンロードでデータ通信量を消費する可能性があります。';
  }

  @override
  String get dictionaryDownloadWifiLost =>
      'Wi-Fiが切断されたため、ダウンロードが停止しました。「ダウンロード」をタップしてもう一度お試しください。';

  @override
  String get downloadStoppedInBackground =>
      'Mekuruがバックグラウンドにあったため、ダウンロードが停止しました。「ダウンロード」をタップして再開してください。';

  @override
  String get catalogFindMoreTitle => '辞書をさらに探す';

  @override
  String get catalogFindMoreBody =>
      'これらのサイトでは、Mekuruで直接ダウンロードできないものも含め、さらに多くのYomitan辞書が紹介されています。辞書の.zipファイルをダウンロードし、「辞書の管理」の+ボタンからインポートしてください。';

  @override
  String get dictionaryManagerMoreDictionariesTooltip => 'その他の辞書';

  @override
  String get aboutCatalogDictionariesTitle => 'Jitendex・Wiktionary';

  @override
  String get aboutCatalogDictionariesDescription =>
      'Jitendex（作者：Stephen Kraus）は、JMdictとTatoebaプロジェクトの例文（CC BY 2.0 FR）をもとに作られています。Wiktionaryの辞書は、wiktextract、Kaikki.org、Wiktionary to Yomitanの各プロジェクトによってWiktionaryから作られています。';

  @override
  String get aboutJmnedictLabel => 'JMnedict：';

  @override
  String dictionaryManagerImportedOnVersion({
    required String date,
    required String version,
  }) {
    return '$dateに追加・v$version';
  }

  @override
  String get dictionaryImportParsingCollection => 'コレクションを解析中…';

  @override
  String dictionaryImportImportingCollection({
    required String name,
    required int current,
    required int total,
  }) {
    return '$nameをインポート中…（辞書 $current/$total）';
  }

  @override
  String dictionaryImportImportingEntries({
    required int processed,
    required int total,
  }) {
    return 'インポート中… $processed/$total';
  }

  @override
  String get dictionaryImportFinishing => '最終処理中… 少し時間がかかる場合があります';

  @override
  String dictionaryImportEntriesProgress({
    required int processed,
    required int total,
  }) {
    return '$processed/$total 項目';
  }

  @override
  String dictionaryImportedEntries({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件の項目をインポートしました',
      one: '1件の項目をインポートしました',
    );
    return '$_temp0';
  }

  @override
  String dictionaryImportedCollection({
    required int dictionaries,
    required int entries,
  }) {
    String _temp0 = intl.Intl.pluralLogic(
      dictionaries,
      locale: localeName,
      other: '辞書を$dictionaries件インポートしました（$entries項目）',
      one: '辞書を1件インポートしました（$entries項目）',
    );
    return '$_temp0';
  }

  @override
  String get dictionaryImportNoneInCollection => 'コレクションに辞書が見つかりませんでした';

  @override
  String backgroundWorkDictionaries({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '辞書を$count件ダウンロード中',
      one: '辞書を1件ダウンロード中',
    );
    return '$_temp0';
  }

  @override
  String get catalogJmdictInstalledTitle => 'JMdictはインストール済みです';

  @override
  String get catalogJmdictInstalledBody =>
      'JitendexはJMdictをもとに作られているため、両方をインストールしていると、ほとんどの意味が二重に表示されます。Jitendexのほうがレイアウトが見やすく、例文も収録されています。\n\n「JMdictを置き換える」を選ぶと、Jitendexのインストールが完了した時点でJMdictが削除されます。JMdictは「その他の辞書」からいつでも再ダウンロードできます。';

  @override
  String get catalogReplaceJmdict => 'JMdictを置き換える';

  @override
  String youFreeBooksSubtitle({required int classics, required int readers}) {
    final intl.NumberFormat classicsNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String classicsString = classicsNumberFormat.format(classics);

    return '名作$classicsString冊以上、レベル別読み物$readers冊';
  }

  @override
  String youStatsSubtitle({required String duration}) {
    return '今週は$duration';
  }

  @override
  String get youSettingsSubtitle => 'リーダー、辞書、バックアップなど';

  @override
  String get statsScreenTitle => '読書統計';

  @override
  String get libraryFreeBooksTipInApp =>
      'ヒント：レベル別読み物から名作まで、無料の日本語の本をこのアプリ内で入手できます。';

  @override
  String get freeBooksTitle => '無料の本';

  @override
  String get freeBooksSearchHint => 'タイトルや著者名で検索';

  @override
  String get freeBooksNoResults => '該当する本がありません。フィルターをいくつか解除してみてください。';

  @override
  String get freeBooksCatalogFailed => '本の一覧を読み込めませんでした。';

  @override
  String get freeBooksSortPopular => '人気順';

  @override
  String get freeBooksSortEasiest => 'やさしい順';

  @override
  String get freeBooksSortHardest => '難しい順';

  @override
  String get freeBooksSortShortest => '短い順';

  @override
  String get freeBooksSortLongest => '長い順';

  @override
  String get freeBooksSortByTitle => 'タイトル（五十音順）';

  @override
  String get freeBooksSortByAuthor => '著者（五十音順）';

  @override
  String get freeBooksLevel => 'レベル';

  @override
  String freeBooksLevelEstimate({required int level}) {
    return '~N$level';
  }

  @override
  String get freeBooksLevelBeyondN1 => 'N1超';

  @override
  String get freeBooksLevelEstimateNote =>
      'レベルは各書籍の漢字と文の長さから推定したもので、JLPTの公式な判定ではありません。';

  @override
  String get freeBooksEstimatedLevel => '推定レベル';

  @override
  String get freeBooksLength => '長さ';

  @override
  String get freeBooksLengthNote => '読書時間は一般的な学習者の読む速さで計算しています。';

  @override
  String get freeBooksLengthUnder10Minutes => '10分未満';

  @override
  String get freeBooksLengthUnder30Minutes => '10～30分';

  @override
  String get freeBooksLengthUnder1Hour => '30～60分';

  @override
  String get freeBooksLengthUnder3Hours => '1～3時間';

  @override
  String get freeBooksLengthLonger => '3時間以上';

  @override
  String freeBooksLengthAtLearnerPace({
    required String time,
    required int characters,
  }) {
    final intl.NumberFormat charactersNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String charactersString = charactersNumberFormat.format(characters);

    return '一般的な学習者のペースで約$time・$charactersString文字';
  }

  @override
  String get freeBooksGenre => 'ジャンル';

  @override
  String get freeBooksGenreFiction => '小説';

  @override
  String get freeBooksGenreChildren => '児童文学';

  @override
  String get freeBooksGenrePoetry => '詩歌';

  @override
  String get freeBooksGenrePlays => '戯曲';

  @override
  String get freeBooksGenreEssays => '随筆';

  @override
  String get freeBooksGenreDiaries => '日記・紀行';

  @override
  String get freeBooksGenreHistory => '歴史・伝記';

  @override
  String get freeBooksGenrePhilosophy => '哲学・宗教';

  @override
  String get freeBooksGenreNonfiction => 'その他のノンフィクション';

  @override
  String get freeBooksGenreOther => 'その他';

  @override
  String get freeBooksSpelling => '表記';

  @override
  String get freeBooksSpellingNote =>
      '戦前の表記は旧仮名遣いや旧字体を使っているため、学習者にはかなり難しくなります。';

  @override
  String get freeBooksSpellingModern => '新字新仮名';

  @override
  String get freeBooksSpellingOldKana => '新字旧仮名';

  @override
  String get freeBooksSpellingOldKanji => '旧字旧仮名';

  @override
  String get freeBooksSpellingOther => 'その他';

  @override
  String get freeBooksHideInLibrary => 'ライブラリにある本を非表示';

  @override
  String freeBooksResultCount({required int count}) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString冊',
      one: '$countString冊',
    );
    return '$_temp0';
  }

  @override
  String get freeBooksClearFilters => 'フィルターを解除';

  @override
  String get freeBooksEasyPicks => 'やさしい本';

  @override
  String get freeBooksInLibrary => 'ライブラリに追加済み';

  @override
  String get freeBooksViewOnAozora => '青空文庫で見る';

  @override
  String get freeBooksDownloading => 'ダウンロード中…';

  @override
  String get freeBooksRead => '読む';

  @override
  String get freeBooksDownloadFailed =>
      '本をダウンロードできませんでした。サイトが混み合っているか、接続が切れた可能性があります。もう一度お試しください。';

  @override
  String get freeBooksImportFailed => 'この本をライブラリに追加できませんでした。';

  @override
  String get freeBooksAozoraAttribution =>
      'ボランティアの手で入力された日本語書籍の無料図書館「青空文庫」より。各書籍の最終ページに入力・校正者のクレジットを掲載しています。';

  @override
  String get freeBooksTabGradedReaders => 'レベル別読み物';

  @override
  String get freeBooksTabAozora => '青空文庫';

  @override
  String get freeBooksTadokuSearchHint => 'レベル別読み物を検索';

  @override
  String get freeBooksTadokuLevelStart => 'スタート';

  @override
  String get freeBooksTadokuPagesOnly => '画像のみ';

  @override
  String get freeBooksTadokuPagesOnlyNote =>
      'この本のPDFはページの画像なので、単語をタップできません。OCR（Pro機能）を使うとタップできるようになります。';

  @override
  String get freeBooksTadokuAudio => 'tadoku.orgで音声を再生できます。';

  @override
  String get freeBooksViewOnTadoku => 'Tadokuで見る';

  @override
  String get freeBooksTadokuLicense => 'ライセンス：CC BY-NC-ND 4.0';

  @override
  String freeBooksTadokuLevel({required int level}) {
    return 'L$level';
  }

  @override
  String freeBooksTadokuLevelJlpt({required int level, required String jlpt}) {
    return 'L$level・$jlpt';
  }

  @override
  String freeBooksTadokuCharacters({required int characters}) {
    final intl.NumberFormat charactersNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String charactersString = charactersNumberFormat.format(characters);

    return '$charactersString文字';
  }

  @override
  String freeBooksTadokuAttribution({required String publisher}) {
    return '$publisher（NPO Tadoku Supporters）によるレベル別読み物で、CC BY-NC-ND 4.0のもと無料で公開されています。Mekuruはtadoku.orgから無改変でダウンロードしています。';
  }

  @override
  String get attributionFreeBooksTitle => '無料の本';

  @override
  String get attributionFreeBooksDescription =>
      '名作は青空文庫から収録しており、その目録はCC BY 4.0で公開されています。読書レベルと長さはaozorabunko-cleanデータセット（CC BY 4.0）を使って推定しています。レベル別読み物はNPO多言語多読（NPO Tadoku Supporters）によるもので、CC BY-NC-ND 4.0で公開されており、tadoku.orgから無改変でダウンロードしています。';

  @override
  String readingProgressPercent({required int percent}) {
    return '$percent%読了';
  }

  @override
  String get libraryBookOptions => '本のオプション';

  @override
  String get highlightColorYellow => 'イエロー';

  @override
  String get readerSelectSentence => '文を選択';

  @override
  String readerPageOf({required int page, required int total}) {
    return '$totalページ中$pageページ';
  }

  @override
  String get readerNextPage => '次のページ';

  @override
  String get readerPreviousPage => '前のページ';

  @override
  String get readerShowHideControls => 'コントロールを表示または非表示にします';

  @override
  String get readerSeekBarLabel => '読書位置';

  @override
  String get readerVolumeKeysTitle => '音量ボタンでページめくり';

  @override
  String get readerVolumeKeysDownNext => '下：次へ';

  @override
  String get readerVolumeKeysUpNext => '上：次へ';

  @override
  String get ndlTextModelTitle => 'スキャン書籍用読み取りモデル — NDLOCR-Lite';

  @override
  String get ndlTextModelDescription =>
      'PDFからインポートした本を端末上の文字認識（OCR）で読み取るときに使われ、長い行のテキストをはるかに正確に読み取れます。「無料の本」のスキャン版レベル別読み物にはこのモデルが必要です。ページ画像が端末の外に送信されることはありません。';

  @override
  String get ndlTextModelPromptTitle => 'スキャン書籍用読み取りモデルが必要';

  @override
  String ndlTextModelPromptBody({required String size}) {
    return 'この無料の本は、テキストのページをスキャンしたものです。端末上のOCRでは、スキャン書籍用読み取りモデル（$size、「ダウンロード」から入手）を使って読み取ります。';
  }

  @override
  String get localOcrLicenseNdl =>
      'NDLOCR-Lite 文字認識モデル © National Diet Library, Japan（国立国会図書館）。スキャンした本の読み取りに無改変で使用しています。CC BY 4.0。';

  @override
  String get lookupTabDictionary => '辞書';

  @override
  String get lookupTabSentence => '文';

  @override
  String get sentenceTranslationTapToShow => 'タップして翻訳を表示';

  @override
  String sentenceTranslationDownload({required String size}) {
    return '日本語翻訳データ（$size）をダウンロードすると、オフラインで文を翻訳できます。';
  }

  @override
  String get sentenceTranslationDownloadIos => '翻訳にはAppleの日本語言語パックが必要です。';

  @override
  String get sentenceTranslationUnsupported => 'この端末では文の翻訳を利用できません。';

  @override
  String get sentenceTranslationFailed => 'この文を翻訳できませんでした。';

  @override
  String get sentenceTranslationEngine => '機械翻訳';

  @override
  String get sentenceTranslationEngineIos => 'Appleによる翻訳';

  @override
  String get sentenceTranslationEdit => '文を編集';

  @override
  String get settingsSentenceTranslationTitle => '文の翻訳';

  @override
  String get settingsSentenceTranslationShown => '翻訳を表示';

  @override
  String get settingsSentenceTranslationHidden => 'タップするまで隠す';

  @override
  String get settingsSentenceTranslationOff => 'オフ';

  @override
  String get downloadsSentenceTranslationTitle => '日本語翻訳';

  @override
  String get downloadsSentenceTranslationSubtitle => '調べた単語を含む文を、オフラインで翻訳します。';

  @override
  String get ankidroidDataSourceSentenceTranslation => '文の翻訳';

  @override
  String get attributionFirefoxTranslationsTitle => 'Firefox Translations';

  @override
  String get attributionFirefoxTranslationsDescription =>
      'Androidでは、文の翻訳にMozillaのFirefox Translationsのエンジンとモデルを使い、端末上で処理しています。';

  @override
  String get sentenceTranslationLowMemoryTitle => 'この端末では動作が重くなる可能性があります';

  @override
  String get sentenceTranslationLowMemoryBody =>
      '文の翻訳には約250 MBのメモリが必要です。この端末では動作が遅くなったり、Mekuruが終了したりする可能性があります。その場合は「設定 › 文の翻訳」でオフにしてください。';

  @override
  String get sentenceTranslationTurnOff => 'オフにする';

  @override
  String get settingsTranslationModelTitle => '翻訳モデル';

  @override
  String get translationModelStandard => '標準';

  @override
  String get translationModelHigh => '高品質';

  @override
  String translationModelStandardOption({required String size}) {
    return '標準（$size）';
  }

  @override
  String translationModelHighOption({required String size}) {
    return '高品質（$size）';
  }

  @override
  String translationHighQualityDownloading({required String percent}) {
    return '高品質：ダウンロード中 $percent%';
  }

  @override
  String translationModelHighDownloadFirst({required String size}) {
    return '未ダウンロードです。タップするとダウンロードします（$size）。';
  }

  @override
  String get translationHighQualityNotReady => '高品質はまだ準備ができていないため、標準を使用しています。';

  @override
  String get translationHighQualityCouldNotLoad => '高品質を読み込めなかったため、標準を使用しています。';

  @override
  String get translationHighQualityTooSlow => '高品質に時間がかかっているため、いったん標準を使用しています。';

  @override
  String get translationHighQualityStarting =>
      '高品質を起動しています。最初の翻訳には少し時間がかかることがあります。';

  @override
  String get translationHighQualityDownloadFailedTitle =>
      '高品質モデルのダウンロードに失敗しました';

  @override
  String get translationHighQualityDownloadFailedBody =>
      'Mekuruの「ダウンロード」から、もう一度お試しください。';

  @override
  String get translationHighQualityNeedsStandard =>
      '高品質を読み込めませんでした。この文を翻訳するには、標準をダウンロードしてください。';

  @override
  String get translationHighQualityLowMemoryBody =>
      '高品質モデルには約2 GBのメモリが必要です。この端末では動作が遅くなったり、Mekuruが終了したりする可能性があります。その場合は「設定 › 翻訳モデル」で元に戻してください。';

  @override
  String get translationHighQualityUseStandard => '標準を使う';

  @override
  String get downloadsHighQualityTitle => '高品質翻訳（Gemma 4）';

  @override
  String get downloadsHighQualitySubtitle =>
      'より精度の高い文の翻訳ができる大きめのモデルです。メモリに余裕のある端末向けです。';

  @override
  String get attributionGemmaTitle => 'Gemma 4';

  @override
  String get attributionGemmaDescription =>
      'Androidでは、高品質翻訳モデルとしてGoogleのGemma 4を使い、LiteRT-LMで端末上で実行しています。';

  @override
  String translationMobileDataBody({required String size}) {
    return '翻訳モデルのサイズは約$sizeです。モバイルデータ通信またはテザリングで接続中のため、ダウンロードでデータ通信量を消費する可能性があります。';
  }

  @override
  String get serverBrowseDownloadInterrupted =>
      'ダウンロードが中断されました。もう一度本をダウンロードしてください。';

  @override
  String get serverErrorConnectionGone => 'サーバー接続が削除されたか、オフになりました。';

  @override
  String get ocrErrorCertificateUntrusted =>
      'OCRサーバーの証明書が信頼されていません。独自の（自己署名）証明書を使っている場合は、「カスタムOCRサーバー」の設定で「自己署名証明書を許可」をオンにしてください。';

  @override
  String get ocrErrorAuthFailed => '認証に失敗しました。「カスタムOCRサーバー」の設定で共有キーを確認してください。';

  @override
  String get ocrErrorJobForbidden => 'このOCRジョブは別のアカウントのものです。新しくOCRを実行してください。';

  @override
  String get ocrErrorNoCredits => 'OCRクレジットが足りません。';

  @override
  String get ocrErrorJobNotFound => 'OCRジョブが見つかりませんでした。新しくOCRを実行してください。';

  @override
  String get ocrErrorJobInactive => 'このOCRジョブはすでに無効です。新しくOCRを実行してください。';

  @override
  String ocrErrorRejected({required String details}) {
    return 'OCRサーバーがリクエストを拒否しました：$details';
  }

  @override
  String ocrErrorServer({required int status}) {
    return 'OCRサーバーエラー（$status）。サーバーが停止しているか、設定に誤りがある可能性があります。';
  }

  @override
  String get ocrErrorConnectFailed =>
      'OCRサーバーに接続できませんでした。サーバーのURLと、サーバーが起動しているかを確認してください。';

  @override
  String get ocrErrorTimedOut => 'OCRサーバーが応答しません（タイムアウト）。';

  @override
  String get ocrErrorHostNotFound =>
      'OCRサーバーのアドレスが見つかりませんでした。サーバーのURLを確認してください。';

  @override
  String ocrErrorNetwork({required String details}) {
    return 'ネットワークエラー：$details';
  }

  @override
  String ocrErrorStatus({required int status, required String details}) {
    return 'OCRサーバーがエラー $status を返しました：$details';
  }

  @override
  String get ocrErrorMalformedResponse =>
      'OCRサーバーから、Mekuruが読み取れない応答が返されました。サーバーのURLが対応するOCRサーバーを指しているか確認してください。';

  @override
  String get ocrErrorServerUrlInvalid =>
      'OCRサーバーのURLが無効です。http:// または https:// から始まる完全なURLを入力してください。';

  @override
  String get ocrErrorSignInFailed => 'OCRサービスにサインインできませんでした。';

  @override
  String ocrErrorPageImageMissing({required String path}) {
    return 'マンガの画像「$path」を読み込めませんでした。マンガの画像フォルダがまだあるか確認してください。';
  }

  @override
  String ocrErrorPageImageAccessLost({required String path}) {
    return '選択したフォルダからマンガの画像「$path」を読み込めませんでした。フォルダへのアクセス権が変わった場合は、マンガをもう一度インポートしてください。';
  }

  @override
  String get ocrErrorRecognitionFailed => '文字認識に失敗しました。';

  @override
  String get localOcrImageUnsupported => 'ページ画像の形式またはサイズがOCRで読み取れません。';

  @override
  String get localOcrTooManyFailures =>
      '複数のページで続けて失敗したため、スキャンを停止しました。進捗は保存されています。';

  @override
  String get localOcrBookChanged => 'マンガが変更されたか、ファイルが見つかりません。新しくスキャンを開始してください。';

  @override
  String get localOcrStillRunning => 'OCRはまだ実行中か停止処理中です。しばらく待ってから、もう一度お試しください。';

  @override
  String get localOcrJobEnded => 'このスキャンはすでに停止または完了しています。';

  @override
  String get localOcrDownloadNetwork =>
      'ダウンロードで接続できませんでした。インターネット接続を確認して、もう一度お試しください。';

  @override
  String get localOcrDownloadDamaged =>
      'ダウンロードしたファイルが破損しています。もう一度ダウンロードしてください。';

  @override
  String get localOcrModelInstallFailed =>
      'ダウンロードしたモデルをインストールできませんでした。もう一度お試しください。';

  @override
  String proErrorLoadBilling({required String store, required String details}) {
    return '$storeに接続できませんでした：$details';
  }

  @override
  String proErrorLoadAccess({required String details}) {
    return 'Proの利用状況を確認できませんでした：$details';
  }

  @override
  String proErrorLoadPrice({required String store, required String details}) {
    return '$storeから価格を読み込めませんでした：$details';
  }

  @override
  String get proErrorOffline => 'インターネットに接続されていません。接続を確認して、もう一度お試しください。';

  @override
  String get proErrorSignInRequired => 'OCRの課金機能を使う前に、Googleでサインインしてください。';

  @override
  String get proErrorAppCheck => 'サーバーでMekuruを確認できませんでした。数分待ってから、もう一度お試しください。';

  @override
  String proErrorStore({required String store}) {
    return '$storeに接続できませんでした。しばらくしてから、もう一度お試しください。';
  }

  @override
  String get proErrorPurchasesUnavailable => 'この端末では購入を利用できません。';

  @override
  String get proErrorPurchaseNotStarted => '購入を開始できませんでした。もう一度お試しください。';

  @override
  String proErrorPurchaseTimeout({required String store}) {
    return '$storeで購入が時間内に完了しませんでした。料金が請求された場合は、「購入を復元」をタップしてください。';
  }

  @override
  String get proPurchasePending => 'お支払いを処理しています。確認が完了すると、Proが自動的に有効になります。';

  @override
  String get proErrorPaymentDeclined => 'お支払いを処理できませんでした。別のお支払い方法をお試しください。';

  @override
  String get proErrorPurchaseCancelled => '購入がキャンセルされました。';

  @override
  String get proErrorPurchaseNotConfirmed =>
      '購入を確認できませんでした。「購入を復元」をタップして、もう一度お試しください。';

  @override
  String get proErrorSignInCancelled => 'Googleへのサインインがキャンセルされました。';

  @override
  String get proErrorTooManySignIns => 'サインインの試行回数が多すぎます。数分待ってから、もう一度お試しください。';

  @override
  String settingsCustomOcrServerUnhealthy({required String status}) {
    return '接続できましたが、/health のステータスが「ok」ではなく「$status」でした。';
  }

  @override
  String get downloadInterrupted =>
      'ダウンロードが中断されました。「ダウンロード」をタップして、もう一度お試しください。';

  @override
  String get settingsLowRamModeTitle => '省メモリモード';

  @override
  String get settingsLowRamModeSubtitle => '電子ペーパー端末や、RAMが4 GB以下の端末向け';

  @override
  String get lowRamModeHintTitle => '省メモリモードをオンにしますか？';

  @override
  String get lowRamModeHintBody =>
      'この端末のRAMは4 GB以下です。省メモリモードではMekuruのメモリ使用量が減り、アプリを切り替えたときにAndroidに終了されにくくなります。文の翻訳、端末上のOCR、拡張ふりがな辞書、アニメーションはオフになります。この設定は「設定 › 省メモリモード」で変更できます。';

  @override
  String get lowRamModeHintDontShowAgain => '今後表示しない';

  @override
  String get lowRamModeTurnOn => 'オンにする';

  @override
  String get lowRamModeNotNow => '後で';

  @override
  String get lowRamModeCloseBody =>
      '拡張ふりがな辞書は、Mekuruを終了するまで約250 MBのメモリを使い続けます。メモリを解放するには、今すぐMekuruを終了してから、もう一度開いてください。';

  @override
  String get lowRamModeCloseNow => '今すぐMekuruを終了';

  @override
  String get lowRamModeOffHere => '省メモリモードではオフ';

  @override
  String get readerSearchTooltip => '本の中を検索';

  @override
  String get readerSearchHint => 'この本を検索';

  @override
  String get readerSearchNoResults => 'この本には一致する箇所がありません';

  @override
  String readerSearchResultCount({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件一致',
      one: '1件一致',
    );
    return '$_temp0';
  }

  @override
  String readerSearchResultsCapped({required int count}) {
    return '最初の$count件を表示しています';
  }

  @override
  String get mangaDetectSpreadsTitle => '見開きページを検出';

  @override
  String get mangaDetectSpreadsSubtitle => '見開きで横長のページを単独表示';

  @override
  String get mangaShiftSpreadsTitle => 'ページの組み合わせを1ページずらす';

  @override
  String get mangaShiftSpreadsSubtitle => 'ページの組み合わせがずれている本向け';
}
