// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'Mekuru';

  @override
  String get navLibrary => 'Biblioteca';

  @override
  String get navDictionary => 'Diccionario';

  @override
  String get navVocabulary => 'Vocabulario';

  @override
  String get navSettings => 'Configuración';

  @override
  String get commonHelp => 'Ayuda';

  @override
  String get commonImport => 'Importar';

  @override
  String get commonOpenNow => 'Abrir ahora';

  @override
  String get commonCancel => 'Cancelar';

  @override
  String get commonClose => 'Cerrar';

  @override
  String get commonSave => 'Guardar';

  @override
  String get commonDelete => 'Eliminar';

  @override
  String get commonDownload => 'Descargar';

  @override
  String get commonOpenDictionary => 'Abrir diccionario';

  @override
  String get commonManageDictionaries => 'Administrar diccionarios';

  @override
  String get commonClearAll => 'Borrar todo';

  @override
  String get commonClearSearch => 'Borrar búsqueda';

  @override
  String get commonSearch => 'Buscar';

  @override
  String get commonBack => 'Atrás';

  @override
  String get commonRetry => 'Reintentar';

  @override
  String get commonOk => 'OK';

  @override
  String get commonDone => 'Listo';

  @override
  String get commonUndo => 'Deshacer';

  @override
  String get commonUnlock => 'Desbloquear';

  @override
  String get commonOpenSettings => 'Abrir configuración';

  @override
  String get commonGotIt => 'Entendido';

  @override
  String commonErrorWithDetails({required String details}) {
    return 'Error: $details';
  }

  @override
  String librarySortTooltip({required String label}) {
    return 'Ordenar: $label';
  }

  @override
  String get libraryEmptyTitle =>
      'Tu biblioteca está lista para su primer libro';

  @override
  String get libraryEmptySubtitle =>
      'Importa algo para leer, instala un diccionario y podrás guardar palabras en unos minutos.';

  @override
  String get libraryImportEpub => 'Importar EPUB';

  @override
  String get libraryImportManga => 'Importar Manga';

  @override
  String get libraryGetDictionaries => 'Obtener diccionarios';

  @override
  String get libraryRestoreBackup => 'Restaurar copia de seguridad';

  @override
  String get librarySupportedMediaTitle => 'Medios compatibles';

  @override
  String get libraryEpubBooksTitle => 'Libros EPUB';

  @override
  String get libraryEpubBooksDescription =>
      'Se admiten archivos .epub estándar. Toca el botón + y selecciona \"Importar EPUB\" para añadir uno desde tu dispositivo.';

  @override
  String get libraryMokuroTitle => 'Manga Mokuro';

  @override
  String get libraryMokuroDescription =>
      'Importa manga seleccionando una carpeta y luego eligiendo un archivo .mokuro o .html. Las imágenes de las páginas se cargan desde otra carpeta con el mismo nombre.';

  @override
  String get libraryMokuroFormatDescription =>
      'El archivo .mokuro es generado por la herramienta mokuro, que realiza OCR en las páginas del manga para extraer texto japonés.';

  @override
  String get libraryLearnHowToCreateMokuroFiles =>
      'Aprende a crear archivos .mokuro';

  @override
  String get librarySortBy => 'Ordenar por';

  @override
  String get librarySortDateImported => 'Fecha de importación';

  @override
  String get librarySortRecentlyRead => 'Leído recientemente';

  @override
  String get librarySortAlphabetical => 'Alfabético';

  @override
  String get libraryImportTitle => 'Importar';

  @override
  String get libraryImportEpubSubtitle => 'Importar un archivo EPUB';

  @override
  String get libraryImportMangaSubtitle =>
      'Elegir un archivo CBZ o una carpeta Mokuro';

  @override
  String get libraryImportMangaTitle => 'Importar Manga';

  @override
  String get libraryImportMangaDescription =>
      'Elige si quieres importar un archivo CBZ o una carpeta exportada por Mokuro.';

  @override
  String get libraryImportMokuroFolder => 'Carpeta Mokuro';

  @override
  String get libraryImportMokuroFolderSubtitle =>
      'Selecciona la carpeta que contiene un archivo .mokuro o .html junto con la carpeta de imágenes.';

  @override
  String get libraryWhatIsMokuro => '¿Qué es Mokuro?';

  @override
  String get libraryImportCbzArchive => 'Archivo CBZ';

  @override
  String get libraryImportCbzArchiveSubtitle =>
      'Importar un archivo de cómic .cbz';

  @override
  String get libraryImportedWithoutOcrMessage =>
      'Importado sin OCR. Para obtener superposiciones de texto, importa una salida OCR externa (por ejemplo, .mokuro).';

  @override
  String get libraryCouldNotOpenMokuroProjectPage =>
      'No se pudo abrir la página del proyecto Mokuro.';

  @override
  String get libraryNoMangaManifestFound =>
      'No se encontraron archivos .mokuro ni .html en la carpeta seleccionada.';

  @override
  String get librarySelectMangaFolder => 'Seleccionar carpeta de manga';

  @override
  String get librarySelectedFolder => 'Carpeta seleccionada';

  @override
  String libraryMangaFilesFound({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count archivos de manga encontrados',
      one: '$count archivo de manga encontrado',
    );
    return '$_temp0';
  }

  @override
  String get dictionarySearchHint => 'Buscar en kanji, kana o romaji...';

  @override
  String get dictionaryNoDictionariesTitle =>
      'No se han importado diccionarios';

  @override
  String get dictionaryNoDictionariesSubtitle =>
      'Instala el paquete inicial o importa tus propios diccionarios Yomitan para empezar a buscar.';

  @override
  String get dictionaryRecommendedStarterPack => 'Paquete inicial recomendado';

  @override
  String get dictionaryNoEnabledTitle => 'Tus diccionarios están desactivados';

  @override
  String get dictionaryNoEnabledSubtitle =>
      'Activa al menos un diccionario para poder hacer búsquedas, o instala el paquete inicial recomendado.';

  @override
  String get dictionaryEnableDictionaries => 'Activar diccionarios';

  @override
  String get dictionaryStarterPack => 'Paquete inicial';

  @override
  String get dictionaryNoResultsFound => 'No se encontraron resultados.';

  @override
  String get dictionarySearchForAWord => 'Buscar una palabra';

  @override
  String get dictionarySearchForAWordSubtitle =>
      'Escribe en kanji, hiragana, katakana o romaji';

  @override
  String get dictionaryRecent => 'Reciente';

  @override
  String dictionarySavedWord({required String expression}) {
    return '\"$expression\" guardada';
  }

  @override
  String get dictionaryWordAlreadyExistsInVocab =>
      'La palabra ya existe en la lista de vocabulario';

  @override
  String dictionaryCopiedWord({required String expression}) {
    return 'Copiado \"$expression\"';
  }

  @override
  String get dictionaryWordAlreadyExistsInAnki =>
      'La palabra ya existe en el mazo predeterminado';

  @override
  String dictionaryAddedToAnki({required String expression}) {
    return 'Añadido \"$expression\" a Anki';
  }

  @override
  String get dictionaryCopyTooltip => 'Copiar';

  @override
  String get dictionaryAlreadyInAnkiTooltip =>
      'Ya está en el mazo predeterminado de Anki. Mantén pulsado para agregar de todas formas';

  @override
  String get dictionaryCheckingAnkiTooltip =>
      'Comprobando el mazo predeterminado de Anki';

  @override
  String get dictionarySendToAnkiTooltip => 'Enviar a AnkiDroid';

  @override
  String get dictionaryAlreadyInVocabTooltip =>
      'Ya está en la lista de vocabulario';

  @override
  String get dictionarySaveToVocabularyTooltip => 'Guardar en Vocabulario';

  @override
  String get dictionaryVeryCommon => 'Muy común';

  @override
  String get dictionaryOnyomiLabel => 'Onyomi: ';

  @override
  String get dictionaryKunyomiLabel => 'Kunyomi: ';

  @override
  String dictionaryKanjiStrokeCount({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count trazos',
      one: '$count trazo',
    );
    return '$_temp0';
  }

  @override
  String get dictionaryAnimateStrokeOrderTooltip =>
      'Animar el orden de los trazos';

  @override
  String get vocabularySearchSavedWordsHint => 'Buscar palabras guardadas';

  @override
  String get vocabularyExportCsvTooltip => 'Exportar CSV';

  @override
  String get vocabularyEmptyTitle => 'Aún no hay palabras guardadas';

  @override
  String get vocabularyEmptySubtitle =>
      'Guarda palabras desde búsquedas en el diccionario o mientras lees, y aparecerán aquí junto con el contexto.';

  @override
  String vocabularyNoMatches({required String query}) {
    return 'No hay coincidencias para \"$query\"';
  }

  @override
  String get vocabularyNoMatchesSubtitle =>
      'Prueba con la expresión, la lectura o parte de una definición.';

  @override
  String vocabularySelectedCount({required int count}) {
    return '$count seleccionadas';
  }

  @override
  String get vocabularyDeselectAllTooltip => 'Deseleccionar todas';

  @override
  String get vocabularySelectAllTooltip => 'Seleccionar todas';

  @override
  String get vocabularyExportSelectedTooltip => 'Exportar seleccionadas';

  @override
  String get vocabularyNoDefinition => 'Sin definición';

  @override
  String get vocabularyContextLabel => 'Contexto:';

  @override
  String vocabularyAddedOn({required String date}) {
    return 'Añadido: $date';
  }

  @override
  String vocabularyDeletedWord({required String expression}) {
    return '\"$expression\" eliminado';
  }

  @override
  String ocrPagesProgress({required int completed, required int total}) {
    return '$completed/$total páginas';
  }

  @override
  String ocrEtaSecondsRemaining({required int seconds}) {
    return '~${seconds}s restantes';
  }

  @override
  String ocrEtaMinutesRemaining({required int minutes}) {
    return '~$minutes min restantes';
  }

  @override
  String ocrEtaHoursMinutesRemaining({
    required int hours,
    required int minutes,
  }) {
    return '~${hours}h ${minutes}m restantes';
  }

  @override
  String get ocrPaused => 'OCR en pausa';

  @override
  String get ocrComplete => 'OCR completo';

  @override
  String get ocrFailed => 'Error de OCR';

  @override
  String get ocrTapForDetails => 'Toca para más detalles';

  @override
  String get ocrCustomServerRequiredTitle =>
      'Servidor OCR personalizado requerido';

  @override
  String get ocrCustomServerRequiredBody =>
      'El OCR remoto de manga ahora utiliza tu propio servidor. Ve a Configuración y añade la URL de tu servidor OCR personalizado junto con la clave compartida correspondiente.';

  @override
  String get ocrCustomServerKeyRequiredTitle =>
      'Configuración de servidor personalizado requerida';

  @override
  String get ocrCustomServerKeyRequiredBody =>
      'Los servidores OCR personalizados requieren una clave compartida. Abre la configuración del servidor OCR personalizado e introduce el mismo valor de AUTH_API_KEY configurado en tu servidor.';

  @override
  String get proTitle => 'Pro';

  @override
  String get proPurchaseConfirmed => '¡Tu compra ha sido confirmada!';

  @override
  String get proUnlockOnceTitle => 'Desbloquear Pro una vez';

  @override
  String get proStatusUnlocked => 'Desbloqueado';

  @override
  String get proStatusLocked => 'Bloqueado';

  @override
  String get proUnlockDescription =>
      'Compra única para funciones avanzadas de lectura.';

  @override
  String get proRestorePurchase => 'Restaurar compra';

  @override
  String get proFeatureAutoCropTitle => 'Recorte automático';

  @override
  String get proFeatureAutoCropDescription =>
      'Recorta los márgenes vacíos de las páginas de manga después de una configuración única por libro.';

  @override
  String get proFeatureHighlightsTitle => 'Resaltados del libro';

  @override
  String get proFeatureHighlightsDescription =>
      'Guarda y revisa pasajes destacados mientras lees libros EPUB.';

  @override
  String get proFeatureCustomOcrTitle => 'Servidor OCR personalizado';

  @override
  String get proFeatureCustomOcrDescription =>
      'Ejecuta OCR remoto de manga usando tu propio servidor y clave compartida.';

  @override
  String get proServerRepo => 'Repositorio del servidor';

  @override
  String get proAlreadyUnlocked => 'Ya desbloqueado';

  @override
  String get proUnlock => 'Desbloquear Pro';

  @override
  String proUnlockWithPrice({required String price}) {
    return 'Desbloquear Pro $price';
  }

  @override
  String get downloadsTitle => 'Descargas';

  @override
  String get downloadsRecommendedStarterPackTitle =>
      'Paquete inicial recomendado';

  @override
  String get downloadsRecommendedStarterPackSubtitle =>
      'Instala JMdict English y datos de frecuencia de palabras juntos para una configuración más rápida.';

  @override
  String get downloadsStarterPackJmdict => 'JMdict English';

  @override
  String get downloadsStarterPackWordFrequency => 'Frecuencia de palabras';

  @override
  String get downloadsInstallStarterPack => 'Instalar paquete inicial';

  @override
  String get downloadsSectionDictionaries => 'Diccionarios';

  @override
  String get downloadsSectionAssets => 'Recursos';

  @override
  String get downloadsFetchingLatestRelease => 'Buscando la última versión...';

  @override
  String downloadsDownloadingPercent({required int percent}) {
    return 'Descargando... $percent%';
  }

  @override
  String get downloadsImporting => 'Importando...';

  @override
  String get downloadsExtractingFiles => 'Extrayendo archivos...';

  @override
  String get downloadsJpdbAttribution =>
      'Datos de frecuencia de palabras de JPDB (jpdb.io), distribuidos por Kuuuube.';

  @override
  String get downloadsKanjiStrokeOrderTitle => 'Orden de los trazos de kanji';

  @override
  String downloadsKanjiStrokeOrderDownloaded({required int count}) {
    return '$count archivos de orden de trazos descargados';
  }

  @override
  String get downloadsKanjiStrokeOrderDescription =>
      'Descargar datos del orden de trazos de kanji desde KanjiVG';

  @override
  String get downloadsDeleteKanjiDataTooltip => 'Eliminar datos de kanji';

  @override
  String get downloadsDeleteKanjiDataTitle => 'Eliminar datos de kanji';

  @override
  String get downloadsDeleteKanjiDataBody =>
      '¿Eliminar todos los archivos descargados del orden de trazos de kanji? Puedes volver a descargarlos más tarde.';

  @override
  String get downloadsWordFrequencyDownloaded =>
      'Datos de frecuencia descargados';

  @override
  String get downloadsWordFrequencyDescription =>
      'Descargar datos de frecuencia de palabras para ordenar resultados de búsqueda';

  @override
  String get downloadsDeleteFrequencyDataTooltip =>
      'Eliminar datos de frecuencia';

  @override
  String get downloadsDeleteFrequencyDataTitle =>
      'Eliminar datos de frecuencia';

  @override
  String get downloadsDeleteFrequencyDataBody =>
      '¿Eliminar los datos de frecuencia de palabras? Los resultados de búsqueda ya no se ordenarán por frecuencia. Puedes volver a descargarlos más tarde.';

  @override
  String get downloadsJmdictDownloaded =>
      'Diccionario japonés-inglés descargado';

  @override
  String get downloadsJmdictDescription =>
      'Descargar diccionario japonés-inglés';

  @override
  String get downloadsDeleteJmdictTooltip => 'Eliminar JMdict';

  @override
  String get downloadsChooseJmdictVariant => 'Elegir variante de JMdict';

  @override
  String get downloadsJmdictStandardSubtitle => 'Diccionario estándar (~15 MB)';

  @override
  String get downloadsJmdictExamplesTitle => 'JMdict inglés con ejemplos';

  @override
  String get downloadsJmdictExamplesSubtitle =>
      'Incluye oraciones de ejemplo (~18 MB)';

  @override
  String get downloadsDeleteJmdictTitle => 'Eliminar JMdict';

  @override
  String get downloadsDeleteJmdictBody =>
      '¿Eliminar JMdict y todas sus entradas? Puedes volver a descargarlo más tarde.';

  @override
  String get downloadsKanjidicDownloaded => 'Diccionario de kanji descargado';

  @override
  String get downloadsKanjidicDescription => 'Descargar diccionario de kanji';

  @override
  String get downloadsDeleteKanjidicTooltip => 'Eliminar KANJIDIC';

  @override
  String get downloadsDeleteKanjidicTitle => 'Eliminar KANJIDIC';

  @override
  String get downloadsDeleteKanjidicBody =>
      '¿Eliminar KANJIDIC y todas sus entradas? Puedes volver a descargarlo más tarde.';

  @override
  String get commonClear => 'Limpiar';

  @override
  String get commonSubmit => 'Enviar';

  @override
  String get commonLoading => 'Cargando...';

  @override
  String get commonError => 'Error';

  @override
  String get commonRestore => 'Restaurar';

  @override
  String get settingsTitle => 'Configuración';

  @override
  String get settingsSectionGeneral => 'General';

  @override
  String get settingsAppLanguageTitle => 'Idioma de la aplicación';

  @override
  String settingsAppLanguageSystemValue({required String language}) {
    return 'Predeterminado del sistema ($language)';
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
  String get settingsSectionAppearance => 'Apariencia';

  @override
  String get settingsSectionReadingDefaults =>
      'Opciones de lectura predeterminadas';

  @override
  String get settingsSectionDictionary => 'Diccionario';

  @override
  String get settingsSectionVocabularyExport => 'Vocabulario y exportación';

  @override
  String get settingsSectionPro => 'Pro';

  @override
  String get settingsSectionMangaAutoCrop => 'Recorte automático de manga';

  @override
  String get settingsSectionMangaOcr => 'OCR de manga';

  @override
  String get settingsSectionDownloads => 'Descargas';

  @override
  String get settingsSectionBackupRestore =>
      'Copia de seguridad y restauración';

  @override
  String get settingsSectionAboutFeedback => 'Acerca de y comentarios';

  @override
  String get settingsStartupScreenTitle => 'Pantalla de inicio';

  @override
  String get settingsStartupScreenLibrary => 'Biblioteca';

  @override
  String get settingsStartupScreenDictionary => 'Diccionario';

  @override
  String get settingsStartupScreenLastRead => 'Último libro leído';

  @override
  String get settingsThemeTitle => 'Tema';

  @override
  String get settingsThemeLight => 'Claro';

  @override
  String get settingsThemeDark => 'Oscuro';

  @override
  String get settingsThemeSystemDefault => 'Predeterminado del sistema';

  @override
  String get settingsColorThemeTitle => 'Color del tema';

  @override
  String get settingsColorThemeMekuruRed => 'Rojo Mekuru';

  @override
  String get settingsColorThemeIndigo => 'Índigo';

  @override
  String get settingsColorThemeTeal => 'Verde azulado';

  @override
  String get settingsColorThemeDeepPurple => 'Púrpura intenso';

  @override
  String get settingsColorThemeBlue => 'Azul';

  @override
  String get settingsColorThemeGreen => 'Verde';

  @override
  String get settingsColorThemeOrange => 'Naranja';

  @override
  String get settingsColorThemePink => 'Rosa';

  @override
  String get settingsColorThemeBlueGrey => 'Gris azul';

  @override
  String get settingsFontSizeTitle => 'Tamaño de fuente';

  @override
  String settingsPointsValue({required int points}) {
    return '$points pt';
  }

  @override
  String get settingsColorModeTitle => 'Modo de color';

  @override
  String get settingsColorModeNormal => 'Normal';

  @override
  String get settingsColorModeSepia => 'Sepia';

  @override
  String get settingsColorModeDark => 'Oscuro';

  @override
  String get settingsSepiaIntensityTitle => 'Intensidad de sepia';

  @override
  String get settingsKeepScreenOnTitle => 'Mantener pantalla encendida';

  @override
  String get settingsKeepScreenOnSubtitle =>
      'Evitar que la pantalla se apague mientras lees';

  @override
  String settingsHorizontalMarginValue({required int pixels}) {
    return 'Margen horizontal: ${pixels}px';
  }

  @override
  String settingsVerticalMarginValue({required int pixels}) {
    return 'Margen vertical: ${pixels}px';
  }

  @override
  String get settingsSwipeSensitivityTitle => 'Sensibilidad del deslizamiento';

  @override
  String settingsPercentValue({required int percent}) {
    return '$percent%';
  }

  @override
  String get settingsSwipeSensitivityHint =>
      'Más bajo = menos movimiento de dedo para deslizar';

  @override
  String get settingsManageDictionariesSubtitle =>
      'Importar, reordenar, activar/desactivar';

  @override
  String get settingsLookupFontSizeTitle => 'Tamaño de fuente para búsquedas';

  @override
  String get settingsFilterRomanLetterEntriesTitle =>
      'Filtrar entradas con letras romanas';

  @override
  String get settingsFilterRomanLetterEntriesSubtitle =>
      'Ocultar entradas que usan letras inglesas en la cabecera';

  @override
  String get settingsAutoFocusSearchTitle => 'Búsqueda con autoenfoque';

  @override
  String get settingsAutoFocusSearchSubtitle =>
      'Abrir el teclado al seleccionar la pestaña del diccionario';

  @override
  String get settingsAnkiDroidIntegrationTitle => 'Integración con AnkiDroid';

  @override
  String get settingsAnkiDroidIntegrationSubtitle =>
      'Configura el tipo de nota, mazo y asignación de campos';

  @override
  String get settingsProUnavailableSubtitle =>
      'Los servicios Pro no están disponibles temporalmente.';

  @override
  String get settingsProSubtitle =>
      'Desbloquea recorte automático, resaltados de libros y OCR personalizado';

  @override
  String get settingsWhiteThresholdTitle => 'Umbral de blanco';

  @override
  String settingsWhiteThresholdSubtitle({required int threshold}) {
    return '$threshold (valores más bajos ignoran más artefactos casi blancos)';
  }

  @override
  String get settingsCustomOcrServerTitle => 'Servidor OCR personalizado';

  @override
  String get settingsCustomOcrServerUnavailableSubtitle =>
      'Los servicios de OCR no están disponibles temporalmente.';

  @override
  String get settingsCustomOcrServerNotConfigured =>
      'No configurado. Añade la URL de tu servidor y la clave compartida.';

  @override
  String settingsCustomOcrServerConfigured({required String url}) {
    return '$url\nUsa la misma clave compartida configurada en tu servidor.';
  }

  @override
  String get settingsCustomOcrServerUrlLabel => 'URL del servidor';

  @override
  String get settingsCustomOcrServerUrlHint => 'http://192.168.1.100:8000';

  @override
  String get settingsCustomOcrServerLearnHow =>
      'Aprende cómo ejecutar tu propio servidor';

  @override
  String get settingsCustomOcrServerTestAction => 'Probar conexión';

  @override
  String get settingsCustomOcrServerTesting => 'Probando conexión...';

  @override
  String settingsCustomOcrServerHealthy({required String status}) {
    return 'Conectado. /health devolvió el estado: $status.';
  }

  @override
  String get settingsCustomOcrServerKeyLabel =>
      'Clave compartida personalizada';

  @override
  String get settingsCustomOcrServerKeyHint => 'AUTH_API_KEY requerido';

  @override
  String get settingsCustomOcrServerDescription =>
      'Introduce el mismo AUTH_API_KEY compartido que utiliza tu servidor OCR. Mekuru lo envía como Authorization: Bearer <key> para solicitudes de OCR remoto de manga.';

  @override
  String get settingsCustomOcrServerUrlRequired =>
      'Introduce la URL de tu servidor.';

  @override
  String get settingsCustomOcrServerUrlInvalid =>
      'Introduce una URL completa del servidor http:// o https://.';

  @override
  String get settingsCustomOcrServerKeyRequired =>
      'Se requiere una clave compartida para servidores personalizados.';

  @override
  String get settingsDownloadsSubtitle => 'Diccionarios, datos de kanji y más';

  @override
  String get settingsBackupRestoreTitle => 'Copia de seguridad y restaurar';

  @override
  String get settingsBackupRestoreSubtitle =>
      'Haz copias de seguridad y restaura tus datos';

  @override
  String get settingsSendFeedbackSubtitle =>
      'Informa de un error o sugiere una función';

  @override
  String get settingsFeedbackThanks => '¡Gracias por tu comentario!';

  @override
  String get settingsFeedbackFailed =>
      'Error al enviar el comentario. Por favor, inténtalo de nuevo.';

  @override
  String get settingsDocumentationTitle => 'Documentación';

  @override
  String get settingsDocumentationSubtitle => 'Guías y artículos explicativos';

  @override
  String get settingsAboutMekuruTitle => 'Acerca de Mekuru';

  @override
  String get settingsAboutMekuruSubtitle => 'Versión, licencias y más';

  @override
  String get feedbackTitle => 'Enviar comentarios';

  @override
  String get feedbackNameLabel => 'Nombre';

  @override
  String get feedbackNameHint => 'Tu nombre';

  @override
  String get feedbackEmailLabel => 'Correo electrónico';

  @override
  String get feedbackEmailHint => 'tu@email.com';

  @override
  String get feedbackMessageLabel => 'Mensaje';

  @override
  String get feedbackRequired => '(obligatorio)';

  @override
  String get feedbackMessageHint => 'Describe tu error o sugerencia...';

  @override
  String get feedbackMessageRequiredError => 'Por favor, introduce un mensaje';

  @override
  String get backupTitle => 'Copia de seguridad y restauración';

  @override
  String get backupSectionBackup => 'Copia de seguridad';

  @override
  String get backupCreateNowTitle => 'Crear copia ahora';

  @override
  String get backupCreateNowSubtitle =>
      'Guarda tu configuración y tus datos de usuario, como marcadores, resaltados y listas de vocabulario. Los archivos EPUB y manga no se incluyen.';

  @override
  String get backupExportTitle => 'Exportar copia';

  @override
  String get backupExportSubtitle =>
      'Guarda en un archivo tu copia más reciente de configuración y datos de usuario. Los archivos EPUB y manga no se incluyen.';

  @override
  String get backupSaveFileDialogTitle => 'Guardar copia de seguridad';

  @override
  String get backupScopeNoteTitle => '¿Qué se respalda?';

  @override
  String get backupScopeNoteBody =>
      'Las copias de seguridad incluyen tu configuración y los datos que creaste en Mekuru, como marcadores, resaltados y listas de vocabulario. No incluyen los archivos EPUB o manga reales.';

  @override
  String get backupScopeNoteRestore =>
      'Después de restaurar, vuelve a importar el mismo contenido EPUB o manga. Si el contenido coincide exactamente, tu historial volverá.';

  @override
  String get backupSectionAutoBackup => 'Copia automática';

  @override
  String get backupAutoBackupIntervalTitle => 'Intervalo de copia automática';

  @override
  String get backupIntervalOff => 'Desactivado';

  @override
  String get backupIntervalDaily => 'Diario';

  @override
  String get backupIntervalWeekly => 'Semanal';

  @override
  String get backupSectionRestore => 'Restaurar';

  @override
  String get backupImportFileTitle => 'Importar archivo de copia de seguridad';

  @override
  String get backupImportFileSubtitle =>
      'Restaura la configuración y los datos de usuario desde un archivo .mekuru. Vuelve a importar el mismo contenido EPUB o manga para recuperar su historial.';

  @override
  String get backupSectionHistory => 'Historial de copias de seguridad';

  @override
  String get backupNoBackupsYet => 'Aún no hay copias de seguridad';

  @override
  String backupErrorLoadingHistory({required String details}) {
    return 'Error al cargar las copias de seguridad: $details';
  }

  @override
  String get backupCreatedSuccess => 'Copia de seguridad creada exitosamente';

  @override
  String backupFailed({required String details}) {
    return 'Error de copia de seguridad: $details';
  }

  @override
  String get backupNoBackupsToExport =>
      'No hay copias de seguridad para exportar. Crea una primero.';

  @override
  String get backupExportedSuccess =>
      'Copia de seguridad exportada exitosamente';

  @override
  String backupExportFailed({required String details}) {
    return 'Error al exportar: $details';
  }

  @override
  String get backupInvalidFile =>
      'Por favor, selecciona un archivo de copia de seguridad .mekuru.';

  @override
  String backupCouldNotOpenFile({required String details}) {
    return 'No se pudo abrir el archivo: $details';
  }

  @override
  String backupRestoreFailed({required String details}) {
    return 'Error al restaurar: $details';
  }

  @override
  String backupBooksUpdatedFromBackup({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count libros actualizados desde la copia de seguridad',
      one: '$count libro actualizado desde la copia de seguridad',
    );
    return '$_temp0';
  }

  @override
  String backupApplyBookDataFailed({required String details}) {
    return 'No se pudieron aplicar los datos del libro: $details';
  }

  @override
  String get backupConflictDialogTitle => 'Libros en conflicto';

  @override
  String get backupConflictDialogBody =>
      'Los siguientes libros ya tienen datos de lectura. Selecciona cuáles sobrescribir con los datos de la copia de seguridad:';

  @override
  String backupConflictEntrySubtitle({
    required String bookType,
    required int progress,
  }) {
    return '$bookType - $progress% en la copia de seguridad';
  }

  @override
  String get backupConflictSkipAll => 'Omitir todo';

  @override
  String backupConflictOverwriteSelected({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Sobrescribir $count',
      one: 'Sobrescribir $count',
    );
    return '$_temp0';
  }

  @override
  String get backupBookTypeEpub => 'EPUB';

  @override
  String get backupBookTypeManga => 'Manga';

  @override
  String get backupRestoreSummarySettingsRestored => 'Ajustes restaurados';

  @override
  String get backupRestoreSummarySettingsPartial =>
      'Algunos ajustes no se pudieron restaurar';

  @override
  String backupRestoreSummaryWords({required int added, required int skipped}) {
    return '$added palabras añadidas, $skipped omitidas';
  }

  @override
  String backupRestoreSummaryBooksRestored({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count libros restaurados',
      one: '$count libro restaurado',
    );
    return '$_temp0';
  }

  @override
  String backupRestoreSummaryBooksPending({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count libros están esperando que se vuelva a importar el mismo contenido EPUB o manga',
      one:
          '$count libro está esperando que se vuelva a importar el mismo contenido EPUB o manga',
    );
    return '$_temp0';
  }

  @override
  String get backupRestoreComplete => 'Restauración completada';

  @override
  String get backupRestoreDialogTitle => '¿Restaurar copia de seguridad?';

  @override
  String backupRestoreDialogBody({required String fileName}) {
    return 'Esto restaurará la configuración y los datos de usuario desde $fileName, como marcadores, resaltados y listas de vocabulario. No restaura los archivos EPUB o manga reales. Después de restaurar, vuelve a importar el mismo contenido EPUB o manga para recuperar su historial. Tu configuración actual será sobrescrita.';
  }

  @override
  String get backupQueueDictionaryPreferencesTitle =>
      'Queue dictionary settings from this backup';

  @override
  String get backupQueueDictionaryPreferencesBody =>
      'You can apply matching dictionary order and enabled states later from Dictionary Manager.';

  @override
  String backupRestoreSummaryDictionaryPreferencesQueued({
    required int matching,
    required int missing,
  }) {
    return 'Dictionary settings queued: $matching ready to apply, $missing missing and will be skipped';
  }

  @override
  String get backupRestoreSummaryDictionaryPreferencesSkipped =>
      'Dictionary settings were not queued';

  @override
  String get backupDeleteDialogTitle => '¿Eliminar copia de seguridad?';

  @override
  String backupDeleteDialogBody({required String fileName}) {
    return '¿Eliminar $fileName? Esta acción no se puede deshacer.';
  }

  @override
  String get backupHistoryTypeAuto => 'Copia de seguridad automática';

  @override
  String get backupHistoryTypeManual => 'Copia de seguridad manual';

  @override
  String get readerDismiss => 'Cerrar';

  @override
  String readerFailedToLoadContent({required String details}) {
    return 'No se pudo cargar el contenido EPUB.\n$details';
  }

  @override
  String readerFailedToLoad({required String details}) {
    return 'No se pudo cargar el EPUB.\n$details';
  }

  @override
  String get readerVerticalTextNonNativeWarning =>
      'Este libro no fue originalmente formateado para texto vertical. Puede haber problemas de visualización.';

  @override
  String get readerHorizontalTextNonNativeWarning =>
      'Este libro fue originalmente formateado para texto vertical. Puede haber problemas de visualización en modo horizontal.';

  @override
  String get readerBookmarkRemoved => 'Marcador eliminado';

  @override
  String get readerPageBookmarked => 'Página marcada';

  @override
  String get readerTableOfContents => 'Tabla de contenido';

  @override
  String get readerRemoveBookmarkTooltip => 'Eliminar marcador';

  @override
  String get readerBookmarkPageTooltip => 'Marcar página';

  @override
  String get readerViewBookmarksTooltip => 'Ver marcadores';

  @override
  String get readerHighlightsTooltip => 'Destacados';

  @override
  String get readerNextPageTooltip => 'Página siguiente';

  @override
  String get readerPreviousPageTooltip => 'Página anterior';

  @override
  String get readerUnknownError => 'Error de lector desconocido.';

  @override
  String get readerQuickSettings => 'Ajustes rápidos';

  @override
  String get readerVerticalTextTitle => 'Texto vertical';

  @override
  String get readerThisBook => 'Este libro';

  @override
  String get readerVerticalTextUnavailable =>
      'No disponible para el idioma de este libro';

  @override
  String get readerReadingDirectionTitle => 'Dirección de lectura';

  @override
  String get readerReadingDirectionRtl => 'De derecha a izquierda';

  @override
  String get readerReadingDirectionLtr => 'De izquierda a derecha';

  @override
  String get readerDisableLinksTitle => 'Desactivar enlaces';

  @override
  String get readerDisableLinksSubtitle =>
      'Toca el texto enlazado para buscar palabras en lugar de navegar';

  @override
  String get readerHighlightSelectionTooltip => 'Resaltar selección';

  @override
  String get commonCopy => 'Copiar';

  @override
  String get commonShare => 'Compartir';

  @override
  String get commonContinue => 'Continuar';

  @override
  String get commonNotSelected => 'No seleccionado';

  @override
  String get commonUnknown => 'Desconocido';

  @override
  String get commonRename => 'Renombrar';

  @override
  String get commonTitleLabel => 'Título';

  @override
  String libraryCouldNotReadFolder({required String details}) {
    return 'No se pudo leer la carpeta:\n$details';
  }

  @override
  String get libraryBookmarksTitle => 'Marcadores';

  @override
  String get libraryChangeCoverAction => 'Cambiar portada';

  @override
  String get libraryRenameBookTitle => 'Renombrar libro';

  @override
  String get libraryDeleteBookTitle => 'Eliminar libro';

  @override
  String libraryDeleteBookBody({required String title}) {
    return '¿Eliminar \"$title\" de tu biblioteca?';
  }

  @override
  String libraryChangeCoverFailed({required String details}) {
    return 'No se pudo cambiar la portada: $details';
  }

  @override
  String get dictionaryManagerTitle => 'Gestor de diccionarios';

  @override
  String get dictionaryManagerImportTooltip => 'Importar diccionario';

  @override
  String get dictionaryManagerEmptySubtitle =>
      'Toca + para importar un diccionario Yomitan (.zip)\no una colección (.json)';

  @override
  String get dictionaryManagerBrowseDownloads => 'Explorar descargas';

  @override
  String get dictionaryManagerBrowseDownloadsCaption =>
      'Descarga diccionarios y otros recursos';

  @override
  String dictionaryManagerImportedOn({required String date}) {
    return 'Importado el $date';
  }

  @override
  String get dictionaryManagerSupportedFormatsTitle => 'Formatos compatibles';

  @override
  String get dictionaryManagerSupportedFormatsYomitan =>
      'Diccionario Yomitan (.zip)\nSe admite cualquier diccionario que pueda importarse en Yomitan. Estos son archivos .zip que contienen archivos JSON de bancos de términos.';

  @override
  String get dictionaryManagerSupportedFormatsCollection =>
      'Colección Yomitan (.json)\nUna exportación de base de datos Dexie que contiene varios diccionarios en un solo archivo. Puedes exportarlo desde la configuración de Yomitan en Copia de seguridad.';

  @override
  String get dictionaryManagerOrderTitle => 'Orden de los diccionarios';

  @override
  String get dictionaryManagerOrderBody =>
      'Arrastra los diccionarios usando el asa a la izquierda para reordenarlos. El orden aquí controla cómo aparecen las definiciones al pulsar una palabra mientras lees.';

  @override
  String get dictionaryManagerPendingBackupTitle =>
      'Backup dictionary settings ready';

  @override
  String get dictionaryManagerPendingBackupBody =>
      'Apply the dictionary order and enabled states saved in your restored backup. Missing dictionaries will be skipped.';

  @override
  String dictionaryManagerPendingBackupMatching({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count matching dictionaries installed',
      one: '1 matching dictionary installed',
      zero: '0 matching dictionaries installed',
    );
    return '$_temp0';
  }

  @override
  String dictionaryManagerPendingBackupMissing({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dictionaries missing and will be skipped',
      one: '1 dictionary missing and will be skipped',
      zero: '0 dictionaries missing',
    );
    return '$_temp0';
  }

  @override
  String get dictionaryManagerPendingBackupNoMatches =>
      'Install at least one matching dictionary to apply these backup settings.';

  @override
  String get dictionaryManagerPendingBackupApplyButton =>
      'Apply Backup Settings';

  @override
  String get dictionaryManagerPendingBackupWarningTitle =>
      'Overwrite current dictionary settings?';

  @override
  String get dictionaryManagerPendingBackupWarningBody =>
      'This will overwrite the current order and enabled or disabled state for matching dictionaries. Missing dictionaries will be skipped.';

  @override
  String dictionaryManagerPendingBackupApplied({
    required int applied,
    required int missing,
  }) {
    return 'Applied backup settings to $applied dictionaries. Skipped $missing missing dictionaries.';
  }

  @override
  String get dictionaryManagerEnablingTitle => 'Activar y desactivar';

  @override
  String get dictionaryManagerEnablingBody =>
      'Usa el interruptor para activar o desactivar un diccionario. Los diccionarios desactivados no se buscarán al consultar palabras.';

  @override
  String get dictionaryManagerFindingTitle => 'Encontrar diccionarios';

  @override
  String get dictionaryManagerFindingPrefix =>
      'Explora diccionarios compatibles en ';

  @override
  String get dictionaryManagerDeleteTitle => 'Eliminar diccionario';

  @override
  String dictionaryManagerDeleteBody({required String name}) {
    return '¿Eliminar \"$name\" y todas sus entradas?\nEsta acción no se puede deshacer.';
  }

  @override
  String get ankidroidDataSourceExpression => 'Expresión';

  @override
  String get ankidroidDataSourceReading => 'Lectura';

  @override
  String get ankidroidDataSourceFurigana => 'Furigana (formato Anki)';

  @override
  String get ankidroidDataSourceGlossary => 'Glosario / Significado';

  @override
  String get ankidroidDataSourceSentenceContext => 'Contexto de la frase';

  @override
  String get ankidroidDataSourceFrequency => 'Rango de frecuencia';

  @override
  String get ankidroidDataSourceDictionaryName => 'Nombre del diccionario';

  @override
  String get ankidroidDataSourcePitchAccent => 'Acento de tono';

  @override
  String get ankidroidDataSourceEmpty => '(Vacío)';

  @override
  String get ankidroidPermissionNotGrantedLong =>
      'No se ha concedido el permiso de AnkiDroid. Asegúrate de que AnkiDroid esté instalado e inténtalo de nuevo.';

  @override
  String get ankidroidCouldNotConnectLong =>
      'No se pudo conectar con AnkiDroid. Asegúrate de que AnkiDroid esté instalado y en funcionamiento.';

  @override
  String get ankidroidPermissionNotGrantedShort =>
      'Permiso de AnkiDroid no concedido.';

  @override
  String get ankidroidCouldNotConnectShort =>
      'No se pudo conectar con AnkiDroid.';

  @override
  String get ankidroidFailedToAddNote =>
      'No se pudo añadir la nota. Asegúrate de que AnkiDroid esté en funcionamiento y que el tipo de nota y baraja seleccionados sigan existiendo.';

  @override
  String get ankidroidSettingsNoteTypeSection => 'Tipo de nota';

  @override
  String get ankidroidSettingsNoteTypeTitle => 'Tipo de nota de Anki';

  @override
  String get ankidroidSettingsDefaultDeckSection => 'Baraja predeterminada';

  @override
  String get ankidroidSettingsTargetDeckTitle => 'Baraja objetivo';

  @override
  String get ankidroidSettingsFieldMappingSection => 'Asignación de campos';

  @override
  String get ankidroidSettingsFieldMappingHelp =>
      'Asigna cada campo de Anki a una fuente de datos de la app.';

  @override
  String get ankidroidSettingsDefaultTagsSection => 'Etiquetas predeterminadas';

  @override
  String get ankidroidSettingsDefaultTagsHelp =>
      'Etiquetas separadas por comas que se aplican a cada nota exportada.';

  @override
  String get ankidroidTagsHint => 'mekuru, japanese';

  @override
  String get ankidroidSettingsSelectNoteType => 'Seleccionar tipo de nota';

  @override
  String get ankidroidSettingsSelectDeck => 'Seleccionar baraja';

  @override
  String ankidroidSettingsMapFieldTo({required String ankiFieldName}) {
    return 'Asignar \"$ankiFieldName\" a:';
  }

  @override
  String get ankidroidCardSettingsTooltip => 'Ajustes de AnkiDroid';

  @override
  String get ankidroidCardDeckTitle => 'Baraja';

  @override
  String get ankidroidCardTagsTitle => 'Etiquetas';

  @override
  String get ankidroidCardAddToAnki => 'Añadir a Anki';

  @override
  String get mangaReaderSettingsTitle => 'Ajustes del lector';

  @override
  String get mangaViewModeSingle => 'Página única';

  @override
  String get mangaViewModeSpread => 'Dos páginas';

  @override
  String get mangaViewModeScroll => 'Desplazamiento';

  @override
  String get mangaAutoCropSubtitle => 'Eliminar márgenes vacíos';

  @override
  String get mangaAutoCropRerunTitle => 'Volver a ejecutar Auto-Recorte';

  @override
  String get mangaAutoCropRerunSubtitle =>
      'Volver a escanear todas las páginas de este libro';

  @override
  String get mangaTransparentLookupTitle => 'Búsqueda Transparente';

  @override
  String get mangaTransparentLookupSubtitle =>
      'Hoja de diccionario translúcida';

  @override
  String get mangaPageTurnEdgeZoneTitle => 'Zona lateral para pasar página';

  @override
  String get mangaPageTurnEdgeZoneSubtitle =>
      'Cuánto de cada borde del dispositivo se reserva para pasar de página.';

  @override
  String get mangaDebugWordOverlayTitle => 'Depurar Superposición de Palabras';

  @override
  String get mangaDebugWordOverlaySubtitle =>
      'Mostrar cajas delimitadoras de palabras';

  @override
  String get mangaAutoCropComputeTitle => '¿Calcular Auto-Recorte?';

  @override
  String get mangaAutoCropComputeBody =>
      'El auto-recorte necesita escanear todas las páginas de este libro antes de poder activarse. Esto puede tomar un minuto.';

  @override
  String get mangaAutoCropRerunDialogTitle =>
      '¿Volver a ejecutar Auto-Recorte?';

  @override
  String get mangaAutoCropRerunDialogBody =>
      'El auto-recorte volverá a escanear todas las páginas de este libro y reemplazará los límites recortados guardados. Esto puede tomar un minuto.';

  @override
  String get mangaAutoCropComputingProgress =>
      'Calculando límites del auto-recorte. Esto puede tomar un minuto.';

  @override
  String get mangaAutoCropRecomputingProgress =>
      'Recalculando límites del auto-recorte. Esto puede tomar un minuto.';

  @override
  String get mangaAutoCropBoundsRefreshed =>
      'Límites del auto-recorte actualizados.';

  @override
  String mangaAutoCropSetupFailed({required String details}) {
    return 'Error al configurar el auto-recorte: $details';
  }

  @override
  String get ocrNoPagesCacheFound =>
      'No se encontró caché de páginas para este libro';

  @override
  String get ocrAlreadyCompleteResetHint =>
      'El OCR ya está completo. Usa \"Eliminar OCR\" para reiniciar.';

  @override
  String get ocrMangaImageDirectoryNotFound =>
      'Directorio de imágenes de manga no encontrado';

  @override
  String get ocrBuildWordOverlaysTitle => 'Crear Superposiciones de Palabras';

  @override
  String get ocrBuildWordOverlaysBody =>
      'El texto OCR ya existe. Esto volverá a crear las áreas táctiles de palabras para que las superposiciones del diccionario funcionen correctamente.';

  @override
  String get ocrRunActionTitle => 'Ejecutar OCR';

  @override
  String ocrProcessPagesBody({required int count}) {
    return 'Esto procesará $count páginas. El OCR se ejecutará en segundo plano y continuará incluso si cierras la app.';
  }

  @override
  String get ocrProcessAction => 'Procesar';

  @override
  String get ocrStartAction => 'Iniciar';

  @override
  String ocrPrepareFailed({required String details}) {
    return 'No se pudo preparar el OCR: $details';
  }

  @override
  String ocrStartFailed({required String details}) {
    return 'No se pudo iniciar el OCR: $details';
  }

  @override
  String get ocrWordOverlayStartedBackground =>
      'Procesamiento de la superposición de palabras iniciado en segundo plano';

  @override
  String get ocrStartedBackground => 'OCR iniciado en segundo plano';

  @override
  String get ocrCancelActionTitle => 'Pausar OCR';

  @override
  String get ocrCancelSavedProgress => 'OCR en pausa. Progreso guardado.';

  @override
  String get ocrReplaceActionTitle => 'Reemplazar OCR';

  @override
  String get ocrReplaceMokuroBody =>
      'Esto sobrescribirá los datos de OCR importados del archivo Mokuro/HTML y volverá a ejecutar el OCR en TODAS las páginas usando tu propio servidor.\n\nDespués podrás usar Eliminar OCR para restaurar el OCR original.';

  @override
  String get ocrReplaceStartedBackground =>
      'Reemplazo de OCR iniciado en segundo plano';

  @override
  String get ocrRemoveActionTitle => 'Eliminar OCR';

  @override
  String get ocrRemoveBody =>
      '¿Eliminar todo el texto OCR y las superposiciones de palabras de este manga? Puedes ejecutar OCR de nuevo más tarde.';

  @override
  String get ocrRemoveSubtitle => 'Eliminar todo el texto OCR de este libro';

  @override
  String get ocrRemovedFromBook => 'OCR eliminado de este libro';

  @override
  String ocrRemoveFailed({required String details}) {
    return 'No se pudo eliminar el OCR: $details';
  }

  @override
  String get ocrUnlockProSubtitle =>
      'Desbloquea Pro para usar tu propio servidor OCR';

  @override
  String get ocrStopAndSaveProgressSubtitle =>
      'Pausar el procesamiento y guardar el progreso';

  @override
  String get ocrReplaceMokuroSubtitle =>
      'Reemplaza el OCR de Mokuro con tu propio servidor OCR';

  @override
  String get ocrRestoreOriginalMokuroBody =>
      '¿Eliminar el OCR actual y restaurar el OCR original importado desde el archivo Mokuro/HTML?';

  @override
  String get ocrRestoreOriginalMokuroSubtitle =>
      'Eliminar el OCR actual y restaurar el OCR original de Mokuro/HTML';

  @override
  String get ocrOriginalMokuroRestored =>
      'Se restauró el OCR original de Mokuro/HTML';

  @override
  String get ocrBuildWordTargetsSubtitle =>
      'Generar zonas táctiles desde el OCR guardado';

  @override
  String ocrResumeSubtitle({required int completed, required int total}) {
    return 'Reanudar OCR ($completed/$total completados)';
  }

  @override
  String get ocrRecognizeAllPagesSubtitle =>
      'Reconocer texto en todas las páginas';

  @override
  String get readerEditNoteTitle => 'Editar nota';

  @override
  String get readerAddNoteHint => 'Añadir una nota...';

  @override
  String get readerCopiedToClipboard => 'Copiado al portapapeles';

  @override
  String get aboutPrivacyPolicyTitle => 'Política de privacidad';

  @override
  String get aboutPrivacyPolicySubtitle =>
      'Consulta cómo Mekuru gestiona los datos locales y de OCR';

  @override
  String get aboutOpenSourceLicensesTitle => 'Licencias de código abierto';

  @override
  String get aboutOpenSourceLicensesSubtitle => 'Ver licencias de dependencias';

  @override
  String get aboutTagline => '\"pasar páginas\"';

  @override
  String get aboutEpubJsLicenseTitle => 'Licencia de epub.js';

  @override
  String get downloadsKanjidicTitle => 'KANJIDIC';

  @override
  String get readerBookmarksTitle => 'Marcadores';

  @override
  String get readerNoBookmarksYet =>
      'Aún no hay marcadores.\nToca el icono de marcador mientras lees para añadir uno.';

  @override
  String readerBookmarkProgressDate({
    required String progress,
    required String date,
  }) {
    return '$progress - $date';
  }

  @override
  String aboutVersion({required String version}) {
    return 'Versión $version';
  }

  @override
  String get aboutDescription =>
      'Un lector EPUB enfocado en japonés con texto vertical, diccionario sin conexión y gestión de vocabulario.';

  @override
  String get aboutAttributionTitle => 'Atribución';

  @override
  String get aboutKanjiVgTitle => 'KanjiVG';

  @override
  String get aboutKanjiVgDescription =>
      'Los datos de orden de trazos kanji son proporcionados por el proyecto KanjiVG, creado por Ulrich Apel.';

  @override
  String get aboutLicensedUnderPrefix => 'Licenciado bajo la ';

  @override
  String get aboutLicenseSuffix => ' licencia.';

  @override
  String get aboutProjectLabel => 'Proyecto: ';

  @override
  String get aboutSourceLabel => 'Fuente: ';

  @override
  String get aboutJpdbTitle => 'Diccionario de Frecuencias JPDB';

  @override
  String get aboutJpdbDescription =>
      'Los datos de frecuencia de palabras provienen del diccionario de frecuencias JPDB, distribuidos a través de yomitan-dictionaries por Kuuuube.';

  @override
  String get aboutDataSourceLabel => 'Fuente de datos: ';

  @override
  String get aboutDictionaryLabel => 'Diccionario: ';

  @override
  String get aboutJmdictKanjidicTitle => 'JMdict & KANJIDIC';

  @override
  String get aboutJmdictKanjidicDescriptionPrefix =>
      'Los datos del diccionario japonés multilingüe provienen del proyecto JMdict/EDICT y los datos de kanji del proyecto KANJIDIC, ambos creados por Jim Breen y el ';

  @override
  String get aboutJmdictLabel => 'JMdict: ';

  @override
  String get aboutKanjidicLabel => 'KANJIDIC: ';

  @override
  String get aboutEpubJsTitle => 'epub.js';

  @override
  String get aboutEpubJsDescription =>
      'La visualización de EPUB funciona con epub.js, una biblioteca EPUB de JavaScript de código abierto.';

  @override
  String get dictionaryPartOfSpeechNoun => 'Noun';

  @override
  String get dictionaryPartOfSpeechPronoun => 'Pronoun';

  @override
  String get dictionaryPartOfSpeechPrefix => 'Prefix';

  @override
  String get dictionaryPartOfSpeechSuffix => 'Suffix';

  @override
  String get dictionaryPartOfSpeechCounter => 'Counter';

  @override
  String get dictionaryPartOfSpeechNumeric => 'Numeric';

  @override
  String get dictionaryPartOfSpeechExpression => 'Expression';

  @override
  String get dictionaryPartOfSpeechInterjection => 'Interjection';

  @override
  String get dictionaryPartOfSpeechConjunction => 'Conjunction';

  @override
  String get dictionaryPartOfSpeechParticle => 'Particle';

  @override
  String get dictionaryPartOfSpeechCopula => 'Copula';

  @override
  String get dictionaryPartOfSpeechAuxiliary => 'Auxiliary';

  @override
  String get dictionaryPartOfSpeechAuxiliaryVerb => 'Auxiliary verb';

  @override
  String get dictionaryPartOfSpeechAuxiliaryAdjective => 'Auxiliary adjective';

  @override
  String get dictionaryPartOfSpeechIAdjective => 'I-adjective';

  @override
  String get dictionaryPartOfSpeechNaAdjective => 'Na-adjective';

  @override
  String get dictionaryPartOfSpeechNoAdjective => 'No-adjective';

  @override
  String get dictionaryPartOfSpeechPreNounAdjectival => 'Pre-noun adjectival';

  @override
  String get dictionaryPartOfSpeechAdverb => 'Adverb';

  @override
  String get dictionaryPartOfSpeechToAdverb => 'To-adverb';

  @override
  String get dictionaryPartOfSpeechAdverbialNoun => 'Adverbial noun';

  @override
  String get dictionaryPartOfSpeechSuruVerb => 'Suru verb';

  @override
  String get dictionaryPartOfSpeechKuruVerb => 'Kuru verb';

  @override
  String get dictionaryPartOfSpeechIchidanVerb => 'Ichidan verb';

  @override
  String get dictionaryPartOfSpeechGodanVerb => 'Godan verb';

  @override
  String get dictionaryPartOfSpeechZuruVerb => 'Zuru verb';

  @override
  String get dictionaryPartOfSpeechIntransitiveVerb => 'Intransitive verb';

  @override
  String get dictionaryPartOfSpeechTransitiveVerb => 'Transitive verb';
}
