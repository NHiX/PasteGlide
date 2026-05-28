# PasteGlide

PasteGlide is a native macOS clipboard manager written in Swift/AppKit. It keeps a local history, classifies copied content, shows fast cards, and can appear at the bottom, top, sides, or center of the screen.

Documentation en français: [README.md](README.md)

## Requirements

- macOS 14 or newer
- Swift 6 or newer
- Xcode Command Line Tools
- System SQLite via `libsqlite3`
- Vision.framework for local image OCR

## Run

```bash
swift run
```

Build a macOS app bundle in `dist/`:

```bash
./scripts/build_app.sh
```

Build the distribution DMG with the app and an `/Applications` shortcut:

```bash
./scripts/build_dmg.sh
```

Also build the `PasteGlide.app` zip published with releases:

```bash
./scripts/build_zip.sh
```

GitHub releases publish `PasteGlide.dmg` and `PasteGlide.app.zip`. The DMG contains `PasteGlide.app` and an `Applications` shortcut for drag-and-drop installation. The app is ad-hoc signed so the macOS bundle stays consistent; without an Apple Developer ID certificate and notarization, macOS may still require right-clicking the app and choosing `Open`.

To produce an Apple-notarized DMG, you need an Apple Developer account, a `Developer ID Application` certificate, and a stored `notarytool` keychain profile. Then run:

```bash
DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)" \
NOTARYTOOL_PROFILE="pasteglide-notary" \
./scripts/notarize_dmg.sh
```

Without notarization, if macOS shows "Apple could not verify PasteGlide is free of malware", open `System Settings > Privacy & Security` and click `Open Anyway`, or right-click the app and choose `Open`.

## Shortcuts

The default global shortcut is `⌥⌘V`.

Inside the panel:

- `←` / `→` / `↑` / `↓`: select a card
- `Return`: copy and close
- `Space`: show preview
- `Delete`: delete card
- `⌘F`: focus search
- `⌘1` to `⌘8`: switch filter
- `Escape`: close

## Cards and Actions

PasteGlide detects:

- YouTube links;
- general web links;
- text;
- likely passwords;
- numbers;
- images.

Right-click a card to copy without closing, copy as plain text, open a link, save an image, reveal a password, pin, delete one card, or delete all cards of the same type.

## Search

Search works across type, preview, text content, and OCR.

Supported operators:

- `type:image`, `type:text`, `type:url`, `type:youtube`, `type:password`, `type:number`
- `pinned:true`
- `after:2h`, `after:7d`, `after:2w`

Example:

```text
type:image after:7d invoice
```

## Filters and Stats

Below search, PasteGlide shows the total stored items, per-type counts, and the latest card date. Quick filters show all items, pinned items, YouTube, links, text, passwords, numbers, or images.

## Panel Positions

The panel can appear at the bottom, top, left, right, or center of the screen. Left, right, and center use a vertical scrolling column; top and bottom use a horizontal row.

## Privacy

PasteGlide can:

- skip likely passwords;
- mask sensitive content;
- never capture images;
- limit captured image size;
- exclude applications;
- pause capture for 5, 15, or 30 minutes.

## Memory Footprint

Original images are no longer loaded with the card list. PasteGlide:

- stores original images as files in `Application Support`;
- keeps only a lightweight thumbnail for cards;
- loads the original image on demand for copy, preview, or save;
- uses a bounded image cache;
- removes associated image files during cleanup.

## Images and OCR

Captured images are saved as PNG files. A thumbnail is kept for fast display. When OCR is enabled, Vision.framework analyzes images locally and makes recognized text searchable.

## Cleanup

Preferences let you set the history limit, retention, delete images, delete items older than retention, or clear all history. Pinned items survive automatic retention.

## Storage

SQLite database:

```text
~/Library/Application Support/PasteGlide/history.sqlite
```

Externalized images:

```text
~/Library/Application Support/PasteGlide/Images/
```

## Import and Export

The macOS menu bar menu supports SQLite and JSON import/export.

## Tests

```bash
swift run PasteGlideCoreTests
```

## Troubleshooting

If `⌥⌘V` does not respond, check whether another app already uses this shortcut.

To reset history:

```bash
rm ~/Library/Application\ Support/PasteGlide/history.sqlite
rm -rf ~/Library/Application\ Support/PasteGlide/Images
```
