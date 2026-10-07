import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/shared/widgets/mobile_data_dialog.dart';

import '../../test_app.dart';
import '../fake_download_notifiers.dart';

void main() {
  Future<void> ask(WidgetTester tester) async {
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                confirmMobileData(context, size: '55 MB', body: 'Mobile body'),
            child: const Text('Ask'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Ask'));
    await tester.pumpAndSettle();
  }

  testWidgets('off Wi-Fi it asks about mobile data', (tester) async {
    mockWifiConnected(false);
    await ask(tester);

    expect(find.text('Download over mobile data?'), findsOneWidget);
    expect(find.text('Mobile body'), findsOneWidget);
  });

  testWidgets('through a VPN it says the VPN is why it asks', (tester) async {
    mockWifiConnected(false, vpn: true);
    await ask(tester);

    expect(find.text('Download through your VPN?'), findsOneWidget);
    expect(
      find.text(
        "You're connected through a VPN, so Mekuru can't tell whether this "
        'download (55 MB) would use mobile data.',
      ),
      findsOneWidget,
    );
    expect(find.text('Mobile body'), findsNothing);
  });
}
