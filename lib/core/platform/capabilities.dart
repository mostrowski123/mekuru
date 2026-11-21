import 'package:flutter/foundation.dart';

// The two questions features keep asking of the platform, answered once.
// Read from defaultTargetPlatform, so tests switch them with
// debugDefaultTargetPlatformOverride. Where each answer does something,
// switch on it: a new case then fails to compile where it is not handled.

/// How work that outlasts its screen runs: downloads, OCR scans, the full
/// backup.
enum LongWork {
  /// Android: the system runs it apart from the app, as WorkManager jobs and
  /// the full backup's foreground service. It goes on after Mekuru closes and
  /// says how it ended in a notification.
  systemJob,

  /// iOS: it runs in Mekuru's process, downloads and scans kept going by one
  /// BGContinuedProcessingTask (`BackgroundWork`), the full backup with the
  /// wakelock held. It ends with the app, and the next launch cleans up.
  inApp,
}

LongWork get longWork => _ios ? LongWork.inApp : LongWork.systemJob;

/// Whose names a text uses. A key whose text names Android things (Google
/// Play, AnkiDroid, background notifications) has an `…Ios` sibling: pick
/// between them with a switch on this.
enum Wording { android, ios }

Wording get wording => _ios ? Wording.ios : Wording.android;

/// The store that sells Pro.
String get storeName => switch (wording) {
  Wording.android => 'Google Play',
  Wording.ios => 'App Store',
};

/// The Anki app cards are sent to.
String get ankiAppName => switch (wording) {
  Wording.android => 'AnkiDroid',
  Wording.ios => 'Anki',
};

bool get _ios => defaultTargetPlatform == TargetPlatform.iOS;
