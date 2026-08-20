import SwiftUI

@main
struct MarkDownNotesApp: App {
    @StateObject private var store: NotesStore
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Theme.registerFonts()
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
