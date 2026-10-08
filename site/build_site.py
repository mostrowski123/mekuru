from datetime import date
from pathlib import Path
from html.parser import HTMLParser
import hashlib
import html
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "docs"
OUTPUT = ROOT / ".site-dist"
CONFIG = ROOT / "site" / "mkdocs.yml"
BASE_URL = "https://mekuru.matthew.moe"

# The same subjects release-ios.yml puts in the TestFlight notes.
CHANGE = re.compile(r"^(feat|fix|perf|l10n)(?:\(([^)]*)\))?!?: (.+)")
CHANGE_HEADINGS = {"feat": "New", "l10n": "New", "perf": "Faster", "fix": "Fixed"}
INTERNAL_SCOPES = {
    "build", "ci", "deps", "release", "review", "sentry", "site", "store",
    "telemetry", "test",
}
SCOPE_LABELS = {
    "a11y": "accessibility",
    "ios": "iOS",
    "l10n": "translations",
    "ocr": "OCR",
    "pdf": "PDF",
}


class MetadataParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.titles = 0
        self.descriptions = []
        self.canonicals = []

    def handle_starttag(self, tag, attrs) -> None:
        attributes = dict(attrs)
        if tag == "title":
            self.titles += 1
        elif tag == "meta" and attributes.get("name") == "description":
            self.descriptions.append(attributes.get("content", ""))
        elif tag == "link" and attributes.get("rel") == "canonical":
            self.canonicals.append(attributes.get("href", ""))


def copy_marketing_site() -> None:
    for name in (
        "index.html",
        "privacy.html",
        "credits.html",
        "404.html",
        "style.css",
        "icon.png",
    ):
        shutil.copy2(SOURCE / name, OUTPUT / name)

    for directory in ("delete-data", "images"):
        shutil.copytree(SOURCE / directory, OUTPUT / directory)

    for verification_file in SOURCE.glob("google*.html"):
        shutil.copy2(verification_file, OUTPUT / verification_file.name)


def git(*args: str) -> str:
    return subprocess.run(
        ["git", *args], cwd=ROOT, check=True, capture_output=True, text=True
    ).stdout


def app_version() -> str:
    pubspec = (ROOT / "pubspec.yaml").read_text(encoding="utf-8")
    return re.search(r"^version: *([^+\s]+)", pubspec, re.M)[1]


def changelog_versions() -> list[tuple[str, str, list[tuple[str, str, str]]]]:
    """Each version bump with the user-facing commits since the previous one,
    newest first. Commits after the latest bump wait for the next one."""
    if git("rev-parse", "--is-shallow-repository").strip() == "true":
        raise RuntimeError("The changelog needs the full git history")

    bumps = {}
    sha = None
    for line in git(
        "log", "-G^version:", "--format=%H", "-p", "--unified=0",
        "--", "pubspec.yaml",
    ).splitlines():
        if re.fullmatch(r"[0-9a-f]{40}", line):
            sha = line
        elif match := re.match(r"\+version: *([^+\s]+)", line):
            bumps[sha] = match[1]

    versions = []
    changes = []
    for line in git(
        "log", "--reverse", "--no-merges", "--date=short",
        "--format=%H%x09%ad%x09%s",
    ).splitlines():
        sha, day, subject = line.split("\t", 2)
        if (match := CHANGE.match(subject)) and match[2] not in INTERNAL_SCOPES:
            changes.append(match.groups())
        version = bumps.get(sha)
        if version and (not versions or versions[-1][0] != version):
            versions.append((version, day, changes))
            changes = []
    return versions[::-1]


def changelog_item(scope: str | None, text: str) -> str:
    tag = SCOPE_LABELS.get(scope, scope)
    tag = f'<span class="tag">{html.escape(tag)}</span> ' if tag else ""
    return f"<li>{tag}{html.escape(text[0].upper() + text[1:])}</li>"


def changelog_section(
    version: str, day: str, changes, is_open: bool, empty_text: str
) -> str:
    groups = []
    for heading in dict.fromkeys(CHANGE_HEADINGS.values()):
        items = "\n".join(
            changelog_item(scope, text)
            for kind, scope, text in changes
            if CHANGE_HEADINGS[kind] == heading
        )
        if items:
            groups.append(f"<h3>{heading}</h3>\n<ul>\n{items}\n</ul>")
    released = date.fromisoformat(day)
    return (
        f'<details{" open" if is_open else ""}>\n'
        f'<summary><h2>{html.escape(version)}</h2> '
        f'<time datetime="{day}">{released.day} {released:%B %Y}</time></summary>\n'
        + ("\n".join(groups) or f"<p>{empty_text}</p>")
        + "\n</details>"
    )


