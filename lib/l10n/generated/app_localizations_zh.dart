// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'Mekuru';

  @override
  String get navLibrary => '书库';

  @override
  String get navDictionary => '词典';

  @override
  String get navVocabulary => '生词本';

  @override
  String get navSettings => '设置';

  @override
  String get commonHelp => '帮助';

  @override
  String get commonImport => '导入';

  @override
  String get commonOpenNow => '立即打开';

  @override
  String get commonCancel => '取消';

  @override
  String get commonClose => '关闭';

  @override
  String get commonSave => '保存';

  @override
  String get commonDelete => '删除';

  @override
  String get commonDownload => '下载';

  @override
  String get commonOpenDictionary => '打开词典';

  @override
  String get commonManageDictionaries => '管理词典';

  @override
  String get commonClearAll => '全部清除';

  @override
  String get commonClearSearch => '清除搜索';

  @override
  String get commonSearch => '搜索';

  @override
  String get commonBack => '返回';

  @override
  String get commonRetry => '重试';

  @override
  String get commonOk => '确定';

  @override
  String get commonDone => '完成';

  @override
  String get commonUndo => '撤销';

  @override
  String get commonUnlock => '解锁';

  @override
  String get commonOpenSettings => '打开设置';

  @override
  String get commonGotIt => '知道了';

  @override
  String commonErrorWithDetails({required String details}) {
    return '错误：$details';
  }

  @override
  String librarySortTooltip({required String label}) {
    return '排序：$label';
  }

  @override
  String get libraryEmptyTitle => '你的书库已准备好迎接第一本书';

  @override
  String get libraryEmptySubtitle => '导入一些可阅读的内容，安装词典，几分钟内就可以开始保存单词。';

  @override
  String get libraryImportEpub => '导入EPUB';

  @override
  String get libraryImportManga => '导入漫画';

  @override
  String get libraryGetDictionaries => '获取词典';

  @override
  String get libraryRestoreBackup => '恢复备份';

  @override
  String get librarySupportedMediaTitle => '支持的媒体格式';

  @override
  String get libraryEpubBooksTitle => 'EPUB电子书';

  @override
  String get libraryEpubBooksDescription =>
      '支持标准.epub文件。点击“+”按钮并选择“导入EPUB”即可从设备添加。';

  @override
  String get libraryMokuroTitle => 'Mokuro漫画';

  @override
  String get libraryMokuroDescription =>
      '通过选择文件夹，然后选择.mokuro或.html文件来导入漫画。页面图片将从同名的相邻文件夹加载。';

  @override
  String get libraryMokuroFormatDescription =>
      '.mokuro文件由mokuro工具生成，该工具对漫画页面进行OCR以提取日文文本。';

  @override
  String get libraryLearnHowToCreateMokuroFiles => '了解如何创建.mokuro文件';

  @override
  String get librarySortBy => '排序方式';

  @override
  String get librarySortDateImported => '导入日期';

  @override
  String get librarySortRecentlyRead => '最近阅读';

  @override
  String get librarySortAlphabetical => '按字母顺序';

  @override
  String get libraryImportTitle => '导入';

  @override
  String get libraryImportEpubSubtitle => '导入EPUB文件';

  @override
  String get libraryImportMangaSubtitle => '选择CBZ压缩包或Mokuro文件夹';

  @override
  String get libraryImportMangaTitle => '导入漫画';

  @override
  String get libraryImportMangaDescription => '请选择要导入CBZ压缩包还是Mokuro导出的文件夹。';

  @override
  String get libraryImportMokuroFolder => 'Mokuro 文件夹';

  @override
  String get libraryImportMokuroFolderSubtitle =>
      '请选择包含 .mokuro 或 .html 文件及图片文件夹的文件夹。';

  @override
  String get libraryWhatIsMokuro => '什么是 Mokuro？';

  @override
  String get libraryImportCbzArchive => 'CBZ 压缩包';

  @override
  String get libraryImportCbzArchiveSubtitle => '导入 .cbz 漫画压缩包';

  @override
  String get libraryImportedWithoutOcrMessage =>
      '已导入，但未包含 OCR。要获得文本覆盖层，请导入外部 OCR 输出（如 .mokuro）。';

  @override
  String get libraryCouldNotOpenMokuroProjectPage => '无法打开 Mokuro 项目页面。';

  @override
  String get libraryNoMangaManifestFound => '在选定的文件夹中未找到 .mokuro 或 .html 文件。';

  @override
  String get librarySelectMangaFolder => '选择漫画文件夹';

  @override
  String get librarySelectedFolder => '已选择文件夹';

  @override
  String libraryMangaFilesFound({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '找到#个漫画文件',
      one: '找到#个漫画文件',
    );
    return '$_temp0';
  }

  @override
  String get dictionarySearchHint => '可用汉字、假名或罗马音搜索...';

  @override
  String get dictionaryNoDictionariesTitle => '尚未导入词典';

  @override
  String get dictionaryNoDictionariesSubtitle =>
      '安装入门词包或导入你自己的 Yomitan 词典后即可开始搜索。';

  @override
  String get dictionaryRecommendedStarterPack => '推荐入门词包';

  @override
  String get dictionaryNoEnabledTitle => '你的词典已关闭';

  @override
  String get dictionaryNoEnabledSubtitle => '至少启用一个词典以完成查词，或安装推荐入门词包。';

  @override
  String get dictionaryEnableDictionaries => '启用词典';

  @override
  String get dictionaryStarterPack => '入门词包';

  @override
  String get dictionaryNoResultsFound => '未找到结果。';

  @override
  String get dictionarySearchForAWord => '查找单词';

  @override
  String get dictionarySearchForAWordSubtitle => '可输入汉字、平假名、片假名或罗马音';

  @override
  String get dictionaryRecent => '最近';

  @override
  String dictionarySavedWord({required String expression}) {
    return '已保存“$expression”';
  }

  @override
  String get dictionaryWordAlreadyExistsInVocab => '单词已存在于词汇列表';

  @override
  String dictionaryCopiedWord({required String expression}) {
    return '已复制“$expression”';
  }

  @override
  String get dictionaryWordAlreadyExistsInAnki => '单词已存在于默认牌组';

  @override
  String dictionaryAddedToAnki({required String expression}) {
    return '已将“$expression”添加到Anki';
  }

  @override
  String get dictionaryCopyTooltip => '复制';

  @override
  String get dictionaryAlreadyInAnkiTooltip => '已在默认Anki牌组。长按可强制添加';

  @override
  String get dictionaryCheckingAnkiTooltip => '正在检查默认Anki牌组';

  @override
  String get dictionarySendToAnkiTooltip => '发送到AnkiDroid';

  @override
  String get dictionaryAlreadyInVocabTooltip => '已在单词本';

  @override
  String get dictionarySaveToVocabularyTooltip => '保存到单词本';

  @override
  String get dictionaryVeryCommon => '非常常见';

  @override
  String get dictionaryOnyomiLabel => '音读：';

  @override
  String get dictionaryKunyomiLabel => '训读：';

  @override
  String dictionaryKanjiStrokeCount({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '#画',
      one: '#画',
    );
    return '$_temp0';
  }

  @override
  String get dictionaryAnimateStrokeOrderTooltip => '演示笔顺';

  @override
  String get vocabularySearchSavedWordsHint => '搜索已保存单词';

  @override
  String get vocabularyExportCsvTooltip => '导出CSV';

  @override
  String get vocabularyEmptyTitle => '还没有已保存的单词';

  @override
  String get vocabularyEmptySubtitle => '通过词典查询或阅读时保存单词，它们会带有上下文显示在这里。';

  @override
  String vocabularyNoMatches({required String query}) {
    return '未找到与“$query”匹配的内容';
  }

  @override
  String get vocabularyNoMatchesSubtitle => '请尝试表达、读音或释义片段。';

  @override
  String vocabularySelectedCount({required int count}) {
    return '已选$count个';
  }

  @override
  String get vocabularyDeselectAllTooltip => '取消全选';

  @override
  String get vocabularySelectAllTooltip => '全选';

  @override
  String get vocabularyExportSelectedTooltip => '导出已选';

  @override
  String get vocabularyNoDefinition => '暂无释义';

  @override
  String get vocabularyContextLabel => '上下文：';

  @override
  String vocabularyAddedOn({required String date}) {
    return '添加时间：$date';
  }

  @override
  String vocabularyDeletedWord({required String expression}) {
    return '已删除“$expression”';
  }

  @override
  String ocrPagesProgress({required int completed, required int total}) {
    return '$completed/$total 页';
  }

  @override
  String ocrEtaSecondsRemaining({required int seconds}) {
    return '约剩余 $seconds 秒';
  }

  @override
  String ocrEtaMinutesRemaining({required int minutes}) {
    return '约剩余 $minutes 分钟';
  }

  @override
  String ocrEtaHoursMinutesRemaining({
    required int hours,
    required int minutes,
  }) {
    return '约剩余 $hours 小时 $minutes 分钟';
  }

  @override
  String get ocrPaused => 'OCR 已暂停';

  @override
  String get ocrComplete => 'OCR 完成';

  @override
  String get ocrFailed => 'OCR 失败';

  @override
  String get ocrTapForDetails => '点击查看详情';

  @override
  String get ocrCustomServerRequiredTitle => '需要自定义 OCR 服务器';

  @override
  String get ocrCustomServerRequiredBody =>
      '远程漫画 OCR 现在需要使用您自己的服务器。请在设置中添加自定义 OCR 服务器地址和匹配的共享密钥。';

  @override
  String get ocrCustomServerKeyRequiredTitle => '需要自定义服务器设置';

  @override
  String get ocrCustomServerKeyRequiredBody =>
      '自定义 OCR 服务器需要共享密钥。请在自定义 OCR 服务器设置中输入与您的服务器一致的 AUTH_API_KEY。';

  @override
  String get proTitle => '专业版';

  @override
  String get proPurchaseConfirmed => '您的购买已确认！';

  @override
  String get proUnlockOnceTitle => '一次性解锁专业版';

  @override
  String get proStatusUnlocked => '已解锁';

  @override
  String get proStatusLocked => '未解锁';

  @override
  String get proUnlockDescription => '一次性购买，解锁阅读增强功能。';

  @override
  String get proRestorePurchase => '恢复购买';

  @override
  String get proFeatureAutoCropTitle => '自动裁边';

  @override
  String get proFeatureAutoCropDescription => '每本书设置一次后，自动裁剪漫画页面的空白边缘。';

  @override
  String get proFeatureHighlightsTitle => '书籍高亮';

  @override
  String get proFeatureHighlightsDescription => '在阅读 EPUB 书籍时保存并回顾高亮内容。';

  @override
  String get proFeatureCustomOcrTitle => '自定义 OCR 服务器';

  @override
  String get proFeatureCustomOcrDescription => '使用你自己的服务器和共享密钥进行远程漫画 OCR。';

  @override
  String get proServerRepo => '服务器仓库';

  @override
  String get proAlreadyUnlocked => '已解锁';

  @override
  String get proUnlock => '解锁 Pro 版';

  @override
  String proUnlockWithPrice({required String price}) {
    return '解锁 Pro 版 $price';
  }

  @override
  String get downloadsTitle => '下载';

  @override
  String get downloadsRecommendedStarterPackTitle => '推荐入门包';

  @override
  String get downloadsRecommendedStarterPackSubtitle =>
      '一起安装 JMdict 英文词典和词频数据，实现最快速设置。';

  @override
  String get downloadsStarterPackJmdict => 'JMdict 英文版';

  @override
  String get downloadsStarterPackWordFrequency => '词频';

  @override
  String get downloadsInstallStarterPack => '安装入门包';

  @override
  String get downloadsSectionDictionaries => '词典';

  @override
  String get downloadsSectionAssets => '资源';

  @override
  String get downloadsFetchingLatestRelease => '正在获取最新版本…';

  @override
  String downloadsDownloadingPercent({required int percent}) {
    return '正在下载…$percent%';
  }

  @override
  String get downloadsImporting => '正在导入…';

  @override
  String get downloadsExtractingFiles => '正在解压文件…';

  @override
  String get downloadsJpdbAttribution => '词频数据来自 JPDB（jpdb.io），由 Kuuuube 分发。';

  @override
  String get downloadsKanjiStrokeOrderTitle => '汉字笔顺';

  @override
  String downloadsKanjiStrokeOrderDownloaded({required int count}) {
    return '已下载 $count 个笔顺文件';
  }

  @override
  String get downloadsKanjiStrokeOrderDescription => '从 KanjiVG 下载汉字笔顺数据';

  @override
  String get downloadsDeleteKanjiDataTooltip => '删除汉字数据';

  @override
  String get downloadsDeleteKanjiDataTitle => '删除汉字数据';

  @override
  String get downloadsDeleteKanjiDataBody => '删除所有已下载的汉字笔顺文件？您可以稍后重新下载。';

  @override
  String get downloadsWordFrequencyDownloaded => '词频数据已下载';

  @override
  String get downloadsWordFrequencyDescription => '下载词频数据，用于搜索排名';

  @override
  String get downloadsDeleteFrequencyDataTooltip => '删除词频数据';

  @override
  String get downloadsDeleteFrequencyDataTitle => '删除词频数据';

  @override
  String get downloadsDeleteFrequencyDataBody =>
      '删除词频数据？搜索结果将不再按词频排序。您可以稍后重新下载。';

  @override
  String get downloadsJmdictDownloaded => '日英词典已下载';

  @override
  String get downloadsJmdictDescription => '下载日英词典';

  @override
  String get downloadsDeleteJmdictTooltip => '删除 JMdict';

  @override
  String get downloadsChooseJmdictVariant => '选择 JMdict 版本';

  @override
  String get downloadsJmdictStandardSubtitle => '标准词典（约 15 MB）';

  @override
  String get downloadsJmdictExamplesTitle => 'JMdict 英文带例句';

  @override
  String get downloadsJmdictExamplesSubtitle => '包含例句（约 18 MB）';

  @override
  String get downloadsDeleteJmdictTitle => '删除 JMdict';

  @override
  String get downloadsDeleteJmdictBody => '删除 JMdict 及其所有词条？您可以稍后重新下载。';

  @override
  String get downloadsKanjidicDownloaded => '汉字字典已下载';

  @override
  String get downloadsKanjidicDescription => '下载汉字字典';

  @override
  String get downloadsDeleteKanjidicTooltip => '删除 KANJIDIC';

  @override
  String get downloadsDeleteKanjidicTitle => '删除 KANJIDIC';

  @override
  String get downloadsDeleteKanjidicBody => '删除 KANJIDIC 及其所有词条？您可以稍后重新下载。';

  @override
  String get commonClear => '清除';

  @override
  String get commonSubmit => '提交';

  @override
  String get commonLoading => '加载中...';

  @override
  String get commonError => '错误';

  @override
  String get commonRestore => '恢复';

  @override
  String get settingsTitle => '设置';

  @override
  String get settingsSectionGeneral => '通用';

  @override
  String get settingsAppLanguageTitle => '应用语言';

  @override
  String settingsAppLanguageSystemValue({required String language}) {
    return '系统默认（$language）';
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
  String get settingsSectionAppearance => '外观';

  @override
  String get settingsSectionReadingDefaults => '阅读默认';

  @override
  String get settingsSectionDictionary => '词典';

  @override
  String get settingsSectionVocabularyExport => '词汇与导出';

  @override
  String get settingsSectionPro => '专业版';

  @override
  String get settingsSectionMangaAutoCrop => '漫画自动裁边';

  @override
  String get settingsSectionMangaOcr => '漫画OCR';

  @override
  String get settingsSectionDownloads => '下载';

  @override
  String get settingsSectionBackupRestore => '备份与恢复';

  @override
  String get settingsSectionAboutFeedback => '关于与反馈';

  @override
  String get settingsStartupScreenTitle => '启动界面';

  @override
  String get settingsStartupScreenLibrary => '书库';

  @override
  String get settingsStartupScreenDictionary => '词典';

  @override
  String get settingsStartupScreenLastRead => '上次阅读';

  @override
  String get settingsThemeTitle => '主题';

  @override
  String get settingsThemeLight => '浅色';

  @override
  String get settingsThemeDark => '深色';

  @override
  String get settingsThemeSystemDefault => '系统默认';

  @override
  String get settingsColorThemeTitle => '配色主题';

  @override
  String get settingsColorThemeMekuruRed => 'Mekuru红';

  @override
  String get settingsColorThemeIndigo => '靛蓝';

  @override
  String get settingsColorThemeTeal => '青色';

  @override
  String get settingsColorThemeDeepPurple => '深紫色';

  @override
  String get settingsColorThemeBlue => '蓝色';

  @override
  String get settingsColorThemeGreen => '绿色';

  @override
  String get settingsColorThemeOrange => '橙色';

  @override
  String get settingsColorThemePink => '粉色';

  @override
  String get settingsColorThemeBlueGrey => '蓝灰色';

  @override
  String get settingsFontSizeTitle => '字体大小';

  @override
  String settingsPointsValue({required int points}) {
    return '$points 磅';
  }

  @override
  String get settingsColorModeTitle => '色彩模式';

  @override
  String get settingsColorModeNormal => '正常';

  @override
  String get settingsColorModeSepia => '仿古色';

  @override
  String get settingsColorModeDark => '深色';

  @override
  String get settingsSepiaIntensityTitle => '仿古色强度';

  @override
  String get settingsKeepScreenOnTitle => '保持屏幕常亮';

  @override
  String get settingsKeepScreenOnSubtitle => '阅读时防止屏幕休眠';

  @override
  String settingsHorizontalMarginValue({required int pixels}) {
    return '左右边距：${pixels}px';
  }

  @override
  String settingsVerticalMarginValue({required int pixels}) {
    return '上下边距：${pixels}px';
  }

  @override
  String get settingsSwipeSensitivityTitle => '滑动灵敏度';

  @override
  String settingsPercentValue({required int percent}) {
    return '$percent%';
  }

  @override
  String get settingsSwipeSensitivityHint => '数值越低滑动所需手指移动越小';

  @override
  String get settingsManageDictionariesSubtitle => '导入、排序、启用/禁用';

  @override
  String get settingsLookupFontSizeTitle => '查词字体大小';

  @override
  String get settingsFilterRomanLetterEntriesTitle => '过滤西文词条';

  @override
  String get settingsFilterRomanLetterEntriesSubtitle => '隐藏使用英文字符作为词头的词条';

  @override
  String get settingsAutoFocusSearchTitle => '自动聚焦搜索框';

  @override
  String get settingsAutoFocusSearchSubtitle => '切换到词典页时自动打开键盘';

  @override
  String get settingsAnkiDroidIntegrationTitle => 'AnkiDroid 集成';

  @override
  String get settingsAnkiDroidIntegrationSubtitle => '配置笔记类型、牌组和字段映射';

  @override
  String get settingsProUnavailableSubtitle => '专业版服务暂时不可用。';

  @override
  String get settingsProSubtitle => '解锁自动裁边、书籍高亮和自定义 OCR';

  @override
  String get settingsWhiteThresholdTitle => '白色阈值';

  @override
  String settingsWhiteThresholdSubtitle({required int threshold}) {
    return '$threshold（值越低，忽略更多近白杂质）';
  }

  @override
  String get settingsCustomOcrServerTitle => '自定义 OCR 服务器';

  @override
  String get settingsCustomOcrServerUnavailableSubtitle => 'OCR 服务暂时不可用。';

  @override
  String get settingsCustomOcrServerNotConfigured => '未配置。请添加您的服务器 URL 和共享密钥。';

  @override
  String settingsCustomOcrServerConfigured({required String url}) {
    return '$url\n请使用您服务器配置的相同共享密钥。';
  }

  @override
  String get settingsCustomOcrServerUrlLabel => '服务器 URL';

  @override
  String get settingsCustomOcrServerUrlHint => 'http://192.168.1.100:8000';

  @override
  String get settingsCustomOcrServerLearnHow => '了解如何运行自有服务器';

  @override
  String get settingsCustomOcrServerKeyLabel => '自定义共享密钥';

  @override
  String get settingsCustomOcrServerKeyHint => '需要 AUTH_API_KEY';

  @override
  String get settingsCustomOcrServerDescription =>
      '请填写与您的 OCR 服务器相同的 AUTH_API_KEY。Mekuru 会以 Authorization: Bearer <key> 的形式发送远程漫画 OCR 请求。';

  @override
  String get settingsCustomOcrServerUrlRequired => '请输入服务器 URL。';

  @override
  String get settingsCustomOcrServerUrlInvalid =>
      '请输入完整的 http:// 或 https:// 服务器 URL。';

  @override
  String get settingsCustomOcrServerKeyRequired => '自定义服务器需要共享密钥。';

  @override
  String get settingsDownloadsSubtitle => '词典、汉字数据等';

  @override
  String get settingsBackupRestoreTitle => '备份与恢复';

  @override
  String get settingsBackupRestoreSubtitle => '备份和恢复您的数据';

  @override
  String get settingsSendFeedbackSubtitle => '报告错误或建议新功能';

  @override
  String get settingsFeedbackThanks => '感谢您的反馈！';

  @override
  String get settingsFeedbackFailed => '反馈发送失败，请重试。';

  @override
  String get settingsDocumentationTitle => '文档';

  @override
  String get settingsDocumentationSubtitle => '指南和操作文章';

  @override
  String get settingsAboutMekuruTitle => '关于Mekuru';

  @override
  String get settingsAboutMekuruSubtitle => '版本、许可证等信息';

  @override
  String get feedbackTitle => '发送反馈';

  @override
  String get feedbackNameLabel => '姓名';

  @override
  String get feedbackNameHint => '你的名字';

  @override
  String get feedbackEmailLabel => '邮箱';

  @override
  String get feedbackEmailHint => 'your@email.com';

  @override
  String get feedbackMessageLabel => '留言';

  @override
  String get feedbackRequired => '（必填）';

  @override
  String get feedbackMessageHint => '请描述你的问题或功能建议...';

  @override
  String get feedbackMessageRequiredError => '请输入留言内容';

  @override
  String get backupTitle => '备份与恢复';

  @override
  String get backupSectionBackup => '备份';

  @override
  String get backupCreateNowTitle => '立即创建备份';

  @override
  String get backupCreateNowSubtitle =>
      '保存您的设置和用户数据，例如书签、高亮和词汇表。实际的 EPUB 和漫画文件不会包含在备份中。';

  @override
  String get backupExportTitle => '导出备份';

  @override
  String get backupExportSubtitle =>
      '将最新的设置和用户数据备份保存为文件。实际的 EPUB 和漫画文件不会包含在备份中。';

  @override
  String get backupSaveFileDialogTitle => '保存备份';

  @override
  String get backupScopeNoteTitle => '会备份哪些内容？';

  @override
  String get backupScopeNoteBody =>
      '备份会保存您在 Mekuru 中的设置和自己创建的数据，例如书签、高亮和词汇表。实际的 EPUB 或漫画文件不会包含在备份中。';

  @override
  String get backupScopeNoteRestore =>
      '恢复后，请重新导入相同的 EPUB 或漫画内容。如果内容完全一致，您的阅读记录会恢复。';

  @override
  String get backupSectionAutoBackup => '自动备份';

  @override
  String get backupAutoBackupIntervalTitle => '自动备份间隔';

  @override
  String get backupIntervalOff => '关闭';

  @override
  String get backupIntervalDaily => '每日';

  @override
  String get backupIntervalWeekly => '每周';

  @override
  String get backupSectionRestore => '恢复';

  @override
  String get backupImportFileTitle => '导入备份文件';

  @override
  String get backupImportFileSubtitle =>
      '从 .mekuru 文件恢复设置和用户数据。重新导入相同的 EPUB 或漫画内容即可恢复记录。';

  @override
  String get backupSectionHistory => '备份历史';

  @override
  String get backupNoBackupsYet => '暂无备份';

  @override
  String backupErrorLoadingHistory({required String details}) {
    return '加载备份时出错：$details';
  }

  @override
  String get backupCreatedSuccess => '备份创建成功';

  @override
  String backupFailed({required String details}) {
    return '备份失败：$details';
  }

  @override
  String get backupNoBackupsToExport => '没有可导出的备份，请先创建。';

  @override
  String get backupExportedSuccess => '备份导出成功';

  @override
  String backupExportFailed({required String details}) {
    return '导出失败：$details';
  }

  @override
  String get backupInvalidFile => '请选择一个 .mekuru 备份文件。';

  @override
  String backupCouldNotOpenFile({required String details}) {
    return '无法打开文件：$details';
  }

  @override
  String backupRestoreFailed({required String details}) {
    return '恢复失败：$details';
  }

  @override
  String backupBooksUpdatedFromBackup({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '# 本书已通过备份更新',
      one: '# 本书已通过备份更新',
    );
    return '$_temp0';
  }

  @override
  String backupApplyBookDataFailed({required String details}) {
    return '应用书籍数据失败：$details';
  }

  @override
  String get backupConflictDialogTitle => '书籍冲突';

  @override
  String get backupConflictDialogBody => '以下书籍已存在阅读数据。请选择要用备份数据覆盖的书籍：';

  @override
  String backupConflictEntrySubtitle({
    required String bookType,
    required int progress,
  }) {
    return '$bookType - 备份进度 $progress%';
  }

  @override
  String get backupConflictSkipAll => '全部跳过';

  @override
  String backupConflictOverwriteSelected({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '覆盖 # 本',
      one: '覆盖 # 本',
    );
    return '$_temp0';
  }

  @override
  String get backupBookTypeEpub => 'EPUB';

  @override
  String get backupBookTypeManga => '漫画';

  @override
  String get backupRestoreSummarySettingsRestored => '设置已恢复';

  @override
  String get backupRestoreSummarySettingsPartial => '部分设置无法恢复';

  @override
  String backupRestoreSummaryWords({required int added, required int skipped}) {
    return '已添加 $added 个单词，跳过 $skipped 个';
  }

  @override
  String backupRestoreSummaryBooksRestored({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '# 本书已恢复',
      one: '# 本书已恢复',
    );
    return '$_temp0';
  }

  @override
  String backupRestoreSummaryBooksPending({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '# 本书正在等待重新导入相同的 EPUB 或漫画内容',
      one: '# 本书正在等待重新导入相同的 EPUB 或漫画内容',
    );
    return '$_temp0';
  }

  @override
  String get backupRestoreComplete => '恢复完成';

  @override
  String get backupRestoreDialogTitle => '恢复备份？';

  @override
  String backupRestoreDialogBody({required String fileName}) {
    return '这将从 $fileName 恢复设置和用户数据，例如书签、高亮和词汇表。它不会恢复实际的 EPUB 或漫画文件。恢复后，请重新导入相同的 EPUB 或漫画内容以找回记录。您当前的设置将被覆盖。';
  }

  @override
  String get backupDeleteDialogTitle => '删除备份？';

  @override
  String backupDeleteDialogBody({required String fileName}) {
    return '删除 $fileName？此操作无法撤销。';
  }

  @override
  String get backupHistoryTypeAuto => '自动备份';

  @override
  String get backupHistoryTypeManual => '手动备份';

  @override
  String get readerDismiss => '关闭';

  @override
  String readerFailedToLoadContent({required String details}) {
    return '无法加载 EPUB 内容。\n$details';
  }

  @override
  String readerFailedToLoad({required String details}) {
    return '无法加载 EPUB 文件。\n$details';
  }

  @override
  String get readerVerticalTextNonNativeWarning => '此书最初未为竖排文本设计，可能会出现显示问题。';

  @override
  String get readerHorizontalTextNonNativeWarning =>
      '此书最初为竖排文本设计，横排模式下可能会出现显示问题。';

  @override
  String get readerBookmarkRemoved => '书签已移除';

  @override
  String get readerPageBookmarked => '已添加书签';

  @override
  String get readerTableOfContents => '目录';

  @override
  String get readerRemoveBookmarkTooltip => '移除书签';

  @override
  String get readerBookmarkPageTooltip => '添加书签';

  @override
  String get readerViewBookmarksTooltip => '查看书签';

  @override
  String get readerHighlightsTooltip => '高亮';

  @override
  String get readerNextPageTooltip => '下一页';

  @override
  String get readerPreviousPageTooltip => '上一页';

  @override
  String get readerUnknownError => '未知阅读器错误。';

  @override
  String get readerQuickSettings => '快速设置';

  @override
  String get readerVerticalTextTitle => '竖排文本';

  @override
  String get readerThisBook => '本书';

  @override
  String get readerVerticalTextUnavailable => '本书的语言暂不支持竖排显示';

  @override
  String get readerReadingDirectionTitle => '阅读方向';

  @override
  String get readerReadingDirectionRtl => '从右到左';

  @override
  String get readerReadingDirectionLtr => '从左到右';

  @override
  String get readerDisableLinksTitle => '禁用链接';

  @override
  String get readerDisableLinksSubtitle => '点击已链接的文本以查词，而不是跳转';

  @override
  String get readerHighlightSelectionTooltip => '高亮所选内容';

  @override
  String get commonCopy => '复制';

  @override
  String get commonShare => '分享';

  @override
  String get commonContinue => '继续';

  @override
  String get commonNotSelected => '未选择';

  @override
  String get commonUnknown => '未知';

  @override
  String get commonRename => '重命名';

  @override
  String get commonTitleLabel => '标题';

  @override
  String libraryCouldNotReadFolder({required String details}) {
    return '无法读取文件夹：\n$details';
  }

  @override
  String get libraryBookmarksTitle => '书签';

  @override
  String get libraryChangeCoverAction => '更换封面';

  @override
  String get libraryRenameBookTitle => '重命名图书';

  @override
  String get libraryDeleteBookTitle => '删除图书';

  @override
  String libraryDeleteBookBody({required String title}) {
    return '从您的书库中删除“$title”？';
  }

  @override
  String libraryChangeCoverFailed({required String details}) {
    return '更换封面失败：$details';
  }

  @override
  String get dictionaryManagerTitle => '词典管理';

  @override
  String get dictionaryManagerImportTooltip => '导入词典';

  @override
  String get dictionaryManagerEmptySubtitle =>
      '点击 + 导入一个 Yomitan 词典（.zip）\n或词典集合（.json）';

  @override
  String get dictionaryManagerBrowseDownloads => '浏览下载';

  @override
  String get dictionaryManagerBrowseDownloadsCaption => '下载词典和其他资源';

  @override
  String dictionaryManagerImportedOn({required String date}) {
    return '已导入 $date';
  }

  @override
  String get dictionaryManagerSupportedFormatsTitle => '支持的格式';

  @override
  String get dictionaryManagerSupportedFormatsYomitan =>
      'Yomitan 词典（.zip）\n支持可导入到 Yomitan 的所有词典。这些是包含词库 JSON 文件的 .zip 文件。';

  @override
  String get dictionaryManagerSupportedFormatsCollection =>
      'Yomitan 集合（.json）\n包含多个词典的 Dexie 数据库导出文件。你可以在 Yomitan 的设置中通过“备份”导出此文件。';

  @override
  String get dictionaryManagerOrderTitle => '词典顺序';

  @override
  String get dictionaryManagerOrderBody =>
      '使用左侧的拖动柄拖动词典进行排序。这里的顺序决定你阅读时点击单词时词典释义的显示顺序。';

  @override
  String get dictionaryManagerEnablingTitle => '启用与禁用';

  @override
  String get dictionaryManagerEnablingBody => '使用开关按钮启用或禁用词典。禁用的词典不会在查词时被检索。';

  @override
  String get dictionaryManagerFindingTitle => '查找词典';

  @override
  String get dictionaryManagerFindingPrefix => '在此处浏览兼容词典 ';

  @override
  String get dictionaryManagerDeleteTitle => '删除词典';

  @override
  String dictionaryManagerDeleteBody({required String name}) {
    return '删除“$name”及其所有词条？\n此操作不可撤销。';
  }

  @override
  String get ankidroidDataSourceExpression => '表达式';

  @override
  String get ankidroidDataSourceReading => '读音';

  @override
  String get ankidroidDataSourceFurigana => '振假名（Anki 格式）';

  @override
  String get ankidroidDataSourceGlossary => '释义/含义';

  @override
  String get ankidroidDataSourceSentenceContext => '例句上下文';

  @override
  String get ankidroidDataSourceFrequency => '频率排名';

  @override
  String get ankidroidDataSourceDictionaryName => '词典名称';

  @override
  String get ankidroidDataSourcePitchAccent => '音调';

  @override
  String get ankidroidDataSourceEmpty => '（空）';

  @override
  String get ankidroidPermissionNotGrantedLong =>
      '未授予 AnkiDroid 权限。请确保已安装 AnkiDroid 后重试。';

  @override
  String get ankidroidCouldNotConnectLong =>
      '无法连接到 AnkiDroid。请确保已安装并正在运行 AnkiDroid。';

  @override
  String get ankidroidPermissionNotGrantedShort => '未授予 AnkiDroid 权限。';

  @override
  String get ankidroidCouldNotConnectShort => '无法连接到 AnkiDroid。';

  @override
  String get ankidroidFailedToAddNote =>
      '添加笔记失败。请确认 AnkiDroid 正在运行，所选笔记类型和牌组仍然存在。';

  @override
  String get ankidroidSettingsNoteTypeSection => '笔记类型';

  @override
  String get ankidroidSettingsNoteTypeTitle => 'Anki 笔记类型';

  @override
  String get ankidroidSettingsDefaultDeckSection => '默认牌组';

  @override
  String get ankidroidSettingsTargetDeckTitle => '目标牌组';

  @override
  String get ankidroidSettingsFieldMappingSection => '字段映射';

  @override
  String get ankidroidSettingsFieldMappingHelp => '将每个 Anki 字段映射到应用的数据来源。';

  @override
  String get ankidroidSettingsDefaultTagsSection => '默认标签';

  @override
  String get ankidroidSettingsDefaultTagsHelp => '每条导出笔记都会添加以逗号分隔的标签。';

  @override
  String get ankidroidTagsHint => 'mekuru, japanese';

  @override
  String get ankidroidSettingsSelectNoteType => '选择笔记类型';

  @override
  String get ankidroidSettingsSelectDeck => '选择牌组';

  @override
  String ankidroidSettingsMapFieldTo({required String ankiFieldName}) {
    return '将“$ankiFieldName”映射为：';
  }

  @override
  String get ankidroidCardSettingsTooltip => 'AnkiDroid 设置';

  @override
  String get ankidroidCardDeckTitle => '牌组';

  @override
  String get ankidroidCardTagsTitle => '标签';

  @override
  String get ankidroidCardAddToAnki => '添加到 Anki';

  @override
  String get mangaReaderSettingsTitle => '阅读器设置';

  @override
  String get mangaViewModeSingle => '单页';

  @override
  String get mangaViewModeSpread => '双页';

  @override
  String get mangaViewModeScroll => '滚动';

  @override
  String get mangaAutoCropSubtitle => '移除空白边距';

  @override
  String get mangaAutoCropRerunTitle => '重新执行自动裁边';

  @override
  String get mangaAutoCropRerunSubtitle => '重新扫描本书的每一页图片';

  @override
  String get mangaTransparentLookupTitle => '透明查词';

  @override
  String get mangaTransparentLookupSubtitle => '半透明字典面板';

  @override
  String get mangaDebugWordOverlayTitle => '调试词语覆盖层';

  @override
  String get mangaDebugWordOverlaySubtitle => '显示单词边框';

  @override
  String get mangaAutoCropComputeTitle => '计算自动裁边？';

  @override
  String get mangaAutoCropComputeBody => '自动裁边需要先扫描本书的所有页面图片，才能启用。可能需要几分钟。';

  @override
  String get mangaAutoCropRerunDialogTitle => '重新执行自动裁边？';

  @override
  String get mangaAutoCropRerunDialogBody =>
      '自动裁边将重新扫描本书的每一页图片，并替换已保存的裁切范围。可能需要几分钟。';

  @override
  String get mangaAutoCropComputingProgress => '正在计算自动裁边范围，可能需要几分钟。';

  @override
  String get mangaAutoCropRecomputingProgress => '正在重新计算自动裁边范围，可能需要几分钟。';

  @override
  String get mangaAutoCropBoundsRefreshed => '自动裁边范围已刷新。';

  @override
  String mangaAutoCropSetupFailed({required String details}) {
    return '自动裁边设置失败：$details';
  }

  @override
  String get ocrNoPagesCacheFound => '未找到本书的页面缓存';

  @override
  String get ocrAlreadyCompleteResetHint => 'OCR 已完成。使用“移除 OCR”可重置。';

  @override
  String get ocrMangaImageDirectoryNotFound => '未找到漫画图片目录';

  @override
  String get ocrBuildWordOverlaysTitle => '生成单词覆盖层';

  @override
  String get ocrBuildWordOverlaysBody => 'OCR 文本已存在。这会重新生成单词点击目标，使查词覆盖层正确显示。';

  @override
  String get ocrRunActionTitle => '运行 OCR';

  @override
  String ocrProcessPagesBody({required int count}) {
    return '将处理 $count 页。OCR 会在后台运行，即使关闭应用也会继续。';
  }

  @override
  String get ocrProcessAction => '处理';

  @override
  String get ocrStartAction => '开始';

  @override
  String ocrPrepareFailed({required String details}) {
    return '无法准备 OCR：$details';
  }

  @override
  String ocrStartFailed({required String details}) {
    return '启动 OCR 失败：$details';
  }

  @override
  String get ocrWordOverlayStartedBackground => '词语遮罩处理已在后台开始';

  @override
  String get ocrStartedBackground => 'OCR 已在后台启动';

  @override
  String get ocrCancelActionTitle => '取消 OCR';

  @override
  String get ocrCancelSavedProgress => 'OCR 已取消。进度已保存。';

  @override
  String get ocrReplaceActionTitle => '替换 OCR';

  @override
  String get ocrReplaceMokuroBody =>
      '这将覆盖从 Mokuro/HTML 文件导入的 OCR 数据，并使用您的自定义服务器对所有页面重新执行 OCR。\n\n要恢复原始 OCR，请重新导入书籍。';

  @override
  String get ocrReplaceStartedBackground => 'OCR 替换已在后台开始';

  @override
  String get ocrRemoveActionTitle => '移除 OCR';

  @override
  String get ocrRemoveBody => '要从本漫画中移除 OCR 文字和词语遮罩吗？您以后可以再次运行 OCR。';

  @override
  String get ocrRemoveSubtitle => '从所有页面移除 OCR 文字';

  @override
  String get ocrRemovedFromBook => '已从本书移除 OCR';

  @override
  String ocrRemoveFailed({required String details}) {
    return '移除 OCR 失败：$details';
  }

  @override
  String get ocrUnlockProSubtitle => '解锁 Pro 以使用自定义 OCR 服务器';

  @override
  String get ocrStopAndSaveProgressSubtitle => '停止处理并保存进度';

  @override
  String get ocrReplaceMokuroSubtitle => '用自定义 OCR 服务器替换 Mokuro 的 OCR';

  @override
  String get ocrBuildWordTargetsSubtitle => '根据已保存的 OCR 构建词语点击区域';

  @override
  String ocrResumeSubtitle({required int completed, required int total}) {
    return '继续 OCR（已完成 $completed/$total）';
  }

  @override
  String get ocrRecognizeAllPagesSubtitle => '识别所有页面中的文本';

  @override
  String get readerEditNoteTitle => '编辑笔记';

  @override
  String get readerAddNoteHint => '添加笔记...';

  @override
  String get readerCopiedToClipboard => '已复制到剪贴板';

  @override
  String get aboutPrivacyPolicyTitle => '隐私政策';

  @override
  String get aboutPrivacyPolicySubtitle => '查看 Mekuru 如何处理本地与 OCR 数据';

  @override
  String get aboutOpenSourceLicensesTitle => '开源许可证';

  @override
  String get aboutOpenSourceLicensesSubtitle => '查看依赖项的许可证';

  @override
  String get aboutTagline => '“翻页”';

  @override
  String get aboutEpubJsLicenseTitle => 'epub.js 许可证';

  @override
  String get downloadsKanjidicTitle => 'KANJIDIC';

  @override
  String get readerBookmarksTitle => '书签';

  @override
  String get readerNoBookmarksYet => '还没有书签。\n阅读时点击书签图标即可添加。';

  @override
  String readerBookmarkProgressDate({
    required String progress,
    required String date,
  }) {
    return '$progress - $date';
  }

  @override
  String aboutVersion({required String version}) {
    return '版本 $version';
  }

  @override
  String get aboutDescription => '一款以日语为主的EPUB阅读器，支持竖排、离线词典和词汇管理。';

  @override
  String get aboutAttributionTitle => '归属';

  @override
  String get aboutKanjiVgTitle => 'KanjiVG';

  @override
  String get aboutKanjiVgDescription => '汉字笔顺数据由Ulrich Apel创建的KanjiVG项目提供。';

  @override
  String get aboutLicensedUnderPrefix => '授权协议：';

  @override
  String get aboutLicenseSuffix => ' 协议。';

  @override
  String get aboutProjectLabel => '项目：';

  @override
  String get aboutSourceLabel => '来源：';

  @override
  String get aboutJpdbTitle => 'JPDB 词频词典';

  @override
  String get aboutJpdbDescription =>
      '词频数据由JPDB词频词典提供，通过Kuuuube的yomitan-dictionaries分发。';

  @override
  String get aboutDataSourceLabel => '数据来源：';

  @override
  String get aboutDictionaryLabel => '词典：';

  @override
  String get aboutJmdictKanjidicTitle => 'JMdict & KANJIDIC';

  @override
  String get aboutJmdictKanjidicDescriptionPrefix =>
      '日语多语种词典数据由JMdict/EDICT项目提供，汉字词典数据由KANJIDIC项目提供，二者均由Jim Breen和';

  @override
  String get aboutJmdictLabel => 'JMdict：';

  @override
  String get aboutKanjidicLabel => 'KANJIDIC：';

  @override
  String get aboutEpubJsTitle => 'epub.js';

  @override
  String get aboutEpubJsDescription =>
      'EPUB渲染由epub.js驱动，这是一款开源的JavaScript EPUB阅读库。';

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

/// The translations for Chinese, using the Han script (`zh_Hans`).
class AppLocalizationsZhHans extends AppLocalizationsZh {
  AppLocalizationsZhHans() : super('zh_Hans');

  @override
  String get appTitle => 'Mekuru';

  @override
  String get navLibrary => '书库';

  @override
  String get navDictionary => '词典';

  @override
  String get navVocabulary => '生词本';

  @override
  String get navSettings => '设置';

  @override
  String get commonHelp => '帮助';

  @override
  String get commonImport => '导入';

  @override
  String get commonOpenNow => '立即打开';

  @override
  String get commonCancel => '取消';

  @override
  String get commonClose => '关闭';

  @override
  String get commonSave => '保存';

  @override
  String get commonDelete => '删除';

  @override
  String get commonDownload => '下载';

  @override
  String get commonOpenDictionary => '打开词典';

  @override
  String get commonManageDictionaries => '管理词典';

  @override
  String get commonClearAll => '全部清除';

  @override
  String get commonClearSearch => '清除搜索';

  @override
  String get commonSearch => '搜索';

  @override
  String get commonBack => '返回';

  @override
  String get commonRetry => '重试';

  @override
  String get commonOk => '确定';

  @override
  String get commonDone => '完成';

  @override
  String get commonUndo => '撤销';

  @override
  String get commonUnlock => '解锁';

  @override
  String get commonOpenSettings => '打开设置';

  @override
  String get commonGotIt => '知道了';

  @override
  String commonErrorWithDetails({required String details}) {
    return '错误：$details';
  }

  @override
  String librarySortTooltip({required String label}) {
    return '排序：$label';
  }

  @override
  String get libraryEmptyTitle => '你的书库已准备好迎接第一本书';

  @override
  String get libraryEmptySubtitle => '导入一些可阅读的内容，安装词典，几分钟内就可以开始保存单词。';

  @override
  String get libraryImportEpub => '导入EPUB';

  @override
  String get libraryImportManga => '导入漫画';

  @override
  String get libraryGetDictionaries => '获取词典';

  @override
  String get libraryRestoreBackup => '恢复备份';

  @override
  String get librarySupportedMediaTitle => '支持的媒体格式';

  @override
  String get libraryEpubBooksTitle => 'EPUB电子书';

  @override
  String get libraryEpubBooksDescription =>
      '支持标准.epub文件。点击“+”按钮并选择“导入EPUB”即可从设备添加。';

  @override
  String get libraryMokuroTitle => 'Mokuro漫画';

  @override
  String get libraryMokuroDescription =>
      '通过选择文件夹，然后选择.mokuro或.html文件来导入漫画。页面图片将从同名的相邻文件夹加载。';

  @override
  String get libraryMokuroFormatDescription =>
      '.mokuro文件由mokuro工具生成，该工具对漫画页面进行OCR以提取日文文本。';

  @override
  String get libraryLearnHowToCreateMokuroFiles => '了解如何创建.mokuro文件';

  @override
  String get librarySortBy => '排序方式';

  @override
  String get librarySortDateImported => '导入日期';

  @override
  String get librarySortRecentlyRead => '最近阅读';

  @override
  String get librarySortAlphabetical => '按字母顺序';

  @override
  String get libraryImportTitle => '导入';

  @override
  String get libraryImportEpubSubtitle => '导入EPUB文件';

  @override
  String get libraryImportMangaSubtitle => '选择CBZ压缩包或Mokuro文件夹';

  @override
  String get libraryImportMangaTitle => '导入漫画';

  @override
  String get libraryImportMangaDescription => '请选择要导入CBZ压缩包还是Mokuro导出的文件夹。';

  @override
  String get libraryImportMokuroFolder => 'Mokuro 文件夹';

  @override
  String get libraryImportMokuroFolderSubtitle =>
      '请选择包含 .mokuro 或 .html 文件及图片文件夹的文件夹。';

  @override
  String get libraryWhatIsMokuro => '什么是 Mokuro？';

  @override
  String get libraryImportCbzArchive => 'CBZ 压缩包';

  @override
  String get libraryImportCbzArchiveSubtitle => '导入 .cbz 漫画压缩包';

  @override
  String get libraryImportedWithoutOcrMessage =>
      '已导入，但未包含 OCR。要获得文本覆盖层，请导入外部 OCR 输出（如 .mokuro）。';

  @override
  String get libraryCouldNotOpenMokuroProjectPage => '无法打开 Mokuro 项目页面。';

  @override
  String get libraryNoMangaManifestFound => '在选定的文件夹中未找到 .mokuro 或 .html 文件。';

  @override
  String get librarySelectMangaFolder => '选择漫画文件夹';

  @override
  String get librarySelectedFolder => '已选择文件夹';

  @override
  String libraryMangaFilesFound({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '找到#个漫画文件',
      one: '找到#个漫画文件',
    );
    return '$_temp0';
  }

  @override
  String get dictionarySearchHint => '可用汉字、假名或罗马音搜索...';

  @override
  String get dictionaryNoDictionariesTitle => '尚未导入词典';

  @override
  String get dictionaryNoDictionariesSubtitle =>
      '安装入门词包或导入你自己的 Yomitan 词典后即可开始搜索。';

  @override
  String get dictionaryRecommendedStarterPack => '推荐入门词包';

  @override
  String get dictionaryNoEnabledTitle => '你的词典已关闭';

  @override
  String get dictionaryNoEnabledSubtitle => '至少启用一个词典以完成查词，或安装推荐入门词包。';

  @override
  String get dictionaryEnableDictionaries => '启用词典';

  @override
  String get dictionaryStarterPack => '入门词包';

  @override
  String get dictionaryNoResultsFound => '未找到结果。';

  @override
  String get dictionarySearchForAWord => '查找单词';

  @override
  String get dictionarySearchForAWordSubtitle => '可输入汉字、平假名、片假名或罗马音';

  @override
  String get dictionaryRecent => '最近';

  @override
  String dictionarySavedWord({required String expression}) {
    return '已保存“$expression”';
  }

  @override
  String get dictionaryWordAlreadyExistsInVocab => '单词已存在于词汇列表';

  @override
  String dictionaryCopiedWord({required String expression}) {
    return '已复制“$expression”';
  }

  @override
  String get dictionaryWordAlreadyExistsInAnki => '单词已存在于默认牌组';

  @override
  String dictionaryAddedToAnki({required String expression}) {
    return '已将“$expression”添加到Anki';
  }

  @override
  String get dictionaryCopyTooltip => '复制';

  @override
  String get dictionaryAlreadyInAnkiTooltip => '已在默认Anki牌组。长按可强制添加';

  @override
  String get dictionaryCheckingAnkiTooltip => '正在检查默认Anki牌组';

  @override
  String get dictionarySendToAnkiTooltip => '发送到AnkiDroid';

  @override
  String get dictionaryAlreadyInVocabTooltip => '已在单词本';

  @override
  String get dictionarySaveToVocabularyTooltip => '保存到单词本';

  @override
  String get dictionaryVeryCommon => '非常常见';

  @override
  String get dictionaryOnyomiLabel => '音读：';

  @override
  String get dictionaryKunyomiLabel => '训读：';

  @override
  String dictionaryKanjiStrokeCount({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '#画',
      one: '#画',
    );
    return '$_temp0';
  }

  @override
  String get dictionaryAnimateStrokeOrderTooltip => '演示笔顺';

  @override
  String get vocabularySearchSavedWordsHint => '搜索已保存单词';

  @override
  String get vocabularyExportCsvTooltip => '导出CSV';

  @override
  String get vocabularyEmptyTitle => '还没有已保存的单词';

  @override
  String get vocabularyEmptySubtitle => '通过词典查询或阅读时保存单词，它们会带有上下文显示在这里。';

  @override
  String vocabularyNoMatches({required String query}) {
    return '未找到与“$query”匹配的内容';
  }

  @override
  String get vocabularyNoMatchesSubtitle => '请尝试表达、读音或释义片段。';

  @override
  String vocabularySelectedCount({required int count}) {
    return '已选$count个';
  }

  @override
  String get vocabularyDeselectAllTooltip => '取消全选';

  @override
  String get vocabularySelectAllTooltip => '全选';

  @override
  String get vocabularyExportSelectedTooltip => '导出已选';

  @override
  String get vocabularyNoDefinition => '暂无释义';

  @override
  String get vocabularyContextLabel => '上下文：';

  @override
  String vocabularyAddedOn({required String date}) {
    return '添加时间：$date';
  }

  @override
  String vocabularyDeletedWord({required String expression}) {
    return '已删除“$expression”';
  }

  @override
  String ocrPagesProgress({required int completed, required int total}) {
    return '$completed/$total 页';
  }

  @override
  String ocrEtaSecondsRemaining({required int seconds}) {
    return '约剩余 $seconds 秒';
  }

  @override
  String ocrEtaMinutesRemaining({required int minutes}) {
    return '约剩余 $minutes 分钟';
  }

  @override
  String ocrEtaHoursMinutesRemaining({
    required int hours,
    required int minutes,
  }) {
    return '约剩余 $hours 小时 $minutes 分钟';
  }

  @override
  String get ocrPaused => 'OCR 已暂停';

  @override
  String get ocrComplete => 'OCR 完成';

  @override
  String get ocrFailed => 'OCR 失败';

  @override
  String get ocrTapForDetails => '点击查看详情';

  @override
  String get ocrCustomServerRequiredTitle => '需要自定义 OCR 服务器';

  @override
  String get ocrCustomServerRequiredBody =>
      '远程漫画 OCR 现在需要使用您自己的服务器。请在设置中添加自定义 OCR 服务器地址和匹配的共享密钥。';

  @override
  String get ocrCustomServerKeyRequiredTitle => '需要自定义服务器设置';

  @override
  String get ocrCustomServerKeyRequiredBody =>
      '自定义 OCR 服务器需要共享密钥。请在自定义 OCR 服务器设置中输入与您的服务器一致的 AUTH_API_KEY。';

  @override
  String get proTitle => '专业版';

  @override
  String get proPurchaseConfirmed => '您的购买已确认！';

  @override
  String get proUnlockOnceTitle => '一次性解锁专业版';

  @override
  String get proStatusUnlocked => '已解锁';

  @override
  String get proStatusLocked => '未解锁';

  @override
  String get proUnlockDescription => '一次性购买，解锁阅读增强功能。';

  @override
  String get proRestorePurchase => '恢复购买';

  @override
  String get proFeatureAutoCropTitle => '自动裁边';

  @override
  String get proFeatureAutoCropDescription => '每本书设置一次后，自动裁剪漫画页面的空白边缘。';

  @override
  String get proFeatureHighlightsTitle => '书籍高亮';

  @override
  String get proFeatureHighlightsDescription => '在阅读 EPUB 书籍时保存并回顾高亮内容。';

  @override
  String get proFeatureCustomOcrTitle => '自定义 OCR 服务器';

  @override
  String get proFeatureCustomOcrDescription => '使用你自己的服务器和共享密钥进行远程漫画 OCR。';

  @override
  String get proServerRepo => '服务器仓库';

  @override
  String get proAlreadyUnlocked => '已解锁';

  @override
  String get proUnlock => '解锁 Pro 版';

  @override
  String proUnlockWithPrice({required String price}) {
    return '解锁 Pro 版 $price';
  }

  @override
  String get downloadsTitle => '下载';

  @override
  String get downloadsRecommendedStarterPackTitle => '推荐入门包';

  @override
  String get downloadsRecommendedStarterPackSubtitle =>
      '一起安装 JMdict 英文词典和词频数据，实现最快速设置。';

  @override
  String get downloadsStarterPackJmdict => 'JMdict 英文版';

  @override
  String get downloadsStarterPackWordFrequency => '词频';

  @override
  String get downloadsInstallStarterPack => '安装入门包';

  @override
  String get downloadsSectionDictionaries => '词典';

  @override
  String get downloadsSectionAssets => '资源';

  @override
  String get downloadsFetchingLatestRelease => '正在获取最新版本…';

  @override
  String downloadsDownloadingPercent({required int percent}) {
    return '正在下载…$percent%';
  }

  @override
  String get downloadsImporting => '正在导入…';

  @override
  String get downloadsExtractingFiles => '正在解压文件…';

  @override
  String get downloadsJpdbAttribution => '词频数据来自 JPDB（jpdb.io），由 Kuuuube 分发。';

  @override
  String get downloadsKanjiStrokeOrderTitle => '汉字笔顺';

  @override
  String downloadsKanjiStrokeOrderDownloaded({required int count}) {
    return '已下载 $count 个笔顺文件';
  }

  @override
  String get downloadsKanjiStrokeOrderDescription => '从 KanjiVG 下载汉字笔顺数据';

  @override
  String get downloadsDeleteKanjiDataTooltip => '删除汉字数据';

  @override
  String get downloadsDeleteKanjiDataTitle => '删除汉字数据';

  @override
  String get downloadsDeleteKanjiDataBody => '删除所有已下载的汉字笔顺文件？您可以稍后重新下载。';

  @override
  String get downloadsWordFrequencyDownloaded => '词频数据已下载';

  @override
  String get downloadsWordFrequencyDescription => '下载词频数据，用于搜索排名';

  @override
  String get downloadsDeleteFrequencyDataTooltip => '删除词频数据';

  @override
  String get downloadsDeleteFrequencyDataTitle => '删除词频数据';

  @override
  String get downloadsDeleteFrequencyDataBody =>
      '删除词频数据？搜索结果将不再按词频排序。您可以稍后重新下载。';

  @override
  String get downloadsJmdictDownloaded => '日英词典已下载';

  @override
  String get downloadsJmdictDescription => '下载日英词典';

  @override
  String get downloadsDeleteJmdictTooltip => '删除 JMdict';

  @override
  String get downloadsChooseJmdictVariant => '选择 JMdict 版本';

  @override
  String get downloadsJmdictStandardSubtitle => '标准词典（约 15 MB）';

  @override
  String get downloadsJmdictExamplesTitle => 'JMdict 英文带例句';

  @override
  String get downloadsJmdictExamplesSubtitle => '包含例句（约 18 MB）';

  @override
  String get downloadsDeleteJmdictTitle => '删除 JMdict';

  @override
  String get downloadsDeleteJmdictBody => '删除 JMdict 及其所有词条？您可以稍后重新下载。';

  @override
  String get downloadsKanjidicDownloaded => '汉字字典已下载';

  @override
  String get downloadsKanjidicDescription => '下载汉字字典';

  @override
  String get downloadsDeleteKanjidicTooltip => '删除 KANJIDIC';

  @override
  String get downloadsDeleteKanjidicTitle => '删除 KANJIDIC';

  @override
  String get downloadsDeleteKanjidicBody => '删除 KANJIDIC 及其所有词条？您可以稍后重新下载。';

  @override
  String get commonClear => '清除';

  @override
  String get commonSubmit => '提交';

  @override
  String get commonLoading => '加载中...';

  @override
  String get commonError => '错误';

  @override
  String get commonRestore => '恢复';

  @override
  String get settingsTitle => '设置';

  @override
  String get settingsSectionGeneral => '通用';

  @override
  String get settingsAppLanguageTitle => '应用语言';

  @override
  String settingsAppLanguageSystemValue({required String language}) {
    return '系统默认（$language）';
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
  String get settingsSectionAppearance => '外观';

  @override
  String get settingsSectionReadingDefaults => '阅读默认';

  @override
  String get settingsSectionDictionary => '词典';

  @override
  String get settingsSectionVocabularyExport => '词汇与导出';

  @override
  String get settingsSectionPro => '专业版';

  @override
  String get settingsSectionMangaAutoCrop => '漫画自动裁边';

  @override
  String get settingsSectionMangaOcr => '漫画OCR';

  @override
  String get settingsSectionDownloads => '下载';

  @override
  String get settingsSectionBackupRestore => '备份与恢复';

  @override
  String get settingsSectionAboutFeedback => '关于与反馈';

  @override
  String get settingsStartupScreenTitle => '启动界面';

  @override
  String get settingsStartupScreenLibrary => '书库';

  @override
  String get settingsStartupScreenDictionary => '词典';

  @override
  String get settingsStartupScreenLastRead => '上次阅读';

  @override
  String get settingsThemeTitle => '主题';

  @override
  String get settingsThemeLight => '浅色';

  @override
  String get settingsThemeDark => '深色';

  @override
  String get settingsThemeSystemDefault => '系统默认';

  @override
  String get settingsColorThemeTitle => '配色主题';

  @override
  String get settingsColorThemeMekuruRed => 'Mekuru红';

  @override
  String get settingsColorThemeIndigo => '靛蓝';

  @override
  String get settingsColorThemeTeal => '青色';

  @override
  String get settingsColorThemeDeepPurple => '深紫色';

  @override
  String get settingsColorThemeBlue => '蓝色';

  @override
  String get settingsColorThemeGreen => '绿色';

  @override
  String get settingsColorThemeOrange => '橙色';

  @override
  String get settingsColorThemePink => '粉色';

  @override
  String get settingsColorThemeBlueGrey => '蓝灰色';

  @override
  String get settingsFontSizeTitle => '字体大小';

  @override
  String settingsPointsValue({required int points}) {
    return '$points 磅';
  }

  @override
  String get settingsColorModeTitle => '色彩模式';

  @override
  String get settingsColorModeNormal => '正常';

  @override
  String get settingsColorModeSepia => '仿古色';

  @override
  String get settingsColorModeDark => '深色';

  @override
  String get settingsSepiaIntensityTitle => '仿古色强度';

  @override
  String get settingsKeepScreenOnTitle => '保持屏幕常亮';

  @override
  String get settingsKeepScreenOnSubtitle => '阅读时防止屏幕休眠';

  @override
  String settingsHorizontalMarginValue({required int pixels}) {
    return '左右边距：${pixels}px';
  }

  @override
  String settingsVerticalMarginValue({required int pixels}) {
    return '上下边距：${pixels}px';
  }

  @override
  String get settingsSwipeSensitivityTitle => '滑动灵敏度';

  @override
  String settingsPercentValue({required int percent}) {
    return '$percent%';
  }

  @override
  String get settingsSwipeSensitivityHint => '数值越低滑动所需手指移动越小';

  @override
  String get settingsManageDictionariesSubtitle => '导入、排序、启用/禁用';

  @override
  String get settingsLookupFontSizeTitle => '查词字体大小';

  @override
  String get settingsFilterRomanLetterEntriesTitle => '过滤西文词条';

  @override
  String get settingsFilterRomanLetterEntriesSubtitle => '隐藏使用英文字符作为词头的词条';

  @override
  String get settingsAutoFocusSearchTitle => '自动聚焦搜索框';

  @override
  String get settingsAutoFocusSearchSubtitle => '切换到词典页时自动打开键盘';

  @override
  String get settingsAnkiDroidIntegrationTitle => 'AnkiDroid 集成';

  @override
  String get settingsAnkiDroidIntegrationSubtitle => '配置笔记类型、牌组和字段映射';

  @override
  String get settingsProUnavailableSubtitle => '专业版服务暂时不可用。';

  @override
  String get settingsProSubtitle => '解锁自动裁边、书籍高亮和自定义 OCR';

  @override
  String get settingsWhiteThresholdTitle => '白色阈值';

  @override
  String settingsWhiteThresholdSubtitle({required int threshold}) {
    return '$threshold（值越低，忽略更多近白杂质）';
  }

  @override
  String get settingsCustomOcrServerTitle => '自定义 OCR 服务器';

  @override
  String get settingsCustomOcrServerUnavailableSubtitle => 'OCR 服务暂时不可用。';

  @override
  String get settingsCustomOcrServerNotConfigured => '未配置。请添加您的服务器 URL 和共享密钥。';

  @override
  String settingsCustomOcrServerConfigured({required String url}) {
    return '$url\n请使用您服务器配置的相同共享密钥。';
  }

  @override
  String get settingsCustomOcrServerUrlLabel => '服务器 URL';

  @override
  String get settingsCustomOcrServerUrlHint => 'http://192.168.1.100:8000';

  @override
  String get settingsCustomOcrServerLearnHow => '了解如何运行自有服务器';

  @override
  String get settingsCustomOcrServerKeyLabel => '自定义共享密钥';

  @override
  String get settingsCustomOcrServerKeyHint => '需要 AUTH_API_KEY';

  @override
  String get settingsCustomOcrServerDescription =>
      '请填写与您的 OCR 服务器相同的 AUTH_API_KEY。Mekuru 会以 Authorization: Bearer <key> 的形式发送远程漫画 OCR 请求。';

  @override
  String get settingsCustomOcrServerUrlRequired => '请输入服务器 URL。';

  @override
  String get settingsCustomOcrServerUrlInvalid =>
      '请输入完整的 http:// 或 https:// 服务器 URL。';

  @override
  String get settingsCustomOcrServerKeyRequired => '自定义服务器需要共享密钥。';

  @override
  String get settingsDownloadsSubtitle => '词典、汉字数据等';

  @override
  String get settingsBackupRestoreTitle => '备份与恢复';

  @override
  String get settingsBackupRestoreSubtitle => '备份和恢复您的数据';

  @override
  String get settingsSendFeedbackSubtitle => '报告错误或建议新功能';

  @override
  String get settingsFeedbackThanks => '感谢您的反馈！';

  @override
  String get settingsFeedbackFailed => '反馈发送失败，请重试。';

  @override
  String get settingsDocumentationTitle => '文档';

  @override
  String get settingsDocumentationSubtitle => '指南和操作文章';

  @override
  String get settingsAboutMekuruTitle => '关于Mekuru';

  @override
  String get settingsAboutMekuruSubtitle => '版本、许可证等信息';

  @override
  String get feedbackTitle => '发送反馈';

  @override
  String get feedbackNameLabel => '姓名';

  @override
  String get feedbackNameHint => '你的名字';

  @override
  String get feedbackEmailLabel => '邮箱';

  @override
  String get feedbackEmailHint => 'your@email.com';

  @override
  String get feedbackMessageLabel => '留言';

  @override
  String get feedbackRequired => '（必填）';

  @override
  String get feedbackMessageHint => '请描述你的问题或功能建议...';

  @override
  String get feedbackMessageRequiredError => '请输入留言内容';

  @override
  String get backupTitle => '备份与恢复';

  @override
  String get backupSectionBackup => '备份';

  @override
  String get backupCreateNowTitle => '立即创建备份';

  @override
  String get backupCreateNowSubtitle =>
      '保存您的设置和用户数据，例如书签、高亮和词汇表。实际的 EPUB 和漫画文件不会包含在备份中。';

  @override
  String get backupExportTitle => '导出备份';

  @override
  String get backupExportSubtitle =>
      '将最新的设置和用户数据备份保存为文件。实际的 EPUB 和漫画文件不会包含在备份中。';

  @override
  String get backupSaveFileDialogTitle => '保存备份';

  @override
  String get backupScopeNoteTitle => '会备份哪些内容？';

  @override
  String get backupScopeNoteBody =>
      '备份会保存您在 Mekuru 中的设置和自己创建的数据，例如书签、高亮和词汇表。实际的 EPUB 或漫画文件不会包含在备份中。';

  @override
  String get backupScopeNoteRestore =>
      '恢复后，请重新导入相同的 EPUB 或漫画内容。如果内容完全一致，您的阅读记录会恢复。';

  @override
  String get backupSectionAutoBackup => '自动备份';

  @override
  String get backupAutoBackupIntervalTitle => '自动备份间隔';

  @override
  String get backupIntervalOff => '关闭';

  @override
  String get backupIntervalDaily => '每日';

  @override
  String get backupIntervalWeekly => '每周';

  @override
  String get backupSectionRestore => '恢复';

  @override
  String get backupImportFileTitle => '导入备份文件';

  @override
  String get backupImportFileSubtitle =>
      '从 .mekuru 文件恢复设置和用户数据。重新导入相同的 EPUB 或漫画内容即可恢复记录。';

  @override
  String get backupSectionHistory => '备份历史';

  @override
  String get backupNoBackupsYet => '暂无备份';

  @override
  String backupErrorLoadingHistory({required String details}) {
    return '加载备份时出错：$details';
  }

  @override
  String get backupCreatedSuccess => '备份创建成功';

  @override
  String backupFailed({required String details}) {
    return '备份失败：$details';
  }

  @override
  String get backupNoBackupsToExport => '没有可导出的备份，请先创建。';

  @override
  String get backupExportedSuccess => '备份导出成功';

  @override
  String backupExportFailed({required String details}) {
    return '导出失败：$details';
  }

  @override
  String get backupInvalidFile => '请选择一个 .mekuru 备份文件。';

  @override
  String backupCouldNotOpenFile({required String details}) {
    return '无法打开文件：$details';
  }

  @override
  String backupRestoreFailed({required String details}) {
    return '恢复失败：$details';
  }

  @override
  String backupBooksUpdatedFromBackup({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '# 本书已通过备份更新',
      one: '# 本书已通过备份更新',
    );
    return '$_temp0';
  }

  @override
  String backupApplyBookDataFailed({required String details}) {
    return '应用书籍数据失败：$details';
  }

  @override
  String get backupConflictDialogTitle => '书籍冲突';

  @override
  String get backupConflictDialogBody => '以下书籍已存在阅读数据。请选择要用备份数据覆盖的书籍：';

  @override
  String backupConflictEntrySubtitle({
    required String bookType,
    required int progress,
  }) {
    return '$bookType - 备份进度 $progress%';
  }

  @override
  String get backupConflictSkipAll => '全部跳过';

  @override
  String backupConflictOverwriteSelected({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '覆盖 # 本',
      one: '覆盖 # 本',
    );
    return '$_temp0';
  }

  @override
  String get backupBookTypeEpub => 'EPUB';

  @override
  String get backupBookTypeManga => '漫画';

  @override
  String get backupRestoreSummarySettingsRestored => '设置已恢复';

  @override
  String get backupRestoreSummarySettingsPartial => '部分设置无法恢复';

  @override
  String backupRestoreSummaryWords({required int added, required int skipped}) {
    return '已添加 $added 个单词，跳过 $skipped 个';
  }

  @override
  String backupRestoreSummaryBooksRestored({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '# 本书已恢复',
      one: '# 本书已恢复',
    );
    return '$_temp0';
  }

  @override
  String backupRestoreSummaryBooksPending({required int count}) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '# 本书正在等待重新导入相同的 EPUB 或漫画内容',
      one: '# 本书正在等待重新导入相同的 EPUB 或漫画内容',
    );
    return '$_temp0';
  }

  @override
  String get backupRestoreComplete => '恢复完成';

  @override
  String get backupRestoreDialogTitle => '恢复备份？';

  @override
  String backupRestoreDialogBody({required String fileName}) {
    return '这将从 $fileName 恢复设置和用户数据，例如书签、高亮和词汇表。它不会恢复实际的 EPUB 或漫画文件。恢复后，请重新导入相同的 EPUB 或漫画内容以找回记录。您当前的设置将被覆盖。';
  }

  @override
  String get backupDeleteDialogTitle => '删除备份？';

  @override
  String backupDeleteDialogBody({required String fileName}) {
    return '删除 $fileName？此操作无法撤销。';
  }

  @override
  String get backupHistoryTypeAuto => '自动备份';

  @override
  String get backupHistoryTypeManual => '手动备份';

  @override
  String get readerDismiss => '关闭';

  @override
  String readerFailedToLoadContent({required String details}) {
    return '无法加载 EPUB 内容。\n$details';
  }

  @override
  String readerFailedToLoad({required String details}) {
    return '无法加载 EPUB 文件。\n$details';
  }

  @override
  String get readerVerticalTextNonNativeWarning => '此书最初未为竖排文本设计，可能会出现显示问题。';

  @override
  String get readerHorizontalTextNonNativeWarning =>
      '此书最初为竖排文本设计，横排模式下可能会出现显示问题。';

  @override
  String get readerBookmarkRemoved => '书签已移除';

  @override
  String get readerPageBookmarked => '已添加书签';

  @override
  String get readerTableOfContents => '目录';

  @override
  String get readerRemoveBookmarkTooltip => '移除书签';

  @override
  String get readerBookmarkPageTooltip => '添加书签';

  @override
  String get readerViewBookmarksTooltip => '查看书签';

  @override
  String get readerHighlightsTooltip => '高亮';

  @override
  String get readerNextPageTooltip => '下一页';

  @override
  String get readerPreviousPageTooltip => '上一页';

  @override
  String get readerUnknownError => '未知阅读器错误。';

  @override
  String get readerQuickSettings => '快速设置';

  @override
  String get readerVerticalTextTitle => '竖排文本';

  @override
  String get readerThisBook => '本书';

  @override
  String get readerVerticalTextUnavailable => '本书的语言暂不支持竖排显示';

  @override
  String get readerReadingDirectionTitle => '阅读方向';

  @override
  String get readerReadingDirectionRtl => '从右到左';

  @override
  String get readerReadingDirectionLtr => '从左到右';

  @override
  String get readerDisableLinksTitle => '禁用链接';

  @override
  String get readerDisableLinksSubtitle => '点击已链接的文本以查词，而不是跳转';

  @override
  String get readerHighlightSelectionTooltip => '高亮所选内容';

  @override
  String get commonCopy => '复制';

  @override
  String get commonShare => '分享';

  @override
  String get commonContinue => '继续';

  @override
  String get commonNotSelected => '未选择';

  @override
  String get commonUnknown => '未知';

  @override
  String get commonRename => '重命名';

  @override
  String get commonTitleLabel => '标题';

  @override
  String libraryCouldNotReadFolder({required String details}) {
    return '无法读取文件夹：\n$details';
  }

  @override
  String get libraryBookmarksTitle => '书签';

  @override
  String get libraryChangeCoverAction => '更换封面';

  @override
  String get libraryRenameBookTitle => '重命名图书';

  @override
  String get libraryDeleteBookTitle => '删除图书';

  @override
  String libraryDeleteBookBody({required String title}) {
    return '从您的书库中删除“$title”？';
  }

  @override
  String libraryChangeCoverFailed({required String details}) {
    return '更换封面失败：$details';
  }

  @override
  String get dictionaryManagerTitle => '词典管理';

  @override
  String get dictionaryManagerImportTooltip => '导入词典';

  @override
  String get dictionaryManagerEmptySubtitle =>
      '点击 + 导入一个 Yomitan 词典（.zip）\n或词典集合（.json）';

  @override
  String get dictionaryManagerBrowseDownloads => '浏览下载';

  @override
  String get dictionaryManagerBrowseDownloadsCaption => '下载词典和其他资源';

  @override
  String dictionaryManagerImportedOn({required String date}) {
    return '已导入 $date';
  }

  @override
  String get dictionaryManagerSupportedFormatsTitle => '支持的格式';

  @override
  String get dictionaryManagerSupportedFormatsYomitan =>
      'Yomitan 词典（.zip）\n支持可导入到 Yomitan 的所有词典。这些是包含词库 JSON 文件的 .zip 文件。';

  @override
  String get dictionaryManagerSupportedFormatsCollection =>
      'Yomitan 集合（.json）\n包含多个词典的 Dexie 数据库导出文件。你可以在 Yomitan 的设置中通过“备份”导出此文件。';

  @override
  String get dictionaryManagerOrderTitle => '词典顺序';

  @override
  String get dictionaryManagerOrderBody =>
      '使用左侧的拖动柄拖动词典进行排序。这里的顺序决定你阅读时点击单词时词典释义的显示顺序。';

  @override
  String get dictionaryManagerEnablingTitle => '启用与禁用';

  @override
  String get dictionaryManagerEnablingBody => '使用开关按钮启用或禁用词典。禁用的词典不会在查词时被检索。';

  @override
  String get dictionaryManagerFindingTitle => '查找词典';

  @override
  String get dictionaryManagerFindingPrefix => '在此处浏览兼容词典 ';

  @override
  String get dictionaryManagerDeleteTitle => '删除词典';

  @override
  String dictionaryManagerDeleteBody({required String name}) {
    return '删除“$name”及其所有词条？\n此操作不可撤销。';
  }

  @override
  String get ankidroidDataSourceExpression => '表达式';

  @override
  String get ankidroidDataSourceReading => '读音';

  @override
  String get ankidroidDataSourceFurigana => '振假名（Anki 格式）';

  @override
  String get ankidroidDataSourceGlossary => '释义/含义';

  @override
  String get ankidroidDataSourceSentenceContext => '例句上下文';

  @override
  String get ankidroidDataSourceFrequency => '频率排名';

  @override
  String get ankidroidDataSourceDictionaryName => '词典名称';

  @override
  String get ankidroidDataSourcePitchAccent => '音调';

  @override
  String get ankidroidDataSourceEmpty => '（空）';

  @override
  String get ankidroidPermissionNotGrantedLong =>
      '未授予 AnkiDroid 权限。请确保已安装 AnkiDroid 后重试。';

  @override
  String get ankidroidCouldNotConnectLong =>
      '无法连接到 AnkiDroid。请确保已安装并正在运行 AnkiDroid。';

  @override
  String get ankidroidPermissionNotGrantedShort => '未授予 AnkiDroid 权限。';

  @override
  String get ankidroidCouldNotConnectShort => '无法连接到 AnkiDroid。';

  @override
  String get ankidroidFailedToAddNote =>
      '添加笔记失败。请确认 AnkiDroid 正在运行，所选笔记类型和牌组仍然存在。';

  @override
  String get ankidroidSettingsNoteTypeSection => '笔记类型';

  @override
  String get ankidroidSettingsNoteTypeTitle => 'Anki 笔记类型';

  @override
  String get ankidroidSettingsDefaultDeckSection => '默认牌组';

  @override
  String get ankidroidSettingsTargetDeckTitle => '目标牌组';

  @override
  String get ankidroidSettingsFieldMappingSection => '字段映射';

  @override
  String get ankidroidSettingsFieldMappingHelp => '将每个 Anki 字段映射到应用的数据来源。';

  @override
  String get ankidroidSettingsDefaultTagsSection => '默认标签';

  @override
  String get ankidroidSettingsDefaultTagsHelp => '每条导出笔记都会添加以逗号分隔的标签。';

  @override
  String get ankidroidTagsHint => 'mekuru, japanese';

  @override
  String get ankidroidSettingsSelectNoteType => '选择笔记类型';

  @override
  String get ankidroidSettingsSelectDeck => '选择牌组';

  @override
  String ankidroidSettingsMapFieldTo({required String ankiFieldName}) {
    return '将“$ankiFieldName”映射为：';
  }

  @override
  String get ankidroidCardSettingsTooltip => 'AnkiDroid 设置';

  @override
  String get ankidroidCardDeckTitle => '牌组';

  @override
  String get ankidroidCardTagsTitle => '标签';

  @override
  String get ankidroidCardAddToAnki => '添加到 Anki';

  @override
  String get mangaReaderSettingsTitle => '阅读器设置';

  @override
  String get mangaViewModeSingle => '单页';

  @override
  String get mangaViewModeSpread => '双页';

  @override
  String get mangaViewModeScroll => '滚动';

  @override
  String get mangaAutoCropSubtitle => '移除空白边距';

  @override
  String get mangaAutoCropRerunTitle => '重新执行自动裁边';

  @override
  String get mangaAutoCropRerunSubtitle => '重新扫描本书的每一页图片';

  @override
  String get mangaTransparentLookupTitle => '透明查词';

  @override
  String get mangaTransparentLookupSubtitle => '半透明字典面板';

  @override
  String get mangaDebugWordOverlayTitle => '调试词语覆盖层';

  @override
  String get mangaDebugWordOverlaySubtitle => '显示单词边框';

  @override
  String get mangaAutoCropComputeTitle => '计算自动裁边？';

  @override
  String get mangaAutoCropComputeBody => '自动裁边需要先扫描本书的所有页面图片，才能启用。可能需要几分钟。';

  @override
  String get mangaAutoCropRerunDialogTitle => '重新执行自动裁边？';

  @override
  String get mangaAutoCropRerunDialogBody =>
      '自动裁边将重新扫描本书的每一页图片，并替换已保存的裁切范围。可能需要几分钟。';

  @override
  String get mangaAutoCropComputingProgress => '正在计算自动裁边范围，可能需要几分钟。';

  @override
  String get mangaAutoCropRecomputingProgress => '正在重新计算自动裁边范围，可能需要几分钟。';

  @override
  String get mangaAutoCropBoundsRefreshed => '自动裁边范围已刷新。';

  @override
  String mangaAutoCropSetupFailed({required String details}) {
    return '自动裁边设置失败：$details';
  }

  @override
  String get ocrNoPagesCacheFound => '未找到本书的页面缓存';

  @override
  String get ocrAlreadyCompleteResetHint => 'OCR 已完成。使用“移除 OCR”可重置。';

  @override
  String get ocrMangaImageDirectoryNotFound => '未找到漫画图片目录';

  @override
  String get ocrBuildWordOverlaysTitle => '生成单词覆盖层';

  @override
  String get ocrBuildWordOverlaysBody => 'OCR 文本已存在。这会重新生成单词点击目标，使查词覆盖层正确显示。';

  @override
  String get ocrRunActionTitle => '运行 OCR';

  @override
  String ocrProcessPagesBody({required int count}) {
    return '将处理 $count 页。OCR 会在后台运行，即使关闭应用也会继续。';
  }

  @override
  String get ocrProcessAction => '处理';

  @override
  String get ocrStartAction => '开始';

  @override
  String ocrPrepareFailed({required String details}) {
    return '无法准备 OCR：$details';
  }

  @override
  String ocrStartFailed({required String details}) {
    return '启动 OCR 失败：$details';
  }

  @override
  String get ocrWordOverlayStartedBackground => '词语遮罩处理已在后台开始';

  @override
  String get ocrStartedBackground => 'OCR 已在后台启动';

  @override
  String get ocrCancelActionTitle => '取消 OCR';

  @override
  String get ocrCancelSavedProgress => 'OCR 已取消。进度已保存。';

  @override
  String get ocrReplaceActionTitle => '替换 OCR';

  @override
  String get ocrReplaceMokuroBody =>
      '这将覆盖从 Mokuro/HTML 文件导入的 OCR 数据，并使用您的自定义服务器对所有页面重新执行 OCR。\n\n要恢复原始 OCR，请重新导入书籍。';

  @override
  String get ocrReplaceStartedBackground => 'OCR 替换已在后台开始';

  @override
  String get ocrRemoveActionTitle => '移除 OCR';

  @override
  String get ocrRemoveBody => '要从本漫画中移除 OCR 文字和词语遮罩吗？您以后可以再次运行 OCR。';

  @override
  String get ocrRemoveSubtitle => '从所有页面移除 OCR 文字';

  @override
  String get ocrRemovedFromBook => '已从本书移除 OCR';

  @override
  String ocrRemoveFailed({required String details}) {
    return '移除 OCR 失败：$details';
  }

  @override
  String get ocrUnlockProSubtitle => '解锁 Pro 以使用自定义 OCR 服务器';

  @override
  String get ocrStopAndSaveProgressSubtitle => '停止处理并保存进度';

  @override
  String get ocrReplaceMokuroSubtitle => '用自定义 OCR 服务器替换 Mokuro 的 OCR';

  @override
  String get ocrBuildWordTargetsSubtitle => '根据已保存的 OCR 构建词语点击区域';

  @override
  String ocrResumeSubtitle({required int completed, required int total}) {
    return '继续 OCR（已完成 $completed/$total）';
  }

  @override
  String get ocrRecognizeAllPagesSubtitle => '识别所有页面中的文本';

  @override
  String get readerEditNoteTitle => '编辑笔记';

  @override
  String get readerAddNoteHint => '添加笔记...';

  @override
  String get readerCopiedToClipboard => '已复制到剪贴板';

  @override
  String get aboutPrivacyPolicyTitle => '隐私政策';

  @override
  String get aboutPrivacyPolicySubtitle => '查看 Mekuru 如何处理本地与 OCR 数据';

  @override
  String get aboutOpenSourceLicensesTitle => '开源许可证';

  @override
  String get aboutOpenSourceLicensesSubtitle => '查看依赖项的许可证';

  @override
  String get aboutTagline => '“翻页”';

  @override
  String get aboutEpubJsLicenseTitle => 'epub.js 许可证';

  @override
  String get downloadsKanjidicTitle => 'KANJIDIC';

  @override
  String get readerBookmarksTitle => '书签';

  @override
  String get readerNoBookmarksYet => '还没有书签。\n阅读时点击书签图标即可添加。';

  @override
  String readerBookmarkProgressDate({
    required String progress,
    required String date,
  }) {
    return '$progress - $date';
  }

  @override
  String aboutVersion({required String version}) {
    return '版本 $version';
  }

  @override
  String get aboutDescription => '一款以日语为主的EPUB阅读器，支持竖排、离线词典和词汇管理。';

  @override
  String get aboutAttributionTitle => '归属';

  @override
  String get aboutKanjiVgTitle => 'KanjiVG';

  @override
  String get aboutKanjiVgDescription => '汉字笔顺数据由Ulrich Apel创建的KanjiVG项目提供。';

  @override
  String get aboutLicensedUnderPrefix => '授权协议：';

  @override
  String get aboutLicenseSuffix => ' 协议。';

  @override
  String get aboutProjectLabel => '项目：';

  @override
  String get aboutSourceLabel => '来源：';

  @override
  String get aboutJpdbTitle => 'JPDB 词频词典';

  @override
  String get aboutJpdbDescription =>
      '词频数据由JPDB词频词典提供，通过Kuuuube的yomitan-dictionaries分发。';

  @override
  String get aboutDataSourceLabel => '数据来源：';

  @override
  String get aboutDictionaryLabel => '词典：';

  @override
  String get aboutJmdictKanjidicTitle => 'JMdict & KANJIDIC';

  @override
  String get aboutJmdictKanjidicDescriptionPrefix =>
      '日语多语种词典数据由JMdict/EDICT项目提供，汉字词典数据由KANJIDIC项目提供，二者均由Jim Breen和';

  @override
  String get aboutJmdictLabel => 'JMdict：';

  @override
  String get aboutKanjidicLabel => 'KANJIDIC：';

  @override
  String get aboutEpubJsTitle => 'epub.js';

  @override
  String get aboutEpubJsDescription =>
      'EPUB渲染由epub.js驱动，这是一款开源的JavaScript EPUB阅读库。';

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
