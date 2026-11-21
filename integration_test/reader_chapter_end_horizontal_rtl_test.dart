// One scenario per file: see integration_test/shared/chapter_end_scenario.dart.

import 'package:integration_test/integration_test.dart';

import 'shared/chapter_end_scenario.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerChapterEndScenario(vertical: false, rtl: true);
}
