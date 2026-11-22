import 'dart:io';

import 'package:drift/drift.dart' show CouldNotRollBackException;
import 'package:drift/isolate.dart' show DriftRemoteException;
import 'package:sqlite3/sqlite3.dart' show SqliteException;

/// Whether [error] is the device running out of room: ENOSPC from a file
/// write, or SQLITE_FULL from the database.
bool isStorageFull(Object? error) => switch (error) {
  FileSystemException(osError: OSError(errorCode: 28)) => true,
  SqliteException(resultCode: 13) => true,
  // The database runs on drift's background isolate, which wraps what it
  // throws. SQLite rolls a transaction back itself on SQLITE_FULL, so drift's
  // own ROLLBACK fails and wraps it again.
  DriftRemoteException(remoteCause: final cause) ||
  CouldNotRollBackException(:final cause) => isStorageFull(cause),
  _ => false,
};
