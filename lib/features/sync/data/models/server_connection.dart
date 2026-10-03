import 'package:drift/drift.dart';

/// A configured self-hosted book server (Komga or Kavita).
///
/// Credentials are NOT stored here — they live in flutter_secure_storage
/// keyed by this row's id (see ServerSecretStorage).
class ServerConnections extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 'komga' or 'kavita'.
  TextColumn get serverType => text()();
  TextColumn get name => text()();
  TextColumn get baseUrl => text()();

  /// Disabled connections (e.g. restored from backup before credentials are
  /// re-entered) are skipped by sync and browse.
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();

  /// Accept a certificate from this server that fails validation (a
  /// self-signed one). Its book downloads then run in the app, not in the
  /// background downloader, which can't make that exception per server.
  BoolColumn get allowSelfSignedCert =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
