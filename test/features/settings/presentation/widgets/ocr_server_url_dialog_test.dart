import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/settings/presentation/widgets/ocr_server_url_dialog.dart';

import '../../../../test_app.dart';

typedef _DialogResult = ({String url, String? bearerKey, bool allowSelfSigned});

/// Opens [OcrServerUrlDialog] from a button and records what it pops.
Future<List<_DialogResult?>> _openDialog(
  WidgetTester tester, {
  String initialUrl = '',
  String initialBearerKey = '',
  bool initialAllowSelfSigned = false,
}) async {
  final results = <_DialogResult?>[];
  await tester.pumpWidget(
    buildLocalizedTestApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            results.add(
              await showDialog<_DialogResult>(
                context: context,
                builder: (_) => OcrServerUrlDialog(
                  initialUrl: initialUrl,
                  initialBearerKey: initialBearerKey,
                  initialAllowSelfSigned: initialAllowSelfSigned,
                ),
              ),
            );
          },
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return results;
}

SwitchListTile _switchTile(WidgetTester tester) =>
    tester.widget<SwitchListTile>(find.byType(SwitchListTile));

void main() {
  testWidgets('shows the self-signed switch only for https, off by default', (
    tester,
  ) async {
    await _openDialog(tester);
    final toggle = find.text('Accept self-signed certificate');
    final url = find.byType(TextField).first;
    expect(toggle, findsNothing);

    await tester.enterText(url, 'http://192.168.1.5:8000');
    await tester.pump();
    expect(toggle, findsNothing);

    await tester.enterText(url, 'https://192.168.1.5:8443');
    await tester.pump();
    expect(toggle, findsOneWidget);
    expect(_switchTile(tester).value, isFalse);
  });

  testWidgets('an http URL saves the switch as off', (tester) async {
    final results = await _openDialog(
      tester,
      initialUrl: 'https://nas.local:8443',
      initialBearerKey: 'secret',
      initialAllowSelfSigned: true,
    );

    await tester.enterText(
      find.byType(TextField).first,
      'http://nas.local:8000',
    );
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(results.single?.url, 'http://nas.local:8000');
    expect(results.single?.allowSelfSigned, isFalse);
  });

  testWidgets('returns allowSelfSigned=true after toggling and saving', (
    tester,
  ) async {
    final results = await _openDialog(
      tester,
      initialUrl: 'https://nas.local:8443',
      initialBearerKey: 'secret',
    );

    await tester.tap(find.text('Accept self-signed certificate'));
    await tester.pumpAndSettle();
    expect(_switchTile(tester).value, isTrue);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(results, hasLength(1));
    expect(results.single?.url, 'https://nas.local:8443');
    expect(results.single?.bearerKey, 'secret');
    expect(results.single?.allowSelfSigned, isTrue);
  });

  testWidgets('starts from the saved value and Clear turns it off', (
    tester,
  ) async {
    await _openDialog(
      tester,
      initialUrl: 'https://nas.local:8443',
      initialBearerKey: 'secret',
      initialAllowSelfSigned: true,
    );
    expect(_switchTile(tester).value, isTrue);

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    // Cleared URL: no switch; typing https again shows it off.
    expect(find.byType(SwitchListTile), findsNothing);
    await tester.enterText(
      find.byType(TextField).first,
      'https://nas.local:8443',
    );
    await tester.pump();
    expect(_switchTile(tester).value, isFalse);
  });
}
