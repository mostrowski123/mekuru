#!/usr/bin/env python3
"""Generate the PDF fixtures for the PDF-import tests.

Writes integration_test/shared/pdf_fixtures.dart (base64 constants, so the
fixtures reach the device with the test) — re-run after changing this file:

    pip install -r tools/requirements-free-books.txt
    python tools/make_pdf_fixtures.py

The text PDF mimics NPO Tadoku Supporters' graded readers without copying
them: a horizontal page and a vertical page, every glyph placed on its own
(vertical books do this), with furigana at half size beside or above the
kanji it reads, and a page number. The font is PyMuPDF's bundled CJK
fallback font (Droid Sans Fallback, Apache-2.0), embedded as a subset with
a ToUnicode map — PDFium reads no text from non-embedded CJK fonts. The
scanned PDF is two pages that are only images, with no text layer.
"""

from __future__ import annotations

import base64
import io
import re
from pathlib import Path

import pymupdf

REPO = Path(__file__).resolve().parent.parent
OUT = REPO / "integration_test" / "shared" / "pdf_fixtures.dart"
SIZE = 20
WIDTH, HEIGHT = 420, 595  # A5 in points

# (base, reading or None) runs; the sentence repeats to fill the lines.
SENTENCE = [("今日", "きょう"), ("は", None), ("学校", "がっこう"), ("で", None), ("日本語", "にほんご"), ("を勉強します。", None)]


def _runs(repeat: int):
    for _ in range(repeat):
        yield from SENTENCE


def _put(page: pymupdf.Page, char: str, x: float, top: float, size: float) -> None:
    """One glyph whose em box starts at (x, top); PyMuPDF places by baseline."""
    page.insert_text((x, top + size * 0.88), char, fontsize=size, fontname="cjk", fontfile=None)


def horizontal_page(page: pymupdf.Page) -> None:
    x, top = 30.0, 60.0
    for base, reading in _runs(12):
        run = len(base) * SIZE
        if x + run > WIDTH - 30:
            x, top = 30.0, top + SIZE * 2
        if reading:
            offset = (run - len(reading) * SIZE / 2) / 2
            for i, char in enumerate(reading):
                _put(page, char, x + offset + i * SIZE / 2, top - SIZE / 2, SIZE / 2)
        for char in base:
            _put(page, char, x, top, SIZE)
            x += SIZE
    _put(page, "1", WIDTH / 2, HEIGHT - 30, SIZE / 2)


def vertical_page(page: pymupdf.Page) -> None:
    x, top = WIDTH - 60.0, 40.0
    for base, reading in _runs(12):
        run = len(base) * SIZE
        if top + run > HEIGHT - 50:
            x, top = x - SIZE * 2, 40.0
        for char in base:
            _put(page, char, x, top, SIZE)
            top += SIZE
        if reading:
            # Readings come after their run in drawing order, as in Tadoku's PDFs.
            start = top - run + (run - len(reading) * SIZE / 2) / 2
            for i, char in enumerate(reading):
                _put(page, char, x + SIZE, start + i * SIZE / 2, SIZE / 2)
    _put(page, "2", WIDTH / 2, HEIGHT - 30, SIZE / 2)


def text_pdf() -> bytes:
    document = pymupdf.open()
    for draw in (horizontal_page, vertical_page):
        page = document.new_page(width=WIDTH, height=HEIGHT)
        page.insert_font(fontname="cjk", fontbuffer=pymupdf.Font("cjk").buffer)
        draw(page)
    document.subset_fonts()
    return document.tobytes(garbage=4, deflate=True, no_new_id=True)


