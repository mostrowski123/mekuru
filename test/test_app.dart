import 'package:flutter/material.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';

Widget buildLocalizedTestApp({required Widget home, Locale? locale}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );
}
