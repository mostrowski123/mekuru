import 'package:flutter/material.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/dictionary/data/models/dictionary_catalog.dart';
import 'package:mekuru/features/dictionary/presentation/widgets/catalog_dictionary_tile.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/widgets/settings/settings_rows.dart';
import 'package:url_launcher/url_launcher.dart';

/// "More dictionaries": openly licensed Yomitan dictionaries Mekuru
/// downloads itself, then links to guides that list everything else.
class DictionaryCatalogScreen extends StatelessWidget {
  const DictionaryCatalogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.catalogTitle)),
      body: ListView(
        children: [
          for (final section in CatalogSection.values) ...[
            SettingsSectionHeader(title: _sectionTitle(l10n, section)),
            for (final entry in CatalogDictionary.values)
              if (entry.section == section) CatalogDictionaryTile(entry: entry),
            const Divider(),
          ],
          SettingsSectionHeader(title: l10n.catalogFindMoreTitle),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              l10n.catalogFindMoreBody,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          for (final guide in dictionaryGuides)
            ListTile(
              leading: Icon(
                Icons.open_in_new,
                color: theme.colorScheme.primary,
              ),
              title: Text(guide.name),
              onTap: () {
                logUsage(
                  'dictionary_catalog.guide_opened',
                  attrs: {'guide': guide.name},
                );
                launchUrl(
                  Uri.parse(guide.url),
                  mode: LaunchMode.externalApplication,
                );
              },
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  static String _sectionTitle(AppLocalizations l10n, CatalogSection section) =>
      switch (section) {
        CatalogSection.japaneseEnglish => l10n.catalogSectionJapaneseEnglish,
        CatalogSection.japaneseJapanese => l10n.catalogSectionJapaneseJapanese,
        CatalogSection.names => l10n.catalogSectionNames,
        CatalogSection.otherLanguages => l10n.catalogSectionOtherLanguages,
      };
}
