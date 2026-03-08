import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ja.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ja'),
  ];

  /// Application title.
  ///
  /// In en, this message translates to:
  /// **'Mekuru'**
  String get appTitle;

  /// Bottom navigation label for the library tab.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get navLibrary;

  /// Bottom navigation label for the dictionary tab.
  ///
  /// In en, this message translates to:
  /// **'Dictionary'**
  String get navDictionary;

  /// Bottom navigation label for the vocabulary tab.
  ///
  /// In en, this message translates to:
  /// **'Vocabulary'**
  String get navVocabulary;

  /// Bottom navigation label for the settings tab.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// Tooltip or button label for help.
  ///
  /// In en, this message translates to:
  /// **'Help'**
  String get commonHelp;

  /// Generic import label.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get commonImport;

  /// Action label to open imported content immediately.
  ///
  /// In en, this message translates to:
  /// **'Open now'**
  String get commonOpenNow;

  /// Generic cancel action.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// Generic close action.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// Generic save action.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// Generic delete action.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// Generic download action.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get commonDownload;

  /// Button label to open the dictionary screen.
  ///
  /// In en, this message translates to:
  /// **'Open Dictionary'**
  String get commonOpenDictionary;

  /// Action label to manage installed dictionaries.
  ///
  /// In en, this message translates to:
  /// **'Manage Dictionaries'**
  String get commonManageDictionaries;

  /// Action label to clear a list.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get commonClearAll;

  /// Action label to clear the search query.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get commonClearSearch;

  /// Generic search label.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get commonSearch;

  /// Generic back action.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get commonBack;

  /// Generic retry action.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// Generic confirmation action.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get commonOk;

  /// Generic undo action.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get commonUndo;

  /// Generic unlock action.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get commonUnlock;

  /// Action label to open the settings screen.
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get commonOpenSettings;

  /// Acknowledgement action label.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get commonGotIt;

  /// Generic error message with details.
  ///
  /// In en, this message translates to:
  /// **'Error: {details}'**
  String commonErrorWithDetails({required String details});

  /// Tooltip for the library sort button.
  ///
  /// In en, this message translates to:
  /// **'Sort: {label}'**
  String librarySortTooltip({required String label});

  /// Title shown when the library has no books.
  ///
  /// In en, this message translates to:
  /// **'Your library is ready for its first book'**
  String get libraryEmptyTitle;

  /// Description shown when the library has no books.
  ///
  /// In en, this message translates to:
  /// **'Import something to read, install a dictionary, and you will be ready to save words in a few minutes.'**
  String get libraryEmptySubtitle;

  /// Button label to import an EPUB file.
  ///
  /// In en, this message translates to:
  /// **'Import EPUB'**
  String get libraryImportEpub;

  /// Button label to import manga content.
  ///
  /// In en, this message translates to:
  /// **'Import Manga'**
  String get libraryImportManga;

  /// Button label to open downloadable dictionaries.
  ///
  /// In en, this message translates to:
  /// **'Get Dictionaries'**
  String get libraryGetDictionaries;

  /// Button label to restore a backup.
  ///
  /// In en, this message translates to:
  /// **'Restore Backup'**
  String get libraryRestoreBackup;

  /// Title for the supported media help dialog.
  ///
  /// In en, this message translates to:
  /// **'Supported Media'**
  String get librarySupportedMediaTitle;

  /// Heading for EPUB help information.
  ///
  /// In en, this message translates to:
  /// **'EPUB Books'**
  String get libraryEpubBooksTitle;

  /// Description of supported EPUB imports.
  ///
  /// In en, this message translates to:
  /// **'Standard .epub files are supported. Tap the + button and select \"Import EPUB\" to add one from your device.'**
  String get libraryEpubBooksDescription;

  /// Heading for Mokuro import help.
  ///
  /// In en, this message translates to:
  /// **'Mokuro Manga'**
  String get libraryMokuroTitle;

  /// Description of Mokuro manga imports.
  ///
  /// In en, this message translates to:
  /// **'Import manga by selecting a folder, then choosing a .mokuro or .html file. The page images are loaded from a sibling folder with the same name.'**
  String get libraryMokuroDescription;

  /// Description of the Mokuro format.
  ///
  /// In en, this message translates to:
  /// **'The .mokuro file is generated by the mokuro tool, which runs OCR on manga pages to extract Japanese text.'**
  String get libraryMokuroFormatDescription;

  /// Button label to learn about Mokuro file creation.
  ///
  /// In en, this message translates to:
  /// **'Learn how to create .mokuro files'**
  String get libraryLearnHowToCreateMokuroFiles;

  /// Title for the library sort picker.
  ///
  /// In en, this message translates to:
  /// **'Sort by'**
  String get librarySortBy;

  /// Sort label for imported date.
  ///
  /// In en, this message translates to:
  /// **'Date imported'**
  String get librarySortDateImported;

  /// Sort label for recently read books.
  ///
  /// In en, this message translates to:
  /// **'Recently read'**
  String get librarySortRecentlyRead;

  /// Sort label for alphabetical ordering.
  ///
  /// In en, this message translates to:
  /// **'Alphabetical'**
  String get librarySortAlphabetical;

  /// Title for the import picker.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get libraryImportTitle;

  /// Subtitle describing EPUB import.
  ///
  /// In en, this message translates to:
  /// **'Import an EPUB file'**
  String get libraryImportEpubSubtitle;

  /// Subtitle describing manga import.
  ///
  /// In en, this message translates to:
  /// **'Choose a CBZ archive or Mokuro folder'**
  String get libraryImportMangaSubtitle;

  /// Title for the manga import type picker.
  ///
  /// In en, this message translates to:
  /// **'Import Manga'**
  String get libraryImportMangaTitle;

  /// Description for the manga import type picker.
  ///
  /// In en, this message translates to:
  /// **'Choose whether you want to import a CBZ archive or a Mokuro-exported folder.'**
  String get libraryImportMangaDescription;

  /// Title for the Mokuro folder import option.
  ///
  /// In en, this message translates to:
  /// **'Mokuro folder'**
  String get libraryImportMokuroFolder;

  /// Subtitle for the Mokuro folder import option.
  ///
  /// In en, this message translates to:
  /// **'Select the folder that contains a .mokuro or .html file alongside the images folder.'**
  String get libraryImportMokuroFolderSubtitle;

  /// Button label to learn what Mokuro is.
  ///
  /// In en, this message translates to:
  /// **'What is Mokuro?'**
  String get libraryWhatIsMokuro;

  /// Title for the CBZ import option.
  ///
  /// In en, this message translates to:
  /// **'CBZ archive'**
  String get libraryImportCbzArchive;

  /// Subtitle for the CBZ import option.
  ///
  /// In en, this message translates to:
  /// **'Import a .cbz comic book archive'**
  String get libraryImportCbzArchiveSubtitle;

  /// Snackbar shown after importing manga without OCR data.
  ///
  /// In en, this message translates to:
  /// **'Imported without OCR. To get text overlays, import external OCR output (e.g. .mokuro).'**
  String get libraryImportedWithoutOcrMessage;

  /// Snackbar shown when the Mokuro project link cannot be opened.
  ///
  /// In en, this message translates to:
  /// **'Could not open the Mokuro project page.'**
  String get libraryCouldNotOpenMokuroProjectPage;

  /// Error shown when no supported manga manifest file is found.
  ///
  /// In en, this message translates to:
  /// **'No .mokuro or .html files found in the selected folder.'**
  String get libraryNoMangaManifestFound;

  /// Native dialog title for picking a manga folder.
  ///
  /// In en, this message translates to:
  /// **'Select manga folder'**
  String get librarySelectMangaFolder;

  /// Fallback label for a selected folder.
  ///
  /// In en, this message translates to:
  /// **'Selected folder'**
  String get librarySelectedFolder;

  /// Subtitle showing how many manga manifest files were found.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {# manga file found} other {# manga files found}}'**
  String libraryMangaFilesFound({required int count});

  /// Placeholder text for the dictionary search field.
  ///
  /// In en, this message translates to:
  /// **'Search in kanji, kana, or romaji...'**
  String get dictionarySearchHint;

  /// Title shown when no dictionaries have been imported.
  ///
  /// In en, this message translates to:
  /// **'No dictionaries imported'**
  String get dictionaryNoDictionariesTitle;

  /// Description shown when no dictionaries have been imported.
  ///
  /// In en, this message translates to:
  /// **'Install the starter pack or import your own Yomitan dictionaries to start searching.'**
  String get dictionaryNoDictionariesSubtitle;

  /// Button label for the recommended dictionary starter pack.
  ///
  /// In en, this message translates to:
  /// **'Recommended starter pack'**
  String get dictionaryRecommendedStarterPack;

  /// Title shown when all dictionaries are disabled.
  ///
  /// In en, this message translates to:
  /// **'Your dictionaries are turned off'**
  String get dictionaryNoEnabledTitle;

  /// Description shown when all dictionaries are disabled.
  ///
  /// In en, this message translates to:
  /// **'Enable at least one dictionary to make lookups work, or install the recommended starter pack.'**
  String get dictionaryNoEnabledSubtitle;

  /// Button label to enable dictionaries.
  ///
  /// In en, this message translates to:
  /// **'Enable dictionaries'**
  String get dictionaryEnableDictionaries;

  /// Button label for the starter pack.
  ///
  /// In en, this message translates to:
  /// **'Starter pack'**
  String get dictionaryStarterPack;

  /// Message shown when a dictionary search returns no matches.
  ///
  /// In en, this message translates to:
  /// **'No results found.'**
  String get dictionaryNoResultsFound;

  /// Title shown in the empty dictionary search state.
  ///
  /// In en, this message translates to:
  /// **'Search for a word'**
  String get dictionarySearchForAWord;

  /// Description shown in the empty dictionary search state.
  ///
  /// In en, this message translates to:
  /// **'Type in kanji, hiragana, katakana, or romaji'**
  String get dictionarySearchForAWordSubtitle;

  /// Heading for recent dictionary searches.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get dictionaryRecent;

  /// Snackbar shown after saving a word to vocabulary.
  ///
  /// In en, this message translates to:
  /// **'Saved \"{expression}\"'**
  String dictionarySavedWord({required String expression});

  /// Snackbar shown when a word is already saved in vocabulary.
  ///
  /// In en, this message translates to:
  /// **'Word already exists in vocab list'**
  String get dictionaryWordAlreadyExistsInVocab;

  /// Snackbar shown after copying a word.
  ///
  /// In en, this message translates to:
  /// **'Copied \"{expression}\"'**
  String dictionaryCopiedWord({required String expression});

  /// Snackbar shown when a word already exists in Anki.
  ///
  /// In en, this message translates to:
  /// **'Word already exists in default deck'**
  String get dictionaryWordAlreadyExistsInAnki;

  /// Snackbar shown after adding a word to Anki.
  ///
  /// In en, this message translates to:
  /// **'Added \"{expression}\" to Anki'**
  String dictionaryAddedToAnki({required String expression});

  /// Tooltip for copying a dictionary expression.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get dictionaryCopyTooltip;

  /// Tooltip shown when the word already exists in Anki.
  ///
  /// In en, this message translates to:
  /// **'Already in default Anki deck. Long press to add anyway'**
  String get dictionaryAlreadyInAnkiTooltip;

  /// Tooltip shown while checking for an existing Anki note.
  ///
  /// In en, this message translates to:
  /// **'Checking default Anki deck'**
  String get dictionaryCheckingAnkiTooltip;

  /// Tooltip for sending a word to AnkiDroid.
  ///
  /// In en, this message translates to:
  /// **'Send to AnkiDroid'**
  String get dictionarySendToAnkiTooltip;

  /// Tooltip shown when a word is already saved to vocabulary.
  ///
  /// In en, this message translates to:
  /// **'Already in vocab list'**
  String get dictionaryAlreadyInVocabTooltip;

  /// Tooltip for saving a word to vocabulary.
  ///
  /// In en, this message translates to:
  /// **'Save to Vocabulary'**
  String get dictionarySaveToVocabularyTooltip;

  /// Badge label for very common words.
  ///
  /// In en, this message translates to:
  /// **'Very Common'**
  String get dictionaryVeryCommon;

  /// Label for onyomi readings.
  ///
  /// In en, this message translates to:
  /// **'Onyomi: '**
  String get dictionaryOnyomiLabel;

  /// Label for kunyomi readings.
  ///
  /// In en, this message translates to:
  /// **'Kunyomi: '**
  String get dictionaryKunyomiLabel;

  /// Placeholder text for searching saved vocabulary.
  ///
  /// In en, this message translates to:
  /// **'Search saved words'**
  String get vocabularySearchSavedWordsHint;

  /// Tooltip for exporting vocabulary as CSV.
  ///
  /// In en, this message translates to:
  /// **'Export CSV'**
  String get vocabularyExportCsvTooltip;

  /// Title shown when there are no saved vocabulary entries.
  ///
  /// In en, this message translates to:
  /// **'No saved words yet'**
  String get vocabularyEmptyTitle;

  /// Description shown when there are no saved vocabulary entries.
  ///
  /// In en, this message translates to:
  /// **'Save words from dictionary searches or while reading, and they will show up here with context.'**
  String get vocabularyEmptySubtitle;

  /// Title shown when no saved vocabulary matches the search query.
  ///
  /// In en, this message translates to:
  /// **'No matches for \"{query}\"'**
  String vocabularyNoMatches({required String query});

  /// Description shown when no vocabulary items match the search query.
  ///
  /// In en, this message translates to:
  /// **'Try the expression, reading, or part of a definition.'**
  String get vocabularyNoMatchesSubtitle;

  /// App bar title showing how many vocabulary items are selected.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String vocabularySelectedCount({required int count});

  /// Tooltip for deselecting all vocabulary items.
  ///
  /// In en, this message translates to:
  /// **'Deselect all'**
  String get vocabularyDeselectAllTooltip;

  /// Tooltip for selecting all vocabulary items.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get vocabularySelectAllTooltip;

  /// Tooltip for exporting selected vocabulary items.
  ///
  /// In en, this message translates to:
  /// **'Export selected'**
  String get vocabularyExportSelectedTooltip;

  /// Fallback text when a saved word has no definition.
  ///
  /// In en, this message translates to:
  /// **'No definition'**
  String get vocabularyNoDefinition;

  /// Label for the saved sentence context.
  ///
  /// In en, this message translates to:
  /// **'Context:'**
  String get vocabularyContextLabel;

  /// Date label shown for a saved vocabulary entry.
  ///
  /// In en, this message translates to:
  /// **'Added: {date}'**
  String vocabularyAddedOn({required String date});

  /// Snackbar shown after deleting a vocabulary entry.
  ///
  /// In en, this message translates to:
  /// **'Deleted \"{expression}\"'**
  String vocabularyDeletedWord({required String expression});

  /// Progress label for OCR pages completed.
  ///
  /// In en, this message translates to:
  /// **'{completed}/{total} pages'**
  String ocrPagesProgress({required int completed, required int total});

  /// ETA label for OCR progress under one minute.
  ///
  /// In en, this message translates to:
  /// **'~{seconds}s remaining'**
  String ocrEtaSecondsRemaining({required int seconds});

  /// ETA label for OCR progress in minutes.
  ///
  /// In en, this message translates to:
  /// **'~{minutes} min remaining'**
  String ocrEtaMinutesRemaining({required int minutes});

  /// ETA label for OCR progress in hours and minutes.
  ///
  /// In en, this message translates to:
  /// **'~{hours}h {minutes}m remaining'**
  String ocrEtaHoursMinutesRemaining({
    required int hours,
    required int minutes,
  });

  /// Title shown when OCR work is paused.
  ///
  /// In en, this message translates to:
  /// **'OCR Paused'**
  String get ocrPaused;

  /// Title shown when OCR work is complete.
  ///
  /// In en, this message translates to:
  /// **'OCR Complete'**
  String get ocrComplete;

  /// Title shown when OCR work fails.
  ///
  /// In en, this message translates to:
  /// **'OCR Failed'**
  String get ocrFailed;

  /// Prompt shown when OCR errors have details.
  ///
  /// In en, this message translates to:
  /// **'Tap for details'**
  String get ocrTapForDetails;

  /// Dialog title shown when OCR requires a custom server.
  ///
  /// In en, this message translates to:
  /// **'Custom OCR Server Required'**
  String get ocrCustomServerRequiredTitle;

  /// Dialog body shown when OCR requires a custom server.
  ///
  /// In en, this message translates to:
  /// **'Remote manga OCR now uses your own server. Open Settings and add a custom OCR server URL plus the matching shared key.'**
  String get ocrCustomServerRequiredBody;

  /// Dialog title shown when a custom OCR server key is missing.
  ///
  /// In en, this message translates to:
  /// **'Custom Server Setup Required'**
  String get ocrCustomServerKeyRequiredTitle;

  /// Dialog body shown when a custom OCR server key is missing.
  ///
  /// In en, this message translates to:
  /// **'Custom OCR servers require a shared key. Open Custom OCR Server settings and enter the same AUTH_API_KEY value configured on your server.'**
  String get ocrCustomServerKeyRequiredBody;

  /// Title for the Pro upgrade screen.
  ///
  /// In en, this message translates to:
  /// **'Pro'**
  String get proTitle;

  /// Snackbar shown after a purchase confirmation is received.
  ///
  /// In en, this message translates to:
  /// **'Your purchase has been confirmed!'**
  String get proPurchaseConfirmed;

  /// Heading for the Pro purchase card.
  ///
  /// In en, this message translates to:
  /// **'Unlock Pro once'**
  String get proUnlockOnceTitle;

  /// Chip label when Pro is unlocked.
  ///
  /// In en, this message translates to:
  /// **'Unlocked'**
  String get proStatusUnlocked;

  /// Chip label when Pro is locked.
  ///
  /// In en, this message translates to:
  /// **'Locked'**
  String get proStatusLocked;

  /// Description of the Pro purchase.
  ///
  /// In en, this message translates to:
  /// **'One-time purchase for reader power features.'**
  String get proUnlockDescription;

  /// Button label to restore a Pro purchase.
  ///
  /// In en, this message translates to:
  /// **'Restore Purchase'**
  String get proRestorePurchase;

  /// Title of the auto-crop Pro feature.
  ///
  /// In en, this message translates to:
  /// **'Auto-Crop'**
  String get proFeatureAutoCropTitle;

  /// Description of the auto-crop Pro feature.
  ///
  /// In en, this message translates to:
  /// **'Trim empty manga page margins after a one-time setup per book.'**
  String get proFeatureAutoCropDescription;

  /// Title of the book highlights Pro feature.
  ///
  /// In en, this message translates to:
  /// **'Book Highlights'**
  String get proFeatureHighlightsTitle;

  /// Description of the book highlights Pro feature.
  ///
  /// In en, this message translates to:
  /// **'Save and review highlighted passages while reading EPUB books.'**
  String get proFeatureHighlightsDescription;

  /// Title of the custom OCR server Pro feature.
  ///
  /// In en, this message translates to:
  /// **'Custom OCR Server'**
  String get proFeatureCustomOcrTitle;

  /// Description of the custom OCR server Pro feature.
  ///
  /// In en, this message translates to:
  /// **'Run remote manga OCR with your own server and shared key.'**
  String get proFeatureCustomOcrDescription;

  /// Button label linking to the OCR server repository.
  ///
  /// In en, this message translates to:
  /// **'Server Repo'**
  String get proServerRepo;

  /// Button label when Pro is already unlocked.
  ///
  /// In en, this message translates to:
  /// **'Already Unlocked'**
  String get proAlreadyUnlocked;

  /// Button label to unlock Pro.
  ///
  /// In en, this message translates to:
  /// **'Unlock Pro'**
  String get proUnlock;

  /// Button label to unlock Pro with the price included.
  ///
  /// In en, this message translates to:
  /// **'Unlock Pro {price}'**
  String proUnlockWithPrice({required String price});

  /// Title for the downloads screen.
  ///
  /// In en, this message translates to:
  /// **'Downloads'**
  String get downloadsTitle;

  /// Heading for the recommended dictionary starter pack.
  ///
  /// In en, this message translates to:
  /// **'Recommended starter pack'**
  String get downloadsRecommendedStarterPackTitle;

  /// Description for the recommended starter pack.
  ///
  /// In en, this message translates to:
  /// **'Install JMdict English and word frequency data together for the fastest setup.'**
  String get downloadsRecommendedStarterPackSubtitle;

  /// Starter pack row label for JMdict English.
  ///
  /// In en, this message translates to:
  /// **'JMdict English'**
  String get downloadsStarterPackJmdict;

  /// Starter pack row label for word frequency data.
  ///
  /// In en, this message translates to:
  /// **'Word Frequency'**
  String get downloadsStarterPackWordFrequency;

  /// Button label to install the starter pack.
  ///
  /// In en, this message translates to:
  /// **'Install Starter Pack'**
  String get downloadsInstallStarterPack;

  /// Section header for downloadable dictionaries.
  ///
  /// In en, this message translates to:
  /// **'Dictionaries'**
  String get downloadsSectionDictionaries;

  /// Section header for downloadable assets.
  ///
  /// In en, this message translates to:
  /// **'Assets'**
  String get downloadsSectionAssets;

  /// Progress message shown while fetching the latest downloadable release.
  ///
  /// In en, this message translates to:
  /// **'Fetching latest release...'**
  String get downloadsFetchingLatestRelease;

  /// Progress message shown while downloading data.
  ///
  /// In en, this message translates to:
  /// **'Downloading... {percent}%'**
  String downloadsDownloadingPercent({required int percent});

  /// Progress message shown while importing downloaded data.
  ///
  /// In en, this message translates to:
  /// **'Importing...'**
  String get downloadsImporting;

  /// Progress message shown while extracting downloaded files.
  ///
  /// In en, this message translates to:
  /// **'Extracting files...'**
  String get downloadsExtractingFiles;

  /// Attribution text for JPDB frequency data.
  ///
  /// In en, this message translates to:
  /// **'Word frequency data from JPDB (jpdb.io), distributed by Kuuuube.'**
  String get downloadsJpdbAttribution;

  /// Title for the KanjiVG download tile.
  ///
  /// In en, this message translates to:
  /// **'Kanji Stroke Order'**
  String get downloadsKanjiStrokeOrderTitle;

  /// Subtitle shown when KanjiVG data has been downloaded.
  ///
  /// In en, this message translates to:
  /// **'{count} stroke order files downloaded'**
  String downloadsKanjiStrokeOrderDownloaded({required int count});

  /// Subtitle shown before KanjiVG data is downloaded.
  ///
  /// In en, this message translates to:
  /// **'Download kanji stroke order data from KanjiVG'**
  String get downloadsKanjiStrokeOrderDescription;

  /// Tooltip for deleting KanjiVG data.
  ///
  /// In en, this message translates to:
  /// **'Delete kanji data'**
  String get downloadsDeleteKanjiDataTooltip;

  /// Dialog title for deleting KanjiVG data.
  ///
  /// In en, this message translates to:
  /// **'Delete Kanji Data'**
  String get downloadsDeleteKanjiDataTitle;

  /// Dialog body for deleting KanjiVG data.
  ///
  /// In en, this message translates to:
  /// **'Delete all downloaded kanji stroke order files? You can re-download them later.'**
  String get downloadsDeleteKanjiDataBody;

  /// Subtitle shown when word frequency data has been downloaded.
  ///
  /// In en, this message translates to:
  /// **'Frequency data downloaded'**
  String get downloadsWordFrequencyDownloaded;

  /// Subtitle shown before word frequency data is downloaded.
  ///
  /// In en, this message translates to:
  /// **'Download word frequency data for search ranking'**
  String get downloadsWordFrequencyDescription;

  /// Tooltip for deleting word frequency data.
  ///
  /// In en, this message translates to:
  /// **'Delete frequency data'**
  String get downloadsDeleteFrequencyDataTooltip;

  /// Dialog title for deleting word frequency data.
  ///
  /// In en, this message translates to:
  /// **'Delete Frequency Data'**
  String get downloadsDeleteFrequencyDataTitle;

  /// Dialog body for deleting word frequency data.
  ///
  /// In en, this message translates to:
  /// **'Delete word frequency data? Search results will no longer be ranked by frequency. You can re-download it later.'**
  String get downloadsDeleteFrequencyDataBody;

  /// Subtitle shown when JMdict has been downloaded.
  ///
  /// In en, this message translates to:
  /// **'Japanese-English dictionary downloaded'**
  String get downloadsJmdictDownloaded;

  /// Subtitle shown before JMdict has been downloaded.
  ///
  /// In en, this message translates to:
  /// **'Download Japanese-English dictionary'**
  String get downloadsJmdictDescription;

  /// Tooltip for deleting JMdict data.
  ///
  /// In en, this message translates to:
  /// **'Delete JMdict'**
  String get downloadsDeleteJmdictTooltip;

  /// Title for the JMdict variant picker.
  ///
  /// In en, this message translates to:
  /// **'Choose JMdict variant'**
  String get downloadsChooseJmdictVariant;

  /// Subtitle for the standard JMdict variant.
  ///
  /// In en, this message translates to:
  /// **'Standard dictionary (~15 MB)'**
  String get downloadsJmdictStandardSubtitle;

  /// Title for the JMdict variant with example sentences.
  ///
  /// In en, this message translates to:
  /// **'JMdict English with Examples'**
  String get downloadsJmdictExamplesTitle;

  /// Subtitle for the JMdict variant with example sentences.
  ///
  /// In en, this message translates to:
  /// **'Includes example sentences (~18 MB)'**
  String get downloadsJmdictExamplesSubtitle;

  /// Dialog title for deleting JMdict data.
  ///
  /// In en, this message translates to:
  /// **'Delete JMdict'**
  String get downloadsDeleteJmdictTitle;

  /// Dialog body for deleting JMdict data.
  ///
  /// In en, this message translates to:
  /// **'Delete JMdict and all its entries? You can re-download it later.'**
  String get downloadsDeleteJmdictBody;

  /// Subtitle shown when KANJIDIC has been downloaded.
  ///
  /// In en, this message translates to:
  /// **'Kanji dictionary downloaded'**
  String get downloadsKanjidicDownloaded;

  /// Subtitle shown before KANJIDIC has been downloaded.
  ///
  /// In en, this message translates to:
  /// **'Download kanji dictionary'**
  String get downloadsKanjidicDescription;

  /// Tooltip for deleting KANJIDIC data.
  ///
  /// In en, this message translates to:
  /// **'Delete KANJIDIC'**
  String get downloadsDeleteKanjidicTooltip;

  /// Dialog title for deleting KANJIDIC data.
  ///
  /// In en, this message translates to:
  /// **'Delete KANJIDIC'**
  String get downloadsDeleteKanjidicTitle;

  /// Dialog body for deleting KANJIDIC data.
  ///
  /// In en, this message translates to:
  /// **'Delete KANJIDIC and all its entries? You can re-download it later.'**
  String get downloadsDeleteKanjidicBody;

  /// Generic clear action.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get commonClear;

  /// Generic submit action.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get commonSubmit;

  /// Generic loading label.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get commonLoading;

  /// Generic error label.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get commonError;

  /// Generic restore action.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get commonRestore;

  /// Title for the settings screen.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// Settings section header for general preferences.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get settingsSectionGeneral;

  /// Settings section header for appearance preferences.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsSectionAppearance;

  /// Settings section header for default reader settings.
  ///
  /// In en, this message translates to:
  /// **'Reading Defaults'**
  String get settingsSectionReadingDefaults;

  /// Settings section header for dictionary settings.
  ///
  /// In en, this message translates to:
  /// **'Dictionary'**
  String get settingsSectionDictionary;

  /// Settings section header for vocabulary export settings.
  ///
  /// In en, this message translates to:
  /// **'Vocabulary & Export'**
  String get settingsSectionVocabularyExport;

  /// Settings section header for Pro settings.
  ///
  /// In en, this message translates to:
  /// **'Pro'**
  String get settingsSectionPro;

  /// Settings section header for manga auto-crop preferences.
  ///
  /// In en, this message translates to:
  /// **'Manga Auto-Crop'**
  String get settingsSectionMangaAutoCrop;

  /// Settings section header for manga OCR preferences.
  ///
  /// In en, this message translates to:
  /// **'Manga OCR'**
  String get settingsSectionMangaOcr;

  /// Settings section header for downloads.
  ///
  /// In en, this message translates to:
  /// **'Downloads'**
  String get settingsSectionDownloads;

  /// Settings section header for backup settings.
  ///
  /// In en, this message translates to:
  /// **'Backup & Restore'**
  String get settingsSectionBackupRestore;

  /// Settings section header for about and feedback links.
  ///
  /// In en, this message translates to:
  /// **'About & Feedback'**
  String get settingsSectionAboutFeedback;

  /// Title for the startup screen setting.
  ///
  /// In en, this message translates to:
  /// **'Startup Screen'**
  String get settingsStartupScreenTitle;

  /// Label for the library startup screen option.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get settingsStartupScreenLibrary;

  /// Label for the dictionary startup screen option.
  ///
  /// In en, this message translates to:
  /// **'Dictionary'**
  String get settingsStartupScreenDictionary;

  /// Label for the last-read-book startup screen option.
  ///
  /// In en, this message translates to:
  /// **'Last Read Book'**
  String get settingsStartupScreenLastRead;

  /// Title for the app theme setting.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsThemeTitle;

  /// Label for the light theme option.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsThemeLight;

  /// Label for the dark theme option.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsThemeDark;

  /// Label for the system theme option.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get settingsThemeSystemDefault;

  /// Title for the color theme setting.
  ///
  /// In en, this message translates to:
  /// **'Color Theme'**
  String get settingsColorThemeTitle;

  /// Color theme label for Mekuru Red.
  ///
  /// In en, this message translates to:
  /// **'Mekuru Red'**
  String get settingsColorThemeMekuruRed;

  /// Color theme label for Indigo.
  ///
  /// In en, this message translates to:
  /// **'Indigo'**
  String get settingsColorThemeIndigo;

  /// Color theme label for Teal.
  ///
  /// In en, this message translates to:
  /// **'Teal'**
  String get settingsColorThemeTeal;

  /// Color theme label for Deep Purple.
  ///
  /// In en, this message translates to:
  /// **'Deep Purple'**
  String get settingsColorThemeDeepPurple;

  /// Color theme label for Blue.
  ///
  /// In en, this message translates to:
  /// **'Blue'**
  String get settingsColorThemeBlue;

  /// Color theme label for Green.
  ///
  /// In en, this message translates to:
  /// **'Green'**
  String get settingsColorThemeGreen;

  /// Color theme label for Orange.
  ///
  /// In en, this message translates to:
  /// **'Orange'**
  String get settingsColorThemeOrange;

  /// Color theme label for Pink.
  ///
  /// In en, this message translates to:
  /// **'Pink'**
  String get settingsColorThemePink;

  /// Color theme label for Blue Grey.
  ///
  /// In en, this message translates to:
  /// **'Blue Grey'**
  String get settingsColorThemeBlueGrey;

  /// Title for the reader font size setting.
  ///
  /// In en, this message translates to:
  /// **'Font Size'**
  String get settingsFontSizeTitle;

  /// Value label showing a size in points.
  ///
  /// In en, this message translates to:
  /// **'{points} pt'**
  String settingsPointsValue({required int points});

  /// Title for the reader color mode setting.
  ///
  /// In en, this message translates to:
  /// **'Color Mode'**
  String get settingsColorModeTitle;

  /// Label for the normal reader color mode.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get settingsColorModeNormal;

  /// Label for the sepia reader color mode.
  ///
  /// In en, this message translates to:
  /// **'Sepia'**
  String get settingsColorModeSepia;

  /// Label for the dark reader color mode.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsColorModeDark;

  /// Label for the sepia intensity slider.
  ///
  /// In en, this message translates to:
  /// **'Sepia Intensity'**
  String get settingsSepiaIntensityTitle;

  /// Title for the keep-screen-on setting.
  ///
  /// In en, this message translates to:
  /// **'Keep Screen On'**
  String get settingsKeepScreenOnTitle;

  /// Subtitle for the keep-screen-on setting.
  ///
  /// In en, this message translates to:
  /// **'Prevent screen from sleeping while reading'**
  String get settingsKeepScreenOnSubtitle;

  /// Label showing the horizontal reader margin.
  ///
  /// In en, this message translates to:
  /// **'Horizontal Margin: {pixels}px'**
  String settingsHorizontalMarginValue({required int pixels});

  /// Label showing the vertical reader margin.
  ///
  /// In en, this message translates to:
  /// **'Vertical Margin: {pixels}px'**
  String settingsVerticalMarginValue({required int pixels});

  /// Title for the swipe sensitivity setting.
  ///
  /// In en, this message translates to:
  /// **'Swipe Sensitivity'**
  String get settingsSwipeSensitivityTitle;

  /// Value label showing a percentage.
  ///
  /// In en, this message translates to:
  /// **'{percent}%'**
  String settingsPercentValue({required int percent});

  /// Help text for the swipe sensitivity setting.
  ///
  /// In en, this message translates to:
  /// **'Lower = less finger movement needed to swipe'**
  String get settingsSwipeSensitivityHint;

  /// Subtitle for managing dictionaries.
  ///
  /// In en, this message translates to:
  /// **'Import, reorder, enable/disable'**
  String get settingsManageDictionariesSubtitle;

  /// Title for the lookup font size setting.
  ///
  /// In en, this message translates to:
  /// **'Lookup Font Size'**
  String get settingsLookupFontSizeTitle;

  /// Title for the roman-letter dictionary filter setting.
  ///
  /// In en, this message translates to:
  /// **'Filter Roman Letter Entries'**
  String get settingsFilterRomanLetterEntriesTitle;

  /// Subtitle for the roman-letter dictionary filter setting.
  ///
  /// In en, this message translates to:
  /// **'Hide entries using English letters in headword'**
  String get settingsFilterRomanLetterEntriesSubtitle;

  /// Title for the auto-focus dictionary search setting.
  ///
  /// In en, this message translates to:
  /// **'Auto-Focus Search'**
  String get settingsAutoFocusSearchTitle;

  /// Subtitle for the auto-focus dictionary search setting.
  ///
  /// In en, this message translates to:
  /// **'Open keyboard when dictionary tab is selected'**
  String get settingsAutoFocusSearchSubtitle;

  /// Title for the AnkiDroid settings entry.
  ///
  /// In en, this message translates to:
  /// **'AnkiDroid Integration'**
  String get settingsAnkiDroidIntegrationTitle;

  /// Subtitle for the AnkiDroid settings entry.
  ///
  /// In en, this message translates to:
  /// **'Configure note type, deck, and field mapping'**
  String get settingsAnkiDroidIntegrationSubtitle;

  /// Subtitle shown when Pro services are unavailable.
  ///
  /// In en, this message translates to:
  /// **'Pro services are temporarily unavailable.'**
  String get settingsProUnavailableSubtitle;

  /// Subtitle describing the Pro upgrade.
  ///
  /// In en, this message translates to:
  /// **'Unlock auto-crop, book highlights, and custom OCR'**
  String get settingsProSubtitle;

  /// Title for the manga auto-crop white threshold setting.
  ///
  /// In en, this message translates to:
  /// **'White Threshold'**
  String get settingsWhiteThresholdTitle;

  /// Subtitle for the manga auto-crop white threshold setting.
  ///
  /// In en, this message translates to:
  /// **'{threshold} (lower values ignore more near-white artifacts)'**
  String settingsWhiteThresholdSubtitle({required int threshold});

  /// Title for the custom OCR server setting and dialog.
  ///
  /// In en, this message translates to:
  /// **'Custom OCR Server'**
  String get settingsCustomOcrServerTitle;

  /// Subtitle shown when OCR services are unavailable.
  ///
  /// In en, this message translates to:
  /// **'OCR services are temporarily unavailable.'**
  String get settingsCustomOcrServerUnavailableSubtitle;

  /// Subtitle shown when a custom OCR server has not been configured.
  ///
  /// In en, this message translates to:
  /// **'Not configured. Add your own server URL and shared key.'**
  String get settingsCustomOcrServerNotConfigured;

  /// Subtitle shown when a custom OCR server has been configured.
  ///
  /// In en, this message translates to:
  /// **'{url}\nUse the same shared key configured on your server.'**
  String settingsCustomOcrServerConfigured({required String url});

  /// Label for the custom OCR server URL field.
  ///
  /// In en, this message translates to:
  /// **'Server URL'**
  String get settingsCustomOcrServerUrlLabel;

  /// Hint for the custom OCR server URL field.
  ///
  /// In en, this message translates to:
  /// **'http://192.168.1.100:8000'**
  String get settingsCustomOcrServerUrlHint;

  /// Button label linking to custom OCR server setup instructions.
  ///
  /// In en, this message translates to:
  /// **'Learn how to run your own server'**
  String get settingsCustomOcrServerLearnHow;

  /// Label for the custom OCR shared key field.
  ///
  /// In en, this message translates to:
  /// **'Custom shared key'**
  String get settingsCustomOcrServerKeyLabel;

  /// Hint for the custom OCR shared key field.
  ///
  /// In en, this message translates to:
  /// **'Required AUTH_API_KEY'**
  String get settingsCustomOcrServerKeyHint;

  /// Description shown in the custom OCR server dialog.
  ///
  /// In en, this message translates to:
  /// **'Enter the same shared AUTH_API_KEY used by your OCR server. Mekuru sends it as Authorization: Bearer <key> for remote manga OCR requests.'**
  String get settingsCustomOcrServerDescription;

  /// Validation error shown when the custom OCR server URL is empty.
  ///
  /// In en, this message translates to:
  /// **'Enter your server URL.'**
  String get settingsCustomOcrServerUrlRequired;

  /// Validation error shown when the custom OCR server URL is invalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a full http:// or https:// server URL.'**
  String get settingsCustomOcrServerUrlInvalid;

  /// Validation error shown when the custom OCR server key is empty.
  ///
  /// In en, this message translates to:
  /// **'A shared key is required for custom servers.'**
  String get settingsCustomOcrServerKeyRequired;

  /// Subtitle for the downloads settings entry.
  ///
  /// In en, this message translates to:
  /// **'Dictionaries, kanji data, and more'**
  String get settingsDownloadsSubtitle;

  /// Title for the backup settings entry.
  ///
  /// In en, this message translates to:
  /// **'Backup & Restore'**
  String get settingsBackupRestoreTitle;

  /// Subtitle for the backup settings entry.
  ///
  /// In en, this message translates to:
  /// **'Back up and restore your data'**
  String get settingsBackupRestoreSubtitle;

  /// Subtitle for the feedback settings entry.
  ///
  /// In en, this message translates to:
  /// **'Report a bug or suggest a feature'**
  String get settingsSendFeedbackSubtitle;

  /// Snackbar shown after feedback is submitted successfully.
  ///
  /// In en, this message translates to:
  /// **'Thank you for your feedback!'**
  String get settingsFeedbackThanks;

  /// Snackbar shown when feedback submission fails.
  ///
  /// In en, this message translates to:
  /// **'Failed to send feedback. Please try again.'**
  String get settingsFeedbackFailed;

  /// Title for the documentation settings entry.
  ///
  /// In en, this message translates to:
  /// **'Documentation'**
  String get settingsDocumentationTitle;

  /// Subtitle for the documentation settings entry.
  ///
  /// In en, this message translates to:
  /// **'Guides and how-to articles'**
  String get settingsDocumentationSubtitle;

  /// Title for the about screen settings entry.
  ///
  /// In en, this message translates to:
  /// **'About Mekuru'**
  String get settingsAboutMekuruTitle;

  /// Subtitle for the about screen settings entry.
  ///
  /// In en, this message translates to:
  /// **'Version, licenses, and more'**
  String get settingsAboutMekuruSubtitle;

  /// Title for the feedback screen.
  ///
  /// In en, this message translates to:
  /// **'Send Feedback'**
  String get feedbackTitle;

  /// Label for the feedback name field.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get feedbackNameLabel;

  /// Hint for the feedback name field.
  ///
  /// In en, this message translates to:
  /// **'Your name'**
  String get feedbackNameHint;

  /// Label for the feedback email field.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get feedbackEmailLabel;

  /// Hint for the feedback email field.
  ///
  /// In en, this message translates to:
  /// **'your@email.com'**
  String get feedbackEmailHint;

  /// Label for the feedback message field.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get feedbackMessageLabel;

  /// Label shown next to a required field.
  ///
  /// In en, this message translates to:
  /// **'(required)'**
  String get feedbackRequired;

  /// Hint for the feedback message field.
  ///
  /// In en, this message translates to:
  /// **'Describe your bug or feature request...'**
  String get feedbackMessageHint;

  /// Validation error shown when the feedback message is empty.
  ///
  /// In en, this message translates to:
  /// **'Please enter a message'**
  String get feedbackMessageRequiredError;

  /// Title for the backup screen.
  ///
  /// In en, this message translates to:
  /// **'Backup & Restore'**
  String get backupTitle;

  /// Section header for backup actions.
  ///
  /// In en, this message translates to:
  /// **'Backup'**
  String get backupSectionBackup;

  /// Title for the create-backup action.
  ///
  /// In en, this message translates to:
  /// **'Create Backup Now'**
  String get backupCreateNowTitle;

  /// Subtitle for the create-backup action.
  ///
  /// In en, this message translates to:
  /// **'Save all settings and reading data'**
  String get backupCreateNowSubtitle;

  /// Title for the export-backup action.
  ///
  /// In en, this message translates to:
  /// **'Export Backup'**
  String get backupExportTitle;

  /// Subtitle for the export-backup action.
  ///
  /// In en, this message translates to:
  /// **'Save your latest backup to a file'**
  String get backupExportSubtitle;

  /// Section header for auto-backup settings.
  ///
  /// In en, this message translates to:
  /// **'Auto-Backup'**
  String get backupSectionAutoBackup;

  /// Title for the auto-backup interval setting.
  ///
  /// In en, this message translates to:
  /// **'Auto-Backup Interval'**
  String get backupAutoBackupIntervalTitle;

  /// Label for turning auto-backup off.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get backupIntervalOff;

  /// Label for daily auto-backups.
  ///
  /// In en, this message translates to:
  /// **'Daily'**
  String get backupIntervalDaily;

  /// Label for weekly auto-backups.
  ///
  /// In en, this message translates to:
  /// **'Weekly'**
  String get backupIntervalWeekly;

  /// Section header for restore actions.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get backupSectionRestore;

  /// Title for the import-backup action.
  ///
  /// In en, this message translates to:
  /// **'Import Backup File'**
  String get backupImportFileTitle;

  /// Subtitle for the import-backup action.
  ///
  /// In en, this message translates to:
  /// **'Restore from a .mekuru file'**
  String get backupImportFileSubtitle;

  /// Section header for the backup history list.
  ///
  /// In en, this message translates to:
  /// **'Backup History'**
  String get backupSectionHistory;

  /// Message shown when there are no backups.
  ///
  /// In en, this message translates to:
  /// **'No backups yet'**
  String get backupNoBackupsYet;

  /// Message shown when backup history fails to load.
  ///
  /// In en, this message translates to:
  /// **'Error loading backups: {details}'**
  String backupErrorLoadingHistory({required String details});

  /// Snackbar shown after a backup is created.
  ///
  /// In en, this message translates to:
  /// **'Backup created successfully'**
  String get backupCreatedSuccess;

  /// Snackbar shown when backup creation fails.
  ///
  /// In en, this message translates to:
  /// **'Backup failed: {details}'**
  String backupFailed({required String details});

  /// Snackbar shown when there are no backups to export.
  ///
  /// In en, this message translates to:
  /// **'No backups to export. Create one first.'**
  String get backupNoBackupsToExport;

  /// Snackbar shown after exporting a backup.
  ///
  /// In en, this message translates to:
  /// **'Backup exported successfully'**
  String get backupExportedSuccess;

  /// Snackbar shown when exporting a backup fails.
  ///
  /// In en, this message translates to:
  /// **'Export failed: {details}'**
  String backupExportFailed({required String details});

  /// Snackbar shown when the selected restore file has the wrong extension.
  ///
  /// In en, this message translates to:
  /// **'Please select a .mekuru backup file.'**
  String get backupInvalidFile;

  /// Snackbar shown when the backup file picker fails.
  ///
  /// In en, this message translates to:
  /// **'Could not open file: {details}'**
  String backupCouldNotOpenFile({required String details});

  /// Snackbar shown when restoring a backup fails.
  ///
  /// In en, this message translates to:
  /// **'Restore failed: {details}'**
  String backupRestoreFailed({required String details});

  /// Snackbar shown after applying conflict selections during restore.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {# book updated from backup} other {# books updated from backup}}'**
  String backupBooksUpdatedFromBackup({required int count});

  /// Snackbar shown when applying restored book data fails.
  ///
  /// In en, this message translates to:
  /// **'Failed to apply book data: {details}'**
  String backupApplyBookDataFailed({required String details});

  /// Part of the restore summary message when settings are restored.
  ///
  /// In en, this message translates to:
  /// **'Settings restored'**
  String get backupRestoreSummarySettingsRestored;

  /// Part of the restore summary message when some settings could not be restored.
  ///
  /// In en, this message translates to:
  /// **'Some settings could not be restored'**
  String get backupRestoreSummarySettingsPartial;

  /// Part of the restore summary message for restored words.
  ///
  /// In en, this message translates to:
  /// **'{added} words added, {skipped} skipped'**
  String backupRestoreSummaryWords({required int added, required int skipped});

  /// Part of the restore summary message for restored books.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {# book restored} other {# books restored}}'**
  String backupRestoreSummaryBooksRestored({required int count});

  /// Part of the restore summary message for pending book data.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {# book saved for later import} other {# books saved for later import}}'**
  String backupRestoreSummaryBooksPending({required int count});

  /// Fallback restore summary when there is nothing else to report.
  ///
  /// In en, this message translates to:
  /// **'Restore complete'**
  String get backupRestoreComplete;

  /// Title for the restore backup confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Restore Backup?'**
  String get backupRestoreDialogTitle;

  /// Body for the restore backup confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'This will restore settings and reading data from {fileName}. Your current settings will be overwritten.'**
  String backupRestoreDialogBody({required String fileName});

  /// Title for the delete backup confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Delete Backup?'**
  String get backupDeleteDialogTitle;

  /// Body for the delete backup confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Delete {fileName}? This cannot be undone.'**
  String backupDeleteDialogBody({required String fileName});

  /// Label for an automatic backup in backup history.
  ///
  /// In en, this message translates to:
  /// **'Auto backup'**
  String get backupHistoryTypeAuto;

  /// Label for a manual backup in backup history.
  ///
  /// In en, this message translates to:
  /// **'Manual backup'**
  String get backupHistoryTypeManual;

  /// Barrier label for dismissing reader overlays.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get readerDismiss;

  /// Reader error shown when the EPUB viewer reports a content-loading failure.
  ///
  /// In en, this message translates to:
  /// **'Failed to load EPUB content.\n{details}'**
  String readerFailedToLoadContent({required String details});

  /// Reader error shown when the EPUB file fails to load.
  ///
  /// In en, this message translates to:
  /// **'Failed to load EPUB.\n{details}'**
  String readerFailedToLoad({required String details});

  /// Warning shown when vertical text is forced for a non-vertical book.
  ///
  /// In en, this message translates to:
  /// **'This book was not originally formatted for vertical text. Some display issues may occur.'**
  String get readerVerticalTextNonNativeWarning;

  /// Warning shown when horizontal text is forced for a vertical book.
  ///
  /// In en, this message translates to:
  /// **'This book was originally formatted for vertical text. Some display issues may occur in horizontal mode.'**
  String get readerHorizontalTextNonNativeWarning;

  /// Snackbar shown after removing a bookmark.
  ///
  /// In en, this message translates to:
  /// **'Bookmark removed'**
  String get readerBookmarkRemoved;

  /// Snackbar shown after bookmarking the current page.
  ///
  /// In en, this message translates to:
  /// **'Page bookmarked'**
  String get readerPageBookmarked;

  /// Title or tooltip for the reader table of contents.
  ///
  /// In en, this message translates to:
  /// **'Table of Contents'**
  String get readerTableOfContents;

  /// Tooltip for removing the current page bookmark.
  ///
  /// In en, this message translates to:
  /// **'Remove Bookmark'**
  String get readerRemoveBookmarkTooltip;

  /// Tooltip for bookmarking the current page.
  ///
  /// In en, this message translates to:
  /// **'Bookmark Page'**
  String get readerBookmarkPageTooltip;

  /// Tooltip for opening the bookmarks sheet.
  ///
  /// In en, this message translates to:
  /// **'View Bookmarks'**
  String get readerViewBookmarksTooltip;

  /// Tooltip for opening the highlights sheet.
  ///
  /// In en, this message translates to:
  /// **'Highlights'**
  String get readerHighlightsTooltip;

  /// Tooltip for moving to the next page.
  ///
  /// In en, this message translates to:
  /// **'Next Page'**
  String get readerNextPageTooltip;

  /// Tooltip for moving to the previous page.
  ///
  /// In en, this message translates to:
  /// **'Previous Page'**
  String get readerPreviousPageTooltip;

  /// Fallback error shown in the reader when no specific error is available.
  ///
  /// In en, this message translates to:
  /// **'Unknown reader error.'**
  String get readerUnknownError;

  /// Title for the reader quick settings sheet.
  ///
  /// In en, this message translates to:
  /// **'Quick Settings'**
  String get readerQuickSettings;

  /// Title for the per-book vertical text setting.
  ///
  /// In en, this message translates to:
  /// **'Vertical Text'**
  String get readerVerticalTextTitle;

  /// Label indicating a reader setting applies to the current book.
  ///
  /// In en, this message translates to:
  /// **'This book'**
  String get readerThisBook;

  /// Subtitle shown when vertical text is unavailable for the current book.
  ///
  /// In en, this message translates to:
  /// **'Not available for this book\'s language'**
  String get readerVerticalTextUnavailable;

  /// Title for the per-book reading direction setting.
  ///
  /// In en, this message translates to:
  /// **'Reading Direction'**
  String get readerReadingDirectionTitle;

  /// Label for right-to-left reading direction.
  ///
  /// In en, this message translates to:
  /// **'Right to Left'**
  String get readerReadingDirectionRtl;

  /// Label for left-to-right reading direction.
  ///
  /// In en, this message translates to:
  /// **'Left to Right'**
  String get readerReadingDirectionLtr;

  /// Title for the disable-links reader setting.
  ///
  /// In en, this message translates to:
  /// **'Disable Links'**
  String get readerDisableLinksTitle;

  /// Subtitle for the disable-links reader setting.
  ///
  /// In en, this message translates to:
  /// **'Tap linked text to look up words instead of navigating'**
  String get readerDisableLinksSubtitle;

  /// Tooltip for the highlight-selection action.
  ///
  /// In en, this message translates to:
  /// **'Highlight selection'**
  String get readerHighlightSelectionTooltip;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ja'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ja':
      return AppLocalizationsJa();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
