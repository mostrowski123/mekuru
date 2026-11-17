import 'package:flutter/material.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:path/path.dart' as p;

/// Asks which of the manga manifests ([files], `.mokuro` or `.html`) found
/// in [folderLabel] to import. Returns the ticked names in list order, or
/// null when the sheet is dismissed.
Future<List<String>?> showMangaManifestPickerSheet(
  BuildContext context, {
  required List<String> files,
  required String folderLabel,
}) => showModalBottomSheet<List<String>>(
  context: context,
  showDragHandle: true,
  builder: (_) =>
      MangaManifestPickerSheet(files: files, folderLabel: folderLabel),
);

/// Whether a file in a chosen folder is a manga manifest. A dotfile never is:
/// macOS leaves a metadata file named `._vol.mokuro` beside each file it copies
/// to a drive that isn't its own.
bool isMangaManifestName(String name) =>
    !name.startsWith('.') &&
    (_isMokuro(name) || p.extension(name).toLowerCase() == '.html');

/// The manifests ticked when the sheet opens: one per volume. mokuro can
/// write `vol.mokuro`, `vol.html` and `vol.mobile.html` for one volume; the
/// `.mokuro` wins, then the `.html`.
Set<String> defaultManifestSelection(List<String> files) {
  final best = <String, String>{};
  for (final name in files) {
    final volume = _volume(name);
    final current = best[volume];
    if (current == null || _rank(name) < _rank(current)) best[volume] = name;
  }
  return best.values.toSet();
}

bool _isMokuro(String name) => p.extension(name).toLowerCase() == '.mokuro';

bool _isMobileHtml(String name) => name.toLowerCase().endsWith('.mobile.html');

/// What [name] is a manifest of: its name without `.mokuro`, `.html` or
/// `.mobile.html`.
String _volume(String name) {
  final stem = p.basenameWithoutExtension(name.toLowerCase());
  return _isMobileHtml(name) ? p.withoutExtension(stem) : stem;
}

int _rank(String name) => _isMokuro(name)
    ? 0
    : _isMobileHtml(name)
    ? 2
    : 1;

class MangaManifestPickerSheet extends StatefulWidget {
  const MangaManifestPickerSheet({
    super.key,
    required this.files,
    required this.folderLabel,
  });

  final List<String> files;
  final String folderLabel;

  @override
  State<MangaManifestPickerSheet> createState() =>
      _MangaManifestPickerSheetState();
}

class _MangaManifestPickerSheetState extends State<MangaManifestPickerSheet> {
  late final Set<String> _chosen = defaultManifestSelection(widget.files);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.folder_open),
            title: Text(widget.folderLabel),
            subtitle: Text(
              l10n.libraryMangaFilesFound(count: widget.files.length),
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final file in widget.files)
                  CheckboxListTile(
                    value: _chosen.contains(file),
                    secondary: Icon(
                      _isMokuro(file) ? Icons.data_object : Icons.html,
                    ),
                    title: Text(file),
                    onChanged: (checked) => setState(() {
                      if (checked ?? false) {
                        _chosen.add(file);
                      } else {
                        _chosen.remove(file);
                      }
                    }),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _chosen.isEmpty
                    ? null
                    : () => Navigator.of(
                        context,
                      ).pop(widget.files.where(_chosen.contains).toList()),
                child: Text(l10n.commonImport),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
