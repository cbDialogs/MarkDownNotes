import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: NotesStore

    var body: some View {
        HSplitView {
            SidebarPane()
                .frame(minWidth: 180, idealWidth: 200, maxWidth: 280)
            NoteListPane()
                .frame(minWidth: 250, idealWidth: 300, maxWidth: 420)
            EditorPane()
                .frame(minWidth: 430, maxWidth: .infinity)
        }
        .background(Theme.paper)
        .ignoresSafeArea()
        .frame(minWidth: 900, minHeight: 560)
    }
}

// MARK: - Pane 1 · Folders

struct SidebarPane: View {
    @EnvironmentObject var store: NotesStore

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 52)   // traffic-light zone

            VStack(alignment: .leading, spacing: 1) {
                if store.recentFolders.count >= 2 {
                    sectionLabel("Recent")
                    ForEach(store.recentFolders, id: \.self) { url in
                        SidebarRow(
                            selected: store.selection == .folder(url),
                            count: store.folders.first { $0.url.path == url.path }?.count ?? 0,
                            action: { store.changeSelection(.folder(url)) }
                        ) { selected in
                            Image(systemName: "clock")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(selected ? Theme.onRust : Theme.iconBrown)
                                .frame(width: 14)
                            Text(url.lastPathComponent)
                                .font(Theme.serif(14.5))
                                .foregroundStyle(selected ? Theme.onRust : Theme.inkFolder)
                                .lineLimit(1)
                        }
                    }
                    Spacer().frame(height: 11)
                }
                sectionLabel("Library")
                ForEach(store.folders) { folder in
                    SidebarRow(
                        selected: store.selection == .folder(folder.url),
                        count: folder.count,
                        action: { store.changeSelection(.folder(folder.url)) }
                    ) { selected in
                        FolderGlyph(selected: selected)
                        Text(folder.name)
                            .font(Theme.serif(14.5))
                            .foregroundStyle(selected ? Theme.onRust : Theme.inkFolder)
                            .lineLimit(1)
                    }
                    .padding(.leading, folder.isRoot ? 0 : 16)
                    .contextMenu {
                        if folder.isRoot && store.roots.count > 1 {
                            Button("Remove from Sidebar") { store.removeRoot(folder.url) }
                        }
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([folder.url])
                        }
                    }
                }

                sectionLabel("Filters").padding(.top, 19)
                SidebarRow(
                    selected: store.selection == .markdown,
                    count: store.markdownCount,
                    action: { store.changeSelection(.markdown) }
                ) { selected in
                    Text("MD")
                        .font(Theme.ui(9, weight: .semibold)).kerning(0.4)
                        .foregroundStyle(selected ? Theme.onRust : Theme.rust)
                        .frame(width: 14)
                    Text("Markdown")
                        .font(Theme.serif(14.5))
                        .foregroundStyle(selected ? Theme.onRust : Theme.inkFolder)
                }
                SidebarRow(
                    selected: store.selection == .plaintext,
                    count: store.plaintextCount,
                    action: { store.changeSelection(.plaintext) }
                ) { selected in
                    Text("TXT")
                        .font(Theme.ui(9, weight: .semibold)).kerning(0.4)
                        .foregroundStyle(selected ? Theme.onRust : Theme.iconBrown)
                        .frame(width: 14)
                    Text("Plain text")
                        .font(Theme.serif(14.5))
                        .foregroundStyle(selected ? Theme.onRust : Theme.inkFolder)
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            Divider().overlay(Theme.hairline)
            Button(action: { store.newNote() }) {
                HStack(spacing: 9) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                    Text("New note").font(Theme.ui(11.5))
                    Spacer()
                }
                .foregroundStyle(Theme.rust)
                .padding(.horizontal, 20)
                .frame(height: 46)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(Theme.pane1)
    }

    private func sectionLabel(_ s: String) -> some View {
        Text(s.uppercased())
            .font(Theme.ui(9.5, weight: .semibold)).kerning(1.5)
            .foregroundStyle(Theme.sectionLabel)
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
    }
}

struct FolderGlyph: View {
    var selected: Bool
    var body: some View {
        Image(systemName: "folder")
            .font(.system(size: 11.5, weight: .regular))
            .foregroundStyle(selected ? Theme.onRust : Theme.iconBrown)
            .frame(width: 14)
    }
}

