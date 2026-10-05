#!/usr/bin/env python3
"""Build Mekuru's bundled Aozora Bunko catalog (standard library only).

Writes assets/free_books/aozora.json and the aozoraWorkCount constant in
lib/features/free_books/data/catalog_counts.dart.

Usage:
    python tools/build_aozora_catalog.py             # build
    python tools/build_aozora_catalog.py --report    # also print the level calibration report
    python tools/build_aozora_catalog.py --refresh   # re-download the catalog and rankings

Inputs, cached under build/free_books/ (gitignored):
  - Aozora's catalog CSV (CC BY 4.0; Aozora allows it as bibliographic data in reading software):
    https://www.aozora.gr.jp/index_pages/list_person_all_extended_utf8.zip
  - Text for the length and level metrics: Hugging Face globis-university/aozorabunko-clean
    (CC BY 4.0, ruby already stripped). Works newer than that snapshot are measured from their
    XHTML, fetched from www.aozora.gr.jp one at a time with a pause between requests.
  - Popularity: Aozora's yearly access rankings 2009-2022 (XHTML and text, top 500 each),
    summed per work. Aozora stopped publishing rankings after 2022.

The level is an *estimate* (the app says so): the easiest JLPT level whose kanji cover at
least --coverage of the kanji in the text, made one step harder for each --long threshold
the mean sentence length exceeds. Kanji levels come from lib/core/utils/jlpt_kanji_levels.dart
(the table the reader's furigana filter uses); kanji missing from it count as beyond N1.
"""

from __future__ import annotations

import argparse
import csv
import gzip
import html
import io
import json
import re
import sys
import time
import urllib.request
import zipfile
from collections import Counter
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CACHE = REPO / "build" / "free_books"
OUT_JSON = REPO / "assets" / "free_books" / "aozora.json"
COUNTS_DART = REPO / "lib" / "features" / "free_books" / "data" / "catalog_counts.dart"
KANJI_LEVELS_DART = REPO / "lib" / "core" / "utils" / "jlpt_kanji_levels.dart"

CATALOG_URL = "https://www.aozora.gr.jp/index_pages/list_person_all_extended_utf8.zip"
HF_URL = (
    "https://huggingface.co/datasets/globis-university/aozorabunko-clean/"
    "resolve/main/aozorabunko-dedupe-clean.jsonl.gz"
)
RANKING_URL = "https://www.aozora.gr.jp/access_ranking/{year}_{kind}.html"
RANKING_YEARS = range(2009, 2023)
CARDS_PREFIXES = ("https://www.aozora.gr.jp/cards/", "http://www.aozora.gr.jp/cards/")
USER_AGENT = "MekuruCatalogBuilder/1.0 (+https://github.com/mostrowski123/mekuru)"
FETCH_PAUSE_SECONDS = 1.5

SPELLING = {"新字新仮名": "m", "新字旧仮名": "k", "旧字旧仮名": "j", "旧字新仮名": "j"}


def fetch(url: str, path: Path, refresh: bool = False, pause: float = 0) -> bytes:
    """Download [url] to [path] once, [pause] seconds after the last request
    (for sites that rate-limit); later runs read the cached copy."""
    if path.exists() and not refresh:
        return path.read_bytes()
    time.sleep(pause)
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=120) as response:
        data = response.read()
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".part")
    tmp.write_bytes(data)
    tmp.replace(path)
    return data


def load_catalog_rows(refresh: bool) -> list[dict[str, str]]:
    data = fetch(CATALOG_URL, CACHE / "list_person_all_extended_utf8.zip", refresh)
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        name = next(n for n in archive.namelist() if n.endswith(".csv"))
        text = archive.read(name).decode("utf-8-sig")
    return list(csv.DictReader(io.StringIO(text)))


#: Aozora's XHTML files are named <work>_<file>.html. The ~116 files named just <work>.html are
#: pre-XHTML HTML 4 pages (uppercase tags, no main_text div) that the app's converter can't read.
_XHTML_NAME = re.compile(r"/\d+_\d+\.html$")


def select_works(rows: list[dict[str, str]]) -> dict[int, dict[str, str]]:
    """One author row per public-domain work whose XHTML lives on aozora.gr.jp."""
    works: dict[int, dict[str, str]] = {}
    for row in rows:
        if row["役割フラグ"] != "著者" or row["作品著作権フラグ"] != "なし":
            continue
        url = row["XHTML/HTMLファイルURL"]
        if not url.startswith(CARDS_PREFIXES) or not _XHTML_NAME.search(url):
            continue
        if not row["図書カードURL"].startswith(CARDS_PREFIXES):
            continue
        works.setdefault(int(row["作品ID"]), row)
    return works


def load_kanji_levels() -> dict[int, int]:
    source = KANJI_LEVELS_DART.read_text(encoding="utf-8")
    return {int(code, 16): int(level) for code, level in re.findall(r"0x([0-9A-Fa-f]+): (\d)", source)}


