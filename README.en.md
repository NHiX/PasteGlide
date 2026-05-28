# PasteGlide

PasteGlide is a native macOS clipboard manager written in Swift/AppKit. It stores a local SQLite history, classifies copied content, shows fast cards, and can appear at the bottom, top, sides, or center of the screen.

Documentation en français: [README.md](README.md)

## Requirements

- macOS 14 or newer
- Swift 6 or newer
- Xcode Command Line Tools
- System SQLite via `libsqlite3`
- Vision.framework for local image OCR

## Run

From the project folder:

```bash
swift run
```

Build a macOS app bundle in `dist/`:

```bash
./scripts/build_app.sh
```

Generated bundles use this format:

```text
dist/PasteGlide_YYYY-MM-DD_HH-MM.app
```

## Shortcuts

The default global shortcut is `⌥⌘V`. It shows or hides the clipboard history panel.

Inside the panel:

- `←` / `→` / `↑` / `↓`: select a card
- `Return`: copy the selected card
- `Space`: show preview
- `Delete`: delete the selected card
- `⌘F`: focus search
- `⌘1` to `⌘7`: switch filter
- `Escape`: close the panel

## Usage

1. Launch PasteGlide.
2. Copy text, a URL, a YouTube link, numbers, a likely password, or an image.
3. Press `⌥⌘V`.
4. Search, filter, or navigate with the keyboard.
5. Click a card or press `Return` to put it back on the clipboard.

Right-click a card for quick actions:

- copy as plain text;
- open a link;
- save an image;
- reveal or hide a password;
- pin or unpin;
- delete the card;
- delete all cards of the same type.

## Filters and Stats

Below search, PasteGlide shows:

- total stored objects;
- image, text, number, password, and YouTube counts;
- date and time of the latest card.

Quick filters show:

- all items;
- pinned items only;
- YouTube;
- text;
- passwords;
- numbers;
- images.

## Panel Positions

In preferences, the panel can be shown:

- bottom, above the Dock;
- top;
- left;
- right;
- center of the screen.

`Left`, `Right`, and `Center` use a vertical scrolling column. `Bottom` and `Top` use a horizontal scrolling row.

## Privacy

PasteGlide can:

- skip likely passwords;
- mask sensitive content in cards;
- exclude applications by name or bundle id;
- pause capture for 5, 15, or 30 minutes from the macOS menu bar menu.

Password detection is heuristic because macOS does not expose the original copy context.

## Images and OCR

Images are converted to PNG, stored as base64 in SQLite, and displayed as thumbnails.

When OCR is enabled, PasteGlide uses Apple's Vision.framework locally. Recognized text is searchable and visible in previews.

## Cleanup

Preferences let you:

- set how many items to keep;
- set retention in days;
- delete images;
- delete items older than the configured retention;
- clear all history.

Pinned items survive automatic retention.

## Storage

The local database is created here:

```text
~/Library/Application Support/PasteGlide/history.sqlite
```

Logical schema:

- `id`: SQLite identifier
- `kind`: card type
- `content`: full content
- `preview`: displayed preview
- `ocr_text`: recognized image text
- `ocr_attempted`: OCR processing status
- `is_pinned`: pinned card flag
- `created_at`: creation date
- `content_hash`: consecutive duplicate prevention hash

## Import and Export

The macOS menu bar menu can:

- export the SQLite history;
- import an existing history.

## Tests

```bash
swift run PasteGlideCoreTests
```

## Troubleshooting

If `⌥⌘V` does not respond, check whether another app already uses this shortcut.

If history looks empty, copy a new item after launching PasteGlide: the app monitors the clipboard only while running.

To reset history:

```bash
rm ~/Library/Application\ Support/PasteGlide/history.sqlite
```
