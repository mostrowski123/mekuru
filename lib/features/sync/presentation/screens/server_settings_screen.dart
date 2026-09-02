import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/settings/data/services/ocr_server_config.dart'
    as server_url;
import 'package:mekuru/features/sync/data/models/remote_models.dart';
import 'package:mekuru/features/sync/presentation/providers/sync_providers.dart';
import 'package:mekuru/features/sync/presentation/screens/server_browse_screen.dart';
import 'package:mekuru/l10n/l10n.dart';

/// Manage Komga/Kavita server connections: add, edit, test, delete.
class ServerSettingsScreen extends ConsumerWidget {
  const ServerSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final connections = ref.watch(serverConnectionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingsServerSyncTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: l10n.serverSettingsSyncNow,
            onPressed: () => _syncNow(context, ref),
          ),
        ],
      ),
      body: connections.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (list) => ListView(
          children: [
            for (final connection in list)
              ListTile(
                leading: Icon(
                  connection.enabled ? Icons.dns : Icons.dns_outlined,
                  color: connection.enabled
                      ? null
                      : Theme.of(context).disabledColor,
                ),
                title: Text(connection.name),
                subtitle: Text(
                  l10n.serverSettingsConnectionSubtitle(
                        serverType: ServerType.displayNameOf(
                          connection.serverType,
                        ),
                        baseUrl: connection.baseUrl,
                      ) +
                      (connection.enabled
                          ? ''
                          : ' · ${l10n.serverSettingsDisabled}'),
                  maxLines: 2,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (connection.enabled)
                      IconButton(
                        icon: const Icon(Icons.playlist_add_check),
                        tooltip: l10n.serverSettingsLinkExisting,
                        onPressed: () =>
                            _linkExisting(context, ref, connection),
                      ),
                    IconButton(
                      icon: const Icon(Icons.edit),
                      tooltip: l10n.serverSettingsEdit,
                      onPressed: () => _showConnectionDialog(
                        context,
                        ref,
                        existing: connection,
                      ),
                    ),
                  ],
                ),
                onTap: connection.enabled
                    ? () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              ServerBrowseScreen(connection: connection),
                        ),
                      )
                    : () => _showConnectionDialog(
                        context,
                        ref,
                        existing: connection,
                      ),
              ),
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l10n.serverSettingsEmptyHint,
                  textAlign: TextAlign.center,
                ),
              ),
            ListTile(
              leading: const Icon(Icons.add),
              title: Text(l10n.serverSettingsAddServer),
              onTap: () => _showConnectionDialog(context, ref),
            ),
          ],
        ),
      ),
    );
  }

  /// Bulk-match unlinked local books against the server by title, link the
  /// unique matches, and run a first sync on each (push local, adopt a
  /// newer server state).
  Future<void> _linkExisting(
    BuildContext context,
    WidgetRef ref,
    ServerConnection connection,
  ) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.serverSettingsMatching)),
    );
    // Everything is read before the first await so the work keeps going if
    // the user backs out of this screen; a throwaway client sidesteps the
    // autoDispose client provider entirely.
    final clientFactory = ref.read(serverClientFactoryProvider);
    final linker = ref.read(bookLinkServiceProvider);
    final sync = ref.read(progressSyncServiceProvider);
    try {
      final client = await clientFactory(connection);
      try {
        final result = await linker.linkExistingBooks(connection, client);
        for (final bookId in result.linkedBookIds) {
          await sync.syncBookById(bookId);
        }
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              result.linkedBookIds.isEmpty
                  ? l10n.serverSettingsNoMatches
                  : l10n.serverSettingsLinkedCount(
                      count: result.linkedBookIds.length,
                    ),
            ),
          ),
        );
      } finally {
        client.dispose();
      }
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.serverSettingsLinkFailed(error: '$e'))),
      );
    }
  }

  Future<void> _syncNow(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(content: Text(l10n.serverSettingsSyncing)));
    final result = await ref.read(progressSyncServiceProvider).syncAll();
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          result.failed > 0
              ? l10n.serverSettingsSyncedWithFailures(
                  pushed: result.pushed,
                  failed: result.failed,
                )
              : result.pushed > 0
              ? l10n.serverSettingsSynced(count: result.pushed)
              : l10n.serverSettingsAlreadyInSync,
        ),
      ),
    );
  }

  void _showConnectionDialog(
    BuildContext context,
    WidgetRef ref, {
    ServerConnection? existing,
  }) {
    showDialog<void>(
      context: context,
      builder: (_) => _ServerConnectionDialog(existing: existing),
    );
  }
}

class _ServerConnectionDialog extends ConsumerStatefulWidget {
  final ServerConnection? existing;

