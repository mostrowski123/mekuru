import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/features/word_audio/data/services/word_audio_lookup.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../../shared/yomitan_glossary_fixtures.dart';

const _gakkou = 'aaaaaaaaaaaaaaa1';
const _dake = 'aaaaaaaaaaaaaaa2';
const _dakeLow = 'aaaaaaaaaaaaaaa3';
const _hashi = 'aaaaaaaaaaaaaaa4';
const _hashiBridge = 'aaaaaaaaaaaaaaa5';
const _roudou = 'aaaaaaaaaaaaaaa6';
const _rare = 'aaaaaaaaaaaaaaa7';
const _kata = 'aaaaaaaaaaaaaaa8';

void main() {
  late Directory dir;
  late WordAudioIndex index;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('word_audio_lookup');
    final path = p.join(dir.path, 'index.sqlite');
    final db = sqlite3.open(path);
    db.execute('''
      CREATE TABLE pair(
        expression TEXT NOT NULL,
        reading TEXT NOT NULL,
        id BLOB NOT NULL,
        score INTEGER NOT NULL,
        PRIMARY KEY (expression, reading)
      ) WITHOUT ROWID;
      CREATE INDEX pair_reading ON pair(reading);
    ''');
    void add(String expression, String reading, String id, int score) =>
        db.execute('INSERT INTO pair VALUES (?,?,?,?)', [
          expression,
          reading,
          _bytes(id),
          score,
        ]);
    add('学校', 'がっこう', _gakkou, 100);
    add('丈', 'だけ', _dake, 50);
    add('岳', 'だけ', _dakeLow, 10);
    add('橋', 'はし', _hashiBridge, 90);
    add('箸', 'はし', _hashi, 80);
    add('労働相', 'ろうどうしょう', _roudou, 70);
    add('稀', 'まれ', _rare, 5);
    add('稀', 'き', _dakeLow, 1);
    add('テレビ', 'テレビ', _kata, 60);
    db.close();
    index = WordAudioIndex.open(path);
  });

  tearDown(() {
    index.close();
    dir.deleteSync(recursive: true);
  });

  test('exact spelling and reading', () {
    expect(index.clipFor('学校', 'がっこう'), _gakkou);
  });

  test('the reading in the other kana', () {
    expect(index.clipFor('学校', 'ガッコウ'), _gakkou);
    expect(index.clipFor('テレビ', 'てれび'), _kata);
  });

  test('no reading: the highest score for the spelling', () {
    expect(index.clipFor('稀', ''), _rare);
  });

  test('a kana spelling reaches the kanji entry filed under it', () {
    expect(index.clipFor('だけ', ''), _dake);
    expect(index.clipFor('だけ', 'だけ'), _dake);
    expect(index.clipFor('ダケ', ''), _dake);
  });

  test('an unknown spelling takes a reading that has one clip', () {
    expect(index.clipFor('學校', 'がっこう'), _gakkou);
  });

  test('an unknown spelling never takes a homophone', () {
    expect(index.clipFor('端', 'はし'), isNull);
  });

  test('nothing fits', () {
    expect(index.clipFor('存在しない', 'そんざいしない'), isNull);
    expect(index.clipFor('存在しない', ''), isNull);
  });

  test('a redirect row follows its target', () {
    final redirect = jsonEncode([jitendexRedirect]);
    expect(index.clipFor('勞働相', '', glossaries: redirect), _roudou);
  });
}

Uint8List _bytes(String id) => Uint8List.fromList([
  for (var i = 0; i < id.length; i += 2)
    int.parse(id.substring(i, i + 2), radix: 16),
]);
