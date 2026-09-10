#!/usr/bin/env python3
"""Check APK/AAB native dependencies, their ELF ABI, and manifest references.

Defaults to every supported ABI for release CI. --abis allows device-specific
preview APKs to receive the same checks instead of bypassing release validation.
"""
import argparse
import json
import struct
import sys
import zipfile

ABIS = ["armeabi-v7a", "arm64-v8a", "x86_64"]
LIBS = ["libc++_shared.so", "libmecab_dart.so", "libsqlite3.so",
        "libmekuru_ocr_detector.so", "libopencv_java4.so",
        "libonnxruntime.so", "libonnxruntime4j_jni.so"]
MACHINES = {"armeabi-v7a": 40, "arm64-v8a": 183, "x86_64": 62}
TARGETS = {"android_arm": "armeabi-v7a", "android_arm64": "arm64-v8a", "android_x64": "x86_64"}


def errors(archive: str, abis=ABIS) -> list[str]:
    problems = []
    with zipfile.ZipFile(archive) as zf:
        names = zf.namelist()
        libraries = {}
        for name in names:
            parts = name.split("/")
            if len(parts) >= 3 and parts[-3] == "lib" and parts[-2] in MACHINES:
                abi, lib = parts[-2:]
                if not lib:  # directory entry such as lib/arm64-v8a/
                    continue
                libraries[abi, lib] = name
                with zf.open(name) as stream:
                    header = stream.read(20)
                if (len(header) < 20 or header[:4] != b"\x7fELF" or header[5] != 1
                        or struct.unpack_from("<H", header, 18)[0] != MACHINES[abi]):
                    problems.append(f"Wrong or invalid ELF ABI: {name}")
        for abi in abis:
            for lib in LIBS:
                if (abi, lib) not in libraries:
                    problems.append(f"Missing lib/{abi}/{lib}")
        manifests = [name for name in names if name.endswith("/NativeAssetsManifest.json")]
        if not manifests:
            problems.append("Missing NativeAssetsManifest.json")
        for manifest in manifests:
            assets = json.loads(zf.read(manifest)).get("native-assets", {})
            for abi in abis:
                target = next(key for key, value in TARGETS.items() if value == abi)
                if target not in assets:
                    problems.append(f"Native asset manifest missing target {target}")
            for target, entries in assets.items():
                abi = TARGETS.get(target)
                if abi not in abis:
                    continue
                for asset_id, location in entries.items():
                    if location[0] == "absolute" and (abi, location[1]) not in libraries:
                        problems.append(f"Unresolved native asset {asset_id}: lib/{abi}/{location[1]}")
    return problems


def main(archive: str, abis=ABIS) -> int:
    problems = errors(archive, abis)
    if problems:
        print(f"Native packaging errors in {archive}:", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        return 1
    print(f"Verified native libraries and manifest in {archive} ({', '.join(abis)})")
    return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive")
    parser.add_argument("--abis", nargs="+", choices=ABIS, default=ABIS)
    args = parser.parse_args()
    sys.exit(main(args.archive, args.abis))
