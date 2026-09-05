import 'dart:async';

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/services/usage_telemetry.dart';
import 'package:mekuru/features/settings/data/services/ocr_server_config.dart'
    as ocr_server_config;
import 'package:mekuru/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/services/ocr_billing_client.dart';
import '../../data/services/ocr_store_service.dart';
import '../providers/pro_access_provider.dart';

class ProUpgradeSnapshot {
  final bool isUnlocked;
  final String? priceLabel;
  final String? errorMessage;
  final bool servicesAvailable;

  const ProUpgradeSnapshot({
    required this.isUnlocked,
    required this.servicesAvailable,
    this.priceLabel,
    this.errorMessage,
  });
}

class ProUpgradeScreen extends ConsumerStatefulWidget {
  const ProUpgradeScreen({
    super.key,
    this.loadSnapshot,
    this.purchaseUpgrade,
    this.restoreUpgrade,
    this.openSelfHostRepo,
    this.forceServicesAvailable,
    this.source,
  });

  final Future<ProUpgradeSnapshot> Function()? loadSnapshot;
  final Future<ProUpgradeSnapshot> Function()? purchaseUpgrade;
  final Future<ProUpgradeSnapshot> Function()? restoreUpgrade;
  final Future<void> Function()? openSelfHostRepo;
  final bool? forceServicesAvailable;

  /// Where the screen was opened from, for usage telemetry (enum-like value,
  /// e.g. 'manga_reader' or 'ocr_setup').
  final String? source;

  @override
  ConsumerState<ProUpgradeScreen> createState() => _ProUpgradeScreenState();
}

class _ProUpgradeScreenState extends ConsumerState<ProUpgradeScreen> {
  static const _confettiShownKey = 'pro_confetti_shown';

  final OcrBillingClient _billingClient = OcrBillingClient();
  final OcrStoreService _storeService = OcrStoreService.instance;
  late final ConfettiController _confettiController;

