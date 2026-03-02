# Cloud OCR

> **Paid feature** - Mekuru's built-in OCR requires a one-time in-app purchase to unlock.

Cloud OCR extracts text from CBZ manga pages so you can tap words and look them up.

## How the Current Workflow Works

1. Import a `.cbz` file from the **Library** tab.
2. Long-press the manga item in the library.
3. Choose **Run OCR**.
4. Mekuru reserves the required page credits, starts the job, and processes pages in the background.
5. Once text overlays are available, open the manga and tap the detected words.

> TODO: Add screenshot - Library action sheet showing the Run OCR action

## Background Processing

OCR runs in the background, so it can continue after you leave the library screen.

Depending on the current state, the long-press actions can change to:

- **Resume OCR** - continue a partial pass
- **Cancel OCR** - stop the background job and keep completed work
- **Remove OCR** - clear OCR text and overlays
- **Build Word Overlays** - rebuild tap targets when OCR text exists but word segmentation is still missing

## Unlock and Credits

- The built-in OCR unlock is a one-time purchase.
- It includes **150 starter page credits**.
- The current UI does not document extra credit packs beyond those starter credits.
- Credits are reserved before an OCR run starts.
- You can refresh the credit balance from the **OCR Purchases** screen.

## Account Linking and Restore

Restoring or buying OCR access can require linking a Google account. In Settings, the restore action may appear as **Sign In to Restore Purchases** until that account link is complete.

## Lookup Integration

Once OCR text is available, the detected words behave like Mokuro overlays and open the same dictionary lookup sheet used elsewhere in the app.

## Avoiding Page Credits

If you want to avoid the built-in page-credit flow, configure a custom OCR server instead. Custom servers do not consume page credits. See [Custom OCR Server](manga/custom-server.md).
