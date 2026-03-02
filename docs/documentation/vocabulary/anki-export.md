# Exporting to Anki

Mekuru supports two ways to move saved vocabulary into Anki.

## CSV Export

Export your saved words as an Anki-friendly CSV file. The export includes:

| Column | Content |
|-|-|
| Word | Saved expression |
| Reading | Saved reading |
| Meaning | Joined dictionary definitions |
| Furigana | Anki-formatted furigana markup generated from the saved word and reading |
| Context | The saved sentence context |

To export:

1. Open the **Vocabulary** tab.
2. Tap the **Export CSV** icon to enter selection mode.
3. Select the entries you want, or use **Select all**.
4. Tap the export icon again to export the selected entries.
5. Choose a save location in the file-save dialog.

The generated CSV can be imported into Anki on desktop or mobile.

## AnkiDroid Direct Integration

> **Android only** - This feature requires the [AnkiDroid](https://play.google.com/store/apps/details?id=com.ichi2.anki) app.

Mekuru can send cards directly to AnkiDroid from dictionary lookup cards.

> TODO: Add screenshot - AnkiDroid field-mapping configuration screen

### Setup

1. Go to **Settings > AnkiDroid Integration**.
2. Select the target deck.
3. Select the note type.
4. Map Mekuru's fields to the note type's fields.
5. Optionally set tags to apply to created cards.

### Sending Cards

Once configured, a send-to-AnkiDroid action appears on dictionary lookup cards. Tap it to create a card immediately.
