import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mekuru/l10n/l10n.dart';
import 'package:mekuru/shared/utils/app_routes.dart';
import 'package:url_launcher/url_launcher.dart';

/// License text is installed with the app, even before downloading any weights.
class OcrAttributions extends StatelessWidget {
  const OcrAttributions({super.key});
  static const mangaOcrRepoUrl = 'https://github.com/kha-white/manga-ocr';
  static const detectorRepoUrl =
      'https://github.com/dmMaze/comic-text-detector';
  static const licenseFiles = [
    'MANGA-OCR.txt',
    'APACHE-2.0.txt',
    'COMIC-TEXT-DETECTOR.txt',
    'GPL-3.0.txt',
    'ONNXRUNTIME.txt',
    'ONNXRUNTIME-THIRD-PARTY.txt',
    'OPENCV.txt',
    'OPENCV-THIRD-PARTY.txt',
  ];
  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.localOcrLicenseTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(l.localOcrLicenseRecognizer),
            const SizedBox(height: 8),
            Text(l.localOcrLicenseDetector),
            const SizedBox(height: 8),
            Text(l.localOcrLicenseRuntime),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () => launchUrl(
                    Uri.parse(mangaOcrRepoUrl),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: const Text('manga-ocr'),
                ),
                TextButton(
                  onPressed: () => launchUrl(
                    Uri.parse(detectorRepoUrl),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: const Text('Comic Text Detector'),
                ),
              ],
            ),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                namedRoute('ocr_licenses', (_) => const OcrLicenseScreen()),
              ),
              child: Text(l.localOcrLicenseOpen),
            ),
          ],
        ),
      ),
    );
  }
}

class OcrLicenseScreen extends StatelessWidget {
  const OcrLicenseScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.l10n.localOcrLicenseTitle)),
    body: ListView(
      children: [
        for (final file in OcrAttributions.licenseFiles)
          ExpansionTile(
            title: Text(file),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: FutureBuilder<String>(
                  future: rootBundle.loadString(
                    'packages/local_manga_ocr/assets/licenses/$file',
                    cache: false,
                  ),
                  builder: (context, snapshot) => snapshot.hasData
                      ? Text(snapshot.data!)
                      : snapshot.hasError
                      ? Text(
                          context.l10n.localOcrError(
                            details: snapshot.error.toString(),
                          ),
                        )
                      : const LinearProgressIndicator(),
                ),
              ),
            ],
          ),
      ],
    ),
  );
}
