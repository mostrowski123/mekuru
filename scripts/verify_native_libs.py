#!/usr/bin/env python3
"""Verify that a release APK or AAB ships the MeCab native libraries
(libc++_shared.so and libmecab_dart.so) for every supported ABI.

CI calls this once per built archive; missing libs mean the runtime
workarounds in android/app/build.gradle.kts silently failed."""

import sys
import zipfile

ABIS = ["armeabi-v7a", "arm64-v8a", "x86_64"]
LIBS = ["libc++_shared.so", "libmecab_dart.so"]


def main(archive: str) -> int:
    with zipfile.ZipFile(archive) as zf:
        names = zf.namelist()

    missing = [
        f"lib/{abi}/{lib}"
        for abi in ABIS
        for lib in LIBS
        if not any(entry.endswith(f"lib/{abi}/{lib}") for entry in names)
    ]
    if missing:
        print(f"Missing required native libraries in {archive}:", file=sys.stderr)
        for name in missing:
            print(f"  - {name}", file=sys.stderr)
        print("Found MeCab-related ABI entries:", file=sys.stderr)
        for entry in sorted(
            name
            for name in names
            if any(f"lib/{abi}/" in name for abi in ABIS)
            and ("libmecab_dart.so" in name or "libc++_shared.so" in name)
        ):
            print(f"  - {entry}", file=sys.stderr)
        return 1

    print(f"Verified required MeCab native libraries in {archive}")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: verify_native_libs.py <archive>", file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
