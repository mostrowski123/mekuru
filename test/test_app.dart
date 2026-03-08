import 'package:flutter/material.dart';
import 'package:mekuru/features/settings/data/services/app_settings_storage.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';

Widget buildLocalizedTestApp({required Widget home, Locale? locale}) {
  return MaterialApp(
    locale: locale,
    localeResolutionCallback: resolveSupportedAppLocale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );
}
