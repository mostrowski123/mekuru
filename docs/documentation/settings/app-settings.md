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

## OCR Purchases

The **OCR Purchases** section handles Mekuru's built-in OCR entitlement.

- The app may show **Sign In to Restore Purchases** when the OCR account is still anonymous.
- Restoring or buying OCR access can require linking a Google account first.
- The OCR purchase screen shows whether OCR is unlocked and how many page credits are currently available.
- The OCR purchase screen can refresh the credit balance from the server.
- The built-in OCR unlock is a one-time purchase that includes 150 starter page credits.

## Manga OCR (OCR Server URL)

The **OCR Server URL** setting controls whether Mekuru sends OCR requests to the built-in Mekuru server or to a custom endpoint.

- **Built-in server** - uses page credits and app authentication
- **Custom server** - does not consume page credits
- **Custom server key** - Mekuru sends a shared bearer token to custom servers

In the current UI, the OCR Server URL setting is usually editable after OCR is unlocked. If the billing status check fails, the app may still allow manual editing so you can switch endpoints.

See [Custom OCR Server](manga/custom-server.md) for the custom-server contract.

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
