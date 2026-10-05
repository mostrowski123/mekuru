# Build tools

## `build_user_dict.ps1`

Compiles `tools/user_gikun.csv` into `assets/user_dict/user.dic` using MeCab inside Docker. The output dict supplements the bundled IPADIC at runtime via MeCab's `-u` flag and fixes mistokenizations such as 二人 (にん → ふたり), 一人 (ひとり), 大人 (おとな), 今日 (きょう), 上手 (じょうず), 七夕 (たなばた), 田舎 (いなか), and ~145 other gikun / 熟字訓 entries.

### Prerequisites

- Docker Desktop running.
- `assets/ipadic/` populated with the bundled IPADIC files (`sys.dic`, `matrix.bin`, `char.bin`, etc.).

Run from the project root:

```powershell
pwsh tools/build_user_dict.ps1
```

The first run pulls `debian:bookworm-slim` (~30 MB) and apt-installs `mecab` inside the container. Because the container is ephemeral (`--rm`), apt-get re-runs each invocation (~10–15 s warm); since user-dict regeneration is roughly once per release, baking a custom image is overkill.

### Verifying the output

After the build, confirm the dict works against your local IPADIC:

```powershell
docker run --rm -v "${PWD}:/work" -w /work debian:bookworm-slim sh -c `
  "apt-get update -qq >/dev/null && apt-get install -y -qq --no-install-recommends mecab && echo 二人 | mecab -d /work/assets/ipadic -u /work/assets/user_dict/user.dic"
```

The output should show `二人` as a single token with reading `フタリ`, not split into `二` + `人`.

### Adding entries

Append rows to `tools/user_gikun.csv` in IPADIC CSV format:

```
表層形,左ID,右ID,コスト,品詞,品詞細分類1,品詞細分類2,品詞細分類3,活用型,活用形,原形,読み,発音
```

Leave left/right context IDs blank — `mecab-dict-index` assigns them from the POS columns by matching the system dictionary. Use a strongly negative cost (around `-1000`) so MeCab prefers the user-dict entry over IPADIC's default segmentation. Reading and pronunciation use katakana; pronunciation uses `ー` for long vowels.

Re-run `build_user_dict.ps1` and commit both the CSV and the regenerated `assets/user_dict/user.dic`.

## `build_aozora_catalog.py`

Builds the Free books screen's Aozora Bunko catalog, `assets/free_books/aozora.json`, and the `aozoraWorkCount` line of `lib/features/free_books/data/catalog_counts.dart`. Standard library only. Re-run it before a release when Aozora has published new works:

```powershell
python tools/build_aozora_catalog.py --report
```

Downloads are cached under `build/free_books/` (gitignored): Aozora's catalog CSV, the ~240 MB `globis-university/aozorabunko-clean` text dataset (used for lengths and level estimates), the XHTML of works newer than that dataset (fetched slowly from aozora.gr.jp), and Aozora's 2009–2022 access rankings (popularity). Per-work text statistics are cached in `build/free_books/stats-v1.json`, so re-runs and calibration take seconds; delete it after changing `text_stats`. `--refresh` re-downloads the catalog and rankings.

The level is an estimate shown with that caveat in the app: the easiest JLPT level whose kanji make up 80% of a work's kanji, one step harder past 45 characters per sentence (two past 75). `--report` prints the per-level counts with popular examples; the defaults were calibrated against well-known works in October 2026. `python -m unittest test_build_aozora_catalog` (from `tools/`) checks the mappings.

## `build_tadoku_catalog.py`

Builds the Graded readers catalog, `assets/free_books/tadoku.json`, and the `tadokuBookCount` line of `lib/features/free_books/data/catalog_counts.dart`, from NPO Tadoku Supporters' free books (tadoku.org). Only metadata is bundled: the books are CC BY-NC-ND 4.0, so the app downloads each PDF straight from tadoku.org when the user asks and never changes it. Needs PyMuPDF:

```powershell
pip install -r tools/requirements-free-books.txt
python tools/build_tadoku_catalog.py
```

It reads the free-books listing, then each book's page (the PDF link, whose version suffix varies, page and character counts, the kana reading of the title), and downloads each screen PDF once to check for a Japanese text layer. Books without one (pages drawn as outlines, or fonts mapped to the wrong characters) are shown as "Pages only". Everything is cached under `build/free_books/tadoku/`, fetched a few seconds apart (the site rate-limits); `--refresh` re-downloads the listing and pages. `python -m unittest test_build_tadoku_catalog` (from `tools/`) checks the text-layer rule, which `pdf_text_blocks.dart` applies again on import.

## `make_pdf_fixtures.py`

Writes `integration_test/shared/pdf_fixtures.dart`: a two-page text PDF (horizontal and vertical Japanese with furigana, glyphs placed one by one like Tadoku's books) and a scanned, image-only PDF, as base64 constants for the PDF import tests. Needs PyMuPDF (as above); re-run after changing the script.
