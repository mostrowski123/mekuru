import 'package:flutter/material.dart';
import 'package:mekuru/core/platform/network_status.dart';
import 'package:mekuru/features/manga/data/services/manga_ocr_ios.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/widgets/mobile_data_dialog.dart';

final _packBytes = mangaOcrIosModelFiles.fold<int>(0, (a, f) => a + f.bytes);
final _packSize = '${(_packBytes / 1000000).toStringAsFixed(1)} MB';

/// Downloads screen tile for the optional manga-ocr model pack on iOS. The
/// Android tile talks to the native job service; this one only needs
/// [MangaOcrIos].
class MangaOcrIosDownloadTile extends StatefulWidget {
  const MangaOcrIosDownloadTile({super.key});

  @override
  State<MangaOcrIosDownloadTile> createState() =>
      _MangaOcrIosDownloadTileState();
}

class _MangaOcrIosDownloadTileState extends State<MangaOcrIosDownloadTile> {
  bool? _installed;
  double? _progress;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    var installed = false;
    try {
      installed = await MangaOcrIos.instance.installed;
    } catch (_) {
      // No readable app directory: offer the download rather than spin.
    }
    if (mounted) setState(() => _installed = installed);
  }

  Future<void> _download() async {
    // Busy before the Wi-Fi check, so a second tap can't start a second
    // download.
    setState(() {
      _progress = 0;
      _error = null;
    });
    final wifi = await isOnWifi();
    if (!wifi) {
      if (!mounted) return;
      final confirmed = await confirmMobileData(
        context,
        context.l10n.localOcrMobileDownloadBody(size: _packSize),
      );
      if (!mounted) return;
      if (!confirmed) {
        setState(() => _progress = null);
        return;
      }
    }
    try {
      // Started on Wi-Fi without asking, so it must not go on over mobile
      // data.
      await MangaOcrIos.instance.download(
        wifiOnly: wifi,
        onProgress: (f) {
          if (mounted) setState(() => _progress = f);
        },
      );
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
    if (mounted) setState(() => _progress = null);
    await _refresh();
  }

  Future<void> _remove() async {
    await MangaOcrIos.instance.remove();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final busy = _progress != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: Icon(
            Icons.document_scanner_outlined,
            color: theme.colorScheme.primary,
          ),
          title: Text(l.localOcrModelTitle),
          subtitle: Text(
            _error is WifiLostException
                ? l.localOcrWifiLostIos
                : _error != null
                ? l.localOcrError(details: '$_error')
                : _installed == true
                ? l.localOcrModelReady
                : '${l.localOcrModelDescriptionIos} ($_packSize)',
          ),
          trailing: _installed == null || busy
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : _installed!
              ? IconButton(
                  tooltip: l.commonRemove,
                  icon: Icon(
                    Icons.delete_outline,
                    color: theme.colorScheme.error,
                  ),
                  onPressed: _remove,
                )
              : FilledButton.tonal(
                  onPressed: _download,
                  child: Text(l.commonDownload),
                ),
        ),
        if (busy)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: LinearProgressIndicator(value: _progress),
          ),
      ],
    );
  }
}
