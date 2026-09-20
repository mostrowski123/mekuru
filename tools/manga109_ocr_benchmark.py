"""Benchmarks iOS on-device OCR (Apple Vision) against manga-ocr on Manga109-s.

Manga109-s has hand-annotated text boxes with transcriptions, so unlike the
.mokuro fixture this is real ground truth. The dataset may not be
redistributed: everything it produces goes under example/ (gitignored), and
published numbers must say they come from Manga109-s.

  python3 tools/manga109_ocr_benchmark.py prepare ~/Downloads/Manga109s_released_2026_05_21.zip
  swift tools/vision_recall.swift --images-from example/manga109s/images.txt --json example/manga109s/vision-lines.json
  dart run tools/group_vision_lines.dart example/manga109s/vision-lines.json example/manga109s/vision-blocks.json
  example/.venv-ocr/bin/python tools/manga109_ocr_benchmark.py score

  example/.venv-ocr/bin/python tools/manga109_ocr_benchmark.py mokuro   (optional, before score)

`mokuro` runs the mokuro package (comic-text-detector + manga-ocr), the
pipeline the Android engine mirrors, as a black box. It is GPL: install it in
the benchmark environment only, never copy from it.

Arms, all scored as character error rate against the annotated text:
  vision      Vision's own text for the lines inside each annotated box
  mocr-oracle manga-ocr on the annotated box itself (perfect detection)
  mocr-vision manga-ocr on the block the app's grouping made from Vision's
              lines (Vision detection + manga-ocr recognition)
  mokuro      the Android-equivalent pipeline end to end, if it was run
"""

import json
import re
import sys
import unicodedata
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

OUT = Path("example/manga109s")
PAGES_PER_BOOK = 2
MIN_TEXTS = 3


def prepare(zip_path):
    OUT.mkdir(parents=True, exist_ok=True)
    sample = []
    with zipfile.ZipFile(zip_path) as z:
        root = z.namelist()[0].split("/")[0]
        books = [l.strip() for l in z.read(f"{root}/books.txt").decode().splitlines() if l.strip()]
        for book in books:
            xml = ET.fromstring(z.read(f"{root}/annotations/{book}.xml"))
            pages = [p for p in xml.iter("page") if len(p.findall("text")) >= MIN_TEXTS]
            # Evenly spaced through the volume, away from covers and credits.
            picks = [pages[len(pages) * (i + 1) // (PAGES_PER_BOOK + 1)] for i in range(PAGES_PER_BOOK)] if pages else []
            for page in picks:
                index = int(page.get("index"))
                target = OUT / "images" / book / f"{index:03d}.jpg"
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(z.read(f"{root}/images/{book}/{index:03d}.jpg"))
                sample.append({
                    "book": book,
                    "path": str(target.resolve()),
                    "texts": [
                        {"box": [int(t.get(k)) for k in ("xmin", "ymin", "xmax", "ymax")], "text": t.text or ""}
                        for t in page.findall("text")
                    ],
                })
    (OUT / "sample.json").write_text(json.dumps(sample, ensure_ascii=False))
    (OUT / "images.txt").write_text("\n".join(p["path"] for p in sample) + "\n")
    print(f"{len(sample)} pages from {len(books)} volumes, {sum(len(p['texts']) for p in sample)} annotated text boxes")


def run_mokuro():
    from mokuro.manga_page_ocr import MangaPageOcr

    mpocr = MangaPageOcr()
    out_file = OUT / "mokuro-blocks.json"
    done = {p["path"]: p for p in json.loads(out_file.read_text())} if out_file.exists() else {}
    for n, page in enumerate(json.loads((OUT / "sample.json").read_text()), 1):
        if page["path"] not in done:
            result = mpocr(page["path"])
            done[page["path"]] = {
                "path": page["path"],
                "blocks": [
                    {
                        # float(): mokuro returns numpy numbers, which json rejects.
                        "box": [float(v) for v in b["box"]],
                        "lines": b["lines"],
                        # Line quads as plain rectangles, for the coverage count.
                        "line_boxes": [
                            [
                                float(min(x for x, _ in q)),
                                float(min(y for _, y in q)),
                                float(max(x for x, _ in q)),
                                float(max(y for _, y in q)),
                            ]
                            for q in b["lines_coords"]
                        ],
                    }
                    for b in result["blocks"]
                ],
            }
        if n % 10 == 0:
            out_file.write_text(json.dumps(list(done.values()), ensure_ascii=False))
            print(f"{n} pages", flush=True)
    out_file.write_text(json.dumps(list(done.values()), ensure_ascii=False))


def norm(s, letters_only=False):
    s = re.sub(r"\s", "", unicodedata.normalize("NFKC", s))
    if letters_only:
        s = "".join(c for c in s if unicodedata.category(c)[0] in "LN")
    return s


def edits(a, b):
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        for j, cb in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb)))
        prev = cur
    return prev[-1]


def area(b):
    return max(0, b[2] - b[0]) * max(0, b[3] - b[1])


def inter(a, b):
    return area([max(a[0], b[0]), max(a[1], b[1]), min(a[2], b[2]), min(a[3], b[3])])


def iou(a, b):
    i = inter(a, b)
    return i / (area(a) + area(b) - i) if i else 0.0