  bool _isLoading = true;
  bool _isBusy = false;
  ProUpgradeSnapshot _snapshot = const ProUpgradeSnapshot(
    isUnlocked: false,
    servicesAvailable: true,
  );

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 3),
    );
    _storeService.onLateDelivery = _handleLateDelivery;
    final source = widget.source;
    logUsage(
      'pro.upgrade_screen_shown',
      attrs: source == null ? null : {'source': source},
    );
    unawaited(_loadSnapshot());
  }

  @override
  void dispose() {
    _storeService.onLateDelivery = null;
    _confettiController.dispose();
    _billingClient.dispose();
    super.dispose();
  }

  void _handleLateDelivery(PurchaseGrantResult result) {
    if (!mounted) return;
    final wasUnlocked = _snapshot.isUnlocked;
    setState(() {
      _snapshot = ProUpgradeSnapshot(
        isUnlocked: result.ocrUnlocked,
        priceLabel: _snapshot.priceLabel,
        servicesAvailable: _snapshot.servicesAvailable,
      );
    });
    ref.invalidate(proUnlockedProvider);

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.proPurchaseConfirmed)));
    if (!wasUnlocked && result.ocrUnlocked) {
      logUsage('pro.purchase_completed');
      unawaited(_maybeShowConfetti());
    }
  }

  Future<void> _loadSnapshot() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    final snapshot = widget.loadSnapshot != null
        ? await widget.loadSnapshot!()
        : await _loadSnapshotDefault();

    if (!mounted) return;
    setState(() {
      _snapshot = snapshot;
      _isLoading = false;
    });
  }

  // Runs synchronously from initState, so it must stay context-free; the
  // store-unavailable message is localized in build() instead.
  Future<ProUpgradeSnapshot> _loadSnapshotDefault() async {
    String? errorMessage;
    String? priceLabel;

    try {
      await _storeService.initialize();
    } catch (e) {
      errorMessage ??= 'Failed to initialize Google Play billing: $e';
    }

    final servicesAvailable =
        widget.forceServicesAvailable ?? _storeService.isStoreAvailable;

    final localStatus = await _billingClient.readLastKnownStatus();
    var unlocked = localStatus?.ocrUnlocked ?? false;

    if (servicesAvailable) {
      try {
        final status = await _billingClient.refreshStatusIfAuthenticated(
          forceRefresh: localStatus == null || !unlocked,
        );
        unlocked = status?.ocrUnlocked ?? unlocked;
      } catch (e) {
        if (!unlocked) {
          errorMessage ??= 'Failed to load your Pro access: $e';
        }
      }

      try {
        final products = await _storeService.queryProducts(
          ocrVisibleProductIds,
        );
        priceLabel = products[proUnlockProductId]?.price;
      } catch (e) {
        errorMessage ??= 'Failed to load Google Play pricing: $e';
      }
    }

    return ProUpgradeSnapshot(
      isUnlocked: unlocked,
      priceLabel: priceLabel,
      errorMessage: errorMessage,
      servicesAvailable: servicesAvailable,
    );
  }

  Future<void> _runBusyAction(
    Future<ProUpgradeSnapshot> Function() action,
  ) async {
    if (_isBusy) return;

    setState(() {
      _isBusy = true;
    });

    try {
      final wasUnlocked = _snapshot.isUnlocked;
      final snapshot = await action();
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
      });
      ref.invalidate(proUnlockedProvider);

      if (!wasUnlocked && snapshot.isUnlocked) {
        unawaited(_maybeShowConfetti());
      }
    } catch (e) {
      if (!mounted) return;
      final isPending =
          e is OcrBillingException && e.code == 'purchase_pending';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(describeOcrError(e)),
          duration: isPending
              ? const Duration(seconds: 5)
              : const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _handlePurchase() {
    logUsage('pro.purchase_started');
    final wasUnlocked = _snapshot.isUnlocked;
    return _runBusyAction(() async {
      try {
        final snapshot = await (widget.purchaseUpgrade ?? _purchaseDefault)();
        if (!wasUnlocked && snapshot.isUnlocked) {
          logUsage('pro.purchase_completed');
        }
        return snapshot;
      } catch (e) {
        final cancellationStage = userCancellationStage(e);
        if (cancellationStage != null) {
          logUsage(
            'pro.purchase_cancelled',
            attrs: {'stage': cancellationStage},
          );
        } else if (e is! OcrBillingException || e.code != 'purchase_pending') {
          // Pending purchases resolve later via the late-delivery callback.
          logFailure('pro.purchase_failed', e);
        }
        rethrow;
      }
    });
  }

  Future<void> _handleRestore() {
    return _runBusyAction(() async {
      try {
        final snapshot = await (widget.restoreUpgrade ?? _restoreDefault)();
        logUsage('pro.restore', attrs: {'result': 'ok'});
        return snapshot;
      } catch (e) {
        logUsage(
          'pro.restore',
          attrs: {
            'result': userCancellationStage(e) == null ? 'error' : 'cancelled',
          },
        );
        rethrow;
      }
    });
  }

  Future<void> _maybeShowConfetti() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_confettiShownKey) ?? false) return;
    await prefs.setBool(_confettiShownKey, true);
    if (!mounted) return;
    _confettiController.play();
  }

  Future<ProUpgradeSnapshot> _purchaseDefault() async {
    final result = await _storeService.purchaseProduct(proUnlockProductId);
    return ProUpgradeSnapshot(
      isUnlocked: result.ocrUnlocked,
      priceLabel: _snapshot.priceLabel,
      servicesAvailable: _snapshot.servicesAvailable,
    );
  }

  Future<ProUpgradeSnapshot> _restoreDefault() async {
    final result = await _storeService.restorePurchases();
    return ProUpgradeSnapshot(
      isUnlocked: result.ocrUnlocked,
      priceLabel: _snapshot.priceLabel,
      servicesAvailable: _snapshot.servicesAvailable,
    );
  }

  Future<void> _openSelfHostRepo() async {
    if (widget.openSelfHostRepo != null) {
      await widget.openSelfHostRepo!();
      return;
    }

    await launchUrl(
      Uri.parse(ocr_server_config.mekuruOcrRepoUrl),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final buttonLabel = _snapshot.priceLabel == null
        ? l10n.proUnlock
        : l10n.proUnlockWithPrice(price: _snapshot.priceLabel!);
    // Mirrors the pre-existing precedence: on a locked install without Play
    // billing, the unavailable notice wins over any load error.
    final errorMessage = !_snapshot.servicesAvailable && !_snapshot.isUnlocked
        ? l10n.settingsProUnavailableSubtitle
        : _snapshot.errorMessage;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.proTitle)),
      body: Stack(
        children: [
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_snapshot.isUnlocked) ...[
                      Card(
                        color: theme.colorScheme.primaryContainer,
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          leading: Icon(
                            Icons.verified,
                            size: 40,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                          title: Text(
                            l10n.proActiveTitle,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                          subtitle: Text(
                            l10n.proActiveSubtitle,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.proUnlockOnceTitle,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 12,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Chip(
                                  avatar: Icon(
                                    _snapshot.isUnlocked
                                        ? Icons.lock_open_outlined
                                        : Icons.lock_outline,
                                    size: 18,
                                  ),
                                  label: Text(
                                    _snapshot.isUnlocked
                                        ? l10n.proStatusUnlocked
                                        : l10n.proStatusLocked,
                                  ),
                                ),
                                Text(
                                  l10n.proUnlockDescription,
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: !_snapshot.servicesAvailable || _isBusy
                                  ? null
                                  : () => _handleRestore(),
                              icon: const Icon(Icons.refresh),
                              label: Text(l10n.proRestorePurchase),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        errorMessage,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    _ProFeatureCard(
                      icon: Icons.crop,
                      title: l10n.proFeatureAutoCropTitle,
                      description: l10n.proFeatureAutoCropDescription,
                    ),
                    const SizedBox(height: 12),
                    _ProFeatureCard(
                      icon: Icons.highlight,
                      title: l10n.proFeatureHighlightsTitle,
                      description: l10n.proFeatureHighlightsDescription,
                    ),
                    const SizedBox(height: 12),
                    _ProFeatureCard(
                      icon: Icons.document_scanner_outlined,
                      title: l10n.proFeatureCustomOcrTitle,
                      description: l10n.proFeatureCustomOcrDescription,
                      trailing: TextButton.icon(
                        onPressed: _openSelfHostRepo,
                        icon: const Icon(Icons.open_in_new),
                        label: Text(l10n.proServerRepo),
                      ),
                    ),
                    if (!_snapshot.isUnlocked) ...[
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: !_snapshot.servicesAvailable || _isBusy
                              ? null
                              : () => _handlePurchase(),
                          child: _isBusy
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(buttonLabel),
                        ),
                      ),
                    ],
                  ],
                ),
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              emissionFrequency: 0.05,
              numberOfParticles: 20,
              maxBlastForce: 30,
              minBlastForce: 10,
              gravity: 0.15,
              colors: [
                theme.colorScheme.primary,
                theme.colorScheme.secondary,
                theme.colorScheme.tertiary,
                Colors.amber,
                Colors.pinkAccent,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> openProUpgrade(
  BuildContext context,
  WidgetRef ref, {
  String? source,
}) async {
  await Navigator.of(context).push(
    MaterialPageRoute(
      settings: const RouteSettings(name: 'pro_upgrade'),
      builder: (_) => ProUpgradeScreen(source: source),
    ),
  );
  ref.invalidate(proUnlockedProvider);
}

class _ProFeatureCard extends StatelessWidget {
  const _ProFeatureCard({
    required this.icon,
    required this.title,
    required this.description,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trailing = this.trailing;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                ...switch (trailing) {
                  final trailing? => [trailing],
                  null => const <Widget>[],
                },
              ],
            ),
            const SizedBox(height: 8),
            Text(description, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
