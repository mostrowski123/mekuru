import 'package:flutter/material.dart';
import 'package:mekuru/core/services/server_http_client.dart';
import 'package:mekuru/features/settings/data/services/ocr_server_config.dart'
    as ocr_server_config;
import 'package:mekuru/features/settings/data/services/ocr_server_health_client.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:url_launcher/url_launcher.dart';

class OcrServerUrlDialog extends StatefulWidget {
  const OcrServerUrlDialog({
    super.key,
    required this.initialUrl,
    required this.initialBearerKey,
    this.initialAllowSelfSigned = false,
  });

  final String initialUrl;
  final String initialBearerKey;
  final bool initialAllowSelfSigned;

  @override
  State<OcrServerUrlDialog> createState() => _OcrServerUrlDialogState();
}

class _OcrServerUrlDialogState extends State<OcrServerUrlDialog> {
  late final TextEditingController _urlController;
  late final TextEditingController _keyController;
  late bool _allowSelfSigned;

  /// The self-signed switch only matters (and only shows) for https.
  bool get _isHttps =>
      _urlController.text.trim().toLowerCase().startsWith('https://');

  bool get _effectiveAllowSelfSigned => _isHttps && _allowSelfSigned;
  bool _obscureKey = true;
  bool _isTestingConnection = false;
  bool? _testSucceeded;
  String? _testMessage;
  String? _urlError;
  String? _keyError;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.initialUrl);
    _keyController = TextEditingController(text: widget.initialBearerKey);
    _allowSelfSigned = widget.initialAllowSelfSigned;
  }

  @override
  void dispose() {
    _urlController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  void _onSave() {
    final l10n = context.l10n;
    final url = ocr_server_config.normalizeOcrServerUrl(_urlController.text);
    final customKey = _keyController.text.trim();

    // No URL means no custom server: saving it (e.g. after Clear) removes
    // the server and its key.
    if (url.isEmpty) {
      Navigator.of(
        context,
      ).pop((url: '', bearerKey: '', allowSelfSigned: false));
      return;
    }

    if (customKey.isEmpty) {
      setState(() {
        _urlError = null;
        _keyError = l10n.settingsCustomOcrServerKeyRequired;
      });
      return;
    }

    if (ocr_server_config.tryParseOcrServerUrl(url) == null) {
      setState(() {
        _urlError = l10n.settingsCustomOcrServerUrlInvalid;
        _keyError = null;
      });
      return;
    }

    Navigator.of(context).pop((
      url: url,
      bearerKey: customKey,
      allowSelfSigned: _effectiveAllowSelfSigned,
    ));
  }

  Future<void> _onTestConnection() async {
    final l10n = context.l10n;
    final url = ocr_server_config.normalizeOcrServerUrl(_urlController.text);
    if (ocr_server_config.tryParseOcrServerUrl(url) == null) {
      setState(() {
        _urlError = url.isEmpty
            ? l10n.settingsCustomOcrServerUrlRequired
            : l10n.settingsCustomOcrServerUrlInvalid;
        _testSucceeded = false;
        _testMessage = null;
      });
      return;
    }

    setState(() {
      _urlError = null;
      _isTestingConnection = true;
      _testSucceeded = null;
      _testMessage = l10n.settingsCustomOcrServerTesting;
    });

    final healthClient = OcrServerHealthClient(
      httpClient: serverHttpClient(
        url,
        allowSelfSigned: _effectiveAllowSelfSigned,
      ),
    );
    try {
      final result = await healthClient.checkHealth(url);
      if (!mounted) return;
      setState(() {
        _isTestingConnection = false;
        _testSucceeded = true;
        _testMessage = l10n.settingsCustomOcrServerHealthy(
          status: result.status,
        );
      });
    } catch (e) {
      if (!mounted) return;
      final message = isUntrustedCertificateError(e)
          ? l10n.serverCertificateUntrusted
          : e is OcrServerHealthException
          ? e.message
          : '$e';
      setState(() {
        _isTestingConnection = false;
        _testSucceeded = false;
        _testMessage = message;
      });
    } finally {
      healthClient.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return AlertDialog(
      title: Text(l10n.settingsCustomOcrServerTitle),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _urlController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: l10n.settingsCustomOcrServerUrlLabel,
                  hintText: l10n.settingsCustomOcrServerUrlHint,
                  border: const OutlineInputBorder(),
                  errorText: _urlError,
                ),
                keyboardType: TextInputType.url,
                onChanged: (_) => setState(() {
                  _urlError = null;
                  _testSucceeded = null;
                  _testMessage = null;
                }),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: () => launchUrl(
                      Uri.parse(ocr_server_config.mekuruOcrRepoUrl),
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: const Icon(Icons.open_in_new),
                    label: Text(l10n.settingsCustomOcrServerLearnHow),
                  ),
                  OutlinedButton.icon(
                    onPressed: _isTestingConnection ? null : _onTestConnection,
                    icon: _isTestingConnection
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.health_and_safety_outlined),
                    label: Text(
                      _isTestingConnection
                          ? l10n.settingsCustomOcrServerTesting
                          : l10n.settingsCustomOcrServerTestAction,
                    ),
                  ),
                ],
              ),
              if (_testMessage != null) ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _testSucceeded == true
                          ? Icons.check_circle_outline
                          : _testSucceeded == false
                          ? Icons.error_outline
                          : Icons.info_outline,
                      size: 18,
                      color: _testSucceeded == true
                          ? theme.colorScheme.primary
                          : _testSucceeded == false
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _testMessage!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: _testSucceeded == true
                              ? theme.colorScheme.primary
                              : _testSucceeded == false
                              ? theme.colorScheme.error
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (_isHttps)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.settingsCustomOcrServerAllowSelfSigned),
                  subtitle: Text(
                    l10n.settingsCustomOcrServerAllowSelfSignedSubtitle,
                  ),
                  value: _allowSelfSigned,
                  onChanged: _isTestingConnection
                      ? null
                      : (value) => setState(() {
                          _allowSelfSigned = value;
                          _testSucceeded = null;
                          _testMessage = null;
                        }),
                ),
              const SizedBox(height: 8),
              TextField(
                controller: _keyController,
                obscureText: _obscureKey,
                decoration: InputDecoration(
                  labelText: l10n.settingsCustomOcrServerKeyLabel,
                  hintText: l10n.settingsCustomOcrServerKeyHint,
                  border: const OutlineInputBorder(),
                  errorText: _keyError,
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: _obscureKey
                            ? l10n.commonShow
                            : l10n.commonHide,
                        onPressed: () {
                          setState(() {
                            _obscureKey = !_obscureKey;
                          });
                        },
                        icon: Icon(
                          _obscureKey
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                      if (_keyController.text.trim().isNotEmpty)
                        IconButton(
                          tooltip: l10n.commonClear,
                          onPressed: () {
                            _keyController.clear();
                            setState(() {
                              _keyError = null;
                            });
                          },
                          icon: const Icon(Icons.clear),
                        ),
                    ],
                  ),
                ),
                onChanged: (_) => setState(() {
                  _keyError = null;
                }),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.settingsCustomOcrServerDescription,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            _urlController.clear();
            _keyController.clear();
            setState(() {
              _allowSelfSigned = false;
              _testSucceeded = null;
              _testMessage = null;
              _urlError = null;
              _keyError = null;
            });
          },
          child: Text(l10n.commonClear),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        TextButton(onPressed: _onSave, child: Text(l10n.commonSave)),
      ],
    );
  }
}
