import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/platform/network_status.dart';
import 'package:mekuru/shared/widgets/mobile_data_dialog.dart';

import '../../test_app.dart';
import '../fake_download_notifiers.dart';

void main() {
  /// Every answer [askNetwork] gave, in order.
  late List<NetworkConsent?> answers;

  Future<void> pumpAsker(WidgetTester tester) async {
    answers = [];
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => answers.add(
              await askNetwork(
                context,
                size: '55 MB',
                body: (size) => 'Mobile body $size',
              ),
            ),
            child: const Text('Ask'),
          ),
        ),
      ),
    );
  }

  Future<void> ask(WidgetTester tester) async {
    await tester.tap(find.text('Ask'));
    await tester.pumpAndSettle();
  }

  Future<void> answer(WidgetTester tester, String button) async {
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(button),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('on Wi-Fi it asks nothing: Wi-Fi only', (tester) async {
    mockWifiConnected(true);
    await pumpAsker(tester);
    await ask(tester);

    expect(find.byType(AlertDialog), findsNothing);
    expect(answers, [NetworkConsent.wifiOnly]);
  });

  testWidgets('off Wi-Fi it asks about mobile data', (tester) async {
    mockWifiConnected(false);
    await pumpAsker(tester);
    await ask(tester);

    expect(find.text('Download over mobile data?'), findsOneWidget);
    expect(find.text('Mobile body 55 MB'), findsOneWidget);
  });

  testWidgets('Download allows mobile data for that download only; Cancel '
      'and Back start nothing', (tester) async {
    mockWifiConnected(false);
    await pumpAsker(tester);

    await ask(tester);
    await answer(tester, 'Download');
    // Nothing is remembered: the next download asks again.
    await ask(tester);
    expect(find.text('Download over mobile data?'), findsOneWidget);
    await answer(tester, 'Cancel');
    await ask(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(answers, [NetworkConsent.mobileData, null, null]);
  });

  testWidgets('through a VPN it says the VPN is why it asks', (tester) async {
    mockWifiConnected(false, vpn: true);
    await pumpAsker(tester);
    await ask(tester);

    expect(find.text('Download through your VPN?'), findsOneWidget);
    expect(
      find.text(
        "You're connected through a VPN, so Mekuru can't tell whether this "
        'download (55 MB) would use mobile data.',
      ),
      findsOneWidget,
    );
    expect(find.text('Mobile body 55 MB'), findsNothing);
  });
}
