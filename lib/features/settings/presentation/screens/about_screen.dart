import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// About screen showing app information, attribution, and open source licenses.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const _appName = 'Mekuru';
  static const _privacyPolicyUrl = 'https://mekuru.pages.dev/privacy.html';
  static final Future<PackageInfo> _packageInfoFuture =
      PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return FutureBuilder<PackageInfo>(
      future: _packageInfoFuture,
      builder: (context, snapshot) {
        final appVersion = snapshot.hasData
            ? '${snapshot.data!.version}+${snapshot.data!.buildNumber}'
            : l10n.commonUnknown;

        return Scaffold(
          appBar: AppBar(title: Text(l10n.settingsAboutMekuruTitle)),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const SizedBox(height: 24),
              Center(
                child: Icon(
                  Icons.auto_stories,
                  size: 80,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _appName,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.aboutVersion(version: appVersion),
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Text(
                l10n.aboutDescription,
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Text(
                l10n.aboutAttributionTitle,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
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
                              text:
                                  'Creative Commons Attribution-Share Alike 3.0',
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
                              text:
                                  'Creative Commons Attribution-Share Alike 4.0',
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
              const SizedBox(height: 16),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(
                        Icons.privacy_tip_outlined,
                        color: theme.colorScheme.primary,
                      ),
                      title: Text(l10n.aboutPrivacyPolicyTitle),
                      subtitle: Text(l10n.aboutPrivacyPolicySubtitle),
                      trailing: const Icon(Icons.open_in_new),
                      onTap: () => _launchUrl(_privacyPolicyUrl),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Card(
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
              ),
              const SizedBox(height: 24),
              Center(
                child: Text(
                  l10n.aboutTagline,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
        );
      },
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
