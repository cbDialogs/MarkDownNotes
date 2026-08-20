import SwiftUI
import AppKit

struct NoteFile: Identifiable, Hashable {
    let url: URL
    let name: String          // filename without extension
    let ext: String           // "md" / "txt" / …
    let modified: Date
    let preview: String
    var id: URL { url }
    var isMarkdown: Bool { ["md", "markdown"].contains(ext.lowercased()) }
}

struct Folder: Identifiable, Hashable {
    let url: URL
    let name: String
    let count: Int
    var id: URL { url }
}

enum SidebarSelection: Hashable {
    case folder(URL)
    case markdown
    case plaintext
}

private let noteExtensions: Set<String> = ["md", "markdown", "txt", "text"]

@MainActor
final class NotesStore: ObservableObject {

    @Published private(set) var rootURL: URL
    @Published private(set) var folders: [Folder] = []
    @Published var selection: SidebarSelection
    @Published private(set) var notes: [NoteFile] = []
    @Published var selectedNote: NoteFile?
    @Published var text: String = ""
    @Published var searchText: String = "" { didSet { rebuildNoteList() } }
    @Published private(set) var lastSaved: Date?
    @Published private(set) var isDirty = false

    var markdownCount = 0
    var plaintextCount = 0

    private var savedText: String = ""
    private var saveTask: Task<Void, Never>?
    private var monitors: [DirectoryMonitor] = []
    private var allFiles: [NoteFile] = []

