import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/platform/network_status.dart';
import 'package:mekuru/features/backup/data/services/full_backup_service.dart'
    show InsufficientSpaceException;
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:mekuru/shared/widgets/download_status.dart';

void main() {
  test('a dictionary download failure is worded for the user', () {
    final l10n = lookupAppLocalizations(const Locale('en'));

    expect(dictionaryDownloadError(l10n, null), isNull);
    expect(
      dictionaryDownloadError(l10n, const WifiLostException()),
      'The download stopped because Wi-Fi disconnected. '
      'Tap Download to try again.',
    );
    expect(
      dictionaryDownloadError(
        l10n,
        const InsufficientSpaceException(neededBytes: 500 << 20),
      ),
      'Not enough free space on this device. About 500 MB more is needed.',
    );
    expect(dictionaryDownloadError(l10n, 'boom'), 'Download failed: boom');
  });
}
