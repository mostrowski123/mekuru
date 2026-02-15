import 'dart:async';

typedef SaveReaderProgress = Future<void> Function(String cfi);

class ReaderProgressPersistence {
  ReaderProgressPersistence({
    required SaveReaderProgress saveProgress,
    this.debounceDuration = const Duration(milliseconds: 350),
  }) : _saveProgress = saveProgress;

  final SaveReaderProgress _saveProgress;
  final Duration debounceDuration;

  Timer? _saveTimer;
  String? _queuedCfi;
  String? _lastSavedCfi;

  void queueSave(String cfi) {
    if (cfi.isEmpty || cfi == _lastSavedCfi) {
      return;
    }

    _queuedCfi = cfi;
    _saveTimer?.cancel();
    _saveTimer = Timer(debounceDuration, _flushQueuedSave);
  }

  Future<void> dispose() async {
    _saveTimer?.cancel();
    await _flushQueuedSave();
  }

  Future<void> _flushQueuedSave() async {
    final cfiToSave = _queuedCfi;
    if (cfiToSave == null || cfiToSave == _lastSavedCfi) {
      return;
    }

    _queuedCfi = null;
    await _saveProgress(cfiToSave);
    _lastSavedCfi = cfiToSave;
  }
}