struct SidebarRow<Content: View>: View {
    var selected: Bool
    var count: Int
    var action: () -> Void
    @ViewBuilder var content: (Bool) -> Content

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                content(selected)
                Spacer(minLength: 4)
                Text("\(count)")
                    .font(Theme.ui(10.5))
                    .foregroundStyle(selected ? Theme.onRustDim : Theme.eyebrow)
            }
            .padding(.horizontal, 10)
            .frame(height: 31)
            .background(selected ? Theme.rust : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Pane 2 · Note list

struct NoteListPane: View {
    @EnvironmentObject var store: NotesStore

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.uiBrown)
                    TextField("", text: $store.searchText,
                              prompt: Text("Search Notes").foregroundStyle(Theme.uiBrown))
                        .textFieldStyle(.plain)
                        .font(Theme.ui(11.5))
                        .foregroundStyle(Theme.ink)
                }
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(Theme.searchBG, in: RoundedRectangle(cornerRadius: 6))
            }
            .padding(.horizontal, 16)
            .frame(height: 52)

            Divider().overlay(Theme.hairlineSoft)

            if store.notes.isEmpty {
                Spacer()
                Text(store.searchText.isEmpty ? "No notes here yet" : "No matches")
                    .font(Theme.serifItalic(15))
                    .foregroundStyle(Theme.eyebrow)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.notes) { note in
                            NoteRow(note: note, selected: note.url == store.selectedNote?.url)
                                .onTapGesture { store.select(note) }
                            Divider().overlay(Theme.hairlineSoft)
                        }
                    }
                }
            }
        }
        .background(Theme.pane2)
    }
}

struct NoteRow: View {
    @EnvironmentObject var store: NotesStore
    let note: NoteFile
    let selected: Bool
    @State private var renaming = false
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(note.name)
                    .font(Theme.serif(15.5, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color(hex: 0x241E19) : Theme.inkSoft)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(Self.dateLabel(note.modified))
                    .font(Theme.ui(10))
                    .foregroundStyle(selected ? Theme.mutedLabel : Theme.eyebrow)
            }
            if !note.preview.isEmpty {
                Text(note.preview)
                    .font(Theme.serif(12.5))
                    .foregroundStyle(selected ? Theme.secondary : Theme.tertiary)
                    .lineSpacing(3)
                    .lineLimit(2)
            }
            HStack(spacing: 7) {
                Text(note.isMarkdown ? "MD" : "TXT")
                    .font(Theme.ui(9, weight: .semibold)).kerning(0.6)
                    .foregroundStyle(note.isMarkdown ? Theme.rust : Theme.uiBrown)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(
                        note.isMarkdown ? (selected ? Theme.rustPale : Theme.rustPale2) : Theme.txtBadgeBG,
                        in: RoundedRectangle(cornerRadius: 3))
                if selected && store.isDirty {
                    Circle().fill(Theme.amber).frame(width: 6, height: 6)
                }
            }
            .padding(.top, 3)
        }
        .padding(.leading, 13).padding(.trailing, 16).padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? Theme.rowSelected : .clear)
        .overlay(alignment: .leading) {
            if selected { Rectangle().fill(Theme.rust).frame(width: 3) }
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Rename…") { newName = note.name; renaming = true }
            Button("Reveal in Finder") { store.revealInFinder(note) }
            Divider()
            Button("Move to Trash", role: .destructive) { store.trash(note) }
        }
        .alert("Rename Note", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Rename") { store.rename(note, to: newName) }
            Button("Cancel", role: .cancel) {}
        }
    }

    static func dateLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}

// MARK: - Pane 3 · Editor

