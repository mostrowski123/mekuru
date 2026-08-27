// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// Points every path_provider lookup at one test-owned directory.
///
/// Install with `PathProviderPlatform.instance = FakePathProviderPlatform(dir)`
/// in setUp; the temp dir's cleanup stays with the test.
class FakePathProviderPlatform extends PathProviderPlatform {
  FakePathProviderPlatform(this.root);
  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}
