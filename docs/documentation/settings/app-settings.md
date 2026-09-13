# App Settings

Mekuru's **Settings** screen collects app-wide preferences, reader defaults, downloads, backup, and support links. Open it from the gear icon in the top corner of the **You** tab.

Many reader behaviors are split between global defaults here and per-book quick settings inside the reader. See [Display Settings](../reading/display-settings.md).

## General

### App Language

Override the app's interface language, or follow the system language.

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

## Reading

The **Reader Settings** entry opens a dedicated screen with the shared reader defaults — text size, colors, margins, the **Animations** switch for e-ink displays, and manga defaults — grouped into **All books**, **EPUB**, and **Manga** sections. The Manga section also holds **White Threshold** (auto-crop tuning) and the **Custom OCR Server** configuration.

**WaniKani** links your WaniKani account with an API token so the reader's WaniKani furigana mode can hide readings for kanji you have learned. The row reads **Linked as _username_** once connected. See [Furigana](../reading/furigana.md#wanikani-mode).

See [Display Settings](../reading/display-settings.md) for the full list of controls.

## Dictionary

The Dictionary section includes:

- **Manage Dictionaries** - import, reorder, enable, disable, or delete installed dictionaries
- **Lookup Font Size** - change the dictionary sheet text size
- **Filter Roman Letter Entries** - hide entries whose headword uses English letters
- **Auto-Focus Search** - open the keyboard automatically when the Dictionary tab is selected

## Vocabulary & Export

On Android, **AnkiDroid Integration** opens the field-mapping setup used for direct card creation. See [Exporting to Anki](../vocabulary/anki-export.md).

## Server Sync

**Book servers** manages connections to self-hosted Komga or Kavita servers: add a server, browse and download its books, link copies you already have, and keep reading progress in sync. See [Book Servers](../library/book-servers.md).

## Pro

The **Pro** section handles Mekuru's one-time paid upgrade.

- The app may show **Sign In to Restore Pro** when the linked account is still anonymous.
- Restoring or buying Pro can require linking a Google account first.
- The Pro screen shows whether Pro is locked or unlocked.
- Pro unlocks **Auto-Crop**, **Book Highlights**, **On-device OCR**, and **Custom OCR Server**.
- **Test device speed** on the Pro screen runs on-device OCR on a sample page, so you can check how fast your phone is before buying.

## Downloads

The **Downloads** screen installs and removes built-in resources:

- JMdict
- JMdict with examples
- KANJIDIC
- KanjiVG
- JPDB frequency data
- Enhanced Furigana Dictionary

See [Downloads](../getting-started/downloadable-data.md) for details.

## Backup & Restore

Two kinds of backup live here: a small reading data backup (`.mekuru`) covering settings, bookmarks, highlights, vocabulary, collections, per-book reader settings, and reading history, with optional daily or weekly auto-backup; and a full backup (`.zip`) that packs your whole library — books, manga, dictionaries, and all reading data — for moving to a new phone. See [Backup & Restore](backup-restore.md).

## About & Feedback

### Send Feedback

You can send bug reports or feature requests from inside the app.

### About Mekuru

The About screen shows the app version, license details, attributions, and links such as the privacy policy.
