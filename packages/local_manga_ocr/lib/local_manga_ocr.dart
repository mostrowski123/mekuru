import 'dart:io';
import 'package:flutter/services.dart';

enum OcrBackend { onDevice, remote }

enum OcrExistingPolicy { missingOnly, replace }

/// Persisted selection. Resume uses these exact indexes, including replacement
/// pages that already have an older, valid result.
class OcrJobSpec {
  final int bookId;
  final String title;
  final String cachePath;
  final List<int> pages;
  final OcrExistingPolicy policy;
  final bool onlyWhileCharging;

  const OcrJobSpec({
    required this.bookId,
    required this.title,
    required this.cachePath,
    required this.pages,
    this.policy = OcrExistingPolicy.missingOnly,
    this.onlyWhileCharging = false,
  });

  Map<String, Object?> toJson() => {
    'bookId': bookId,
    'title': title,
    'cachePath': cachePath,
    'pages': pages,
    'replace': policy == OcrExistingPolicy.replace,
    'onlyWhileCharging': onlyWhileCharging,
  };
}

class OcrJobProgress {
  final Map<String, dynamic> json;
  const OcrJobProgress(this.json);
  String get id => json['id'] as String;
  int get bookId => (json['bookId'] as num).toInt();
  String get status => json['status'] as String;
  String get phase => json['phase'] as String? ?? status;
  String? get reason => json['reason'] as String?;
  int get total => (json['pages'] as List?)?.length ?? 0;
  Map<String, dynamic> get outcomes =>
      Map<String, dynamic>.from(json['outcomes'] as Map? ?? const {});
  int get processed => outcomes.length;
  int get failed => outcomes.values.where((v) => v == 'failed').length;
  int get skipped => outcomes.values.where((v) => v == 'skipped').length;
  int get succeeded => outcomes.values.where((v) => v == 'done').length;

  /// Progress bar value: indeterminate while preparing, else pages done.
  double? get fraction => status == 'preparing'
      ? null
      : total == 0
      ? 0
      : (processed / total).clamp(0, 1);
  int? get etaSeconds {
    final done = (json['regionsDone'] as num?)?.toInt() ?? 0;
    final regions = (json['regionsTotal'] as num?)?.toInt() ?? 0;
    final elapsed = (json['regionElapsedMs'] as num?)?.toDouble() ?? 0;
    if (status == 'running' &&
        total == 1 &&
        done >= 2 &&
        regions > done &&
        elapsed > 0) {
      return ((regions - done) * elapsed / done / 1000).ceil();
    }
    return status == 'running' &&
            ((json['timedPages'] as num?)?.toInt() ?? 0) >= 3 &&
            json['avgPageMs'] is num
        ? (((total - processed).clamp(0, total) * (json['avgPageMs'] as num)) /
                  1000)
              .ceil()
        : null;
  }

  bool get isActive => const {
    'queued',
    'preparing',
    'running',
    'pausing',
    'cancelling',
  }.contains(status);
  bool get canResume =>
      status == 'paused' ||
      status == 'failed' ||
      status == 'completedWithErrors';
}

class OcrModelState {
  final Map<String, dynamic> json;
  const OcrModelState(this.json);
  bool get supported => json['supported'] == true;
  bool get installed => json['installed'] == true;
  bool get busy =>
      const {'queued', 'downloading', 'verifying'}.contains(json['status']);
  String get status => json['status'] as String? ?? 'missing';
  String? get error => json['error'] as String?;
  int get totalBytes => (json['totalBytes'] as num?)?.toInt() ?? 0;
  int get downloadedBytes => (json['downloadedBytes'] as num?)?.toInt() ?? 0;
}

/// No account, server client, Firebase, or purchase dependency belongs here.
class LocalMangaOcr {
  static const channel = MethodChannel('mekuru/local_manga_ocr');
  static bool get available => Platform.isAndroid;

  static Future<Map<String, dynamic>> _map(
    String method, [
    Map<String, Object?>? arguments,
  ]) async => Map<String, dynamic>.from(
    await channel.invokeMapMethod<String, dynamic>(method, arguments) ??
        const <String, dynamic>{},
  );

  static Future<OcrModelState> modelState() async => available
      ? OcrModelState(await _map('modelState'))
      : const OcrModelState({'supported': false});
  static Future<void> download({bool allowMetered = false}) =>
      channel.invokeMethod('download', {'allowMetered': allowMetered});
  static Future<bool> isWifiConnected() async =>
      await channel.invokeMethod<bool>('isWifiConnected') ?? false;
  static Future<void> cancelDownload() =>
      channel.invokeMethod('cancelDownload');
  static Future<void> removeModels() => channel.invokeMethod('removeModels');
  static Future<OcrJobProgress> start(OcrJobSpec spec) async =>
      OcrJobProgress(await _map('start', spec.toJson()));
  static Future<List<OcrJobProgress>> jobs() async {
    if (!available) return const [];
    final result = await channel.invokeListMethod<dynamic>('jobs') ?? [];
    return result
        .map((j) => OcrJobProgress(Map<String, dynamic>.from(j as Map)))
        .toList();
  }

  static Future<void> pause(String id) =>
      channel.invokeMethod('pause', {'id': id});
  static Future<void> cancel(String id) =>
      channel.invokeMethod('cancel', {'id': id});
  static Future<void> resume(String id, {bool retryFailed = false}) =>
      channel.invokeMethod('resume', {'id': id, 'retryFailed': retryFailed});
  static Future<void> quiesce() async {
    if (available) await channel.invokeMethod('quiesce');
  }
}
