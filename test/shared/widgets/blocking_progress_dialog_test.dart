import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/shared/widgets/blocking_progress_dialog.dart';

void main() {
  testWidgets('the spinner closes after the widget that opened it is gone', (
    tester,
  ) async {
    final showOpener = ValueNotifier(true);
    addTearDown(showOpener.dispose);
    late VoidCallback close;
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: showOpener,
          builder: (_, show, _) => show
              ? Builder(
                  builder: (context) => TextButton(
                    onPressed: () =>
                        close = showBlockingProgressDialog(context, 'Working'),
                    child: const Text('Start'),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ),
    );
    await tester.tap(find.text('Start'));
    // The spinner never settles: pump past the dialog animation.
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Working'), findsOneWidget);

    // A library tile can be rebuilt while its export runs.
    showOpener.value = false;
    await tester.pump();
    close();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Working'), findsNothing);
  });
}