def score():
    from manga_ocr import MangaOcr
    from PIL import Image

    sample = json.loads((OUT / "sample.json").read_text())
    lines = {p["path"]: p["lines"] for p in json.loads((OUT / "vision-lines.json").read_text())}
    blocks = {p["path"]: p["blocks"] for p in json.loads((OUT / "vision-blocks.json").read_text())}
    mokuro_file = OUT / "mokuro-blocks.json"
    mokuro = {p["path"]: p["blocks"] for p in json.loads(mokuro_file.read_text())} if mokuro_file.exists() else None
    cache_file = OUT / "mocr-cache.json"
    cache = json.loads(cache_file.read_text()) if cache_file.exists() else {}
    mocr = None

    def read(image, path, box):
        nonlocal mocr
        key = f"{path}|{[round(v) for v in box]}"
        if key not in cache:
            mocr = mocr or MangaOcr()
            cache[key] = mocr(image.crop([round(v) for v in box]))
        return cache[key]

    names = ["vision", "mocr-oracle", "mocr-vision", "vision-same-blocks"] + (["mokuro"] if mokuro else [])
    arms = {name: {"err": 0, "err_letters": 0} for name in names}
    chars = chars_letters = boxes = covered = matched = produced = 0
    mokuro_covered = mokuro_matched = mokuro_produced = 0
    for n, page in enumerate(sample, 1):
        image = Image.open(page["path"]).convert("RGB")
        produced += len(blocks[page["path"]])
        if mokuro:
            mokuro_produced += len(mokuro[page["path"]])
        for t in page["texts"]:
            want = t["text"]
            boxes += 1
            chars += len(norm(want))
            chars_letters += len(norm(want, True))
            inside = [l for l in lines[page["path"]] if inter(l["box"], t["box"]) >= 0.5 * max(area(l["box"]), 1)]
            if sum(inter(l["box"], t["box"]) for l in lines[page["path"]]) >= 0.5 * area(t["box"]):
                covered += 1
            # Columns read right to left, rows top to bottom.
            vertical = sum((l["box"][3] - l["box"][1]) >= (l["box"][2] - l["box"][0]) for l in inside) * 2 >= len(inside)
            inside.sort(key=lambda l: -l["box"][0] if vertical else l["box"][1])
            best = max(blocks[page["path"]], key=lambda b: iou(b["box"], t["box"]), default=None)
            hit = best is not None and iou(best["box"], t["box"]) >= 0.5
            matched += hit
            got = {
                "vision": "".join(l["text"] for l in inside),
                "mocr-oracle": read(image, page["path"], t["box"]),
                "mocr-vision": read(image, page["path"], best["box"]) if hit else "",
                "vision-same-blocks": "".join(best["lines"]) if hit else "",
            }
            if mokuro:
                mblocks = mokuro[page["path"]]
                mbest = max(mblocks, key=lambda b: iou(b["box"], t["box"]), default=None)
                mhit = mbest is not None and iou(mbest["box"], t["box"]) >= 0.5
                mokuro_matched += mhit
                mlines = [lb for b in mblocks for lb in b["line_boxes"]]
                mokuro_covered += sum(inter(lb, t["box"]) for lb in mlines) >= 0.5 * area(t["box"])
                got["mokuro"] = "".join(mbest["lines"]) if mhit else ""
            for name, text in got.items():
                arms[name]["err"] += edits(norm(text), norm(want))
                arms[name]["err_letters"] += edits(norm(text, True), norm(want, True))
        if n % 20 == 0:
            cache_file.write_text(json.dumps(cache, ensure_ascii=False))
            print(f"{n}/{len(sample)} pages", flush=True)
    cache_file.write_text(json.dumps(cache, ensure_ascii=False))

    print(f"\nManga109-s sample: {len(sample)} pages, {boxes} annotated text boxes, {chars} characters")
    print(f"Vision lines cover >=50% of the box: {covered}/{boxes} ({100 * covered / boxes:.1f}%)")
    print(f"grouped block matches the box at IoU >= 0.5: {matched}/{boxes} ({100 * matched / boxes:.1f}%); {produced} blocks produced")
    if mokuro:
        print(f"mokuro lines cover >=50% of the box: {mokuro_covered}/{boxes} ({100 * mokuro_covered / boxes:.1f}%)")
        print(f"mokuro block matches the box at IoU >= 0.5: {mokuro_matched}/{boxes} ({100 * mokuro_matched / boxes:.1f}%); {mokuro_produced} blocks produced")
    print("\ncharacter error rate vs the annotation (lower is better; a missed box counts as all wrong)")
    for name, a in arms.items():
        print(f"  {name:<20} {100 * a['err'] / chars:5.1f}%   letters and digits only {100 * a['err_letters'] / chars_letters:5.1f}%")
    (OUT / "results.json").write_text(json.dumps({"pages": len(sample), "boxes": boxes, "chars": chars, "covered": covered, "matched": matched, "arms": arms}))


if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "prepare":
        prepare(sys.argv[2])
    elif len(sys.argv) >= 2 and sys.argv[1] == "mokuro":
        run_mokuro()
    elif len(sys.argv) >= 2 and sys.argv[1] == "score":
        score()
    else:
        print(__doc__)
