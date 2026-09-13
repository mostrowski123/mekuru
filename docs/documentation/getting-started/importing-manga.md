# Importing Manga

Mekuru supports two manga formats, each with a different workflow:

| Format | Description |
|-|-|
| **CBZ** | Comic Book ZIP archives containing page images. Text lookups require OCR later, unless the archive also carries a `.mokuro` entry. |
| **Mokuro** | Pre-processed manga with text already extracted. Lookups work immediately after import. |

## Importing Mokuro-Processed Manga

[Mokuro](https://github.com/kha-white/mokuro) pre-processes manga pages and stores OCR data with page positions. Mekuru supports both `.mokuro` and Mokuro `.html` manifests.

To import:

1. Open the **Library** tab.
2. Tap **+**.
3. Choose **Manga (Mokuro)**.
4. Select the folder that contains the manga data.
5. Choose the `.mokuro` or `.html` manifest from the picker shown for that folder.

Mekuru then loads the manifest, finds the matching page-image folder, detects individual words, and builds tap targets for lookups.

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

The import creates the manga entry and extracts the page images, but it does **not** add text overlays yet. The exception is a CBZ that includes a `.mokuro` entry (Mekuru's own [CBZ export](#exporting-manga-as-cbz) writes one): its OCR data is imported and lookups work right away.

## Running OCR for CBZ Manga

After import, long-press the manga entry in the library to open its actions. From there, Mekuru can show:

- **Recognize text** - choose on-device OCR or your remote server, and scan missing pages or replace existing OCR
- **Resume OCR** - continue a partial OCR pass
- **Pause OCR** - pause the current OCR job and keep progress so far
- **Delete OCR** - remove OCR text and word overlays; for replaced Mokuro/HTML books this restores the original imported OCR
- **Build Word Overlays** - rebuild tap targets when OCR text exists but word segmentation is missing
- **Export as CBZ** - share the page images, and any OCR text, as a comic archive; see below

You can also start OCR from inside the manga reader: tap **Recognize** to scan the visible page, or hold it for options. See [On-device OCR](../manga/on-device-ocr.md).

Both OCR paths need **Pro**. On-device OCR uses models you download once; remote OCR also needs a configured custom OCR server.

## Exporting Manga as CBZ

Long-press any manga and choose **Export as CBZ** to share its page images as a comic archive through the Android share sheet, which includes saving to a folder. When the manga has OCR text, the archive also carries a `.mokuro` entry, so importing that CBZ into Mekuru again brings the lookups back without re-running OCR. Manga linked from a folder outside Mekuru cannot be exported this way, since you already have their images.

## Converting an Image-Only EPUB

Some manga are sold as EPUBs where every page is a single image. Long-press such a book in the library and choose **Convert to manga**: the book moves to the manga reader with its page-image view modes, its reading position resets, and the EPUB copy stored in the app is removed. Lookups work once you run OCR, or export the book as CBZ and process it with mokuro. To undo, re-import the original file.

## Differences from EPUB

Because manga pages are images rather than flowing text, some features work differently:

| Feature | EPUB | Manga |
|-|-|-|
| Dictionary lookups | Tap text directly | Use Mokuro data or OCR-generated overlays |
| Bookmarks | Yes | Yes |
| Highlights and notes | Pro (EPUB only) | No |
| Text layout settings | Yes | No |
| Image view modes | No | Yes |

## Next Steps

- [Reading Manga](../manga/cbz-reading.md) - view modes, reader settings, and overlays
- [Remote OCR](../manga/cloud-ocr.md) - Pro-powered OCR with your own server
- [On-device OCR](../manga/on-device-ocr.md) - Japanese manga OCR on your phone with separately downloaded models (Pro)
- [Custom OCR Server](../manga/custom-server.md) - using your own OCR endpoint
