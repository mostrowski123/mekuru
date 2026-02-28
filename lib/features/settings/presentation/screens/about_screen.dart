import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// About screen showing app information, attribution, and open source licenses.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const _appName = 'Mekuru';
  static const _appVersion = '1.2.0';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 24),

          // App icon
          Center(
            child: Icon(
              Icons.auto_stories,
              size: 80,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),

          // App name
          Text(
            _appName,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),

          // Version
          Text(
            'Version $_appVersion',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          // Description
          Text(
            'A Japanese-first EPUB reader with vertical text, '
            'offline dictionary, and vocabulary management.',
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),

          // ── Attribution ──
          Text(
            'Attribution',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),

          // KanjiVG attribution card
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
                        'KanjiVG',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Kanji stroke order data is provided by the KanjiVG '
                    'project, created by Ulrich Apel.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  Text.rich(
                    TextSpan(
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      children: [
                        const TextSpan(text: 'Licensed under the '),
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
                        const TextSpan(text: ' license.'),
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
                        const TextSpan(text: 'Project: '),
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
                        const TextSpan(text: 'Source: '),
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

          // JPDB Frequency Dictionary attribution card
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
                          'JPDB Frequency Dictionary',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Word frequency data is provided by the JPDB frequency '
                    'dictionary, distributed via yomitan-dictionaries by Kuuuube.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  Text.rich(
                    TextSpan(
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      children: [
                        const TextSpan(text: 'Data source: '),
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
                        const TextSpan(text: 'Dictionary: '),
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

          // JMdict & KANJIDIC attribution card
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
                          'JMdict & KANJIDIC',
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
                        const TextSpan(
                          text:
                              'Japanese–multilingual dictionary data is '
                              'provided by the JMdict/EDICT project and kanji '
                              'dictionary data by the KANJIDIC project, both '
                              'created by Jim Breen and the ',
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
                        const TextSpan(text: 'Licensed under the '),
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
                        const TextSpan(text: ' license.'),
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
                        const TextSpan(text: 'JMdict: '),
                        TextSpan(
                          text: 'edrdg.org/wiki – JMdict-EDICT',
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
                        const TextSpan(text: 'KANJIDIC: '),
                        TextSpan(
                          text: 'edrdg.org/wiki – KANJIDIC',
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

          // epub.js attribution card
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
                        'epub.js',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'EPUB rendering is powered by epub.js, '
                    'an open source JavaScript EPUB reader library.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  Text.rich(
                    TextSpan(
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      children: [
                        const TextSpan(text: 'Licensed under the '),
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
                        const TextSpan(text: 'Source: '),
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
          const SizedBox(height: 16),

          // Licenses
          Card(
            child: ListTile(
              leading: Icon(
                Icons.description_outlined,
                color: theme.colorScheme.primary,
              ),
              title: const Text('Open Source Licenses'),
              subtitle: const Text('View licenses for dependencies'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showLicensePage(
                context: context,
                applicationName: _appName,
                applicationVersion: _appVersion,
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

          // Tagline
          Center(
            child: Text(
              '"to turn pages"',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static void _showEpubJsLicense(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('epub.js License'),
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
            child: const Text('Close'),
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
