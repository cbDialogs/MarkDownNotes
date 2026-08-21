import SwiftUI

@main
struct MarkDownNotesApp: App {
    @StateObject private var store: NotesStore
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Theme.registerFonts()
        // The app paints one light paper theme; keep AppKit's own chrome
        // (find bar, menus, panels) light too, or it clashes in Dark Mode.
        NSApplication.shared.appearance = NSAppearance(named: .aqua)
        _store = StateObject(wrappedValue: NotesStore())
    }

    var body: some Scene {
        Window("MarkDownNotes", id: "main") {
            ContentView()
                .environmentObject(store)
                .onChange(of: scenePhase) {
                    if scenePhase != .active { store.flushSaveNow() }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1216, height: 764)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Note") { store.newNote() }
                    .keyboardShortcut("n")
            }
            CommandGroup(after: .newItem) {
                Divider()
                Button("Add Notes Folder…") { store.addRootFolder() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Button("Reveal Current Folder in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([store.currentFolderURL])
                }
            }
            CommandGroup(after: .pasteboard) {
                Button("Duplicate") { EditorActions.duplicateSelection() }
                    .keyboardShortcut("d")
                Divider()
                Menu("Find") {
                    Button("Find…") { EditorActions.performFind(.showFindInterface) }
                        .keyboardShortcut("f")
                    Button("Find and Replace…") { EditorActions.performFind(.showReplaceInterface) }
                        .keyboardShortcut("f", modifiers: [.command, .option])
                    Button("Replace…") { EditorActions.performFind(.showReplaceInterface) }
                        .keyboardShortcut("r")
                    Divider()
                    Button("Replace & Find Next") { EditorActions.performFind(.replaceAndFind) }
                        .keyboardShortcut("r", modifiers: [.command, .option])
                    Button("Replace") { EditorActions.performFind(.replace) }
                        .keyboardShortcut("r", modifiers: [.command, .control])
                    Button("Replace All") { EditorActions.performFind(.replaceAll) }
                        .keyboardShortcut("r", modifiers: [.command, .shift])
                    Divider()
                    Button("Find Next") { EditorActions.performFind(.nextMatch) }
                        .keyboardShortcut("g")
                    Button("Find Previous") { EditorActions.performFind(.previousMatch) }
                        .keyboardShortcut("g", modifiers: [.command, .shift])
                    Button("Use Selection for Find") { EditorActions.performFind(.setSearchString) }
                        .keyboardShortcut("e")
                }
            }
            CommandGroup(after: .sidebar) {
                Button("Toggle Rendered/Source") { store.toggleEditorMode() }
                    .keyboardShortcut("l")
                Divider()
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save Now") { store.flushSaveNow() }
                    .keyboardShortcut("s")
            }
        }
    }
}
