# Book Servers (Komga & Kavita)

Mekuru can connect to a self-hosted Komga or Kavita server, browse and download its books and manga, and keep your reading progress in sync with it, so a book you stop reading on one device continues from the same place on another. No Pro upgrade is needed.

## Adding a Server

1. Open **Settings** (gear icon on the **You** tab), then **Book servers** under **Server sync**.
2. Tap **Add server**, pick **Komga** or **Kavita**, and enter a **Name** and the **Server URL** (for example `https://server:port`).
3. Enter your credentials: a Komga API key or `user:password`, or a Kavita API key. They are stored only on this device.
4. Tap **Test** to check the connection, then save.

Tap a server to browse it. **Edit** changes its details or disables it; removing a server drops the connection but keeps the downloaded books and their reading progress on the device.

## Downloading Books

From a server's browse screen, pick a library and series, or use **Search this server**, then tap a book to download it into Mekuru as an EPUB or manga. The **+** button on the **Library** tab also lists **Download from _server_** for every enabled server.

If a title is already on your device, Mekuru asks whether to **Link existing copy**, so the book you already have syncs with the server, or **Download anyway** for a separate copy.

## Linking Books You Already Have

**Link existing books** on the servers screen matches your library against the server by title, links every unambiguous match, and syncs their progress. Titles that match more than one server book are skipped; link those from the browse screen instead.

## How Progress Sync Works

- Opening a linked book pushes your local progress if it is newer than the last sync, then pulls the server's position, which is applied only when it is newer than yours.
- While you read, progress is pushed in the background a moment after each change.
- **Sync now** in the app bar of the servers screen pushes every linked book at once.
- Failed syncs are retried on the next change or open. Progress can be delayed, never lost.

Only reading progress syncs. Bookmarks, highlights, and vocabulary stay on the device.

## Backups

A [full backup](../settings/backup-restore.md) restores server connections disabled and without their credentials. Edit each server and enter the credentials again to turn it back on.
