# Book Servers (Komga & Kavita)

Connect Mekuru to your own Komga or Kavita server to download its books and manga and keep your reading position in sync.

Komga and Kavita are apps you run yourself, for example on a home computer, to store a library of books and comics. You do not need Pro.

## Before you start

You need:

- Your server's address, starting with `http://` or `https://`, for example `https://server:port`.
- For Komga: an API key, or your user name and password.
- For Kavita: an API key. Kavita does not accept a password here.

Mekuru keeps your key or password only on this device. It is never put in a backup.

## Add a server

1. Go to **You › Settings › Book servers**. It is in the **Server sync** section.
2. Tap **Add server**.
3. Choose **Komga** or **Kavita**.
4. Optional: enter a **Name**. If you leave it empty, Mekuru uses "Komga" or "Kavita".
5. Enter the **Server URL**.
6. Enter your key:
    - Komga: in **API key (or user:password)**, enter an API key, or your user name and password with a colon between them, like `user:password`.
    - Kavita: in **API key**, enter your API key.
7. Tap **Test**. **Connection OK** means Mekuru reached the server and your key works.
8. Tap **Save**.

### Self-signed certificates

A home server that uses `https://` often has its own certificate, called a self-signed certificate, instead of one from a certificate authority. Mekuru does not trust these unless you allow it.

When the **Server URL** starts with `https://`, the dialog shows **Accept self-signed certificate**. Turn it on only for your own server: Mekuru then accepts any certificate this server presents.

If the switch is off and the certificate is not trusted, testing, browsing and downloading show a message that the server's certificate isn't trusted.

## Download books

1. In **You › Settings › Book servers**, tap the server. You can also tap **+** in the **Library** tab and then **Download from** followed by your server's name.
2. Tap a library.
3. Tap a series. To find one, type in **Search this server** and press the search key. The search covers the library you opened.
4. Tap a book with the download icon. Each book shows **EPUB** or its number of pages.

A progress circle shows while the book downloads. You can leave the screen. When the book is in your library, a message at the bottom of the screen says so. A green check mark marks books that are on your device; tap one to open it.

Mekuru reads these formats from a server:

- EPUB books.
- CBZ files (a zip of comic page images).
- PDF files. After the download, Mekuru turns each page into an image. For a long PDF this can take a few minutes.

Comics in other archive formats, such as CBR, cannot be imported.

### A book you already have

If your library already has a book with the same title that is not linked to a server, Mekuru asks what to do:

- **Link existing copy**: your copy now syncs its reading position with the server. Nothing is downloaded.
- **Download anyway**: downloads a second copy.

### Link many books at once

1. Go to **You › Settings › Book servers**.
2. Tap **Link existing books** (the checklist icon next to the server).

Mekuru matches the books in your library with the server's books by title. It links each clear match and syncs its position. A title that matches more than one book on the server is skipped. To link it, tap the book in the server's book list and choose **Link existing copy**.

## Downloads in the background

On Android, a download keeps going after you leave or close Mekuru. It waits for a network connection and continues from where it stopped. A book that finished while Mekuru was closed is added to your library the next time you open Mekuru.

!!! note "On iPhone and iPad"
    Downloads keep going after you leave Mekuru, and iOS shows their progress in a Live Activity. If you stop the Live Activity, or iOS ends it, the downloads stop and Mekuru shows **Download stopped**. Tap the book again to download it. If Mekuru is closed in the middle of a download, the download continues the next time you open Mekuru.

## Keep your reading position in sync

The books you downloaded from a server, or linked to it, sync their reading position both ways:

- When you open a linked book, Mekuru sends your position if you have read since the last sync. Then it checks the server. If the server's position is newer, for example because you read further on another device, Mekuru moves to it.
- While you read, Mekuru sends your position a couple of seconds after each page turn.
- When you finish a book, Mekuru marks it as read on the server.
- To send every changed position now, tap **Sync now** (the sync icon) at the top of **Book servers**.

Only the reading position syncs. Bookmarks, highlights and saved words stay on this device.

With Kavita, EPUB positions are less exact. Kavita stores an EPUB position by its own page count, so the book can open a little before the place where you stopped.

## Read without a connection

- Downloaded books are on your device, so you can read them offline.
- Mekuru saves your position on the device. If the server cannot be reached, Mekuru tries again when you open the book, when you tap **Sync now**, and every few minutes while you read. Your position can reach the server late, but it is not lost.
- Browsing a server needs a connection. If the server cannot be reached, Mekuru shows the error and a **Retry** button.
- If a download loses its connection, it continues from where it stopped when the connection comes back. After several failed tries in a row, it stops and shows **Download failed**.

## Change or remove a server

In **You › Settings › Book servers**, tap **Edit** (the pencil icon) next to the server.

- To change the details, edit them and tap **Save**. Leave the key field empty to keep the current key.
- To pause a server, turn off **Enabled**. Its books stop syncing, and it is no longer listed under **+** in the library.
- To remove a server, tap **Remove**, then **Remove** again. Downloaded books and their reading positions stay on this device.

## If something goes wrong

- **Test** shows **Failed:** and a message: check the **Server URL** and your key, and make sure the server is running.
- The certificate message appears: see [Self-signed certificates](#self-signed-certificates).
- A message says a book is no longer on the server and stopped syncing. The server no longer has the book under the same ID, for example after a rescan. Find the book in the server's book list, tap it, and choose **Link existing copy**.
- After you restore a backup, your servers come back turned off and without their keys. Tap **Edit**, enter the key, turn on **Enabled**, and tap **Save**.

!!! note "On iPhone and iPad"
    The first time Mekuru connects to a server on your home network, iOS asks whether Mekuru may find devices on your local network. Allow it, or Mekuru cannot reach the server. You can change this later in the iOS Settings app, under Mekuru.

## Related pages

- [Importing Books (EPUB and PDF)](../getting-started/importing-books.md)
- [Importing Manga](../getting-started/importing-manga.md)
- [Backup & Restore](../settings/backup-restore.md)