def phrase_pdf() -> bytes:
    """One row in three phrases an em apart, as graded readers set them,
    starting with 𠮟 (U+20B9F, beyond the BMP). The bundled font has no 𠮟, so
    叱 is drawn and its ToUnicode entry points at 𠮟, the way PDFs that use
    it encode it: as a UTF-16 surrogate pair."""
    document = pymupdf.open()
    page = document.new_page(width=WIDTH, height=HEIGHT)
    page.insert_font(fontname="cjk", fontbuffer=pymupdf.Font("cjk").buffer)
    x = 30.0
    for phrase in ("叱られた", "ねこが", "にげました。"):
        for char in phrase:
            _put(page, char, x, 60.0, SIZE)
            x += SIZE
        x += SIZE  # the phrase space
    document.subset_fonts()
    _read_as(document, "叱", "\U00020B9F")
    data = document.tobytes(garbage=4, deflate=True, no_new_id=True)
    text = pymupdf.open(stream=data, filetype="pdf")[0].get_text()
    assert text.split() == ["\U00020B9Fられた", "ねこが", "にげました。"], text
    return data


def _read_as(document: pymupdf.Document, drawn: str, read: str) -> None:
    """Points the ToUnicode entry of [drawn]'s glyph at [read] instead."""
    cid = pymupdf.Font("cjk").has_glyph(ord(drawn))
    target = read.encode("utf-16-be").hex().upper()
    for xref in range(1, document.xref_length()):
        if not document.xref_is_stream(xref):
            continue
        lines = document.xref_stream(xref).decode("latin1").split("\n")
        if "begincmap" not in lines:
            continue
        for i, line in enumerate(lines):
            entry = re.fullmatch(r"<([0-9a-f]{4})> <([0-9a-f]{4})> <([0-9a-f]{4})>", line.strip(), re.I)
            if not entry:
                continue
            low, high, first = (int(part, 16) for part in entry.groups())
            if not low < cid < high:
                continue
            # The range up to the glyph stays; the glyph and the rest of the
            # range follow in blocks of their own.
            lines[i] = f"<{low:04x}> <{cid - 1:04x}> <{first:04x}>"
            end = lines.index("endcmap")
            lines[end:end] = [
                "1 beginbfchar", f"<{cid:04x}> <{target}>", "endbfchar",
                "1 beginbfrange", f"<{cid + 1:04x}> <{high:04x}> <{first + cid + 1 - low:04x}>", "endbfrange",
            ]
            document.update_stream(xref, "\n".join(lines).encode("latin1"))
            return
    raise ValueError(f"no ToUnicode range holds {drawn}")


def scanned_pdf() -> bytes:
    """Two pages that are only pictures, like a scanned book."""
    pixmap = pymupdf.Pixmap(pymupdf.csGRAY, pymupdf.IRect(0, 0, 210, 297), False)
    pixmap.clear_with(255)
    for row in range(20, 280, 14):
        pixmap.set_rect(pymupdf.IRect(20, row, 190, row + 6), (60,))
    png = pixmap.tobytes("png")
    document = pymupdf.open()
    for _ in range(2):
        page = document.new_page(width=WIDTH, height=HEIGHT)
        page.insert_image(page.rect, stream=png)
    return document.tobytes(garbage=4, deflate=True, no_new_id=True)


def dart_constant(name: str, data: bytes, doc: str) -> str:
    encoded = base64.b64encode(data).decode("ascii")
    chunks = [encoded[i:i + 76] for i in range(0, len(encoded), 76)]
    body = "\n".join(f"  '{chunk}'" for chunk in chunks)
    return f"/// {doc}\nconst {name} =\n{body};\n"


def main() -> None:
    OUT.write_text(
        "// GENERATED by tools/make_pdf_fixtures.py — do not edit by hand.\n\n"
        + dart_constant(
            "textPdfBase64",
            text_pdf(),
            "Page 1 horizontal, page 2 vertical; glyph by glyph, half-size furigana.",
        )
        + "\n"
        + dart_constant("scannedPdfBase64", scanned_pdf(), "Two image-only pages, no text layer.")
        + "\n"
        + dart_constant(
            "phrasePdfBase64",
            phrase_pdf(),
            "One row in three phrases spaced an em apart; its first kanji is 𠮟, beyond the BMP.",
        ),
        encoding="utf-8",
        newline="\n",
    )
    print(f"wrote {OUT.relative_to(REPO)}")


if __name__ == "__main__":
    main()
