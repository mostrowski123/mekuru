import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/manga/data/services/ocr_billing_client.dart';
import 'package:mekuru/features/manga/presentation/providers/pro_access_provider.dart';

class _FakeBillingClient extends OcrBillingClient {
  _FakeBillingClient({this.status, this.error});

  final OcrBillingStatus? status;
  final Object? error;

  @override
  Future<OcrBillingStatus?> fetchStatusIfAuthenticated({
    bool forceRefresh = false,
  }) async {
    if (error != null) {
      throw error!;
    }
    return status;
  }

  @override
  void dispose() {}
}

void main() {
  test(
    'proUnlockedProvider returns false when no authenticated status exists',
    () async {
      final container = ProviderContainer(
        overrides: [
          ocrBillingClientProvider.overrideWithValue(
            _FakeBillingClient(status: null),
          ),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(proUnlockedProvider.future);

      expect(result, isFalse);
    },
  );

  test(
    'proUnlockedProvider returns cached/live unlock state when available',
    () async {
      final container = ProviderContainer(
        overrides: [
          ocrBillingClientProvider.overrideWithValue(
            _FakeBillingClient(
              status: const OcrBillingStatus(
                ocrUnlocked: true,
                creditBalance: 500,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(proUnlockedProvider.future);

      expect(result, isTrue);
    },
  );

  test('proUnlockedProvider returns false when status lookup fails', () async {
    final container = ProviderContainer(
      overrides: [
        ocrBillingClientProvider.overrideWithValue(
          _FakeBillingClient(
            error: const OcrBillingException(401, 'auth_required'),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final result = await container.read(proUnlockedProvider.future);

    expect(result, isFalse);
  });
}
