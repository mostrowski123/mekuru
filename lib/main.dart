import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'app.dart';
import 'config/environment_config.dart';
import 'core/database/database_provider.dart';
import 'features/reader/data/services/mecab_service.dart';

/// Global navigator key used by Sentry for feedback screenshots
/// and navigator observation.
final navigatorKey = GlobalKey<NavigatorState>();

/// Global Riverpod provider for the Drift database instance.
/// Created once at app startup and disposed when the app is torn down.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SentryFlutter.init(
    (options) {
      options.dsn = EnvironmentConfig.sentryDsn;
      options.environment = EnvironmentConfig.sentryEnvironment;
      options.navigatorKey = navigatorKey;
    },
    appRunner: () async {
      await MecabService.instance.init();

      Sentry.addBreadcrumb(Breadcrumb(
        message: 'MeCab initialized',
        category: 'app.init',
      ));

      runApp(
        SentryWidget(
          child: const ProviderScope(child: MekuruApp()),
        ),
      );
    },
  );
}
