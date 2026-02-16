import 'dart:async';

typedef SaveReaderProgress = Future<void> Function(String cfi, double progress);

class ReaderProgressPersistence {
  ReaderProgressPersistence({
    required SaveReaderProgress saveProgress,
    this.debounceDuration = const Duration(milliseconds: 350),
  }) : _saveProgress = saveProgress;

  final SaveReaderProgress _saveProgress;
  final Duration debounceDuration;

  Timer? _saveTimer;
  String? _queuedCfi;
  double _queuedProgress = 0.0;
  String? _lastSavedCfi;
  double? _lastSavedProgress;

  void queueSave(String cfi, double progress) {
    if (cfi.isEmpty ||
        (cfi == _lastSavedCfi && progress == _lastSavedProgress)) {
      return;
    }

    _queuedCfi = cfi;
    _queuedProgress = progress;
    _saveTimer?.cancel();
    _saveTimer = Timer(debounceDuration, _flushQueuedSave);
  }

  Future<void> dispose() async {
    _saveTimer?.cancel();
    await _flushQueuedSave();
  }

  Future<void> _flushQueuedSave() async {
    final cfiToSave = _queuedCfi;
    if (cfiToSave == null ||
        (cfiToSave == _lastSavedCfi &&
            _queuedProgress == _lastSavedProgress)) {
      return;
    }

    final progressToSave = _queuedProgress;
    _queuedCfi = null;
    await _saveProgress(cfiToSave, progressToSave);
    _lastSavedCfi = cfiToSave;
    _lastSavedProgress = progressToSave;
  }
}
