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

/// The manifests ticked when the sheet opens: one per volume. mokuro can
/// write both `vol.mokuro` and `vol.html` for one volume; the `.mokuro`
/// wins, and an `.html` is ticked only when its volume has no `.mokuro`.
Set<String> defaultManifestSelection(List<String> files) {
  final mokuroStems = {
    for (final name in files.where(_isMokuro))
      p.basenameWithoutExtension(name).toLowerCase(),
  };
  return {
    for (final name in files)
      if (_isMokuro(name) ||
          !mokuroStems.contains(p.basenameWithoutExtension(name).toLowerCase()))
        name,
  };
}

bool _isMokuro(String name) => p.extension(name).toLowerCase() == '.mokuro';

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