  const _ServerConnectionDialog({this.existing});

  @override
  ConsumerState<_ServerConnectionDialog> createState() =>
      _ServerConnectionDialogState();
}

class _ServerConnectionDialogState
    extends ConsumerState<_ServerConnectionDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  final TextEditingController _secretController = TextEditingController();
  late ServerType _type;
  late bool _enabled;
  String? _urlError;
  String? _testResult;
  bool _testOk = false;
  bool _testing = false;
  bool _saving = false;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _urlController = TextEditingController(text: existing?.baseUrl ?? '');
    _type = existing != null
        ? ServerType.fromStorage(existing.serverType)
        : ServerType.komga;
    _enabled = existing?.enabled ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _secretController.dispose();
    super.dispose();
  }

  /// The normalized server URL, or null after surfacing its validation error.
  String? _validatedUrl() {
    final url = server_url.normalizeOcrServerUrl(_urlController.text);
    final error = server_url.validateOcrServerUrl(url);
    if (error != null) setState(() => _urlError = error);
    return error == null ? url : null;
  }

  Future<void> _test() async {
    final l10n = context.l10n;
    final url = _validatedUrl();
    if (url == null) return;
    var secret = _secretController.text.trim();
    if (secret.isEmpty && widget.existing != null) {
      secret =
          await ref
              .read(serverSecretStorageProvider)
              .load(widget.existing!.id) ??
          '';
    }
    setState(() {
      _urlError = null;
      _testing = true;
      _testResult = null;
    });
    final client = buildServerClient(
      type: _type,
      baseUrl: url,
      getSecret: () => secret,
    );
    try {
      await client.testConnection();
      if (mounted) {
        setState(() {
          _testOk = true;
          _testResult = l10n.serverDialogConnectionOk;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _testOk = false;
          _testResult = l10n.serverDialogConnectionFailed(error: '$e');
        });
      }
    } finally {
      client.dispose();
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    final url = _validatedUrl();
    if (url == null) return;
    setState(() {
      _urlError = null;
      _saving = true;
    });
    final repo = ref.read(serverConnectionRepositoryProvider);
    final secrets = ref.read(serverSecretStorageProvider);
    final name = _nameController.text.trim().isEmpty
        ? _type.displayName
        : _nameController.text.trim();
    final secret = _secretController.text.trim();
    try {
      if (_isNew) {
        final id = await repo.create(
          serverType: _type.storageValue,
          name: name,
          baseUrl: url,
        );
        if (secret.isNotEmpty) await secrets.save(id, secret);
      } else {
        await repo.updateConnection(
          widget.existing!.id,
          name: name,
          baseUrl: url,
          enabled: _enabled,
        );
        // Blank secret keeps the stored one.
        if (secret.isNotEmpty) {
          await secrets.save(widget.existing!.id, secret);
        }
      }
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.serverDialogRemoveTitle),
        content: Text(l10n.serverDialogRemoveBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.commonRemove),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final id = widget.existing!.id;
    await ref.read(serverConnectionRepositoryProvider).delete(id);
    await ref.read(serverSecretStorageProvider).clear(id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(
        _isNew ? l10n.serverSettingsAddServer : l10n.serverDialogEditTitle,
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<ServerType>(
              segments: const [
                ButtonSegment(value: ServerType.komga, label: Text('Komga')),
                ButtonSegment(value: ServerType.kavita, label: Text('Kavita')),
              ],
              selected: {_type},
              onSelectionChanged: (selection) =>
                  setState(() => _type = selection.first),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: l10n.serverDialogNameLabel,
                hintText: l10n.serverDialogNameHint,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _urlController,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: l10n.serverDialogUrlLabel,
                hintText: l10n.serverDialogUrlHint,
                errorText: _urlError,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _secretController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: _type == ServerType.komga
                    ? l10n.serverDialogSecretLabelKomga
                    : l10n.serverDialogSecretLabel,
                hintText: _isNew ? null : l10n.serverDialogSecretKeepHint,
              ),
            ),
            if (!_isNew) ...[
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.serverDialogEnabled),
                value: _enabled,
                onChanged: (value) => setState(() => _enabled = value),
              ),
            ],
            if (_testResult != null) ...[
              const SizedBox(height: 8),
              Text(
                _testResult!,
                style: TextStyle(
                  color: _testOk
                      ? Colors.green
                      : Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (!_isNew)
          TextButton(
            onPressed: _saving ? null : _delete,
            child: Text(
              l10n.commonRemove,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        TextButton(
          onPressed: _testing ? null : _test,
          child: _testing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.serverDialogTest),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(l10n.commonSave),
        ),
      ],
    );
  }
}
