# Furigana

Mekuru can show furigana (ruby readings) above kanji while you read an EPUB, with a per-book setting that ranges from no furigana at all to readings on every kanji — including a JLPT mode that only annotates kanji above your study level and a WaniKani mode that skips the kanji you have already learned.

![EPUB quick settings sheet showing the furigana modes](../screenshots/reader-quick-settings-furigana.jpg)

## Furigana Modes

Open the quick settings sheet inside the reader and pick a **Furigana** mode for the current book:

| Mode | What it shows |
|-|-|
| **Off** | No furigana, including ruby text the publisher included |
| **Book** | Exactly the ruby text the publisher included, unchanged |
| **All kanji** | Generated furigana on every kanji word |
| **JLPT** | Furigana only on kanji above the JLPT level you pick |
| **WaniKani** | Furigana only on words that contain a kanji you have not yet learned on WaniKani |

When **JLPT** is selected, a **Furigana for kanji above** picker appears with levels N5 through N1. Choose N3, for example, and only kanji beyond the N3 kanji lists get readings.

## WaniKani Mode

Link your WaniKani account first: open **Settings > Reading > WaniKani** (Settings is behind the gear icon on the **You** tab), tap **Get an API token** to create a read-only token on WaniKani, paste it, and tap **Link account**. Mekuru downloads the SRS stage of every kanji, refreshes the list when you open the app (at most once an hour), and **Sync now** on the same screen forces a refresh.

With **WaniKani** selected in the reader, a **Hide furigana at** row picks which stage counts as known: **Apprentice and up**, **Guru and up**, **Master and up**, **Enlightened and up**, or **Burned** (the default). A word keeps its furigana if any of its kanji is below that stage or missing from your WaniKani list. Until an account is linked the sheet shows a **Link your WaniKani account** button instead, and every kanji counts as unknown.

**Unlink** forgets the token and the kanji list. A backup restores the kanji list but not the token, so after a restore the WaniKani screen asks you to link again to keep it updated.

## Publisher Ruby Follows the Same Rule

In **JLPT** and **WaniKani** modes the filter also applies to furigana that was already in the book: publisher-authored ruby on kanji you know is hidden, so books with full ruby stay readable as you progress.

## Accuracy

Generated readings come from Mekuru's built-in analyzer. Installing the optional [Enhanced Furigana Dictionary](../getting-started/downloadable-data.md#furigana-word-analysis) improves reading accuracy — it does not turn furigana on or off.

## Exporting

The same furigana engine can bake readings into a standalone EPUB file for use in other readers. See [Furigana EPUB Export](../library/furigana-export.md).
