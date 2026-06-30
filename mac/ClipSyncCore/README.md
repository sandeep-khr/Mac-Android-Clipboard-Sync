# ClipSyncCore

The Mac-side core library for the clipboard sync project, plus a small CLI
(`clipsync-cli`) for running it headless during development.

`ClipSyncCore` is the reusable package that the menu bar app (Phase 1) and the
network transport (Phase 3+) build on. Right now it does one job:

- watch the macOS clipboard for plain text changes
- emit a structured `ClipboardEvent` whenever new text is copied
- suppress duplicates via `ClipboardEventStore`

## Why This Exists

Before we add networking, pairing, or encryption, we want one reliable source of truth:

- can the Mac app detect clipboard changes?
- can it normalize text consistently?
- can it suppress obvious duplicates?

If this layer is noisy or unreliable, every later layer gets harder.

## How To Run

The **menu bar app** (Phase 1) — a menu-bar-only app (no Dock icon):

```bash
cd mac/ClipSyncCore
swift run clipsync-menubar
```

A clipboard icon appears in the menu bar; the menu shows the synced-event count
and a preview of the last copied text. Add `CLIPSYNC_DEBUG=1` for stderr logs.

The headless **CLI** (prints each event, handy for development):

```bash
swift run clipsync-cli
```

To run the unit tests:

```bash
swift test
```

Then copy some text on your Mac.

The watcher should print a `ClipboardEvent` containing:

- a generated event ID
- the event timestamp
- a SHA-256 hash of normalized content
- a preview of the copied text
- the raw text length

Stop it with `Ctrl+C`.

## Project Files

- `Package.swift`
  - Swift Package Manager manifest (library + `clipsync-cli` + `clipsync-menubar` + tests)
- `Sources/clipsync-menubar/`
  - menu bar app: `NSStatusItem` shell wiring the watcher into `AppState`
- `Sources/clipsync-cli/main.swift`
  - dev entry point: starts the watcher and keeps the run loop alive
- `Sources/ClipSyncCore/PasteboardWatcher.swift`
  - polls `NSPasteboard.general.changeCount`
- `Sources/ClipSyncCore/ClipboardNormalizer.swift`
  - normalizes text and creates content hashes
- `Sources/ClipSyncCore/ClipboardEventStore.swift`
  - tracks recent content hashes to suppress duplicate sends
- `Sources/ClipSyncCore/ClipboardEvent.swift`
  - event model used by the watcher
- `Tests/ClipSyncCoreTests/`
  - unit tests for normalization and duplicate suppression

## Terms, Explained Simply

### Run Loop

A run loop is the program's event cycle. It keeps timers, input, and other events alive.

In this prototype, the run loop keeps our polling timer active.

### Polling

Polling means checking something repeatedly on a schedule.

Here, we poll the clipboard every `0.4` seconds to see whether `changeCount` changed.

### Normalization

Normalization means converting input into a consistent form before we compare or hash it.

Here we:

- convert line endings to `\n`
- trim outer whitespace and newlines

### Hash

A hash is a fixed-size fingerprint of data.

We use a hash so we can quickly compare clipboard contents without relying only on raw text checks.

## What Comes Next

The next implementation step is to replace "print the event" with "publish the event to a transport layer."

That means we will soon add:

- a local WebSocket server
- a first message format
- a simple way to observe outgoing clipboard events
