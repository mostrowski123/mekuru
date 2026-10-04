import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/platform/network_status.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:mekuru/shared/widgets/download_status.dart';

void main() {
  test('a dictionary download stopped by Wi-Fi says so; other failures show '
      'the error', () {
    final l10n = lookupAppLocalizations(const Locale('en'));

    expect(
      dictionaryDownloadFailure(l10n, const WifiLostException()),
      'The download stopped because Wi-Fi disconnected. '
      'Tap Download to try again.',
    );
    expect(
      dictionaryDownloadFailure(l10n, const HttpExceptionLike()),
      'Download failed: boom',
    );
  });
}

class HttpExceptionLike implements Exception {
  const HttpExceptionLike();

  @override
  String toString() => 'boom';
}