struct EditorPane: View {
    @EnvironmentObject var store: NotesStore
    private var mode: EditorMode { store.editorMode }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.hairlineSoft)

            if let note = store.selectedNote {
                if note.isMarkdown && mode == .preview {
                    RichMarkdownEditor(text: $store.text, onEdit: { store.textEdited() })
                } else {
                    SourceEditor(text: $store.text, onEdit: { store.textEdited() })
                }
                Divider().overlay(Theme.hairlineSoft)
                statusBar
            } else {
                Spacer()
                Text("Select a note, or press ⌘N")
                    .font(Theme.serifItalic(17))
                    .foregroundStyle(Theme.eyebrow)
                Spacer()
            }
        }
        .background(Theme.paper)
    }

    private var header: some View {
        HStack(spacing: 10) {
            if let note = store.selectedNote {
                Text(folderName(of: note))
                    .font(Theme.ui(11.5)).foregroundStyle(Theme.eyebrow)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xCFC0A6))
                Text("\(note.name).\(note.ext)")
                    .font(Theme.ui(11.5, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x3B342B))
                    .lineLimit(1)
            }
            Spacer()
            if store.selectedNote?.isMarkdown == true {
                HStack(spacing: 6) {
                    togglePill("Rendered", .preview)
                    togglePill("Source", .source)
                }
            }
        }
        .padding(.horizontal, 22)
        .frame(height: 52)
    }

    private func togglePill(_ label: String, _ value: EditorMode) -> some View {
        Button(action: { store.setEditorMode(value) }) {
            Text(label)
                .font(Theme.ui(11.5, weight: .medium))
                .foregroundStyle(mode == value ? Theme.onRust : Color(hex: 0x7A6A55))
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(mode == value ? Theme.rust : .clear, in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }

    private var statusBar: some View {
        HStack(spacing: 16) {
            let words = store.text.split { $0.isWhitespace || $0.isNewline }.count
            Text("\(words) word\(words == 1 ? "" : "s")")
            Text("\(max(1, Int((Double(words) / 200).rounded(.up)))) min read")
            Spacer()
            if store.isDirty {
                HStack(spacing: 6) {
                    Circle().fill(Theme.amber).frame(width: 6, height: 6)
                    Text("Editing…")
                }
                .foregroundStyle(Theme.mutedLabel)
            } else if let saved = store.lastSaved {
                Text("Saved \(saved.formatted(date: .omitted, time: .shortened))")
                    .foregroundStyle(Theme.mutedLabel)
            }
        }
        .font(Theme.ui(10.5))
        .foregroundStyle(Theme.eyebrow)
        .padding(.horizontal, 22)
        .frame(height: 32)
    }

    private func folderName(of note: NoteFile) -> String {
        note.url.deletingLastPathComponent().lastPathComponent
    }
}

struct SourceEditor: NSViewRepresentable {
    @EnvironmentObject var store: NotesStore
    @Binding var text: String
    var onEdit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let tv = scroll.documentView as! NSTextView
        tv.delegate = context.coordinator
        tv.allowsUndo = true
        tv.isRichText = false
        tv.usesFontPanel = false
        tv.importsGraphics = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.drawsBackground = true
        tv.backgroundColor = NSColor(Theme.paper)
        tv.insertionPointColor = NSColor(Theme.rust)
        tv.selectedTextAttributes = [.backgroundColor: NSColor(Theme.rowSelected)]
        tv.textContainerInset = NSSize(width: 40, height: 26)
        tv.font = NSFont.monospacedSystemFont(ofSize: 13.5, weight: .regular)
        tv.textColor = NSColor(Color(hex: 0x3B342B))
        tv.defaultParagraphStyle = {
            let p = NSMutableParagraphStyle()
            p.lineHeightMultiple = 1.35
            return p
        }()
        tv.typingAttributes = [
            .font: NSFont.monospacedSystemFont(ofSize: 13.5, weight: .regular),
            .foregroundColor: NSColor(Color(hex: 0x3B342B)),
            .paragraphStyle: tv.defaultParagraphStyle!
        ]
        tv.string = text
        restorePendingSelection(store, in: tv)
        scroll.drawsBackground = true
        scroll.backgroundColor = NSColor(Theme.paper)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        if tv.string != text {
            let selection = tv.selectedRange()
            tv.string = text
            let len = (text as NSString).length
            tv.setSelectedRange(NSRange(location: min(selection.location, len), length: 0))
            tv.undoManager?.removeAllActions()
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SourceEditor
        init(_ parent: SourceEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            parent.onEdit()
        }
    }
}

// MARK: - Menu actions

@MainActor
enum EditorActions {
    /// The editor's text view. During menu actions NSApp.keyWindow is nil,
    /// so walk the app's windows for the responder (or visible editor) instead.
    static func activeTextView() -> NSTextView? {
        for window in NSApp.windows {
            if let tv = window.firstResponder as? NSTextView, tv.isEditable, !tv.isFieldEditor {
                return tv
            }
        }
        for window in NSApp.windows where window.isVisible {
            if let tv = findTextView(in: window.contentView) { return tv }
        }
        return nil
    }

    private static func findTextView(in view: NSView?) -> NSTextView? {
        guard let view else { return nil }
        if let tv = view as? NSTextView, tv.isEditable, !tv.isFieldEditor { return tv }
        for sub in view.subviews {
            if let found = findTextView(in: sub) { return found }
        }
        return nil
    }

    /// Drive the standard find bar. performTextFinderAction reads the
    /// sender's `tag` as an NSTextFinder.Action rawValue, so pass a proxy.
    static func performFind(_ action: NSTextFinder.Action) {
        guard let tv = activeTextView() else { NSSound.beep(); return }
        if tv.window?.firstResponder !== tv { tv.window?.makeFirstResponder(tv) }
        let proxy = NSMenuItem()
        proxy.tag = action.rawValue
        tv.performTextFinderAction(proxy)
    }

    /// Duplicate the selection, or the current line when nothing is selected. (⌘D)
    static func duplicateSelection() {
        guard let tv = activeTextView() else { NSSound.beep(); return }
        let ns = tv.string as NSString
        let sel = tv.selectedRange()
        if sel.length > 0 {
            let copy = ns.substring(with: sel)
            tv.insertText(copy, replacementRange: NSRange(location: NSMaxRange(sel), length: 0))
            tv.setSelectedRange(NSRange(location: NSMaxRange(sel), length: copy.utf16.count))
        } else {
            let lineRange = ns.lineRange(for: sel)
            var line = ns.substring(with: lineRange)
            if !line.hasSuffix("\n") { line = "\n" + line }
            tv.insertText(line, replacementRange: NSRange(location: NSMaxRange(lineRange), length: 0))
        }
    }
}
