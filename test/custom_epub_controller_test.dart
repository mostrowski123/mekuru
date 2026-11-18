// ignore_for_file: unawaited_futures
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:mekuru/features/reader/presentation/widgets/custom_epub_controller.dart';

void main() {
  group('CustomEpubController', () {
    test('getChapters parses JavaScript results from the web view', () async {
      final platformController = _FakePlatformInAppWebViewController(
        onEvaluateJavascript: (source) async => [
          {
            'title': 'Chapter 1',
            'href': 'epubcfi(/6/2[chapter1])',
            'id': 'chapter-1',
            'subitems': [
              {
                'title': 'Section 1',
                'href': 'epubcfi(/6/4[section1])',
                'id': 'section-1',
              },
            ],
          },
        ],
      );
      final controller = CustomEpubController()
        ..attach(
          InAppWebViewController.fromPlatform(platform: platformController),
        );

      final chapters = await controller.getChapters();

      expect(platformController.evaluatedSources, ['getChapters()']);
      expect(chapters, hasLength(1));
      expect(chapters.single.title, 'Chapter 1');
      expect(chapters.single.subitems, hasLength(1));
      expect(chapters.single.subitems.single.title, 'Section 1');
    });

    test('an animated page turn is answered by its own id only', () async {
      final platformController = _FakePlatformInAppWebViewController(
        onEvaluateJavascript: (source) async => null,
      );
      final controller = CustomEpubController()
        ..attach(
          InAppWebViewController.fromPlatform(platform: platformController),
        );

      controller.next();
      controller.prev();
      var firstShown = false, secondShown = false;
      unawaited(
        controller.turnPage(forward: true).then((_) => firstShown = true),
      );
      unawaited(
        controller.turnPage(forward: false).then((_) => secondShown = true),
      );
      await _flushMicrotasks();
      expect(platformController.evaluatedSources, [
        'next()',
        'previous()',
        'next(1)',
        'previous(2)',
      ]);

      // The first turn's answer arrives late: it is not the second's.
      controller.completePageTurn(1);
      await _flushMicrotasks();
      expect([firstShown, secondShown], [false, false]);

      controller.completePageTurn(2);
      controller.completePageTurn(2);
      await _flushMicrotasks();
      expect([firstShown, secondShown], [false, true]);
    });

    test('there is no page picture without a web view', () async {
      expect(await CustomEpubController().takePagePicture(), isNull);
    });

    test(
      'MissingPluginException from getChapters detaches the stale controller',
      () async {
        final platformController = _FakePlatformInAppWebViewController(
          onEvaluateJavascript: (_) => Future<dynamic>.error(
            MissingPluginException('No implementation found'),
          ),
        );
        final controller = CustomEpubController()
          ..attach(
            InAppWebViewController.fromPlatform(platform: platformController),
          );

        await expectLater(
          controller.getChapters(),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'EPUB web view is no longer attached',
            ),
          ),
        );

        controller.next();
        await _flushMicrotasks();

        expect(platformController.evaluatedSources, ['getChapters()']);
      },
    );
  });
}

Future<void> _flushMicrotasks() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _FakePlatformInAppWebViewController
    extends PlatformInAppWebViewController {
  _FakePlatformInAppWebViewController({this.onEvaluateJavascript})
    : super.implementation(
        const PlatformInAppWebViewControllerCreationParams(id: 1),
      );

  final Future<dynamic> Function(String source)? onEvaluateJavascript;
  final List<String> evaluatedSources = <String>[];

  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) {
    evaluatedSources.add(source);
    return onEvaluateJavascript?.call(source) ?? Future<dynamic>.value(null);
  }
}
