import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/wanikani/data/models/wanikani_snapshot.dart';
import 'package:mekuru/features/wanikani/data/services/wanikani_api_client.dart';
import 'package:mekuru/features/wanikani/presentation/providers/wanikani_providers.dart';
import 'package:mekuru/l10n/generated/app_localizations.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/utils/haptics.dart';
import 'package:url_launcher/url_launcher.dart';

/// User-facing text for a failed link or sync. Only the token rejection and
/// the two transient conditions get their own wording; everything else
/// (server errors, malformed payloads) is "try again later".
String wanikaniErrorMessage(AppLocalizations l10n, Object error) {
  final code = error is WanikaniException ? error.code : null;
  return switch (code) {
    WanikaniException.tokenInvalid => l10n.wanikaniErrorTokenInvalid,
    WanikaniException.network => l10n.wanikaniErrorNetwork,
    WanikaniException.rateLimited => l10n.wanikaniErrorRateLimited,
    _ => l10n.wanikaniErrorGeneric,
  };
}

/// Link, refresh, or unlink the WaniKani account that drives the reader's
/// WaniKani furigana mode.
class WanikaniSettingsScreen extends ConsumerStatefulWidget {
  const WanikaniSettingsScreen({super.key});

  @override
  ConsumerState<WanikaniSettingsScreen> createState() =>
      _WanikaniSettingsScreenState();
}

class _WanikaniSettingsScreenState
    extends ConsumerState<WanikaniSettingsScreen> {
  final _tokenController = TextEditingController();
  bool _obscureToken = true;
  bool _linking = false;
  String? _linkError;

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _openTokenPage() async {
    AppHaptics.light();
    logUsage('wanikani.token_page_opened');
    await launchUrl(
      WanikaniApiClient.tokenPageUrl,
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _link() async {
    final l10n = context.l10n;
    AppHaptics.light();
    setState(() {
      _linking = true;
      _linkError = null;
    });
    try {
      await ref.read(wanikaniProvider.notifier).link(_tokenController.text);
      _tokenController.clear();
    } catch (e) {
      if (!mounted) return;
      setState(() => _linkError = wanikaniErrorMessage(l10n, e));
    } finally {
      if (mounted) setState(() => _linking = false);
    }
  }

  Future<void> _syncNow() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    AppHaptics.light();
    try {
      await ref.read(wanikaniProvider.notifier).syncNow();
      final count = ref.read(wanikaniProvider).stages.length;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.wanikaniSettingsSyncDone(count: count))),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(wanikaniErrorMessage(l10n, e))),
      );
    }
  }

  Future<void> _unlink() async {
    final l10n = context.l10n;
    AppHaptics.light();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.wanikaniSettingsUnlink),
        content: Text(l10n.wanikaniSettingsUnlinkConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.wanikaniSettingsUnlink),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(wanikaniProvider.notifier).unlink();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final state = ref.watch(wanikaniProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.readerFuriganaWanikani)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l10n.wanikaniSettingsIntro, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 16),
          if (state.linked)
            _LinkedSection(
              state: state,
              onSyncNow: state.syncing ? null : _syncNow,
              onUnlink: state.syncing ? null : _unlink,
            )
          else
            _LinkSection(
              controller: _tokenController,
              obscure: _obscureToken,
              onToggleObscure: () =>
                  setState(() => _obscureToken = !_obscureToken),
              linking: _linking,
              error: _linkError,
              restoredSnapshot: state.snapshot,
              onGetToken: _openTokenPage,
              onLink: _link,
            ),
          const SizedBox(height: 24),
          Text(
            l10n.wanikaniSettingsThresholdCaption,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkedSection extends StatelessWidget {
  const _LinkedSection({
    required this.state,
    required this.onSyncNow,
    required this.onUnlink,
  });

  final WanikaniState state;
  final VoidCallback? onSyncNow;
  final VoidCallback? onUnlink;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final snapshot = state.snapshot;
    final syncedAt = snapshot?.syncedAt.toLocal();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.check_circle, color: theme.colorScheme.primary),
          title: Text(
            l10n.settingsWanikaniLinkedAs(username: snapshot?.username ?? ''),
          ),
          subtitle: snapshot == null
              ? null
              : Text(
                  '${l10n.wanikaniSettingsStatus(level: snapshot.level, count: snapshot.stages.length)}\n'
                  '${l10n.wanikaniSettingsLastSynced(time: DateFormat.yMd(l10n.localeName).add_jm().format(syncedAt!))}',
                ),
          isThreeLine: snapshot != null,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                key: const Key('wanikani-sync-now'),
                onPressed: onSyncNow,
                icon: state.syncing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync),
                label: Text(l10n.wanikaniSettingsSyncNow),
              ),
            ),
            const SizedBox(width: 12),
            TextButton(
              key: const Key('wanikani-unlink'),
              onPressed: onUnlink,
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              child: Text(l10n.wanikaniSettingsUnlink),
            ),
          ],
        ),
      ],
    );
  }
}

class _LinkSection extends StatelessWidget {
  const _LinkSection({
    required this.controller,
    required this.obscure,
    required this.onToggleObscure,
    required this.linking,
    required this.error,
    required this.restoredSnapshot,
    required this.onGetToken,
    required this.onLink,
  });

  final TextEditingController controller;
  final bool obscure;
  final VoidCallback onToggleObscure;
  final bool linking;
  final String? error;
  final WanikaniSnapshot? restoredSnapshot;
  final VoidCallback onGetToken;
  final VoidCallback onLink;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (restoredSnapshot != null) ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.restore,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            title: Text(l10n.wanikaniSettingsRestoredNoToken),
            subtitle: Text(
              l10n.wanikaniSettingsStatus(
                level: restoredSnapshot!.level,
                count: restoredSnapshot!.stages.length,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        TextField(
          key: const Key('wanikani-token-field'),
          controller: controller,
          obscureText: obscure,
          autocorrect: false,
          enableSuggestions: false,
          enabled: !linking,
          decoration: InputDecoration(
            labelText: l10n.wanikaniSettingsTokenLabel,
            errorText: error,
            errorMaxLines: 3,
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
              onPressed: onToggleObscure,
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const Key('wanikani-get-token'),
            onPressed: onGetToken,
            icon: const Icon(Icons.open_in_new),
            label: Text(l10n.wanikaniSettingsGetToken),
          ),
        ),
        const SizedBox(height: 8),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) => FilledButton.icon(
            key: const Key('wanikani-link'),
            onPressed: linking || value.text.trim().isEmpty ? null : onLink,
            icon: linking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.link),
            label: Text(l10n.wanikaniSettingsLink),
          ),
        ),
      ],
    );
  }
}
