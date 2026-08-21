import SwiftUI
import AppKit

// Editable rendered mode: an NSTextView whose storage is always the raw
// markdown, restyled in place after every edit. Markers (#, **, `, >)
// stay visible but dimmed, so the caret never surprises.
/// Restore a handed-off caret into a freshly mounted editor view.
@MainActor
func restorePendingSelection(_ store: NotesStore, in tv: NSTextView) {
    guard let sel = store.pendingSelection else { return }
    store.pendingSelection = nil
    let len = (tv.string as NSString).length
    let loc = min(sel.location, len)
    let clamped = NSRange(location: loc, length: min(sel.length, len - loc))
    tv.setSelectedRange(clamped)
    DispatchQueue.main.async {
        tv.window?.makeFirstResponder(tv)
        tv.scrollRangeToVisible(clamped)
    }
}

struct RichMarkdownEditor: NSViewRepresentable {
    @EnvironmentObject var store: NotesStore
    @Binding var text: String
    var onEdit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let tv = scroll.documentView as! NSTextView
        tv.delegate = context.coordinator
        tv.allowsUndo = true
        tv.isRichText = true
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
        tv.textContainerInset = NSSize(width: 40, height: 30)
        tv.string = text
        MarkdownStyler.restyle(tv)
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
            MarkdownStyler.restyle(tv)
            let len = (text as NSString).length
            tv.setSelectedRange(NSRange(location: min(selection.location, len), length: 0))
            tv.undoManager?.removeAllActions()
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichMarkdownEditor
        init(_ parent: RichMarkdownEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            MarkdownStyler.restyle(tv)
            parent.text = tv.string
            parent.onEdit()
        }
    }
}

enum MarkdownStyler {

    // MARK: fonts & colors (AppKit side of the theme)

