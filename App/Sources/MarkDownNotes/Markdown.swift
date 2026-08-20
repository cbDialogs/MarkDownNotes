import Foundation

// Markdown helpers for the note-list previews. Rendering/editing styling
// lives in RichEditor.swift (MarkdownStyler).
enum Markdown {

    /// Strip markdown syntax for plain display.
    static func plain(_ s: String) -> String {
        var out = s
        for token in ["**", "__", "*", "_", "`", "# ", "## ", "### ", "> "] {
            out = out.replacingOccurrences(of: token, with: "")
        }
        return out
    }

    /// First few content lines of a note body, syntax stripped.
    static func previewText(_ body: String) -> String {
        let lines = body.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") && $0 != "---" && !$0.hasPrefix("```") }
        return plain(lines.prefix(4).joined(separator: " "))
    }
}
