# Custom OCR Server

Mekuru can send manga OCR requests to a compatible self-hosted server for remote manga OCR.

## Pro Requirement

The **Custom OCR Server** feature is unlocked by the one-time **Pro** upgrade.

## Server Repository

The reference server is public on GitHub:

**[github.com/mostrowski123/mekuru-ocr](https://github.com/mostrowski123/mekuru-ocr)**

## Authentication Contract

Custom OCR servers use a shared `AUTH_API_KEY`.

- Configure the same shared secret on the server and in Mekuru.
- Mekuru sends the key as `Authorization: Bearer <key>`.
- The custom key is stored locally on-device.

## Configuring the App

1. Open **Settings**.
2. Open **Custom OCR Server**.
3. Enter the server URL.
4. Enter the matching shared key.
5. Save the settings.

## Compatibility

Your custom server must implement the same OCR API contract expected by Mekuru. The reference repository above provides the intended behavior and request format.