    private static func serif(_ size: CGFloat) -> NSFont {
        NSFont(name: "Newsreader", size: size) ?? serifFallback(size)
    }
    private static func serifFallback(_ size: CGFloat) -> NSFont {
        let desc = NSFont.systemFont(ofSize: size).fontDescriptor.withDesign(.serif)
        return desc.flatMap { NSFont(descriptor: $0, size: size) } ?? NSFont.systemFont(ofSize: size)
    }
    private static func serifBold(_ size: CGFloat) -> NSFont {
        NSFontManager.shared.convert(serif(size), toHaveTrait: .boldFontMask)
    }
    private static func serifItalic(_ size: CGFloat) -> NSFont {
        NSFontManager.shared.convert(serif(size), toHaveTrait: .italicFontMask)
    }
    private static func serifBoldItalic(_ size: CGFloat) -> NSFont {
        NSFontManager.shared.convert(serifBold(size), toHaveTrait: .italicFontMask)
    }
    private static func mono(_ size: CGFloat) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
    private static func sans(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: weight)
    }

    private static let ink       = NSColor(Theme.ink)
    private static let inkTitle  = NSColor(Theme.inkTitle)
    private static let rust      = NSColor(Theme.rust)
    private static let quoteInk  = NSColor(Theme.quote)
    private static let marker    = NSColor(Theme.eyebrow)      // dimmed syntax
    private static let codeInk   = NSColor(Theme.codeInk)
    private static let codeBG    = NSColor(Theme.codeBG)
    private static let doneInk   = NSColor(Theme.tertiary)     // completed tasks

    // MARK: paragraph styles

    private static func para(_ spacing: CGFloat, before: CGFloat = 0,
                             indent: CGFloat = 0, lineMultiple: CGFloat = 1.22) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.paragraphSpacing = spacing
        p.paragraphSpacingBefore = before
        p.lineHeightMultiple = lineMultiple
        p.headIndent = indent
        return p
    }
    private static let bodyStyle   = para(9)
    private static let h1Style     = para(10, lineMultiple: 1.08)
    private static let h2Style     = para(5, before: 6)
    private static let h3Style     = para(5, before: 4, lineMultiple: 1.1)
    private static let bulletStyle = para(4, indent: 21)
    private static let quoteStyle  = para(9, indent: 21)
    private static let codeStyle   = para(2, lineMultiple: 1.15)
    private static let blankStyle  = para(0, lineMultiple: 1)

    // MARK: inline regexes

    private static let reBold     = try! NSRegularExpression(pattern: #"\*\*(.+?)\*\*|__(.+?)__"#)
    private static let reItalic   = try! NSRegularExpression(pattern: #"(?<![\*\w])\*(?!\*)([^\*\n]+?)\*(?![\*\w])|(?<![_\w])_(?!_)([^_\n]+?)_(?![_\w])"#)
    private static let reCode     = try! NSRegularExpression(pattern: #"(`{1,3})([^`\n]+?)\1"#)
    private static let reTask     = try! NSRegularExpression(pattern: #"^- \[( |x|X)\] "#)
    private static let reLink     = try! NSRegularExpression(pattern: #"\[([^\]\n]+)\]\(([^)\n]*)\)"#)
    private static let reOrdered  = try! NSRegularExpression(pattern: #"^\d{1,3}\. "#)
    private static let reHeader   = try! NSRegularExpression(pattern: #"^(#{1,6}) "#)

    // MARK: restyle

    static func restyle(_ tv: NSTextView) {
        guard let storage = tv.textStorage else { return }
        let ns = storage.string as NSString
        let full = NSRange(location: 0, length: ns.length)

        storage.beginEditing()
        storage.setAttributes([
            .font: serif(17), .foregroundColor: ink, .paragraphStyle: bodyStyle
        ], range: full)

        var inFence = false

        ns.enumerateSubstrings(in: full, options: [.byParagraphs, .substringNotRequired]) { _, range, _, _ in
            let line = ns.substring(with: range)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            func dim(_ r: NSRange) {
                storage.addAttribute(.foregroundColor, value: marker, range: r)
            }
            func prefix(_ n: Int) -> NSRange { NSRange(location: range.location, length: min(n, range.length)) }

            if !inFence && trimmed.isEmpty {
                storage.addAttributes([.font: serif(10), .paragraphStyle: blankStyle], range: range)
                return
            }
            if trimmed.hasPrefix("```") {
                inFence.toggle()
                storage.addAttributes([.font: mono(12), .foregroundColor: marker,
                                       .paragraphStyle: codeStyle], range: range)
                return
            }
            if inFence {
                storage.addAttributes([.font: mono(12.5), .foregroundColor: codeInk,
                                       .backgroundColor: codeBG, .paragraphStyle: codeStyle], range: range)
                return
            }

            if let h = reHeader.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) {
                let level = h.range(at: 1).length
                switch level {
                case 1:
                    storage.addAttributes([.font: serif(33), .foregroundColor: inkTitle,
                                           .paragraphStyle: h1Style], range: range)
                case 2:
                    storage.addAttributes([.font: sans(13, .semibold), .foregroundColor: rust,
                                           .kern: 1.1, .paragraphStyle: h2Style], range: range)
                case 3:
                    storage.addAttributes([.font: serifBold(21), .foregroundColor: inkTitle,
                                           .paragraphStyle: h3Style], range: range)
                case 4:
                    storage.addAttributes([.font: serifBold(18.5), .foregroundColor: inkTitle,
                                           .paragraphStyle: h3Style], range: range)
                case 5:
                    storage.addAttributes([.font: serifBold(17), .foregroundColor: ink,
                                           .paragraphStyle: h3Style], range: range)
                default:
                    storage.addAttributes([.font: serifBold(15.5), .foregroundColor: quoteInk,
                                           .paragraphStyle: h3Style], range: range)
                }
                dim(prefix(level + 1))
            } else if let t = reTask.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) {
                // Task list: "- [ ]" / "- [x]" render as a rust checkbox.
                storage.addAttribute(.paragraphStyle, value: bulletStyle, range: range)
                styleInline(storage, ns, range)
                dim(prefix(2))
                let box = NSRange(location: range.location + 2, length: 3)
                storage.addAttributes([.font: mono(13), .foregroundColor: rust], range: box)
                let checked = ns.substring(with: NSRange(location: range.location + 3, length: 1)).lowercased() == "x"
                if checked && range.length > 6 {
                    let content = NSRange(location: range.location + 6, length: range.length - 6)
                    storage.addAttributes([
                        .foregroundColor: doneInk,
                        .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                        .strikethroughColor: NSColor(Theme.eyebrow)
                    ], range: content)
                }
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                storage.addAttribute(.paragraphStyle, value: bulletStyle, range: range)
                dim(prefix(2))
                styleInline(storage, ns, range)
            } else if let m = reOrdered.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) {
                storage.addAttribute(.paragraphStyle, value: bulletStyle, range: range)
                dim(NSRange(location: range.location, length: m.range.length))
                styleInline(storage, ns, range)
            } else if line.hasPrefix("> ") || trimmed == ">" {
                storage.addAttributes([.font: serifItalic(17), .foregroundColor: quoteInk,
                                       .paragraphStyle: quoteStyle], range: range)
                dim(prefix(2))
            } else if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                storage.addAttributes([.foregroundColor: marker, .kern: 2], range: range)
            } else {
                styleInline(storage, ns, range)
            }
        }
        storage.endEditing()

        tv.typingAttributes = [.font: serif(17), .foregroundColor: ink, .paragraphStyle: bodyStyle]
    }

    private static func styleInline(_ storage: NSTextStorage, _ ns: NSString, _ range: NSRange) {
        func dim(_ r: NSRange) { storage.addAttribute(.foregroundColor, value: marker, range: r) }

        reBold.enumerateMatches(in: ns as String, range: range) { m, _, _ in
            guard let m else { return }
            let inner = m.range(at: 1).location != NSNotFound ? m.range(at: 1) : m.range(at: 2)
            storage.addAttribute(.font, value: serifBold(17), range: inner)
            dim(NSRange(location: m.range.location, length: 2))
            dim(NSRange(location: m.range.location + m.range.length - 2, length: 2))
        }
        reItalic.enumerateMatches(in: ns as String, range: range) { m, _, _ in
            guard let m else { return }
            let inner = m.range(at: 1).location != NSNotFound ? m.range(at: 1) : m.range(at: 2)
            // Bold+italic when nested inside bold.
            var font = serifItalic(17)
            if inner.location > 0,
               let existing = storage.attribute(.font, at: inner.location, effectiveRange: nil) as? NSFont,
               NSFontManager.shared.traits(of: existing).contains(.boldFontMask) {
                font = serifBoldItalic(17)
            }
            storage.addAttribute(.font, value: font, range: inner)
            dim(NSRange(location: m.range.location, length: 1))
            dim(NSRange(location: m.range.location + m.range.length - 1, length: 1))
        }
        reCode.enumerateMatches(in: ns as String, range: range) { m, _, _ in
            guard let m else { return }
            let ticks = m.range(at: 1).length
            storage.addAttributes([.font: mono(13), .foregroundColor: codeInk,
                                   .backgroundColor: codeBG], range: m.range(at: 2))
            dim(NSRange(location: m.range.location, length: ticks))
            dim(NSRange(location: m.range.location + m.range.length - ticks, length: ticks))
        }
        reLink.enumerateMatches(in: ns as String, range: range) { m, _, _ in
            guard let m else { return }
            let label = m.range(at: 1)
            storage.addAttributes([.foregroundColor: rust,
                                   .underlineStyle: NSUnderlineStyle.single.rawValue], range: label)
            let afterLabel = label.location + label.length
            dim(NSRange(location: m.range.location, length: 1))
            dim(NSRange(location: afterLabel, length: m.range.location + m.range.length - afterLabel))
            storage.addAttribute(.font, value: mono(12),
                range: NSRange(location: afterLabel + 2, length: max(0, m.range(at: 2).length)))
        }
    }
}
