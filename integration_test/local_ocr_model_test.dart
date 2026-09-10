import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:local_manga_ocr/local_manga_ocr.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Opt-in only: push pinned models and local evaluation crops first.
/// This file never downloads data and is excluded from routine emulator CI.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'pinned Baberu inference on Android',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('Local model evaluation'))),
      );
      final support = await getApplicationSupportDirectory();
      final manifest = File(
        p.join(
          support.path,
          const String.fromEnvironment(
            'OCR_EVALUATION_DIR',
            defaultValue: 'ocr_evaluation',
          ),
          'inputs.json',
        ),
      );
      final deadline = DateTime.now().add(const Duration(minutes: 2));
      // flutter test installs a fresh test application. The host stages the
      // private archive using run-as once that package is installed.
      while (!await manifest.exists() && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      expect(
        await manifest.exists(),
        true,
        reason: 'Stage the private evaluation archive with adb run-as.',
      );
      final result = await LocalMangaOcr.channel
          .invokeMapMethod<String, dynamic>('test.evaluate', {
            'manifestPath': manifest.path,
            'mode': const String.fromEnvironment(
              'OCR_EVALUATION_MODE',
              defaultValue: 'crops',
            ),
          });
      expect(result?['status'], 'completed');
      expect(result?['completed'], result?['total']);
      // Optional, human-checked geometry expectations from the private input
      // manifest. Completion alone would not catch the ARM line-map failure.
      final inputs = jsonDecode(await manifest.readAsString()) as List;
      final expected = inputs
          .where((row) => (row as Map).containsKey('expectedLineCount'))
          .toList();
      if (expected.isNotEmpty) {
        final rows = await File(
          p.join(manifest.parent.path, 'predictions.jsonl'),
        ).readAsLines();
        final byId = {
          for (final line in rows)
            (jsonDecode(line) as Map)['id']: jsonDecode(line) as Map,
        };
        for (final row in expected) {
          final blocks = byId[(row as Map)['id']]!['blocks'] as List;
          final lines = blocks.fold<int>(
            0,
            (count, block) =>
                count + ((block as Map)['linesCoords'] as List).length,
          );
          expect(
            lines,
            row['expectedLineCount'],
            reason: 'Line geometry for ${row['id']}',
          );
          if (row['expectedVertical'] == true) {
            expect(
              blocks.every((block) => (block as Map)['vertical'] == true),
              true,
              reason: 'Vertical reading order for ${row['id']}',
            );
          }
        }
      }
      // Captured in the private host log before flutter test removes its app.
      // ignore: avoid_print
      print('OCR_EVALUATION_RESULT ${jsonEncode(result)}');
      // Give the private host monitor time to retain the final streamed rows
      // before flutter test uninstalls its temporary application.
      await Future<void>.delayed(const Duration(seconds: 3));
    },
    skip: !const bool.fromEnvironment('OCR_MODEL_EVALUATION'),
    timeout: const Timeout(Duration(hours: 3)),
  );
}
