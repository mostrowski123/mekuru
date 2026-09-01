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
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
