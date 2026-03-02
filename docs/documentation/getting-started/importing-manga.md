# Importing Manga

Mekuru supports two manga formats, each with a different workflow:

| Format | Description |
|-|-|
| **CBZ** | Comic Book ZIP archives containing page images. Text lookups require OCR later. |
| **Mokuro** | Pre-processed manga with text already extracted. Lookups work immediately after import. |

## Importing Mokuro-Processed Manga

[Mokuro](https://github.com/kha-white/mokuro) pre-processes manga pages and stores OCR data with page positions. Mekuru supports both `.mokuro` and Mokuro `.html` manifests.

To import:

1. Open the **Library** tab.
2. Tap **+**.
3. Choose **Manga (Mokuro)**.
4. Select the folder that contains the manga data.
5. Choose the `.mokuro` or `.html` manifest from the picker shown for that folder.

Mekuru then loads the manifest, finds the matching page-image folder, segments words with MeCab, and builds tap targets for lookups.

### Expected Folder Layout

The page images must be stored in the matching sibling folder used by the selected manifest. Typical layouts look like this:

```text
manga_title.mokuro
manga_title/
  001.jpg
  002.jpg

or

manga_title.html
manga_title/
  001.jpg
  002.jpg
_ocr/manga_title/
  001.json
  002.json
```

Mokuro is the fastest path for instant lookups because the OCR text already exists before import.

## Importing CBZ Files

CBZ files contain page images only.

1. Open the **Library** tab.
2. Tap **+**.
3. Choose **Manga (CBZ)**.
4. Select a `.cbz` file from the system file picker.

The import creates the manga entry and extracts the page images, but it does **not** add text overlays yet.

## Running OCR for CBZ Manga

After import, long-press the manga entry in the library to open its actions. From there, Mekuru can show:

- **Run OCR** - start OCR for pages that do not have text yet
- **Resume OCR** - continue a partial OCR pass
- **Cancel OCR** - stop the background job and keep progress so far
- **Remove OCR** - clear OCR text and word overlays
- **Build Word Overlays** - rebuild tap targets when OCR text exists but word segmentation is missing

OCR is started from the library item actions, not from a button inside the manga reader.

## Differences from EPUB

Because manga pages are images rather than flowing text, some features work differently:

| Feature | EPUB | Manga |
|-|-|-|
| Dictionary lookups | Tap text directly | Use Mokuro data or OCR-generated overlays |
| Bookmarks | Yes | Yes |
| Highlights and notes | Yes | No |
| Text layout settings | Yes | No |
| Image view modes | No | Yes |

## Next Steps

- [Reading Manga](manga/cbz-reading.md) - view modes, reader settings, and overlays
- [Cloud OCR](manga/cloud-ocr.md) - Mekuru's built-in OCR flow
- [Custom OCR Server](manga/custom-server.md) - using your own OCR endpoint