def write_changelog() -> None:
    versions = changelog_versions()
    # Browsers keep style.css for hours; a new name makes them fetch new rules.
    css_version = hashlib.sha256((SOURCE / "style.css").read_bytes()).hexdigest()[:8]
    sections = "\n".join(
        changelog_section(
            version,
            day,
            changes,
            is_open=index == 0,
            empty_text="The first release."
            if index == len(versions) - 1
            else "Behind-the-scenes improvements.",
        )
        for index, (version, day, changes) in enumerate(versions)
    )
    (OUTPUT / "changelog.html").write_text(
        f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Changelog - Mekuru</title>
  <meta name="description" content="What changed in each version of Mekuru, the Japanese EPUB and manga reader.">
  <link rel="canonical" href="{BASE_URL}/changelog">
  <link rel="stylesheet" href="style.css?v={css_version}">
  <link rel="icon" href="icon.png" type="image/png">
</head>
<body>
  <main class="container policy changelog">
    <p class="eyebrow">Mekuru</p>
    <h1>Changelog</h1>
    <p class="effective">What changed in each version, newest first. Android, iPhone and iPad share version numbers; the App Store skips some of them.</p>

{sections}

    <a href="/" class="back">&larr; Back to Mekuru</a>
  </main>
</body>
</html>
""",
        encoding="utf-8",
    )


def canonical_url(path: Path) -> str | None:
    relative = path.relative_to(OUTPUT)
    if (
        relative.name == "404.html"
        or "404" in relative.parts
        or relative.name.startswith("google")
    ):
        return None
    if relative == Path("index.html"):
        return f"{BASE_URL}/"
    if relative.name == "index.html":
        return f"{BASE_URL}/{relative.parent.as_posix().strip('/')}/"
    return f"{BASE_URL}/{relative.with_suffix('').as_posix()}"


def write_sitemap() -> None:
    urlset = ET.Element(
        "urlset",
        {"xmlns": "http://www.sitemaps.org/schemas/sitemap/0.9"},
    )
    urls = sorted(
        url
        for path in OUTPUT.rglob("*.html")
        if (url := canonical_url(path)) is not None
    )
    for url in urls:
        entry = ET.SubElement(urlset, "url")
        ET.SubElement(entry, "loc").text = url

    tree = ET.ElementTree(urlset)
    ET.indent(tree, space="  ")
    tree.write(OUTPUT / "sitemap.xml", encoding="utf-8", xml_declaration=True)


def write_robots() -> None:
    (OUTPUT / "robots.txt").write_text(
        "User-agent: *\nAllow: /\n\n"
        f"Sitemap: {BASE_URL}/sitemap.xml\n",
        encoding="utf-8",
    )


def validate_output() -> None:
    required = (
        "index.html",
        "privacy.html",
        "credits.html",
        "changelog.html",
        "404.html",
        "robots.txt",
        "sitemap.xml",
        "documentation/index.html",
        "documentation/getting-started/importing-books/index.html",
    )
    missing = [name for name in required if not (OUTPUT / name).is_file()]
    if missing:
        raise RuntimeError(f"Missing generated site files: {', '.join(missing)}")

    canonical_urls = set()
    for html_path in OUTPUT.rglob("*.html"):
        relative = html_path.relative_to(OUTPUT)
        if (
            relative.name == "404.html"
            or "404" in relative.parts
            or html_path.name.startswith("google")
        ):
            continue

        parser = MetadataParser()
        contents = html_path.read_text(encoding="utf-8")
        parser.feed(contents)
        if parser.titles != 1:
            raise RuntimeError(f"Expected one title in {relative}")
        if len(parser.descriptions) != 1 or not parser.descriptions[0]:
            raise RuntimeError(f"Expected one description in {relative}")
        if len(parser.canonicals) != 1 or not parser.canonicals[0]:
            raise RuntimeError(f"Expected one canonical URL in {relative}")
        canonical = parser.canonicals[0]
        if canonical in canonical_urls:
            raise RuntimeError(f"Duplicate canonical URL: {canonical}")
        canonical_urls.add(canonical)

    changelog = (OUTPUT / "changelog.html").read_text(encoding="utf-8")
    if f"<h2>{app_version()}</h2>" not in changelog:
        raise RuntimeError(f"The changelog is missing version {app_version()}")

    sitemap = (OUTPUT / "sitemap.xml").read_text(encoding="utf-8")
    if "404" in sitemap:
        raise RuntimeError("The sitemap must not include 404 pages")
    missing_from_sitemap = [
        url for url in canonical_urls if f"<loc>{url}</loc>" not in sitemap
    ]
    if missing_from_sitemap:
        raise RuntimeError(
            f"The sitemap is missing canonical URLs: {missing_from_sitemap}"
        )


def main() -> None:
    if OUTPUT.exists():
        shutil.rmtree(OUTPUT)
    OUTPUT.mkdir()

    subprocess.run(
        [sys.executable, "-m", "mkdocs", "build", "-f", str(CONFIG)],
        cwd=ROOT,
        check=True,
    )
    copy_marketing_site()
    write_changelog()
    write_sitemap()
    write_robots()
    validate_output()


if __name__ == "__main__":
    main()
