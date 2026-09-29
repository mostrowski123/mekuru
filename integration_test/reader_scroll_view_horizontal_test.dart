// One scenario per file: see integration_test/shared/scroll_view_fixture.dart.

import 'package:integration_test/integration_test.dart';

import 'shared/scroll_view_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerScrollViewScenario(vertical: false);
}
