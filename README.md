# MarkDownNotes

A native macOS notes editor for Markdown and plain-text files. Warm paper,
a serif voice (Newsreader), and your notes stored as ordinary files in a
folder you choose — no database, no lock-in.

![Rendered mode](screenshots/rendered.png)

## Features

- **Three panes** — folders, a note list with previews, and the editor
- **Multiple notes folders** — add any number of folders to the library
  (File → Add Notes Folder…); each appears in the sidebar with its
  subfolders, with Markdown/plain-text filters across all of them
- **Edit in rendered mode** — Markdown styles itself in place as you type;
  headers, bold, italics, code, quotes, lists, and links render live, with
  the syntax markers hidden from view. They stay in the file — only their
  glyphs are suppressed — so the text on disk is never touched
- **Heading shortcuts** — ⌘1…⌘6 set the current line's heading level and ⌘0
  clears it, in either mode; press the level a line already has to toggle it off
- **Source mode** — a plain monospaced view of the same file with every
  marker visible, one click (or ⌘L) away; the caret keeps its place when you
  switch. Add or change Markdown structure here, or with the shortcuts above
- **Find & replace** — the standard macOS find bar inside the editor, in
  either mode: ⌘F to find, ⌘R (or ⌥⌘F) to replace, ⌘G / ⇧⌘G to step
  through matches, ⌥⌘R to replace one and jump to the next, ⇧⌘R to
  replace them all
- **Autosave** — writes shortly after you stop typing, and on note-switch,
  app-switch, and quit
- **Newest on top** — the note list always sorts by last modified
- **Plays well with other tools** — edits made outside the app appear live;
  notes are plain `.md` / `.txt` files on disk

![Source mode](screenshots/source.png)

## Install

Download `MarkDownNotes-x.y.dmg` from the
[Releases](../../releases) page, open it, and drag the app to Applications.

Releases from v1.3.1 on are Developer ID signed and notarized, so the
app opens normally on first launch. (Older releases were ad-hoc signed
and need right-click → **Open** the first time.)

On first run the app creates `~/Documents/MarkDownNotes` with a welcome
note. Add more folders via **File → Add Notes Folder…** (⇧⌘O); remove
one from the sidebar via right-click.

## Build from source

Requires Xcode (or the command-line tools) on macOS 14+:

```
./App/build-app.sh
```

That compiles the Swift package, assembles `MarkDownNotes.app` in the
repository root, and ad-hoc signs it — fine for the Mac it was built on.
`App/release.sh` additionally signs with a Developer ID certificate,
notarizes through Apple's notary service, and staples the app and DMG
(requires a `notarytool` keychain profile). `App/make-icon.swift`
regenerates the app icon.

## Design

The app's look was chosen from five mockup directions (see `design/`);
the shipped style combines the *Manuscript* palette and typography with
the *Ledger* three-pane layout.

## License

The code is licensed under the [MIT License](LICENSE).

The bundled [Newsreader](https://github.com/productiontype/Newsreader)
fonts are licensed separately under the SIL Open Font License 1.1
(`App/Fonts/OFL.txt`).
