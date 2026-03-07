import 'dart:async';

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mekuru/core/services/firebase_runtime.dart';
import 'package:mekuru/features/settings/data/services/ocr_server_config.dart'
    as ocr_server_config;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/services/ocr_account_link_service.dart';
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
  });

  final Future<ProUpgradeSnapshot> Function()? loadSnapshot;
  final Future<ProUpgradeSnapshot> Function()? purchaseUpgrade;
  final Future<ProUpgradeSnapshot> Function()? restoreUpgrade;
  final Future<void> Function()? openSelfHostRepo;
  final bool? forceServicesAvailable;

  @override
  ConsumerState<ProUpgradeScreen> createState() => _ProUpgradeScreenState();
}

class _ProUpgradeScreenState extends ConsumerState<ProUpgradeScreen> {
  static const _confettiShownKey = 'pro_confetti_shown';

  final OcrAccountLinkService _accountLinkService = OcrAccountLinkService();
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

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Your purchase has been confirmed!')),
    );
    if (!wasUnlocked && result.ocrUnlocked) {
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

  Future<ProUpgradeSnapshot> _loadSnapshotDefault() async {
    final servicesAvailable =
        widget.forceServicesAvailable ??
        FirebaseRuntime.instance.hasFirebaseApp;
    if (!servicesAvailable) {
      return const ProUpgradeSnapshot(
        isUnlocked: false,
        servicesAvailable: false,
        errorMessage: 'Mekuru services are temporarily unavailable.',
      );
    }

    String? errorMessage;
    String? priceLabel;
    var unlocked = false;

    try {
      await _storeService.initialize();
    } catch (e) {
      errorMessage ??= 'Failed to initialize Google Play billing: $e';
    }

    try {
      final status = await _billingClient.fetchStatusIfAuthenticated();
      unlocked = status?.ocrUnlocked ?? false;
    } catch (e) {
      errorMessage ??= 'Failed to load your Pro access: $e';
    }

    try {
      final products = await _storeService.queryProducts(ocrVisibleProductIds);
      priceLabel = products[proUnlockProductId]?.price;
    } catch (e) {
      errorMessage ??= 'Failed to load Google Play pricing: $e';
    }

    return ProUpgradeSnapshot(
      isUnlocked: unlocked,
      priceLabel: priceLabel,
      errorMessage: errorMessage,
      servicesAvailable: true,
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

  Future<void> _maybeShowConfetti() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_confettiShownKey) ?? false) return;
    await prefs.setBool(_confettiShownKey, true);
    if (!mounted) return;
    _confettiController.play();
  }

  Future<ProUpgradeSnapshot> _purchaseDefault() async {
    await _accountLinkService.ensureLinkedAccount();
    final result = await _storeService.purchaseProduct(proUnlockProductId);
    return ProUpgradeSnapshot(
      isUnlocked: result.ocrUnlocked,
      priceLabel: _snapshot.priceLabel,
      servicesAvailable: _snapshot.servicesAvailable,
    );
  }

  Future<ProUpgradeSnapshot> _restoreDefault() async {
    await _accountLinkService.ensureLinkedAccount();
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
    final theme = Theme.of(context);
    final buttonLabel = _snapshot.isUnlocked
        ? 'Already Unlocked'
        : _snapshot.priceLabel == null
        ? 'Unlock Pro'
        : 'Unlock Pro ${_snapshot.priceLabel}';

    return Scaffold(
      appBar: AppBar(title: const Text('Pro')),
      body: Stack(
        children: [
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Unlock Pro once',
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
                                        ? 'Unlocked'
                                        : 'Locked',
                                  ),
                                ),
                                Text(
                                  'One-time purchase for reader power features.',
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: !_snapshot.servicesAvailable || _isBusy
                                  ? null
                                  : () => _runBusyAction(
                                      widget.restoreUpgrade ?? _restoreDefault,
                                    ),
                              icon: const Icon(Icons.refresh),
                              label: const Text('Restore Purchase'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_snapshot.errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _snapshot.errorMessage!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    _ProFeatureCard(
                      icon: Icons.crop,
                      title: 'Auto-Crop',
                      description:
                          'Trim empty manga page margins after a one-time setup per book.',
                    ),
                    const SizedBox(height: 12),
                    _ProFeatureCard(
                      icon: Icons.highlight,
                      title: 'Book Highlights',
                      description:
                          'Save and review highlighted passages while reading EPUB books.',
                    ),
                    const SizedBox(height: 12),
                    _ProFeatureCard(
                      icon: Icons.document_scanner_outlined,
                      title: 'Custom OCR Server',
                      description:
                          'Run remote manga OCR with your own server and shared key.',
                      trailing: TextButton.icon(
                        onPressed: _openSelfHostRepo,
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Server Repo'),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed:
                            !_snapshot.servicesAvailable ||
                                _isBusy ||
                                _snapshot.isUnlocked
                            ? null
                            : () => _runBusyAction(
                                widget.purchaseUpgrade ?? _purchaseDefault,
                              ),
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

Future<void> openProUpgrade(BuildContext context, WidgetRef ref) async {
  await Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const ProUpgradeScreen()));
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
