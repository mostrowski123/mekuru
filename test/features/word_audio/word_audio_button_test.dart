import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/database/database_provider.dart';
import 'package:mekuru/features/dictionary/data/models/dictionary_entry.dart';
import 'package:mekuru/features/dictionary/data/services/dictionary_query_service.dart';
import 'package:mekuru/features/word_audio/data/services/word_audio.dart';
import 'package:mekuru/features/word_audio/presentation/providers/word_audio_providers.dart';
import 'package:mekuru/main.dart' show databaseProvider;
import 'package:mekuru/shared/widgets/grouped_dictionary_entry_card.dart';

import '../../shared/fake_download_notifiers.dart';
import '../../test_app.dart';

class _FakeWordAudio extends WordAudio {
  _FakeWordAudio({this.isInstalled = true, this.clip, this.afterDownload});

  bool isInstalled;
  String? clip;
  String? afterDownload;
  Object? playError;
  Completer<void>? playGate;
  final plays = <String>[];
  var downloads = 0;

  @override
  Future<bool> get installed async => isInstalled;

  @override
  Future<String?> clipFor(
    String expression,
    String reading, {
    String glossaries = '',
  }) async => isInstalled ? clip : null;

  @override
  Future<void> download({
    void Function(double)? onProgress,
    bool wifiOnly = false,
  }) async {
    downloads++;
    isInstalled = true;
    clip = afterDownload;
  }

  @override
  Future<void> play(String id) async {
    plays.add(id);
    await playGate?.future;
    if (playError case final error?) throw error;
  }
}

void main() {
  late AppDatabase db;
  final speaker = find.byIcon(Icons.volume_up_outlined);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    mockWifiConnected(true);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pump(WidgetTester tester, WordAudio audio) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          wordAudioProvider.overrideWithValue(audio),
        ],
        child: buildLocalizedTestApp(
          home: Scaffold(
            body: GroupedDictionaryEntryHeader(
              entries: [
                DictionaryEntryWithSource(
                  entry: DictionaryEntry(
                    id: 1,
                    expression: '学校',
                    reading: 'がっこう',
                    entryKind: DictionaryEntryKinds.regular,
                    kanjiOnyomi: '',
                    kanjiKunyomi: '',
                    definitionTags: '',
                    rules: '',
                    termTags: '',
                    glossaries: '["school"]',
                    searchText: '',
                    dictionaryId: 1,
                  ),
                  dictionaryName: 'JMdict',
                ),
              ],
              pitchAccents: const [],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('installed, clip found: the speaker plays it', (tester) async {
    final audio = _FakeWordAudio(clip: 'abc');
    await pump(tester, audio);

    await tester.tap(speaker);
    await tester.pumpAndSettle();

    expect(audio.plays, ['abc']);
    expect(audio.downloads, 0);
  });

  testWidgets('installed, no clip: no speaker', (tester) async {
    await pump(tester, _FakeWordAudio());

    expect(speaker, findsNothing);
  });

  testWidgets('word list missing: a tap downloads it, then plays', (
    tester,
  ) async {
    final audio = _FakeWordAudio(isInstalled: false, afterDownload: 'abc');
    await pump(tester, audio);

    await tester.tap(speaker);
    await tester.pumpAndSettle();

    expect(audio.downloads, 1);
    expect(audio.plays, ['abc']);
  });

  testWidgets('word list missing, then no clip: the speaker goes', (
    tester,
  ) async {
    final audio = _FakeWordAudio(isInstalled: false);
    await pump(tester, audio);

    await tester.tap(speaker);
    await tester.pumpAndSettle();

    expect(audio.downloads, 1);
    expect(audio.plays, isEmpty);
    expect(speaker, findsNothing);
  });

  testWidgets('off Wi-Fi it asks first; Cancel downloads nothing', (
    tester,
  ) async {
    mockWifiConnected(false);
    final audio = _FakeWordAudio(isInstalled: false, afterDownload: 'abc');
    await pump(tester, audio);

    await tester.tap(speaker);
    // The speaker's spinner never settles while the question is up.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('MB'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(audio.downloads, 0);
    expect(audio.plays, isEmpty);
    expect(speaker, findsOneWidget);
  });

  testWidgets('a spinner while it fetches', (tester) async {
    final audio = _FakeWordAudio(clip: 'abc')..playGate = Completer<void>();
    await pump(tester, audio);

    await tester.tap(speaker);
    await tester.pump();

    expect(speaker, findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    audio.playGate!.complete();
    await tester.pumpAndSettle();
    expect(speaker, findsOneWidget);
  });

  testWidgets('no connection: a snackbar says so', (tester) async {
    final audio = _FakeWordAudio(clip: 'abc')
      ..playError = const SocketException('offline');
    await pump(tester, audio);

    await tester.tap(speaker);
    await tester.pump();

    expect(find.textContaining('Check your internet'), findsOneWidget);
  });

  testWidgets('playback fails: a snackbar says so', (tester) async {
    final audio = _FakeWordAudio(clip: 'abc')
      ..playError = const WordAudioPlaybackException();
    await pump(tester, audio);

    await tester.tap(speaker);
    await tester.pump();

    expect(find.textContaining("Couldn't play"), findsOneWidget);
  });
}
