import json
import struct
import tempfile
import unittest
import zipfile
from pathlib import Path
from verify_native_libs import errors, LIBS


class NativePackagingTests(unittest.TestCase):
    def check_archive(self, *, missing=None, machine=183, prefix="", extra=None, manifest=True):
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / "test.apk"
            with zipfile.ZipFile(archive, "w") as z:
                header = bytearray(20)
                header[:6] = b"\x7fELF\x02\x01"
                struct.pack_into("<H", header, 18, machine)
                for lib in LIBS:
                    if lib != missing:
                        z.writestr(f"{prefix}lib/arm64-v8a/{lib}", header)
                if manifest:
                    entries = {lib: ["absolute", lib] for lib in LIBS}
                    if extra:
                        entries[extra] = ["absolute", extra]
                    z.writestr(f"{prefix}assets/flutter_assets/NativeAssetsManifest.json",
                               json.dumps({"native-assets": {"android_arm64": entries}}))
            return errors(archive, ["arm64-v8a"])

    def test_preview_apk_and_bundle(self):
        self.assertEqual(self.check_archive(), [])
        self.assertEqual(self.check_archive(prefix="base/"), [])

    def test_missing_sqlite_and_mecab_fail(self):
        for lib in ["libsqlite3.so", "libmecab_dart.so"]:
            failures = self.check_archive(missing=lib)
            self.assertTrue(any("Missing lib/arm64-v8a/" + lib in f for f in failures))

    def test_library_with_wrong_architecture_fails(self):
        self.assertTrue(any("Wrong or invalid ELF ABI" in f for f in self.check_archive(machine=62)))

    def test_new_manifest_dependency_must_exist(self):
        self.assertTrue(any("Unresolved native asset" in f for f in self.check_archive(extra="new.so")))

    def test_missing_manifest_fails(self):
        self.assertTrue(any("Missing NativeAssetsManifest" in f for f in self.check_archive(manifest=False)))


if __name__ == "__main__":
    unittest.main()
