import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mekuru/core/services/secret_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const store = SecretStore('test.secret');

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('starts absent', () async {
    expect(await store.load(), isNull);
  });

  test('saves trimmed and reloads', () async {
    await store.save('  abc-123  ');
    expect(await store.load(), 'abc-123');
  });

  test('a stored blank reads as absent', () async {
    FlutterSecureStorage.setMockInitialValues({'test.secret': '   '});
    expect(await store.load(), isNull);
  });

  test('saving blank clears', () async {
    await store.save('abc');
    await store.save('   ');
    expect(await store.load(), isNull);
  });

  test('clear removes the entry', () async {
    await store.save('abc');
    await store.clear();
    expect(await store.load(), isNull);
  });

  test('keys are isolated', () async {
    const other = SecretStore('test.other');
    await store.save('one');
    await other.save('two');
    await store.clear();
    expect(await other.load(), 'two');
  });
}
