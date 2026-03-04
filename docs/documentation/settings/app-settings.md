# App Settings

Mekuru's **Settings** screen mixes app-wide preferences, reading defaults, OCR controls, downloads, and support links.

Many reader behaviors are split between global defaults here and per-book quick settings inside the reader. See [Display Settings](reading/display-settings.md).

## General

### Startup Screen

Choose which screen opens first:

- **Library**
- **Dictionary**
- **Last Read Book**

## Appearance

### Theme

Choose **Light**, **Dark**, or **System default** for the app theme.

### Color Theme

Pick the app's accent color theme. This changes the Material color seed used throughout the app.

## Reading Defaults

The **Reading Defaults** section controls the shared EPUB defaults:

- Font size
- Color mode
- Sepia intensity
- Keep screen on
- Horizontal and vertical margins
- Swipe sensitivity

Per-book reader controls such as **Vertical Text**, **Reading Direction**, and **Disable Links** are changed inside the reader instead of here.

## Dictionary

The Dictionary section includes:

- **Manage Dictionaries** - import, reorder, enable, disable, or delete installed dictionaries
- **Lookup Font Size** - change the dictionary sheet text size
- **Filter Roman Letter Entries** - hide entries whose headword uses English letters
- **Auto-Focus Search** - open the keyboard automatically when the Dictionary tab is selected

### AnkiDroid Integration

On Android, **AnkiDroid Integration** opens the field-mapping setup used for direct card creation. See [Exporting to Anki](vocabulary/anki-export.md).

## Pro

The **Pro** section handles Mekuru's one-time paid upgrade.

- The app may show **Sign In to Restore Pro** when the linked account is still anonymous.
- Restoring or buying Pro can require linking a Google account first.
- The Pro screen shows whether Pro is locked or unlocked.
- Pro unlocks **Auto-Crop**, **Book Highlights**, and **Custom OCR Server**.

## Manga OCR (Custom OCR Server)

The **Custom OCR Server** setting controls the remote OCR endpoint used for CBZ manga processing.

- Add your own server URL
- Add the matching shared `AUTH_API_KEY`
- Mekuru sends the key as a bearer token to your server

See [Custom OCR Server](manga/custom-server.md) for server setup and the API contract.

## Downloads

The **Downloads** screen installs and removes built-in resources:

- JMdict
- JMdict with examples
- KANJIDIC
- KanjiVG
- JPDB frequency data

See [Downloads](getting-started/downloadable-data.md) for details.

## About & Feedback

### Send Feedback

You can send bug reports or feature requests from inside the app.

### About Mekuru

The About screen shows the app version, license details, attributions, and links such as the privacy policy.
