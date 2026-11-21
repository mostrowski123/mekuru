import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// The size of the chunks package:archive streams in. An export may hold
/// this much at once, never the book.
const archiveChunk = 1 << 20;

/// Records the largest single read and write of every file opened in its
/// zone: a phone's heap cannot be measured here, but a whole-book buffer
/// shows up as a whole-book read or write.
final class IoRecorder extends IOOverrides {
  int largestRead = 0;
  int largestWrite = 0;

  @override
  File createFile(String path) => _RecordingFile(super.createFile(path), this);
}

class _RecordingFile implements File {
  _RecordingFile(this._file, this._io);

  final File _file;
  final IoRecorder _io;

  @override
  String get path => _file.path;

  @override
  Future<bool> exists() => _file.exists();

  @override
  Future<Uint8List> readAsBytes() async {
    final bytes = await _file.readAsBytes();
    _io.largestRead = max(_io.largestRead, bytes.length);
    return bytes;
  }

  @override
  Future<String> readAsString({Encoding encoding = utf8}) async {
    final bytes = await readAsBytes();
    return encoding.decode(bytes);
  }

  @override
  Future<File> writeAsBytes(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) {
    _io.largestWrite = max(_io.largestWrite, bytes.length);
    return _file.writeAsBytes(bytes, mode: mode, flush: flush);
  }

  @override
  RandomAccessFile openSync({FileMode mode = FileMode.read}) =>
      _RecordingRandomAccessFile(_file.openSync(mode: mode), _io);

  @override
  void createSync({bool recursive = false, bool exclusive = false}) =>
      _file.createSync(recursive: recursive, exclusive: exclusive);

  @override
  Future<File> copy(String newPath) => _file.copy(newPath);

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) =>
      _file.delete(recursive: recursive);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingRandomAccessFile implements RandomAccessFile {
  _RecordingRandomAccessFile(this._file, this._io);

  final RandomAccessFile _file;
  final IoRecorder _io;

  @override
  int readIntoSync(List<int> buffer, [int start = 0, int? end]) {
    _io.largestRead = max(_io.largestRead, (end ?? buffer.length) - start);
    return _file.readIntoSync(buffer, start, end);
  }

  @override
  void writeFromSync(List<int> buffer, [int start = 0, int? end]) {
    _io.largestWrite = max(_io.largestWrite, (end ?? buffer.length) - start);
    _file.writeFromSync(buffer, start, end);
  }

  @override
  int lengthSync() => _file.lengthSync();

  @override
  void setPositionSync(int position) => _file.setPositionSync(position);

  @override
  void closeSync() => _file.closeSync();

  @override
  Future<void> close() => _file.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
