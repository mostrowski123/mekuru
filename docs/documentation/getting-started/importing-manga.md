# Importing Manga

Add manga to your library from a mokuro folder or a manga archive (a CBZ, CBR, ZIP or RAR file), so you can read it and tap its words.

## Before you start

Mekuru imports manga in two forms:

- **Mokuro folder.** Mokuro is a free tool you run on a computer. It reads the text on manga pages with OCR (reading the text in an image) and saves that text next to the page images. Mekuru uses this text, so you can tap words as soon as the manga is imported.
- **Manga archive.** A CBZ file is a `.zip` file of manga page images, renamed to `.cbz`. A CBR file is the same thing as a `.rar` file. Mekuru imports all four (`.cbz`, `.cbr`, `.zip` and `.rar`). An archive usually has pictures only, so you can't tap words until OCR reads the text. OCR in Mekuru needs Pro. An archive that also holds mokuro data, such as a CBZ exported from Mekuru, keeps its text.

| | Mokuro folder | Manga archive |
|-|-|-|
| You choose | A folder, then one or more volumes in it | One or more `.cbz`, `.cbr`, `.zip` or `.rar` files |
| Tap words right away | Yes | Only if it holds mokuro data |
| Needs Pro | No | Only to run OCR |

Pages can be JPEG, PNG, WebP, GIF, BMP or AVIF images.

!!! tip "A folder of page images"
    To import a folder that holds only page images, zip the folder on your computer or phone, then import the `.zip` file.

## Import a mokuro folder

Mokuro writes a `.mokuro` file (older versions write an `.html` file) next to a folder of page images with the same name:

```text
manga_title.mokuro
manga_title/
  001.jpg
  002.jpg
```

Older `.html` output also has an `_ocr` folder:

```text
manga_title.html
manga_title/
  001.jpg
  002.jpg
_ocr/manga_title/
  001.json
  002.json
```

To import:

1. Open the **Library** tab.
2. Tap **+**.
3. Tap **Import Manga**.
4. Tap **Mokuro folder**.
5. Choose the folder that holds the `.mokuro` or `.html` file. Don't choose the images folder.
6. Mekuru lists the manga files it found, with one file for each volume already ticked. Tick the volumes you want, then tap **Import**.

Each volume appears in your library, and its words are ready to tap. To learn how to make mokuro files, tap **What is Mokuro?** under **Mokuro folder**.

!!! note "On iPhone and iPad"
    Mekuru copies the pages into the app, so the manga uses storage space on your device. You can move or delete the original folder afterwards.

On Android, Mekuru reads the pages from the folder you chose. Keep that folder where it is. If you move, rename or delete it, the pages go missing in Mekuru.

## Import a manga archive

1. Open the **Library** tab.
2. Tap **+**.
3. Tap **Import Manga**.
4. Tap **Manga archive**.
5. Choose one or more `.cbz`, `.cbr`, `.zip` or `.rar` files.

Each manga appears in your library. Mekuru names it after its file.

Mekuru can't import:

- Password-protected archives.
- RAR archives split into parts (`.part1.rar`, `.part2.rar` and so on).
- Solid RAR archives made with RAR 4 or older. Solid RAR files from RAR 5 import as usual.

To import one of these, extract the pages on a computer and put them in a `.zip` or `.cbz` file.

## Make the words tappable

A manga without text needs OCR before you can tap its words. OCR needs Pro. You can run it on your device, or on your own OCR server.

- **From the library:** press and hold the manga, then tap **Recognize text**.
- **In the manga reader:** tap the scan icon at the top to read the page you see. Press and hold the icon for more options.

See [On-device OCR](../manga/on-device-ocr.md) and [Custom OCR Server](../manga/custom-server.md).

## Convert an image-only EPUB

Some manga are sold as EPUB files where every page is one picture. Convert them, so they open in the manga reader.

1. Press and hold the book in the library.
2. Tap **Convert to manga**.
3. Read the message, then tap **Convert**.

The book now opens in the manga reader, and its reading position starts over. Mekuru deletes its own copy of the EPUB. To undo, import the original file again.

To tap words afterwards, run OCR, or export the book as CBZ and process it with mokuro.

If the pages are not all single pictures, Mekuru says **This EPUB doesn't look like a manga — its pages aren't single images** and leaves the book as it is.

## Export manga as CBZ

1. Press and hold the manga in the library.
2. Tap **Export as CBZ**.
3. In the share sheet, choose where to send or save the file. On iPhone and iPad, tap **Save to Files** to keep it on your device.

If the manga has text from mokuro or OCR, the CBZ also holds that text as mokuro data. Import the CBZ into Mekuru again, for example on a new phone, and its words are tappable without new OCR.

On Android, you can't export manga imported from a mokuro folder. Mekuru says **This book's images are stored outside the app, so it can't be exported**. You already have its pages in that folder.

## If something goes wrong

- **No .mokuro or .html files found in the selected folder:** you chose the wrong folder. Choose the folder that holds the `.mokuro` or `.html` file, not the images folder inside it.
- **Pages are missing (Android):** the mokuro folder was moved, renamed or deleted. Import the manga again from its new place.
- **This file is password-protected:** Mekuru can't open the archive. Extract the pages with the password, then import them as a `.zip` file.
- **This RAR file uses solid compression from an older version of RAR, which Mekuru can't open:** extract the pages on a computer, put them in a `.zip` or `.cbz` file, and import that.

## Related pages

- [Reading Manga](../manga/cbz-reading.md)
- [On-device OCR](../manga/on-device-ocr.md)
- [Custom OCR Server](../manga/custom-server.md)
- [Importing Books (EPUB and PDF)](importing-books.md)
