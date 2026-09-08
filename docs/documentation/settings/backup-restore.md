# Backup & Restore

Mekuru has two kinds of backup. They are shown as two separate cards on the **Backup & Restore** screen, each with its own file type, so you always know which one you are using.

![Backup and Restore screen](../screenshots/settings-backup-restore.jpg)

| | Reading data backup | Full backup |
|---|---|---|
| File | small `.mekuru` | large `.zip` |
| Contains | settings, dictionary order, bookmarks, highlights, vocabulary, reading stats, per-book settings | everything: books, manga, dictionaries, settings and all reading data |
| Restoring | merges into what is already in Mekuru | replaces everything in Mekuru on this device |
| Runs automatically | yes, if you turn it on | no, manual only |

Open **Settings** from the gear icon on the **You** tab, then **Backup & Restore**.

## Reading data backup (.mekuru)

Use this for a light, frequent safety net.

1. Tap **Create reading data backup**, then **Export reading data backup (.mekuru)** to save the latest one wherever you like.
2. **Auto-backup interval** can create them daily or weekly instead. The last five automatic backups are kept on the device.

A reading data backup does **not** contain your EPUB, manga or dictionary files.

### Importing reading data

Tap **Import reading data (.mekuru)** and pick the file. Your current settings are overwritten; everything else merges:

- Books restore as entries that wait for their content. Re-import the same EPUB or manga file and its bookmarks, highlights, progress and settings reattach automatically.
- **Reading-time history** is only restored onto a device that has no history of its own.
- **Vocabulary stats** are merged rather than overwritten.
- Matching dictionary order and enabled states can be applied later from Dictionary Manager.

## Full backup (.zip)

Use this to move to a new phone, or before wiping a device. It is one file with your whole library in it, so it can be several gigabytes.

Both the export and the restore run as a background job: Mekuru shows a full-screen page with a progress bar while the job runs, and a notification tracks it if you switch to another app. Nothing else in Mekuru can be used until the job finishes or you cancel it. If Mekuru is closed or the phone restarts in the middle, the job picks up where it left off the next time you open Mekuru.

### Exporting

1. Tap **Export full backup (.zip)…**. Mekuru may ask to show notifications; the backup runs either way, the permission only lets you watch its progress from outside the app.
2. Choose a folder (your phone's storage, an SD card, or a cloud folder that supports saving files).
3. Wait on the **Backing up** page, or leave Mekuru and come back later. Tap **Done** when it finishes. You can cancel at any time; a cancelled export leaves no file behind.

The file is named `mekuru-full-backup-<date>-<time>.zip`. While it is being written it carries a `.partial` ending, so a half-finished file is never mistaken for a backup.

Unzip it on a computer and you will find:

| Folder or file | What is in it |
|---|---|
| `Books/<title>/` | one folder per EPUB, with the original `.epub` file inside |
| `Manga/<title>/` | one folder per manga, with its page images |
| `Mekuru data/` | Mekuru's own files: the database (dictionaries, progress, vocabulary, statistics, collections), the settings file and any custom covers |
| `README.txt` | a short description of the layout and how to restore |
| `manifest.json` | a summary Mekuru checks before restoring |

You can copy individual books out of the archive freely. Do not rename, move or edit files inside it if you plan to restore from it.

Not included:

- Manga you linked from a folder outside Mekuru. Their pages stay in your folder; after restoring on another device, open the manga and re-link the folder.
- The downloaded UniDic-lite dictionary and KanjiVG data. Download them again from Settings.
- The reading data backup history.
- Pro. It is re-checked with Google Play the first time Mekuru opens after a restore.

### Restoring

Restoring a full backup **replaces everything in Mekuru on this device**: its books, manga, dictionaries, settings and reading data. Nothing outside Mekuru is touched.

1. Tap **Restore full backup (.zip)…** and pick the file.
2. Mekuru shows what is in the file (books, dictionaries, size, when it was made) and what is in Mekuru on this device right now. Tap **Continue**.
3. Read the red confirmation, tick **I understand that Mekuru's data on this device will be deleted**, then tap **Delete Mekuru data and replace**. Until the box is ticked the button stays disabled.
4. The **Restoring** page shows the files being copied. You can still cancel here; nothing in Mekuru has changed yet.
5. When the copy finishes, tap **Close Mekuru**. Mekuru closes to swap the data in. If you had left the app, a notification tells you the restore is ready to finish; just open Mekuru.
6. Open Mekuru again. Your restored library appears and a "Full restore complete" message confirms it.

If anything goes wrong before the final step, nothing on the device changes and Mekuru tells you why. If the restore cannot be completed after the restart, your previous data is kept and a message says so.

Things to know:

- A full backup made with a newer version of Mekuru cannot be restored by an older one. Update Mekuru first.
- Server connections (Komga, Kavita) come back disabled. Re-enter their credentials to turn them on again.
- If you pick a `.mekuru` file here, or a `.zip` in the reading data importer, Mekuru points you to the right button instead of importing the wrong kind.
- A `.zip` that was cut short while copying or downloading is refused before anything starts; copy it again from where it was saved.
