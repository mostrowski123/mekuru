# Play Store listing copy

Source of truth for the Google Play store listing text, one file per Play locale.
Edits here are pushed to Play via the Developer API (`edits.listings.update`) using
the service account at `~/.secrets/google-play-service-account.json` — nothing goes
live until the edit is committed.

Validate local metadata and screenshots without contacting Play:

```powershell
python tools/publish_play_store_listings.py
```

Compare the repository metadata with the current Play listings:

```powershell
python tools/publish_play_store_listings.py --remote-diff
```

Publishing requires an explicit `--commit`. Add `en-US` to `--locales` and pass
`--include-tablets` only after both English tablet asset sets pass visual QA.

| File | Play locale(s) |
|------|----------------|
| `en-US.md` | en-US (default) |
| `es.md` | es-ES and es-US (same text) |
| `id.md` | id |
| `zh-CN.md` | zh-CN |
| `ja-JP.md` | ja-JP |

## Field limits (Google Play)

- Title: 30 characters
- Short description: 80 characters
- Full description: 4000 characters

## Format

Each file has exactly three `##` sections — `Title`, `Short description`,
`Full description`. The text under each heading (trimmed) is pushed verbatim;
Play renders plain text, so no markdown inside the sections.

## Writing guidelines

- Every feature claim must match the app (see repo README features list).
  Highlights, manga auto-crop, and custom-server OCR are Pro — label them.
- Keep core search phrases present and natural: learn Japanese, Japanese
  dictionary, manga, EPUB, light novels, kanji, furigana, Anki, immersion,
  vertical text/tategaki, mokuro, Yomitan, JLPT.
- The first ~250 characters of the full description show before "Read more" —
  they must work standalone.
- No competitor app names (Play policy), no unsupported claims (e.g. cloud
  sync is roadmap-only).
