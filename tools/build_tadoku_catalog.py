#!/usr/bin/env python3
"""Build Mekuru's bundled catalog of NPO Tadoku Supporters' free graded readers.

Writes assets/free_books/tadoku.json and the tadokuBookCount constant in
lib/features/free_books/data/catalog_counts.dart.

Usage:
    pip install -r tools/requirements-free-books.txt
    python tools/build_tadoku_catalog.py            # build
    python tools/build_tadoku_catalog.py --refresh  # re-download the listing and book pages

Only metadata is bundled. The books are CC BY-NC-ND 4.0: the app downloads each PDF straight
from tadoku.org when the user taps Download and never hosts or changes them.

Sources, cached under build/free_books/tadoku/ (gitignored), fetched slowly (the site runs a
rate-limiting firewall):
  - the free-books listing (https://tadoku.org/japanese/en/free-books-en/): id, title, level,
    cover and publish date of each book;
  - each book's page: the screen-PDF and MP3 links (version suffixes vary, so they are read, never
    built), page and character counts, and the ruby title, which gives the kana reading;
  - each screen PDF, to check whether its story pages carry a real text layer. Some draw their
    text as vector outlines, and a few map their font to the wrong characters; the app labels
    both "Pages only" (words need OCR to be tapped).
"""

from __future__ import annotations

import argparse
import html
import json
import re
import sys
from pathlib import Path

import pymupdf

from build_aozora_catalog import fetch, update_count

REPO = Path(__file__).resolve().parent.parent
CACHE = REPO / "build" / "free_books" / "tadoku"
OUT_JSON = REPO / "assets" / "free_books" / "tadoku.json"
LISTING_URL = "https://tadoku.org/japanese/en/free-books-en/"
FETCH_PAUSE_SECONDS = 3

#: A page has text when it carries at least MIN_JAPANESE Japanese characters and they make up
#: MIN_JAPANESE_SHARE of everything but plain Latin letters; junk from a wrongly mapped font
#: fails. lib/features/manga/data/services/pdf_text_blocks.dart applies the same rule on import.
MIN_JAPANESE = 5
MIN_JAPANESE_SHARE = 0.6



_ITEM = re.compile(r'<div class="[^"]*freebooks-book-item[^"]*"(.*?)(?=<div class="[^"]*freebooks-book-item|<footer)', re.S)


def parse_listing(page: str) -> list[dict]:
    books = []
    for item in _ITEM.findall(page):
        level = re.search(r'data-level="l-?(start|\d)"', item).group(1)
        book_id = int(re.search(r'/japanese/book/(\d+)/', item).group(1))
        title = re.search(r'<div class="bl-title">.*?<a [^>]*>(.*?)</a>', item, re.S).group(1)
        cover = re.search(r'<img [^>]*src="([^"]+)"', item).group(1)
        date = int(re.search(r'data-date="(\d+)"', item).group(1))
        books.append({
            "i": book_id,
            "t": html.unescape(title).strip(),
            "l": -1 if level == "start" else int(level),
            "cv": cover,
            "d": date,
        })
    return books


def parse_detail(page: str) -> dict | None:
    """A book page's facts, or None when it offers no screen PDF (a few listed titles are paid
    books with only a sample page)."""
    def row(label: str) -> int:
        match = re.search(rf"<th>{label}.*?</th>\s*<td>(.*?)</td>", page, re.S)
        digits = re.sub(r"\D", "", match.group(1)) if match else ""
        return int(digits) if digits else 0

    pdf = re.search(r'href="([^"]+/[a-z]\d{4}e-[^"]+\.pdf)"', page)
    if not pdf:
        return None
    heading = re.search(r"<h1>(.*?)</h1>", page, re.S).group(1)
    # The reading: each ruby's reading in place of its base, then tags dropped.
    reading = re.sub(r"<ruby>.*?<rt>(.*?)</rt></ruby>", r"\1", heading, flags=re.S)
    return {
        "pdf": pdf.group(1),
        "au": bool(re.search(r'href="[^"]+\.mp3"', page)),
        "pg": row("ページ数"),
        "ch": row("文字数"),
        "r": html.unescape(re.sub(r"<[^>]+>", "", reading)).strip(),
    }


def _is_text(ch: str) -> bool:
    code = ord(ch)
    return not ch.isspace() and code >= 0x20 and not 0x7F <= code < 0xA0 and not 0xE000 <= code <= 0xF8FF and code != 0xFFFD


def _is_japanese(ch: str) -> bool:
    code = ord(ch)
    return 0x3000 <= code <= 0x30FF or 0x4E00 <= code <= 0x9FFF or 0xFF00 <= code <= 0xFFEF


def page_has_text(text: str) -> bool:
    counted = [c for c in text if _is_text(c) and not ("A" <= c <= "Z" or "a" <= c <= "z")]
    japanese = sum(1 for c in counted if _is_japanese(c))
    return japanese >= MIN_JAPANESE and japanese >= MIN_JAPANESE_SHARE * len(counted)


def has_text_layer(pdf_bytes: bytes) -> bool:
    """Whether most story pages (not the cover or the last page) carry real Japanese text."""
    with pymupdf.open(stream=pdf_bytes, filetype="pdf") as document:
        pages = list(document)[1:-1] or list(document)
        with_text = sum(1 for page in pages if page_has_text(page.get_text()))
    return with_text * 2 >= len(pages)



def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--refresh", action="store_true", help="re-download the listing and book pages")
    args = parser.parse_args()

    listing = fetch(LISTING_URL, CACHE / "listing.html", args.refresh, FETCH_PAUSE_SECONDS).decode("utf-8")
    listed = parse_listing(listing)
    print(f"{len(listed)} free books listed", file=sys.stderr)
    books = []
    for done, book in enumerate(listed, 1):
        page = fetch(f"https://tadoku.org/japanese/book/{book['i']}/", CACHE / "pages" / f"{book['i']}.html", args.refresh, FETCH_PAUSE_SECONDS)
        detail = parse_detail(page.decode("utf-8"))
        if detail is None:
            print(f"  skip {book['i']}: no screen PDF", file=sys.stderr)
            continue
        book.update(detail)
        pdf = fetch(book["pdf"], CACHE / "pdf" / book["pdf"].rsplit("/", 1)[-1], pause=FETCH_PAUSE_SECONDS)
        book["tx"] = has_text_layer(pdf)
        books.append(book)
        if done % 20 == 0:
            print(f"  {done}/{len(listed)} books checked", file=sys.stderr)

    books.sort(key=lambda b: (b["l"], -b["d"], b["i"]))
    for book in books:
        del book["d"]  # only orders the catalog
    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    OUT_JSON.write_text(json.dumps({"books": books}, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    update_count("tadokuBookCount", len(books))
    with_text = sum(1 for b in books if b["tx"])
    print(f"Wrote {len(books)} books ({with_text} with a text layer) to {OUT_JSON.relative_to(REPO)}", file=sys.stderr)
    for level in sorted({b["l"] for b in books}):
        at = [b for b in books if b["l"] == level]
        name = "Start" if level < 0 else f"L{level}"
        print(f"  {name}: {len(at)} books, {sum(1 for b in at if b['tx'])} with text", file=sys.stderr)


if __name__ == "__main__":
    main()
