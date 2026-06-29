# Journal

A native macOS journaling app. Plain markdown files in a folder you choose — yours, portable, sync-agnostic.

Built because I wanted something that:

- Opens straight to a writing page (no UI to click through)
- Stores entries as markdown so they outlive the app
- Lets me bring decades of old journals (Word docs, Apple Journal exports) forward with their original dates intact
- Surfaces what I wrote on this calendar day in previous years
- Doesn't lock me into any single cloud — Proton Drive, iCloud, Dropbox, a local folder, whatever

## What it does

### Writing
- Opens directly into a blank entry — no splash screen, no list
- Autosave every 2 seconds of idle, on window blur, on quit
- Manual save with `⌘S`
- Crash recovery: a separate recovery file is written 400ms after every keystroke; if the app dies before saving, you're prompted on next launch to restore
- Drag photos into an entry → copied to `attachments/`, rendered inline; markdown image refs (`![](path)`) are what's actually saved
- Drag a URL → markdown link
- On-device spell check, grammar, autocorrect, smart quotes (all macOS-native, nothing leaves the machine)

### Calendar
- Scrollable month grid down the sidebar
- Heatmap shading on days you've written (Git contribution-graph style)
- Auto-scrolls to the current month
- Click a date with entries → see every entry from that month+day across all years
- Auto side panel when the entry you're editing has past-year matches on the same date ("On this day…")

### Import
Two formats supported, with full-folder import:
- **Date-line text**: any `.txt`/`.docx`/`.rtf` where each entry starts with a line like `November 17, 2018 8:40 AM`. macOS's built-in `textutil` handles `.docx` extraction — no Homebrew needed.
- **Apple Journal HTML exports**: parses `<div class="pageHeader">` for the date, title, and body; converts paragraphs/lists/blockquotes to markdown; pulls images from the export folder into `attachments/`.

Imported entries keep their original dates and auto-populate the calendar.

### Search
- Full-text across every entry
- Snippet highlights with `…` context around the first match
- Result count, click to load

### Insights
- Total entries, unique days journaled, total words written
- Current streak, longest streak, average words per entry
- Bar chart of words per month

### Location
- If you drop a photo with EXIF GPS, the entry's location auto-fills from the photo
- Toolbar pin button opens a popover for manual entry (label + lat/lon)
- Shows in the editor's status bar

### Theming
- Dark mode by default
- Custom highlight color (Settings → Appearance → Highlight color) with quick presets (Phoenix Amber, Cool Teal, Magenta, Sage). Applies everywhere — calendar heatmap, title color, selection bars, etc.
- Configurable editor font (System, Serif, Monospaced, Rounded) and size
- The first line of each entry is rendered as the title — larger, in your highlight color

## File format

Each entry is a plain markdown file with YAML-ish frontmatter:

```
---
id: 2026-06-10T143012
created: 2026-06-10T14:30:12-07:00
modified: 2026-06-10T14:47:55-07:00
source: native
tags: [morning, work]
location_lat: 37.7749
location_lon: -122.4194
location_label: San Francisco, CA
---

The title

Body content with **markdown**…

![](attachments/2026/06/2026-06-10T143012/photo.jpg)
```

Folder layout inside your chosen journal root:

```
<JournalRoot>/
├── entries/
│   └── 2026/06/2026-06-10T143012.md
├── attachments/
│   └── 2026/06/2026-06-10T143012/photo.jpg
├── imports/
│   └── raw/        # originals of imported files, never modified
└── .journal/
    └── recovery/   # crash recovery buffers, regenerable
```

Because everything is plain markdown in folders, you can open your journal in any other editor (Obsidian, iA Writer, plain `vim`) and it just works.

## Build

Requires macOS and Xcode.

```bash
git clone https://github.com/phoenixperry/journal.git
cd journal/journal
open journal.xcodeproj
```

Press `⌘R` in Xcode to build and run.

## Status

Personal project. v1 has the writing/calendar/import/search/insights/location/theming features above. Not on the App Store. No promises.

Things still on the someday list:
- iPad + iPhone companion apps reading the same synced folder
- Search filters (date range, tag, source, has-attachment)
- Smart-paste detection (paste a big block → "is this historical?" date picker)
- Theme clustering with a local LLM (Ollama)

## Why these choices

- **Markdown files, not a database**: your journal outlives any single app.
- **User-chosen folder, not iCloud-locked**: works with Proton Drive, Dropbox, plain local, or anything that mounts a folder on macOS.
- **Dark, warm, minimal**: this is for sitting down and writing, not for showing off features.

## License

MIT.
