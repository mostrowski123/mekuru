#!/usr/bin/env python3
"""Stop a release that is missing a translation or a version bump.

--translations: every message key in lib/l10n/app_en.arb must be in every
other lib/l10n/app_*.arb.
--version-bump BEFORE AFTER: when BEFORE..AFTER holds a feat, fix or perf
commit that touches app code and whose scope is not in INTERNAL_SCOPES
(site/build_site.py), `version:` in pubspec.yaml must differ between BEFORE
and AFTER. It passes when it cannot compare because there is no BEFORE (all
zeros or empty: a new branch or a manual run), BEFORE was force-pushed away,
or the range holds no commits. It fails when BEFORE is missing from a shallow
checkout, since every later run would then pass unchecked.
"""
import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP_CODE = ["lib/", "assets/", "android/", "ios/", "packages/"]
NO_COMMIT = "0" * 40


def missing_translations(l10n_dir):
    """One line per group of locales that lack the same English keys."""
    def keys(path):
        return [key for key in json.loads(path.read_text(encoding="utf-8")) if not key.startswith("@")]

    english = keys(l10n_dir / "app_en.arb")
    groups = {}
    for path in sorted(l10n_dir.glob("app_*.arb")):
        locale = path.stem[len("app_"):]
        if locale == "en":
            continue
        present = set(keys(path))
        missing = tuple(key for key in english if key not in present)
        if missing:
            groups.setdefault(missing, []).append(locale)
    return [
        f"{len(missing)} key{'' if len(missing) == 1 else 's'} missing in {', '.join(locales)}: {', '.join(missing)}"
        for missing, locales in groups.items()
    ]


def git(cwd, *args):
    return subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True, text=True).stdout


def version_at(cwd, rev):
    return re.search(r"^version: *([^+\s]+)", git(cwd, "show", f"{rev}:pubspec.yaml"), re.M)[1]


def check_version_bump(before, after, cwd=ROOT):
    """Returns (passed, message)."""
    if not before or before == NO_COMMIT:
        return True, "Version check could not compare: there is no previous pushed commit (a new branch or a manual run). Passing."
    if subprocess.run(["git", "cat-file", "-e", f"{before}^{{commit}}"], cwd=cwd, capture_output=True).returncode:
        if git(cwd, "rev-parse", "--is-shallow-repository").strip() == "true":
            return False, (
                f"Version check could not compare: the previous pushed commit {before} is not in this "
                "shallow checkout. Failing: the checkout step needs fetch-depth: 0."
            )
        return True, (
            f"Version check could not compare: the previous pushed commit {before} is not in the "
            "history (a force-push replaced it). Passing."
        )
    span = f"{before[:12]}..{after[:12]}"
    if git(cwd, "rev-list", "--count", f"{before}..{after}").strip() == "0":
        return True, f"Version check could not compare: there are no commits in {span}. Passing."

    # Imported here so --translations runs on the Python 3.9 that Xcode ships.
    sys.path.insert(0, str(ROOT / "site"))
    from build_site import CHANGE, INTERNAL_SCOPES

    user_facing = []
    log = git(cwd, "log", "--no-merges", "--full-history", "--format=%h %s", f"{before}..{after}", "--", *APP_CODE)
    for line in log.splitlines():
        match = CHANGE.match(line.split(" ", 1)[1])
        if match and match[1] in ("feat", "fix", "perf") and match[2] not in INTERNAL_SCOPES:
            user_facing.append(line)
    old, new = version_at(cwd, before), version_at(cwd, after)
    if not user_facing:
        return True, f"No user-facing feat, fix or perf commit touches app code in {span} (version {old} to {new})."
    if old != new:
        return True, f"Version bumped from {old} to {new} for {len(user_facing)} user-facing commits in {span}."
    return False, (
        f"version: in pubspec.yaml is still {new} at {span}, but these commits are user-facing. "
        "Bump it (minor for feat, patch for fix):\n" + "\n".join(f"  {line}" for line in user_facing)
    )


def main(translations, version_bump):
    failed = False
    if translations:
        problems = missing_translations(ROOT / "lib" / "l10n")
        for problem in problems:
            print(problem, file=sys.stderr)
        if not problems:
            print("Every app_*.arb has every key in app_en.arb.")
        failed = bool(problems)
    if version_bump:
        passed, message = check_version_bump(*version_bump)
        print(message, file=sys.stdout if passed else sys.stderr)
        failed = failed or not passed
    return 1 if failed else 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--translations", action="store_true")
    parser.add_argument("--version-bump", nargs=2, metavar=("BEFORE", "AFTER"))
    args = parser.parse_args()
    if not (args.translations or args.version_bump):
        parser.error("choose --translations, --version-bump or both")
    sys.exit(main(args.translations, args.version_bump))