    init() {
        let fm = FileManager.default
        let stored = UserDefaults.standard.string(forKey: "notesRootPath")
        let fallback = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/MarkDownNotes")
        let root = (stored.map { URL(fileURLWithPath: $0) } ?? fallback).standardizedFileURL
        rootURL = root
        selection = .folder(root)

        if !fm.fileExists(atPath: root.path) {
            try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        }
        seedWelcomeNoteIfEmpty()
        rescan()
        if let first = notes.first { select(first) }
        installMonitors()

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.flushSaveNow() }
        }
    }

    // MARK: scanning

    func rescan() {
        let fm = FileManager.default
        var files: [NoteFile] = []
        var folderList: [Folder] = []
        var subdirs: [URL] = []

        func scan(_ dir: URL) -> [NoteFile] {
            guard let items = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]) else { return [] }
            var found: [NoteFile] = []
            for item in items {
                let values = try? item.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey])
                if values?.isDirectory == true {
                    if dir == rootURL { subdirs.append(item) }
                    continue
                }
                let ext = item.pathExtension.lowercased()
                guard noteExtensions.contains(ext) else { continue }
                let body = (try? String(contentsOf: item, encoding: .utf8)) ?? ""
                found.append(NoteFile(
                    url: item.standardizedFileURL,
                    name: item.deletingPathExtension().lastPathComponent,
                    ext: ext,
                    modified: values?.contentModificationDate ?? .distantPast,
                    preview: Markdown.previewText(body)))
            }
            return found
        }

        let rootFiles = scan(rootURL)
        files.append(contentsOf: rootFiles)
        folderList.append(Folder(url: rootURL, name: "Notes", count: rootFiles.count))

        for sub in subdirs.sorted(by: { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }) {
            let subFiles = scan(sub)
            files.append(contentsOf: subFiles)
            folderList.append(Folder(url: sub.standardizedFileURL, name: sub.lastPathComponent, count: subFiles.count))
        }

        allFiles = files
        folders = folderList
        markdownCount = files.filter(\.isMarkdown).count
        plaintextCount = files.count - markdownCount
        rebuildNoteList()
    }

    private func rebuildNoteList() {
        var list: [NoteFile]
        switch selection {
        case .folder(let dir):
            list = allFiles.filter { $0.url.deletingLastPathComponent().path == dir.path }
        case .markdown:
            list = allFiles.filter(\.isMarkdown)
        case .plaintext:
            list = allFiles.filter { !$0.isMarkdown }
        }
        if !searchText.isEmpty {
            let q = searchText
            list = list.filter {
                $0.name.localizedCaseInsensitiveContains(q)
                || ((try? String(contentsOf: $0.url, encoding: .utf8)) ?? "").localizedCaseInsensitiveContains(q)
            }
        }
        // Newest on top — the default and only sort.
        notes = list.sorted { $0.modified > $1.modified }

        if let current = selectedNote {
            selectedNote = notes.first { $0.url == current.url } ?? selectedNote
        }
    }

    func changeSelection(_ sel: SidebarSelection) {
        flushSaveNow()
        selection = sel
        rebuildNoteList()
        if let current = selectedNote, notes.contains(where: { $0.url == current.url }) { return }
        if let first = notes.first { select(first) } else { selectedNote = nil; text = ""; savedText = "" }
    }

    // MARK: selection & editing

    func select(_ note: NoteFile) {
        guard note.url != selectedNote?.url else { return }
        flushSaveNow()
        selectedNote = note
        savedText = (try? String(contentsOf: note.url, encoding: .utf8)) ?? ""
        text = savedText
        isDirty = false
    }

    func textEdited() {
        guard selectedNote != nil else { return }
        isDirty = text != savedText
        guard isDirty else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            self?.flushSaveNow()
        }
    }

    func flushSaveNow() {
        saveTask?.cancel()
        guard let note = selectedNote, text != savedText else { return }
        do {
            try text.write(to: note.url, atomically: true, encoding: .utf8)
            savedText = text
            isDirty = false
            lastSaved = Date()
            rescan()
        } catch {
            NSSound.beep()
        }
    }

    // MARK: file operations

    func newNote() {
        flushSaveNow()
        let dir: URL
        if case .folder(let d) = selection { dir = d } else { dir = rootURL }
        let fm = FileManager.default
        var name = "Untitled.md"
        var n = 1
        while fm.fileExists(atPath: dir.appendingPathComponent(name).path) {
            n += 1
            name = "Untitled \(n).md"
        }
        let url = dir.appendingPathComponent(name)
        try? "".write(to: url, atomically: true, encoding: .utf8)
        rescan()
        if let created = notes.first(where: { $0.url == url.standardizedFileURL }) {
            select(created)
        }
    }

    func rename(_ note: NoteFile, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        flushSaveNow()
        let dest = note.url.deletingLastPathComponent()
            .appendingPathComponent(trimmed).appendingPathExtension(note.ext)
        guard dest != note.url else { return }
        do {
            try FileManager.default.moveItem(at: note.url, to: dest)
            let wasSelected = selectedNote?.url == note.url
            rescan()
            if wasSelected, let moved = allFilesEntry(for: dest) {
                selectedNote = moved
            }
        } catch { NSSound.beep() }
    }

    func trash(_ note: NoteFile) {
        flushSaveNow()
        try? FileManager.default.trashItem(at: note.url, resultingItemURL: nil)
        if selectedNote?.url == note.url {
            selectedNote = nil; text = ""; savedText = ""
        }
        rescan()
        if selectedNote == nil, let first = notes.first { select(first) }
    }

    func revealInFinder(_ note: NoteFile) {
        NSWorkspace.shared.activateFileViewerSelecting([note.url])
    }

    func changeRootFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use Folder"
        panel.message = "Choose the folder that holds your notes"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        flushSaveNow()
        rootURL = url.standardizedFileURL
        UserDefaults.standard.set(rootURL.path, forKey: "notesRootPath")
        selection = .folder(rootURL)
        selectedNote = nil; text = ""; savedText = ""
        seedWelcomeNoteIfEmpty()
        rescan()
        if let first = notes.first { select(first) }
        installMonitors()
    }

    private func allFilesEntry(for url: URL) -> NoteFile? {
        allFiles.first { $0.url == url.standardizedFileURL }
    }

    // MARK: external changes

    private func installMonitors() {
        monitors = []
        var dirs = [rootURL]
        dirs.append(contentsOf: folders.map(\.url).filter { $0 != rootURL })
        for dir in dirs {
            if let monitor = DirectoryMonitor(url: dir, onChange: { [weak self] in
                MainActor.assumeIsolated { self?.externalChange() }
            }) {
                monitors.append(monitor)
            }
        }
    }

    private var rescanDebounce: Task<Void, Never>?
    private func externalChange() {
        rescanDebounce?.cancel()
        rescanDebounce = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self else { return }
            self.rescan()
            self.installMonitors()
            // Reload the open note if it changed on disk and we have no local edits.
            if let note = self.selectedNote, !self.isDirty {
                let onDisk = (try? String(contentsOf: note.url, encoding: .utf8)) ?? self.savedText
                if onDisk != self.savedText {
                    self.savedText = onDisk
                    self.text = onDisk
                }
            }
        }
    }

    private func seedWelcomeNoteIfEmpty() {
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        let hasNotes = items.contains { noteExtensions.contains($0.pathExtension.lowercased()) }
        guard !hasNotes else { return }
        let welcome = """
        # Welcome to MarkDownNotes

        Your notes live in this folder as ordinary files — **Markdown** or plain text. \
        Nothing is locked in a database, and everything saves *automatically* as you type.

        ## The basics

        - The left sidebar lists your folders; subfolders of the notes folder appear there too
        - The middle pane lists notes, newest on top
        - Toggle **Preview** and **Source** from the top right — plain-text files simply edit as text

        ## Formatting

        Headers with `#`, `##`, `###`, **bold** with `**`, *italics* with `*`, and:

        > Blockquotes look like this.

        Change where notes live from File → Change Notes Folder.
        """
        try? welcome.write(to: rootURL.appendingPathComponent("Welcome.md"), atomically: true, encoding: .utf8)
    }
}

final class DirectoryMonitor {
    private let fd: CInt
    private let source: DispatchSourceFileSystemObject

    init?(url: URL, onChange: @escaping @Sendable () -> Void) {
        fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler(handler: onChange)
        let fd = self.fd
        source.setCancelHandler { close(fd) }
        source.resume()
    }

    deinit { source.cancel() }
}