def is_kanji(ch: str) -> bool:
    code = ord(ch)
    return 0x4E00 <= code <= 0x9FFF or 0x3400 <= code <= 0x4DBF or 0xF900 <= code <= 0xFAFF or 0x20000 <= code <= 0x2FA1F


_SENTENCE_END = re.compile(r"[。！？!?\n]+")
_SPACE = re.compile(r"\s+")


def text_stats(text: str, levels: dict[int, int]) -> dict:
    """Raw counts for a work's body text: characters, sentences, kanji per JLPT level (index 0 = beyond N1)."""
    kanji = [0] * 6
    previous = None
    for ch in text:
        if ch == "々":
            if previous is not None:
                kanji[previous] += 1
            continue
        if is_kanji(ch):
            previous = levels.get(ord(ch), 0)
            kanji[previous] += 1
        else:
            previous = None
    sentences = sum(1 for s in _SENTENCE_END.split(text) if s.strip())
    return {"n": len(_SPACE.sub("", text)), "s": sentences, "k": kanji}


def estimate_level(stats: dict, coverage: float, long: tuple[int, ...]) -> int:
    """Estimated JLPT level 5..1 (0 = beyond N1): the easiest level whose kanji cover [coverage] of the
    kanji occurrences, one step harder per [long] mean-sentence-length threshold exceeded."""
    kanji = stats["k"]
    total = sum(kanji)
    estimate = 0
    if total == 0:
        estimate = 5
    else:
        covered = 0
        for level in (5, 4, 3, 2, 1):
            covered += kanji[level]
            if covered / total >= coverage:
                estimate = level
                break
    if stats["s"] and estimate:
        mean = stats["n"] / stats["s"]
        estimate = max(0, estimate - sum(1 for threshold in long if mean > threshold))
    return estimate


_MAIN_TEXT = re.compile(r'<div class="main_text">(.*?)<div class="bibliographical_information">', re.S)
_RUBY_EXTRAS = re.compile(r"<(rt|rp)>.*?</\1>", re.S)
_TAG = re.compile(r"<[^>]+>")


def xhtml_body_text(raw: bytes) -> str:
    head = raw[:200].decode("ascii", errors="ignore").lower()
    document = raw.decode("utf-8" if "utf-8" in head else "cp932", errors="replace")
    match = _MAIN_TEXT.search(document)
    body = match.group(1) if match else document
    body = _RUBY_EXTRAS.sub("", body).replace("<br />", "\n")
    return html.unescape(_TAG.sub("", body))


STATS_CACHE = CACHE / "stats-v1.json"


def collect_stats(works: dict[int, dict[str, str]], levels: dict[int, int]) -> dict[int, dict]:
    """Text statistics per work: from the dataset, else from the work's XHTML. Cached, since
    streaming the dataset takes minutes and calibrating the level estimate needs many runs."""
    stats: dict[int, dict] = {}
    if STATS_CACHE.exists():
        stats = {int(k): v for k, v in json.loads(STATS_CACHE.read_text(encoding="utf-8")).items()}
    wanted = set(works) - set(stats)
    if wanted:
        path = CACHE / "aozorabunko-dedupe-clean.jsonl.gz"
        if not path.exists():
            print("Downloading the Aozora text dataset (~240 MB)...", file=sys.stderr)
            fetch(HF_URL, path)
        with gzip.open(path, "rt", encoding="utf-8") as lines:
            for line in lines:
                record = json.loads(line)
                work_id = int(record["meta"]["作品ID"])
                if work_id in wanted:
                    stats[work_id] = text_stats(record["text"], levels)
    missing = sorted(set(works) - set(stats))
    print(f"{len(works) - len(missing)} works measured, {len(missing)} left for their XHTML", file=sys.stderr)
    for done, work_id in enumerate(missing, 1):
        url = works[work_id]["XHTML/HTMLファイルURL"]
        try:
            raw = fetch(url, CACHE / "xhtml" / f"{work_id}.html", pause=FETCH_PAUSE_SECONDS)
        except Exception as error:  # noqa: BLE001 - a dead link drops one work, not the build
            print(f"  skip {work_id}: {error}", file=sys.stderr)
            continue
        stats[work_id] = text_stats(xhtml_body_text(raw), levels)
        if done % 100 == 0:
            print(f"  {done}/{len(missing)} XHTML measured", file=sys.stderr)
    STATS_CACHE.write_text(json.dumps(stats), encoding="utf-8")
    return stats


def popularity(refresh: bool) -> Counter:
    counts: Counter = Counter()
    row = re.compile(r'card(\d+)\.html.*?<td class=normal>(\d+)</td>\s*</tr>', re.S)
    for year in RANKING_YEARS:
        for kind in ("xhtml", "txt"):
            page = fetch(
                RANKING_URL.format(year=year, kind=kind),
                CACHE / "ranking" / f"{year}_{kind}.html",
                refresh,
                pause=FETCH_PAUSE_SECONDS,
            ).decode("utf-8", errors="replace")
            for work_id, count in row.findall(page):
                counts[int(work_id)] += int(count)
    return counts


