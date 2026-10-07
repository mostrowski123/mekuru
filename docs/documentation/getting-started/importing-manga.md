# Importing Manga

Add manga to your library from a mokuro folder or a CBZ file, so you can read it and tap its words.

## Before you start

Mekuru imports manga in two forms:

- **Mokuro folder.** Mokuro is a free tool you run on a computer. It reads the text on manga pages with OCR (reading the text in an image) and saves that text next to the page images. Mekuru uses this text, so you can tap words as soon as the manga is imported.
- **CBZ archive.** A CBZ file is a `.zip` file of comic page images, renamed to `.cbz`. It usually has pictures only, so you can't tap words until OCR reads the text. OCR in Mekuru needs Pro. A CBZ that also holds mokuro data, such as one exported from Mekuru, keeps its text.

| | Mokuro folder | CBZ archive |
|-|-|-|
| You choose | A folder | One or more `.cbz` files |
| Tap words right away | Yes | Only if it holds mokuro data |
| Needs Pro | No | Only to run OCR |

Pages can be JPEG, PNG, WebP, GIF, BMP or AVIF images.

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
6. Mekuru lists the manga files it found. Tap the one you want.

The manga appears in your library, and its words are ready to tap. To learn how to make mokuro files, tap **What is Mokuro?** under **Mokuro folder**.

!!! note "On iPhone and iPad"
    Mekuru copies the pages into the app, so the manga uses storage space on your device. You can move or delete the original folder afterwards.

On Android, Mekuru reads the pages from the folder you chose. Keep that folder where it is. If you move, rename or delete it, the pages go missing in Mekuru.

## Import a CBZ file

1. Open the **Library** tab.
2. Tap **+**.
3. Tap **Import Manga**.
4. Tap **CBZ archive**.
5. Choose one or more `.cbz` files.

The manga appears in your library. Mekuru names it after the file.

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

## Related pages

- [Reading Manga](../manga/cbz-reading.md)
- [On-device OCR](../manga/on-device-ocr.md)
- [Custom OCR Server](../manga/custom-server.md)
- [Importing Books (EPUB and PDF)](importing-books.md)
