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
      bool? firstShown, secondShown;
      unawaited(
        controller.turnPage(forward: true).then((came) => firstShown = came),
      );
      unawaited(
        controller.turnPage(forward: false).then((came) => secondShown = came),
      );
      await _flushMicrotasks();
      expect(platformController.evaluatedSources, [
        'next()',
        'previous()',
        'next(1)',
        'previous(2)',
      ]);

      // The first turn's answer arrives late: it is not the second's.
      controller.completePageTurn(1, turned: true);
      await _flushMicrotasks();
      expect([firstShown, secondShown], [null, null]);

      controller.completePageTurn(2, turned: true);
      controller.completePageTurn(2, turned: false);
      await _flushMicrotasks();
      expect([firstShown, secondShown], [null, true]);

      // The last page of the book: the bridge says there was no page.
      final last = controller.turnPage(forward: true);
      controller.completePageTurn(3, turned: false);
      expect(await last, isFalse);

      // Under a finger still dragging, a turn is not yet a page read.
      platformController.evaluatedSources.clear();
      unawaited(controller.turnPage(forward: false, quiet: true));
      controller.countTurnedPage();
      await _flushMicrotasks();
      expect(platformController.evaluatedSources, [
        'previous(4, true)',
        'countTurnedPage()',
      ]);
    });

    test('setTwoPage asks the bridge for two pages or one', () async {
      final platformController = _FakePlatformInAppWebViewController(
        onEvaluateJavascript: (source) async => null,
      );
      final controller = CustomEpubController()
        ..attach(
          InAppWebViewController.fromPlatform(platform: platformController),
        );

      controller.setTwoPage(600);
      controller.setTwoPage(null);
      await _flushMicrotasks();

      expect(platformController.evaluatedSources, [
        'setTwoPage(600.0)',
        'setTwoPage(null)',
      ]);
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
