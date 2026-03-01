import 'dart:async';

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:mekuru/features/settings/data/services/ocr_server_config.dart'
    as ocr_server_config;
import 'package:url_launcher/url_launcher.dart';

import '../../data/services/ocr_account_link_service.dart';
import '../../data/services/ocr_billing_client.dart';
import '../../data/services/ocr_store_service.dart';

class OcrPurchasesScreen extends StatefulWidget {
  const OcrPurchasesScreen({super.key});

  @override
  State<OcrPurchasesScreen> createState() => _OcrPurchasesScreenState();
}

class _OcrPurchasesScreenState extends State<OcrPurchasesScreen> {
  final OcrAccountLinkService _accountLinkService = OcrAccountLinkService();
  final OcrBillingClient _billingClient = OcrBillingClient();
  final OcrStoreService _storeService = OcrStoreService.instance;

  bool _isLoading = true;
  bool _isBusy = false;
  String? _errorMessage;
  OcrBillingStatus? _status;
  Map<String, ProductDetails> _products = const {};

  @override
  void initState() {
    super.initState();
    unawaited(_loadStoreData());
  }

  @override
  void dispose() {
    _billingClient.dispose();
    super.dispose();
  }

  Future<void> _loadStoreData() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    var nextStatus = _status;
    var nextProducts = _products;
    String? nextError;

    try {
      await _storeService.initialize();
    } catch (e) {
      nextError ??= 'Failed to initialize Google Play billing: $e';
    }

    try {
      nextStatus = await _billingClient.readCachedStatus();
    } catch (e) {
      nextError ??= 'Failed to load your cached OCR billing status: $e';
    }

    try {
      nextProducts = await _storeService.queryProducts(ocrVisibleProductIds);
    } catch (e) {
      nextError ??= 'Failed to load Google Play products: $e';
    }

    if (!mounted) return;

    setState(() {
      _status =
          nextStatus ??
          const OcrBillingStatus(ocrUnlocked: false, creditBalance: 0);
      _products = nextProducts;
      _errorMessage = nextError;
      _isLoading = false;
    });
  }

  Future<void> _runBusyAction(Future<void> Function() action) async {
    if (_isBusy) return;

    setState(() {
      _isBusy = true;
    });

    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _purchaseUnlock() async {
    await _runBusyAction(() async {
      final linkResult = await _accountLinkService.ensureLinkedAccount();
      if (linkResult.linkedThisCall) {
        final restoredStatus = await _storeService.restorePurchases();

        if (!mounted) return;

        setState(() {
          _status = restoredStatus;
        });

        if (restoredStatus.ocrUnlocked) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                linkResult.user.email == null
                    ? 'Google account linked. OCR purchases refreshed.'
                    : 'Signed in as ${linkResult.user.email}. Purchases refreshed.',
              ),
            ),
          );
          return;
        }
      }

      final result = await _storeService.purchaseProduct(ocrUnlockProductId);

      if (!mounted) return;

      setState(() {
        _status = OcrBillingStatus(
          ocrUnlocked: result.ocrUnlocked,
          creditBalance: result.creditBalance,
        );
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('OCR unlocked. 250 starter credits added.'),
        ),
      );
    });
  }

  Future<void> _restorePurchases() async {
    await _runBusyAction(() async {
      final linkResult = await _accountLinkService.ensureLinkedAccount();
      final status = await _storeService.restorePurchases();

      if (!mounted) return;

      setState(() {
        _status = status;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(
          content: Text(
            linkResult.linkedThisCall
                ? 'Google account linked. Purchases refreshed.'
                : 'Purchases refreshed.',
          ),
        ),
      );
    });
  }

  Future<void> _refreshStatusFromServer() async {
    await _runBusyAction(() async {
      final status = await _billingClient.fetchStatus(forceRefresh: true);

      if (!mounted) return;

      setState(() {
        _status = status;
        _errorMessage = null;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Page credits refreshed.')));
    });
  }

  Future<void> _openSelfHostRepo() async {
    await launchUrl(
      Uri.parse(ocr_server_config.mekuruOcrRepoUrl),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status =
        _status ?? const OcrBillingStatus(ocrUnlocked: false, creditBalance: 0);

    return Scaffold(
      appBar: AppBar(title: const Text('OCR Purchases')),
      body: _isLoading
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
                          'OCR Access',
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
                                status.ocrUnlocked
                                    ? Icons.lock_open_outlined
                                    : Icons.lock_outline,
                                size: 18,
                              ),
                              label: Text(
                                status.ocrUnlocked ? 'Unlocked' : 'Locked',
                              ),
                            ),
                            Text(
                              '${status.creditBalance} page credits available',
                              style: theme.textTheme.bodyMedium,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _isBusy ? null : _restorePurchases,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Restore Purchases'),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _errorMessage!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  'Unlock OCR',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                _PurchaseCard(
                  title: 'OCR Unlock',
                  description:
                      'One-time unlock for OCR. Includes 250 starter credits.',
                  price: _products[ocrUnlockProductId]?.price,
                  buttonLabel: status.ocrUnlocked
                      ? 'Already Unlocked'
                      : _buttonPriceLabel(
                          _products[ocrUnlockProductId],
                          fallback: 'Unlock',
                        ),
                  onPressed:
                      _isBusy ||
                          status.ocrUnlocked ||
                          _products[ocrUnlockProductId] == null
                      ? null
                      : _purchaseUnlock,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Page Credits',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _isBusy ? null : _refreshStatusFromServer,
                      tooltip: 'Refresh credits',
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${status.creditBalance} page credits available',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Page credits are only used on the Mekuru OCR '
                          'server. Custom OCR servers do not consume page '
                          'credits.',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.terminal_outlined),
                    title: const Text('Run your own OCR server'),
                    subtitle: const Text(
                      'See setup instructions on GitHub.',
                    ),
                    trailing: const Icon(Icons.open_in_new),
                    onTap: _openSelfHostRepo,
                  ),
                ),
              ],
            ),
    );
  }

  static String _buttonPriceLabel(
    ProductDetails? product, {
    required String fallback,
  }) {
    if (product == null) return 'Unavailable';
    return '$fallback ${product.price}';
  }
}

class _PurchaseCard extends StatelessWidget {
  final String title;
  final String description;
  final String? price;
  final String buttonLabel;
  final VoidCallback? onPressed;

  const _PurchaseCard({
    required this.title,
    required this.description,
    required this.price,
    required this.buttonLabel,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (price != null)
                  Text(
                    price!,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(description, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onPressed,
                child: Text(buttonLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
