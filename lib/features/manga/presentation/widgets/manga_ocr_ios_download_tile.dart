import 'package:flutter/material.dart';
import 'package:mekuru/core/platform/network_status.dart';
import 'package:mekuru/features/manga/data/services/manga_ocr_ios.dart';
import 'package:mekuru/features/manga/data/services/model_download.dart';
import 'package:mekuru/features/manga/data/services/ndl_text_model.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/widgets/mobile_data_dialog.dart';

/// Downloads screen tile for the optional manga-ocr model pack on iOS. The
/// Android tile talks to the native job service; this one only needs
/// [MangaOcrIos].
class MangaOcrIosDownloadTile extends StatelessWidget {
  const MangaOcrIosDownloadTile({super.key});

  @override
  Widget build(BuildContext context) {
    final ocr = MangaOcrIos.instance;
    return ModelDownloadTile(
      icon: Icons.document_scanner_outlined,
      title: context.l10n.localOcrModelTitle,
      description: context.l10n.localOcrModelDescriptionIos,
      files: mangaOcrIosModelFiles,
      installed: () => ocr.installed,
      download: ocr.download,
      remove: ocr.remove,
    );
  }
}

/// Downloads screen tile for the optional NDL text-line model, on both
/// platforms: on-device scans of Tadoku's graded readers use it.
class NdlTextModelDownloadTile extends StatelessWidget {
  const NdlTextModelDownloadTile({super.key});

  @override
  Widget build(BuildContext context) {
    final model = NdlTextModel.instance;
    return ModelDownloadTile(
      icon: Icons.menu_book_outlined,
      title: context.l10n.ndlTextModelTitle,
      description: context.l10n.ndlTextModelDescription,
      files: ndlTextModelFiles,
      installed: () => model.installed,
      download: model.download,
      remove: model.remove,
    );
  }
}

/// A model of [files] that the app downloads itself (not Android's native
/// job service): progress, the mobile-data question off Wi-Fi, a stop when
/// Wi-Fi goes, and remove.
class ModelDownloadTile extends StatefulWidget {
  const ModelDownloadTile({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.files,
    required this.installed,
    required this.download,
    required this.remove,
  });

  final IconData icon;
  final String title;
  final String description;
  final List<ModelFile> files;
  final Future<bool> Function() installed;
  final Future<void> Function({
    void Function(double)? onProgress,
    bool wifiOnly,
  })
  download;
  final Future<void> Function() remove;

  @override
  State<ModelDownloadTile> createState() => _ModelDownloadTileState();
}

class _ModelDownloadTileState extends State<ModelDownloadTile> {
  bool? _installed;
  double? _progress;
  Object? _error;

  String get _size => modelFilesSize(widget.files);

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    var installed = false;
    try {
      installed = await widget.installed();
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
        size: _size,
        body: context.l10n.localOcrMobileDownloadBody(size: _size),
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
      await widget.download(
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
    await widget.remove();
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
          leading: Icon(widget.icon, color: theme.colorScheme.primary),
          title: Text(widget.title),
          subtitle: Text(
            _error is WifiLostException
                ? l.localOcrWifiLostIos
                : _error is DownloadStoppedInBackgroundException
                ? l.downloadStoppedInBackground
                : _error != null
                ? l.localOcrError(details: '$_error')
                : _installed == true
                ? l.localOcrModelReady
                : '${widget.description} ($_size)',
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
