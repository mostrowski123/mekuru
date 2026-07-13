import 'package:flutter/material.dart';
import 'package:mekuru/core/config/app_links.dart';
import 'package:mekuru/features/settings/presentation/screens/attributions_screen.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/utils/haptics.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// About screen showing app information and links to attribution / privacy.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const _appName = 'Mekuru';
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
              Card(
                child: ListTile(
                  leading: Icon(
                    Icons.privacy_tip_outlined,
                    color: theme.colorScheme.primary,
                  ),
                  title: Text(l10n.aboutPrivacyPolicyTitle),
                  subtitle: Text(l10n.aboutPrivacyPolicySubtitle),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _launchUrl(AppLinks.privacyPolicy),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: Icon(
                    Icons.collections_bookmark_outlined,
                    color: theme.colorScheme.primary,
                  ),
                  title: Text(l10n.aboutAttributionsTitle),
                  subtitle: Text(l10n.aboutAttributionsSubtitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    AppHaptics.light();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const AttributionsScreen(),
                      ),
                    );
                  },
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

  static Future<void> _launchUrl(Uri uri) async {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
