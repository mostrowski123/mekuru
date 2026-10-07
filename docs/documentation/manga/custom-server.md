# Custom OCR Server

Connect Mekuru to an OCR server you run yourself, so you can use [remote OCR](cloud-ocr.md) on your manga. This is a Pro feature.

## Before you start

You need:

- **Mekuru Pro**. The **Custom OCR Server** setting only appears when Pro is active.
- **An OCR server that your phone can reach**, for example on a computer on your home network. The reference server is open source: [github.com/mostrowski123/mekuru-ocr](https://github.com/mostrowski123/mekuru-ocr). Its README explains how to install and run it.
- **The server's shared key**: the secret you set as `AUTH_API_KEY` on the server.

## Connect Mekuru to your server

1. Open **You › Settings › Reader Settings**.
2. In the **Manga** section, tap **Custom OCR Server**.
3. In **Server URL**, enter the server's full address, starting with `http://` or `https://`. For example: `http://192.168.1.100:8000`.
4. Tap **Test connection**. Mekuru checks that it can reach the server.
5. In **Custom shared key**, enter the same key as the server's `AUTH_API_KEY`.
6. Tap **Save**.

The **Custom OCR Server** row now shows your server's address. You can start a scan with **Remote** in the **Recognize text** sheet. See [Remote OCR (Pro)](cloud-ocr.md).

**Learn how to run your own server**, in the same dialog, opens the reference server's page.

## Use a server with a self-signed certificate

If your server uses `https://` with its own (self-signed) certificate, turn on **Accept self-signed certificate**. The switch appears once the address starts with `https://`.

Mekuru then accepts any certificate this server presents. Turn it on only for a server you trust.

## What the server must do

The reference server already does all of this. If you write your own server, it needs two endpoints. Mekuru adds their paths to the address you entered.

- **`GET /health`** returns JSON with `"status": "ok"`. **Test connection** uses it, without the key.
- **`POST /ocr`** receives one page image as a form upload in a field named `image`. Mekuru sends the key in the header `Authorization: Bearer <your key>`. The server returns JSON with `img_width`, `img_height` and `blocks`. Each block is a text block in the format mokuro uses: `box`, `vertical`, `font_size`, `lines_coords` and `lines`.

## Your key and your pages

- Mekuru keeps the key on this device only, in secure storage. Backups do not include it, so enter it again on a new device.
- Page images go only to the server you set, and only when you choose **Remote**.

!!! note "On iPhone and iPad"
    The first time Mekuru connects to a server on your home network, iOS asks whether Mekuru may find devices on your local network. Allow it, or Mekuru cannot reach the server. You can change this later in the iOS Settings app, under Mekuru.

## If something goes wrong

- **"Enter a full http:// or https:// server URL."** The address is missing `http://` or `https://` at the start.
- **"A shared key is required for custom servers."** Enter the key in **Custom shared key**.
- **"The server's certificate isn't trusted."** The server uses a self-signed certificate. Turn on **Accept self-signed certificate**.
- **Test connection fails.** Check that the server is running and that your phone is on the same network as the server.
- **You don't see Custom OCR Server.** Pro is not active on this device. Open **You › Settings › Pro** and tap **Restore Purchase** if you have bought it.

## Related pages

- [Remote OCR (Pro)](cloud-ocr.md)
- [On-device OCR](on-device-ocr.md)
- [App Settings](../settings/app-settings.md)
