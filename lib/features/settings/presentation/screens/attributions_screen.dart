import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/widgets/download_status.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/ocr_attributions.dart';

class AttributionsScreen extends StatelessWidget {
  const AttributionsScreen({super.key});

  static const _appName = 'Mekuru';
  static final Future<PackageInfo> _packageInfoFuture =
      PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.attributionsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const OcrAttributions(),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.brush_outlined,
                        color: theme.colorScheme.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        l10n.aboutKanjiVgTitle,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.aboutKanjiVgDescription,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  Text.rich(
                    TextSpan(
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      children: [
                        TextSpan(text: l10n.aboutLicensedUnderPrefix),
                        TextSpan(
                          text: 'Creative Commons Attribution-Share Alike 3.0',
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            decoration: TextDecoration.underline,
                          ),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () => _launchUrl(
                              'https://creativecommons.org/licenses/by-sa/3.0/',
                            ),
                        ),
                        TextSpan(text: l10n.aboutLicenseSuffix),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text.rich(
                    TextSpan(
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      children: [
                        TextSpan(text: l10n.aboutProjectLabel),
                        TextSpan(
                          text: 'kanjivg.tagaini.net',
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            decoration: TextDecoration.underline,
                          ),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () =>
                                _launchUrl('https://kanjivg.tagaini.net/'),
                        ),
                      ],
                    ),
                  ),
                  Text.rich(
                    TextSpan(
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      children: [
                        TextSpan(text: l10n.aboutSourceLabel),
                        TextSpan(
                          text: 'github.com/KanjiVG/kanjivg',
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            decoration: TextDecoration.underline,
                          ),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () => _launchUrl(
                              'https://github.com/KanjiVG/kanjivg',
                            ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.bar_chart_outlined,
                        color: theme.colorScheme.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n.aboutJpdbTitle,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.aboutJpdbDescription,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  Text.rich(
                    TextSpan(
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      children: [
                        TextSpan(text: l10n.aboutDataSourceLabel),
                        TextSpan(
                          text: 'jpdb.io',
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            decoration: TextDecoration.underline,
                          ),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () => _launchUrl('https://jpdb.io'),
                        ),
                      ],
                    ),
                  ),
                  Text.rich(
                    TextSpan(
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      children: [
                        TextSpan(text: l10n.aboutDictionaryLabel),
                        TextSpan(
                          text: 'github.com/Kuuuube/yomitan-dictionaries',
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            decoration: TextDecoration.underline,
                          ),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () => _launchUrl(
                              'https://github.com/Kuuuube/yomitan-dictionaries',
                            ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.translate_outlined,
                        color: theme.colorScheme.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n.aboutJmdictKanjidicTitle,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text.rich(
                    TextSpan(
                      style: theme.textTheme.bodyMedium,
                      children: [
                        TextSpan(
                          text: l10n.aboutJmdictKanjidicDescriptionPrefix,
                        ),
                        TextSpan(
                          text:
                              'Electronic Dictionary Research '
                              'and Development Group',
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            decoration: TextDecoration.underline,
                          ),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () =>
                                _launchUrl('https://www.edrdg.org/'),
                        ),
                        const TextSpan(text: '.'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text.rich(
                    TextSpan(
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      children: [
                        TextSpan(text: l10n.aboutLicensedUnderPrefix),
                        TextSpan(
                          text: 'Creative Commons Attribution-Share Alike 4.0',
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            decoration: TextDecoration.underline,
                          ),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () => _launchUrl(
                              'https://creativecommons.org/licenses/by-sa/4.0/',
                            ),
                        ),
                        TextSpan(text: l10n.aboutLicenseSuffix),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text.rich(
                    TextSpan(
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      children: [
                        TextSpan(text: l10n.aboutJmdictLabel),
                        TextSpan(
                          text: 'edrdg.org/wiki - JMdict-EDICT',
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            decoration: TextDecoration.underline,
                          ),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () => _launchUrl(
                              'https://www.edrdg.org/wiki/index.php/JMdict-EDICT_Dictionary_Project',
                            ),
                        ),
                      ],
                    ),
                  ),
                  Text.rich(
                    TextSpan(
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      children: [
                        TextSpan(text: l10n.aboutKanjidicLabel),
                        TextSpan(
                          text: 'edrdg.org/wiki - KANJIDIC',
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            decoration: TextDecoration.underline,
                          ),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () => _launchUrl(
                              'https://www.edrdg.org/wiki/index.php/KANJIDIC_Project',
                            ),
                        ),
                      ],
                    ),
                  ),
                  DownloadAttributionText(
                    prefix: l10n.aboutJmnedictLabel,
                    linkText: 'edrdg.org - JMnedict',
                    url: 'https://www.edrdg.org/enamdict/enamdict_doc.html',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.library_books_outlined,
                        color: theme.colorScheme.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n.aboutCatalogDictionariesTitle,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.aboutCatalogDictionariesDescription,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  DownloadAttributionText(
                    prefix: l10n.aboutLicensedUnderPrefix,
                    linkText: 'Creative Commons Attribution-Share Alike 4.0',
                    url: 'https://creativecommons.org/licenses/by-sa/4.0/',
                    suffix: l10n.aboutLicenseSuffix,
                  ),
                  const SizedBox(height: 8),
                  for (final (label, url) in const [
                    ('Jitendex', 'https://jitendex.org'),
                    ('Tatoeba', 'https://tatoeba.org'),
                    ('Wiktionary', 'https://www.wiktionary.org'),
                    ('Kaikki.org', 'https://kaikki.org'),
                    (
                      'Wiktionary to Yomitan',
                      'https://github.com/yomidevs/wiktionary-to-yomitan',
                    ),
                  ])
                    DownloadAttributionText(linkText: label, url: url),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.local_library_outlined,
                        color: theme.colorScheme.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n.attributionFreeBooksTitle,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.attributionFreeBooksDescription,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  for (final (label, url) in const [
                    ('Aozora Bunko', 'https://www.aozora.gr.jp/'),
                    (
                      'aozorabunko-clean',
                      'https://huggingface.co/datasets/globis-university/aozorabunko-clean',
                    ),
                    (
                      'NPO Tadoku Supporters',
                      'https://tadoku.org/japanese/en/free-books-en/',
                    ),
                    (
                      'CC BY 4.0',
                      'https://creativecommons.org/licenses/by/4.0/',
                    ),
                    (
                      'CC BY-NC-ND 4.0',
                      'https://creativecommons.org/licenses/by-nc-nd/4.0/',
                    ),
                  ])
                    DownloadAttributionText(linkText: label, url: url),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.menu_book_outlined,
                        color: theme.colorScheme.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        l10n.aboutEpubJsTitle,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.aboutEpubJsDescription,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  Text.rich(
                    TextSpan(
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      children: [
                        TextSpan(text: l10n.aboutLicensedUnderPrefix),
                        TextSpan(
                          text: 'BSD 2-Clause License',
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            decoration: TextDecoration.underline,
                          ),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () => _showEpubJsLicense(context),
                        ),
                        const TextSpan(text: '.'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text.rich(
                    TextSpan(
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      children: [
                        TextSpan(text: l10n.aboutSourceLabel),
                        TextSpan(
                          text: 'github.com/futurepress/epub.js',
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            decoration: TextDecoration.underline,
                          ),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () => _launchUrl(
                              'https://github.com/futurepress/epub.js',
                            ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.spellcheck_outlined,
                        color: theme.colorScheme.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        l10n.attributionUniDicTitle,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.attributionUniDicDescription,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.attributionUniDicLicense,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text.rich(
                    TextSpan(
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      children: [
                        TextSpan(text: l10n.aboutProjectLabel),
                        TextSpan(
                          text: 'clrd.ninjal.ac.jp/unidic',
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            decoration: TextDecoration.underline,
                          ),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () =>
                                _launchUrl('https://clrd.ninjal.ac.jp/unidic/'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.g_translate_outlined,
                        color: theme.colorScheme.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        l10n.attributionFirefoxTranslationsTitle,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.attributionFirefoxTranslationsDescription,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  DownloadAttributionText(
                    prefix: l10n.aboutLicensedUnderPrefix,
                    linkText: 'Mozilla Public License 2.0',
                    url: 'https://mozilla.org/MPL/2.0/',
                    suffix: '.',
                  ),
                  const SizedBox(height: 8),
                  DownloadAttributionText(
                    prefix: l10n.aboutSourceLabel,
                    linkText: 'github.com/mozilla/translations',
                    url: 'https://github.com/mozilla/translations',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.auto_awesome_outlined,
                        color: theme.colorScheme.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        l10n.attributionGemmaTitle,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.attributionGemmaDescription,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  DownloadAttributionText(
                    prefix: l10n.aboutLicensedUnderPrefix,
                    linkText: 'Apache License 2.0',
                    url: 'https://www.apache.org/licenses/LICENSE-2.0',
                    suffix: '.',
                  ),
                  const SizedBox(height: 8),
                  DownloadAttributionText(
                    prefix: l10n.aboutSourceLabel,
                    linkText:
                        'huggingface.co/litert-community/gemma-4-E2B-it-litert-lm',
                    url:
                        'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FutureBuilder<PackageInfo>(
            future: _packageInfoFuture,
            builder: (context, snapshot) {
              final appVersion = snapshot.hasData
                  ? '${snapshot.data!.version}+${snapshot.data!.buildNumber}'
                  : l10n.commonUnknown;
              return Card(
                child: ListTile(
                  leading: Icon(
                    Icons.description_outlined,
                    color: theme.colorScheme.primary,
                  ),
                  title: Text(l10n.aboutOpenSourceLicensesTitle),
                  subtitle: Text(l10n.aboutOpenSourceLicensesSubtitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: _appName,
                    applicationVersion: appVersion,
                    applicationIcon: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                        Icons.auto_stories,
                        size: 48,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  static void _showEpubJsLicense(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.aboutEpubJsLicenseTitle),
        content: const SingleChildScrollView(
          child: Text(
            'Copyright (c) 2013, FuturePress\n\n'
            'All rights reserved.\n\n'
            'Redistribution and use in source and binary forms, with or without '
            'modification, are permitted provided that the following conditions '
            'are met:\n\n'
            '1. Redistributions of source code must retain the above copyright '
            'notice, this list of conditions and the following disclaimer.\n\n'
            '2. Redistributions in binary form must reproduce the above '
            'copyright notice, this list of conditions and the following '
            'disclaimer in the documentation and/or other materials provided '
            'with the distribution.\n\n'
            'THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND '
            'CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, '
            'INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF '
            'MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE '
            'DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR '
            'CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, '
            'SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT '
            'LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF '
            'USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED '
            'AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT '
            'LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN '
            'ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE '
            'POSSIBILITY OF SUCH DAMAGE.\n\n'
            'The views and conclusions contained in the software and '
            'documentation are those of the authors and should not be '
            'interpreted as representing official policies, either expressed '
            'or implied, of the FreeBSD Project.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(context.l10n.commonClose),
          ),
        ],
      ),
    );
  }

  static Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