def genre(ndc: str) -> str:
    """Short genre code from Aozora's 分類番号 (e.g. "NDC 913", "NDC K913")."""
    match = re.search(r"NDC\s+(K?)(\d{3})", ndc)
    if not match:
        return "oth"
    if match.group(1):
        return "kid"
    code = match.group(2)
    if code[0] == "9":
        return {"1": "poe", "2": "pla", "3": "fic", "4": "ess", "5": "dia", "6": "dia"}.get(code[2], "oth")
    if code[0] == "1":
        return "phi"
    if code[0] == "2":
        return "his"
    return "non"


def path_after_cards(url: str) -> str:
    for prefix in CARDS_PREFIXES:
        if url.startswith(prefix):
            return url[len(prefix):]
    raise ValueError(url)


def build_entry(work_id: int, row: dict[str, str], chars: int, level: int, pop: int, authors: dict) -> dict:
    # The card page always sits beside the XHTML's folder (cards/<person>/card<id>.html), so the
    # app derives it; checked when this was written.
    xhtml = path_after_cards(row["XHTML/HTMLファイルURL"])
    if path_after_cards(row["図書カードURL"]) != f'{xhtml.split("/")[0]}/card{work_id}.html':
        raise SystemExit(f"card URL of {work_id} is not beside its XHTML; teach the app the card path")
    author = (f'{row["姓"]} {row["名"]}'.strip(), f'{row["姓読み"]} {row["名読み"]}'.strip())
    entry = {
        "i": work_id,
        "t": row["作品名"],
        "r": row["作品名読み"],
        "a": authors.setdefault(author, len(authors)),
        "x": xhtml,
        "g": genre(row["分類番号"]),
        "o": SPELLING.get(row["文字遣い種別"], "x"),
        "n": chars,
        "l": level,
        "p": pop,
    }
    if row["副題"]:
        entry["s"] = row["副題"]
    return entry


def update_count(name: str, value: int) -> None:
    source = COUNTS_DART.read_text(encoding="utf-8")
    updated, replaced = re.subn(rf"const int {name} = \d+;", f"const int {name} = {value};", source)
    if not replaced:
        raise SystemExit(f"{name} not found in {COUNTS_DART}")
    COUNTS_DART.write_text(updated, encoding="utf-8", newline="\n")


def report(entries: list[dict], authors: list[list[str]]) -> None:
    names = {5: "~N5", 4: "~N4", 3: "~N3", 2: "~N2", 1: "~N1", 0: "beyond N1"}
    print("\nLevel distribution (all / modern spelling):")
    for level in (5, 4, 3, 2, 1, 0):
        at = [e for e in entries if e["l"] == level]
        modern = [e for e in at if e["o"] == "m"]
        popular = sorted(modern, key=lambda e: -e["p"])[:6]
        sample = ", ".join(f'{e["t"]} ({authors[e["a"]][0]})' for e in popular)
        print(f"  {names[level]:>9}: {len(at):6d} / {len(modern):6d}   e.g. {sample}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--refresh", action="store_true", help="re-download the catalog CSV and rankings")
    parser.add_argument("--report", action="store_true", help="print the level calibration report")
    # Calibrated 2026-10-05 against well-known works (Matt approved): fairy tales ~N3, Kokoro ~N2,
    # Rashomon ~N1, archaic prose beyond N1; ~870 modern-spelling works at ~N5-~N3.
    parser.add_argument("--coverage", type=float, default=0.80, help="kanji coverage needed for a level")
    parser.add_argument("--long", type=int, nargs="*", default=[45, 75], help="sentence-length thresholds")
    args = parser.parse_args()
    long = tuple(args.long)

    works = select_works(load_catalog_rows(args.refresh))
    print(f"{len(works)} public-domain works with on-site XHTML", file=sys.stderr)
    stats = collect_stats(works, load_kanji_levels())

    pop = popularity(args.refresh)
    authors: dict[tuple[str, str], int] = {}
    entries = [
        build_entry(
            work_id,
            row,
            stats[work_id]["n"],
            estimate_level(stats[work_id], args.coverage, long),
            pop.get(work_id, 0),
            authors,
        )
        for work_id, row in sorted(works.items())
        if work_id in stats
    ]
    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    payload = {"authors": [list(a) for a in authors], "works": entries}
    OUT_JSON.write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    update_count("aozoraWorkCount", len(entries))
    print(f"Wrote {len(entries)} works to {OUT_JSON.relative_to(REPO)}", file=sys.stderr)
    if args.report:
        report(entries, payload["authors"])


if __name__ == "__main__":
    main()
