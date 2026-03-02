# Custom OCR Server

Mekuru can send manga OCR requests to a compatible self-hosted server instead of the built-in Mekuru endpoint.

## Server Repository

The reference server is public on GitHub:

**[github.com/mostrowski123/mekuru-ocr](https://github.com/mostrowski123/mekuru-ocr)**

## Authentication Contract

Custom OCR servers use a shared `AUTH_API_KEY`.

- Configure the same shared secret on the server and in Mekuru.
- Mekuru sends the key as `Authorization: Bearer <key>`.
- The custom key is stored locally on-device.

## Credits and Billing

Custom OCR servers do **not** consume Mekuru page credits.

## Configuring the App

1. Open **Settings**.
2. Open **OCR Server URL**.
3. Enter the server URL.
4. Enter the matching shared key.
5. Save the settings.

In the current app UI, the OCR Server URL setting is usually editable after OCR is unlocked. If the billing status check fails, the app may still allow manual editing so you can switch away from the built-in endpoint.

## Compatibility

Your custom server must implement the same OCR API contract expected by Mekuru. The reference repository above provides the intended behavior and request format.
