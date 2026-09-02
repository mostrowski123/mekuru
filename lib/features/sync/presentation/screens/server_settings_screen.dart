import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/settings/data/services/ocr_server_config.dart'
    as server_url;
import 'package:mekuru/features/sync/data/models/remote_models.dart';
import 'package:mekuru/features/sync/presentation/providers/sync_providers.dart';
import 'package:mekuru/features/sync/presentation/screens/server_browse_screen.dart';

/// Manage Komga/Kavita server connections: add, edit, test, delete.
class ServerSettingsScreen extends ConsumerWidget {
  const ServerSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connections = ref.watch(serverConnectionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Book servers'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Sync now',
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
                  '${ServerType.displayNameOf(connection.serverType)}'
                  ' · ${connection.baseUrl}'
                  '${connection.enabled ? '' : ' · disabled'}',
                  maxLines: 2,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (connection.enabled)
                      IconButton(
                        icon: const Icon(Icons.playlist_add_check),
                        tooltip: 'Link existing books',
                        onPressed: () =>
                            _linkExisting(context, ref, connection),
                      ),
                    IconButton(
                      icon: const Icon(Icons.edit),
                      tooltip: 'Edit',
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
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Connect a self-hosted Komga or Kavita server to browse '
                  'and download its books, and keep reading progress in '
                  'sync.',
                  textAlign: TextAlign.center,
                ),
              ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Add server'),
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
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Matching your library…')),
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
                  ? 'No new matches found — books can also be linked from the '
                        'server browser'
                  : 'Linked ${result.linkedBookIds.length} books and synced '
                        'their progress',
            ),
          ),
        );
      } finally {
        client.dispose();
      }
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text('Linking failed: $e')));
    }
  }

  Future<void> _syncNow(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Syncing…')));
    final result = await ref.read(progressSyncServiceProvider).syncAll();
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          result.failed > 0
              ? 'Synced ${result.pushed} books, ${result.failed} failed'
              : result.pushed > 0
              ? 'Synced ${result.pushed} books'
              : 'Everything already in sync',
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
      if (mounted) setState(() => _testResult = 'Connection OK');
    } catch (e) {
      if (mounted) setState(() => _testResult = 'Failed: $e');
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove server?'),
        content: const Text(
          'Downloaded books and reading progress stay on this device — '
          'only the server link is removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
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
    return AlertDialog(
      title: Text(_isNew ? 'Add server' : 'Edit server'),
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
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'My server',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _urlController,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: 'Server URL',
                hintText: 'https://server:port',
                errorText: _urlError,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _secretController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: _type == ServerType.komga
                    ? 'API key (or user:password)'
                    : 'API key',
                hintText: _isNew ? null : 'Leave blank to keep current',
              ),
            ),
            if (!_isNew) ...[
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enabled'),
                value: _enabled,
                onChanged: (value) => setState(() => _enabled = value),
              ),
            ],
            if (_testResult != null) ...[
              const SizedBox(height: 8),
              Text(
                _testResult!,
                style: TextStyle(
                  color: _testResult == 'Connection OK'
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
              'Remove',
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
              : const Text('Test'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
