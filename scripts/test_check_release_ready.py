import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from check_release_ready import NO_COMMIT, check_version_bump, missing_translations


class TranslationTests(unittest.TestCase):
    def missing(self, **locales):
        with tempfile.TemporaryDirectory() as directory:
            for locale, keys in {"en": ["a", "b", "c"], **locales}.items():
                arb = {"@@locale": locale, "@a": {"description": "only in English"}}
                arb.update({key: key for key in keys})
                Path(directory, f"app_{locale}.arb").write_text(json.dumps(arb), encoding="utf-8")
            return missing_translations(Path(directory))

    def test_none_missing(self):
        self.assertEqual(self.missing(es=["a", "b", "c"], ja=["c", "b", "a"]), [])

    def test_missing_in_one_locale(self):
        self.assertEqual(self.missing(es=["a", "c"], ja=["a", "b", "c"]), ["1 key missing in es: b"])

    def test_missing_in_several_locales(self):
        self.assertEqual(self.missing(es=["a"], ja=["a", "b"], zh=["a"]),
                         ["2 keys missing in es, zh: b, c", "1 key missing in ja: c"])

    def test_extra_key_in_a_locale_is_not_a_failure(self):
        self.assertEqual(self.missing(es=["a", "b", "c", "old"]), [])


class VersionBumpTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.repo = Path(directory.name, "repo")
        config = Path(directory.name, "gitconfig")
        config.write_text("")
        # The fixture repo must not depend on the machine's git config (signing, hooks).
        self.env = dict(os.environ, GIT_CONFIG_GLOBAL=str(config), GIT_CONFIG_NOSYSTEM="1",
                        GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@example.com",
                        GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@example.com")
        self.repo.mkdir()
        self.git("init", "-q")
        self.base = self.commit("chore: start")

    def git(self, *args):
        return subprocess.run(["git", *args], cwd=self.repo, env=self.env, check=True,
                              capture_output=True, text=True).stdout.strip()

    def commit(self, subject, path="lib/main.dart", version="1.0.0"):
        (self.repo / "pubspec.yaml").write_text(f"name: app\nversion: {version}+1\n")
        changed = self.repo / path
        changed.parent.mkdir(parents=True, exist_ok=True)
        changed.write_text(subject)
        self.git("add", "-A")
        self.git("commit", "-q", "-m", subject)
        return self.git("rev-parse", "HEAD")

    def check(self, before, after):
        return check_version_bump(before, after, cwd=self.repo)

    def test_version_bumped(self):
        head = self.commit("feat(reader): add notes", version="1.1.0")
        self.assertTrue(self.check(self.base, head)[0])

    def test_user_facing_commit_without_bump_fails(self):
        self.commit("fix(ci): pin the runner")
        head = self.commit("fix(reader): stop the crash")
        passed, message = self.check(self.base, head)
        self.assertFalse(passed)
        self.assertIn("fix(reader): stop the crash", message)
        self.assertNotIn("pin the runner", message)

    def test_only_internal_scopes_pass(self):
        self.commit("fix(ci): pin the runner")
        head = self.commit("feat(telemetry): count imports")
        self.assertTrue(self.check(self.base, head)[0])

    def test_only_commits_outside_app_code_pass(self):
        head = self.commit("feat: document the reader", path="docs/reader.md")
        self.assertTrue(self.check(self.base, head)[0])

    def test_no_previous_commit_passes(self):
        head = self.commit("feat: add notes")
        for before in (NO_COMMIT, ""):
            passed, message = self.check(before, head)
            self.assertTrue(passed)
            self.assertIn("could not compare", message)

    def test_previous_commit_force_pushed_away_passes(self):
        head = self.commit("feat: add notes")
        passed, message = self.check("1" * 40, head)
        self.assertTrue(passed)
        self.assertIn("could not compare", message)

    def test_previous_commit_missing_from_shallow_clone_fails(self):
        head = self.commit("feat: add notes")
        clone = self.repo.parent / "shallow"
        self.git("clone", "-q", "--depth", "1", self.repo.resolve().as_uri(), str(clone))
        passed, message = check_version_bump(self.base, head, cwd=clone)
        self.assertFalse(passed)
        self.assertIn("could not compare", message)

    def test_empty_range_passes(self):
        passed, message = self.check(self.base, self.base)
        self.assertTrue(passed)
        self.assertIn("could not compare", message)


if __name__ == "__main__":
    unittest.main()
