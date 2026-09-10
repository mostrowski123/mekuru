# On-device manga OCR

On-device OCR recognizes Japanese manga using manga-ocr (the same model as the
Mekuru OCR server) and Comic Text Detector.
It does not require an account, OCR credits, or a server.
After downloading the models, recognition works offline and page images stay
on your device.

## Download the models

Open **Settings → Downloads → Japanese manga OCR — manga-ocr**. The additional
download is approximately 296 MB; it is not included with the app. Transfers use
Wi-Fi by default. When you start or resume without Wi-Fi, confirm the model
download size to use mobile data. Approval applies to that download; saved
partial files are reused.
Interrupted downloads can resume, and installed model files are verified before
use. Removing the models does not remove text already recognized in your manga.

The initial version supports 64-bit Android devices. Recognition needs
substantial free memory and may be slow on older phones. Close other demanding
apps before starting a large scan.

## Scan a page or manga

In the reader, tap **Recognize text** and choose **On device**. Select the current
page or **Entire manga**. A two-page spread lists the individual page numbers.
The library's long-press actions also offer **Recognize text** for the whole manga.

By default, Mekuru scans only pages without OCR. A successfully scanned page with
no detected text is still considered processed. Text imported from Mokuro or
created by remote OCR is preserved.

Enable **Replace existing OCR** to recognize the selected pages again. Each old
result remains available until its replacement is saved. If you stop midway,
completed replacements stay and untouched pages retain their older results.

## Pause, cancel, and resume

- **Pause** saves progress and retains the remaining job for Resume.
- **Cancel scan** removes the remaining job but keeps completed OCR.
- An interrupted scan offers **Resume** after reopening the app.
- Failed pages are listed separately and can be retried.

Whole-manga scans show progress on the library cover and in an Android
notification; open the manga and tap **Recognize text** for controls and error
details. Completed pages remain readable while the rest of the manga is
processing.

Mekuru pauses when memory is low, the device is too hot, or the battery is below
15% without a charger. Connect a charger before resuming a job configured with
**Only while charging**. Android can also stop long background tasks; saved
progress remains available.

## Remote OCR and attribution

Choose **Remote** in the same sheet to use your existing server workflow.
Mekuru remembers your source choice and never uploads pages automatically when
local recognition fails. Remote OCR retains its existing access requirements.
See [Remote OCR](cloud-ocr.md).

About → Attributions contains offline licenses, model credits, and source notices.

A translucent overlay appears on the current page as OCR starts. It shows model
preparation, text-region progress, and **Cancel**. An estimated remaining time
appears after enough regions have been timed; the first scan starts by estimating.
Cancelling retains pages already saved. The reader keeps its page and zoom state.
