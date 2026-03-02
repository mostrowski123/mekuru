# Remote OCR

> **Pro feature** - Remote OCR requires the one-time **Pro** upgrade.

Remote OCR extracts text from CBZ manga pages so you can tap words and look them up.

## How the Workflow Works

1. Import a `.cbz` file from the **Library** tab.
2. Unlock **Pro**.
3. Open **Settings > Custom OCR Server** and enter your own server URL plus shared key.
4. Long-press the manga item in the library.
5. Choose **Run OCR**.
6. Mekuru uploads page images to your configured server and processes pages in the background.
7. Once text overlays are available, open the manga and tap the detected words.

> TODO: Add screenshot - Library action sheet showing the Run OCR action

## Background Processing

OCR runs in the background, so it can continue after you leave the library screen.

Depending on the current state, the long-press actions can change to:

- **Resume OCR** - continue a partial pass
- **Cancel OCR** - stop the background job and keep completed work
- **Remove OCR** - clear OCR text and overlays
- **Build Word Overlays** - rebuild tap targets when OCR text exists but word segmentation is still missing

## Pro Access

- Pro is a one-time purchase.
- Restoring or buying Pro can require linking a Google account first.
- The Settings screen can show **Sign In to Restore Pro** until that link is complete.

## Lookup Integration

Once OCR text is available, the detected words behave like Mokuro overlays and open the same dictionary lookup sheet used elsewhere in the app.

## Custom Server Requirement

Mekuru now expects a custom OCR server for remote OCR. If your OCR server setting still points to Mekuru's legacy built-in endpoint, the app treats it as not configured and sends you to custom server setup first.
