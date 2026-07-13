from pathlib import Path
from html.parser import HTMLParser
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "docs"
OUTPUT = ROOT / ".site-dist"
CONFIG = ROOT / "site" / "mkdocs.yml"
BASE_URL = "https://mekuru.matthew.moe"


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
    write_sitemap()
    write_robots()
    validate_output()


if __name__ == "__main__":
    main()
