# Store listings

Source of truth for the store text and the store image captions.

| Path | What |
|-|-|
| `en-US.md`, `es.md`, `id.md`, `ja-JP.md`, `zh-CN.md` | Google Play title, short description and full description, one file per Play locale (`es.md` serves es-ES and es-US) |
| `app_store/` | App Store metadata in `asc metadata` canonical form: `app-info/<locale>.json` (name, subtitle, privacy URL) and `version/<version>/<locale>.json` (description, keywords, promotional text, URLs) |
| `captions/<lang>.txt` | Headlines and sublines for the store images (en, es, id, ja, zh) |

## Google Play text

Each Play file has exactly three `##` sections: `Title`, `Short description`, `Full description`. The text under each heading is pasted into Play Console as it is; Play shows plain text, so no Markdown inside the sections. Limits: title 30, short description 80, full description 4000 characters. There is no upload script for the text.

## App Store text

```bash
asc metadata validate --dir store_listing/app_store
asc metadata push --app 6814013845 --version <version> --platform IOS --dir store_listing/app_store --dry-run
```

Rename `version/<version>/` when the draft version changes. Drafts only: never submit for review from a script.

## Store images

1. Prepare the screenshot devices once (Android emulators `Shots_Phone` and `Shots_Tablet`, iPhone 17 Pro Max and iPad Pro 13" simulators): a debug build with `--dart-define=MEKURU_FORCE_PRO=true`, the dictionary starter pack, the five Aozora Bunko books with covers, the Black Jack CBZ (`example/blackjack/`, from https://densho810.com/free/) with on-device OCR on page 28, about ten saved words, a collection and seeded reading stats.
2. Capture: `python3 tools/capture_android_store_shots.py <phone|tablet> en es id zh` on Android. Raw files go to `build/store_images/raw/<device>/<lang>/<nn>.png`.
3. Compose: `python3 tools/compose_store_images.py --raw build/store_images/raw --out build/store_images` (macOS fonts). Check the `contact-*.png` sheets. The iPhone Duo set (`duo/`) is made from the iPad captures, because the Duo simulator needs Xcode 27.1 beta. The App Store creative assets (`creative/header.png`, `creative/search.png`) keep the headline, the credit and the manga phone inside the art safe area from Apple's templates.
4. Upload:
   - Play: `python3 tools/publish_play_store_images.py` checks the files; `--commit` replaces every locale's screenshots and feature graphic in one edit (key: `~/.config/google-play-mcp/service-account.json`, packages: `tools/requirements-play-store.txt`). It never touches the listing text.
   - App Store screenshots: `asc screenshots upload` per locale, device types `IPHONE_67`, `IPAD_PRO_3GEN_129` and `IPHONE_DUO`.
   - App Store creative assets: `asc asset-library images upload --library-id 6814013845 --file <file>`, then per locale `asc localizations placements create --localization-id <id> --image-id <id> --placement-type PRODUCT_PAGE_HEADER_ASSET` (or `APP_STORE_SEARCH_RESULTS_ASSET`). To replace one later, use `placements swap`. Give each file a unique name first (`mekuru-header-en.png`), since the library lists files by name.

Every image that shows Black Jack must carry the credit "Give My Regards to Black Jack SHUHO SATO" (Japanese: ブラックジャックによろしく　佐藤秀峰), and the author asks for a short note to info@densho810.com within a month of publishing.

## Writing guidelines

- Every claim must match the app. Highlights, manga auto-crop, on-device OCR and custom-server OCR are Pro: say so.
- Keep the core search phrases natural: learn Japanese, Japanese dictionary, manga, EPUB, light novels, kanji, furigana, Anki, immersion, vertical text/tategaki, mokuro, Yomitan, JLPT.
- The first ~250 characters of a description show before "Read more" and must work on their own.
- No competitor app names, no features that are only planned.
