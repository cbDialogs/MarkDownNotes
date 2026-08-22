import SwiftUI
import AppKit
import CoreText

// Editable rendered mode: an NSTextView whose storage is always the raw
// markdown, restyled in place after every edit. Markers (#, **, `, >) stay
// in the text — and on disk — but their glyphs are suppressed, so the file
// and the display keep identical character offsets.

extension NSAttributedString.Key {
    /// A markdown marker: in the storage, not drawn. The value is the range
    /// of the whole construct it belongs to (the `**…**` pair, the heading's
    /// line), so selection and deletion can treat that construct as one unit.
    static let mdnHidden = NSAttributedString.Key("MDNHiddenMarker")
    /// Draw this character as some other glyph — a bullet for a list hyphen,
    /// a box for a task checkbox. The value is the replacement's scalar.
    static let mdnGlyph = NSAttributedString.Key("MDNSubstituteGlyph")
}
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

/// The rendered editor's text view. Clicking a task's box toggles it done
/// rather than placing the caret.
final class RenderedTextView: NSTextView {

    override func mouseDown(with event: NSEvent) {
        if toggleTaskIfClicked(event) { return }
        super.mouseDown(with: event)
    }

    private func toggleTaskIfClicked(_ event: NSEvent) -> Bool {
        guard event.clickCount == 1, event.modifierFlags.isDisjoint(with: [.shift, .command, .option]),
              let layoutManager, let textContainer, let storage = textStorage, storage.length > 0
        else { return false }

        let local = convert(event.locationInWindow, from: nil)
        let inContainer = NSPoint(x: local.x - textContainerInset.width,
                                  y: local.y - textContainerInset.height)
        let index = layoutManager.characterIndex(for: inContainer, in: textContainer,
                                                 fractionOfDistanceBetweenInsertionPoints: nil)
        guard index < storage.length,
              let scalar = storage.attribute(.mdnGlyph, at: index, effectiveRange: nil) as? NSNumber,
              scalar.uint16Value == MarkdownStyler.uncheckedScalar
                || scalar.uint16Value == MarkdownStyler.checkedScalar
        else { return false }

        // characterIndex returns the *nearest* character, so make sure the
        // click actually landed on the box and not somewhere along the line.
        let glyphs = layoutManager.glyphRange(forCharacterRange: NSRange(location: index, length: 1),
                                              actualCharacterRange: nil)
        var box = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
        box.origin.x += textContainerInset.width
        box.origin.y += textContainerInset.height
        guard box.insetBy(dx: -5, dy: -2).contains(local) else { return false }

        return toggleTask(boxAt: index)
    }

    /// Flip the state character between the brackets. It stays one character
    /// wide, so every offset in the document — including the caret — holds.
    private func toggleTask(boxAt index: Int) -> Bool {
        guard let storage = textStorage else { return false }
        let ns = storage.string as NSString
        let line = ns.lineRange(for: NSRange(location: index, length: 0))
        let state = NSRange(location: line.location + 3, length: 1)
        guard NSMaxRange(state) <= ns.length else { return false }
        let replacement = ns.substring(with: state).lowercased() == "x" ? " " : "x"
        guard shouldChangeText(in: state, replacementString: replacement) else { return true }
        let caret = selectedRange()
        storage.replaceCharacters(in: state, with: replacement)
        didChangeText()
        setSelectedRange(caret)
        return true
    }
}

struct RichMarkdownEditor: NSViewRepresentable {
    @EnvironmentObject var store: NotesStore
    @Binding var text: String
    var onEdit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        // TextKit 1, asked for directly: hiding marker glyphs needs it, and
        // the view has to be our subclass for checkbox clicks.
        let tv = RenderedTextView(usingTextLayoutManager: false)
        tv.autoresizingMask = [.width]
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.minSize = .zero
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                            height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(width: 0,
                                                 height: CGFloat.greatestFiniteMagnitude)

        let scroll = NSScrollView()
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.documentView = tv

        if let layoutManager = tv.layoutManager {
            layoutManager.delegate = context.coordinator
            layoutManager.allowsNonContiguousLayout = true
        }
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

    final class Coordinator: NSObject, NSTextViewDelegate, NSLayoutManagerDelegate {
        var parent: RichMarkdownEditor
        init(_ parent: RichMarkdownEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            MarkdownStyler.restyle(tv)
            parent.text = tv.string
            parent.onEdit()
        }

        // MARK: hiding markers

        /// Suppress marker glyphs and swap list hyphens for bullets. Returning
        /// 0 means "do the default"; otherwise return the count stored.
        func layoutManager(_ layoutManager: NSLayoutManager,
                           shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
                           properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
                           characterIndexes charIndexes: UnsafePointer<Int>,
                           font: NSFont,
                           forGlyphRange glyphRange: NSRange) -> Int {
            guard let storage = layoutManager.textStorage else { return 0 }
            let n = glyphRange.length
            let bound = NSRange(location: 0, length: storage.length)
            var newProps: [NSLayoutManager.GlyphProperty]?
            var newGlyphs: [CGGlyph]?

            var i = 0
            while i < n {
                let ci = charIndexes[i]
                guard ci < storage.length else { break }
                var eff = NSRange()
                if storage.attribute(.mdnHidden, at: ci, longestEffectiveRange: &eff, in: bound) != nil {
                    if newProps == nil {
                        newProps = Array(UnsafeBufferPointer(start: props, count: n))
                    }
                    var j = i
                    while j < n, charIndexes[j] < NSMaxRange(eff) {
                        newProps![j] = .null
                        j += 1
                    }
                    i = max(j, i + 1)
                    continue
                }
                if let scalar = storage.attribute(.mdnGlyph, at: ci, effectiveRange: nil) as? NSNumber,
                   let replacement = MarkdownStyler.glyph(for: scalar.uint16Value, in: font) {
                    if newGlyphs == nil {
                        newGlyphs = Array(UnsafeBufferPointer(start: glyphs, count: n))
                    }
                    newGlyphs![i] = replacement
                }
                i += 1
            }

            guard newProps != nil || newGlyphs != nil else { return 0 }
            var g = newGlyphs ?? Array(UnsafeBufferPointer(start: glyphs, count: n))
            var p = newProps ?? Array(UnsafeBufferPointer(start: props, count: n))
            layoutManager.setGlyphs(&g, properties: &p, characterIndexes: charIndexes,
                                    font: font, forGlyphRange: glyphRange)
            return n
        }

        // MARK: keeping the caret out of hidden text

        func textView(_ tv: NSTextView,
                      willChangeSelectionFromCharacterRanges old: [NSValue],
                      toCharacterRanges new: [NSValue]) -> [NSValue] {
            guard let storage = tv.textStorage, storage.length > 0 else { return new }
            return new.map {
                NSValue(range: MarkdownStyler.clampOutOfHidden($0.rangeValue, in: storage))
            }
        }

        func textView(_ tv: NSTextView, shouldChangeTypingAttributes old: [String: Any],
                      toAttributes new: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
            var attrs = new
            attrs.removeValue(forKey: .mdnHidden)
            attrs.removeValue(forKey: .mdnGlyph)
            return attrs
        }

        func textView(_ tv: NSTextView, doCommandBy sel: Selector) -> Bool {
            switch sel {
            case #selector(NSStandardKeyBindingResponding.deleteBackward(_:)):
                return unwrapConstruct(before: true, in: tv)
            case #selector(NSStandardKeyBindingResponding.deleteForward(_:)):
                return unwrapConstruct(before: false, in: tv)
            default:
                return false
            }
        }

        /// Deleting into a hidden marker would silently change the markup —
        /// backspacing at the visual start of a heading eats its `#`. Instead
        /// strip the whole construct's markers in one undoable edit, so
        /// "## Heading" becomes "Heading" and "**bold**" becomes "bold".
        private func unwrapConstruct(before: Bool, in tv: NSTextView) -> Bool {
            guard let storage = tv.textStorage else { return false }
            let sel = tv.selectedRange()
            guard sel.length == 0 else { return false }
            let probe = before ? sel.location - 1 : sel.location
            guard probe >= 0, probe < storage.length,
                  let value = storage.attribute(.mdnHidden, at: probe, effectiveRange: nil) as? NSValue
            else { return false }

            let construct = value.rangeValue
            guard construct.location >= 0, NSMaxRange(construct) <= storage.length else { return false }

            var visible = ""
            var caretOffset = 0
            storage.enumerateAttribute(.mdnHidden, in: construct) { hidden, range, _ in
                guard hidden == nil else { return }
                let piece = (storage.string as NSString).substring(with: range)
                if range.location < sel.location {
                    caretOffset += min(range.length, sel.location - range.location)
                }
                visible += piece
            }

            guard tv.shouldChangeText(in: construct, replacementString: visible) else { return true }
            storage.replaceCharacters(in: construct, with: visible)
            tv.didChangeText()
            let caret = min(construct.location + caretOffset, (tv.string as NSString).length)
            tv.setSelectedRange(NSRange(location: caret, length: 0))
            return true
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
            /// Keep the marker in the text but out of the display. The dim
            /// colour stays as a fallback in case a glyph ever leaks through.
            func hide(_ r: NSRange, construct: NSRange) {
                guard r.length > 0 else { return }
                storage.addAttributes([.foregroundColor: marker,
                                       .mdnHidden: NSValue(range: construct)], range: r)
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
                hide(prefix(level + 1), construct: range)
            } else if reTask.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil {
                // Task list: "- [ ]" / "- [x]" draw as a single box glyph —
                // the "- " and the brackets are hidden, and the character
                // between them becomes □ or ☑.
                storage.addAttribute(.paragraphStyle, value: bulletStyle, range: range)
                styleInline(storage, ns, range)
                let checked = ns.substring(with: NSRange(location: range.location + 3, length: 1)).lowercased() == "x"
                let boxFont = checkboxFont(14)
                let scalar = checked ? checkedScalar : uncheckedScalar
                if range.length >= 6, glyph(for: scalar, in: boxFont) != nil {
                    // Draw the box on the hyphen and hide "[ ] " after it. The
                    // line then starts with a visible glyph, so checkbox rows
                    // line up with plain bullets.
                    storage.addAttributes([.font: boxFont,
                                           .foregroundColor: checked ? doneInk : rust,
                                           .mdnGlyph: NSNumber(value: scalar)], range: prefix(1))
                    hide(NSRange(location: range.location + 2, length: 4), construct: range)
                } else {
                    // No box glyph in this face: keep the literal brackets.
                    hide(prefix(2), construct: range)
                    storage.addAttributes([.font: mono(13), .foregroundColor: rust],
                                          range: NSRange(location: range.location + 2, length: 3))
                }
                if checked && range.length > 6 {
                    let content = NSRange(location: range.location + 6, length: range.length - 6)
                    storage.addAttributes([
                        .foregroundColor: doneInk,
                        .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                        .strikethroughColor: NSColor(Theme.eyebrow)
                    ], range: content)
                }
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                // The hyphen stays in the text but draws as a bullet; leave
                // the space visible so "• item" spaces correctly.
                storage.addAttribute(.paragraphStyle, value: bulletStyle, range: range)
                storage.addAttributes([.mdnGlyph: NSNumber(value: bulletScalar),
                                       .foregroundColor: rust], range: prefix(1))
                styleInline(storage, ns, range)
            } else if let m = reOrdered.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) {
                storage.addAttribute(.paragraphStyle, value: bulletStyle, range: range)
                dim(NSRange(location: range.location, length: m.range.length))
                styleInline(storage, ns, range)
            } else if line.hasPrefix("> ") || trimmed == ">" {
                storage.addAttributes([.font: serifItalic(17), .foregroundColor: quoteInk,
                                       .paragraphStyle: quoteStyle], range: range)
                hide(prefix(2), construct: range)
            } else if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                storage.addAttributes([.foregroundColor: marker, .kern: 2], range: range)
            } else {
                styleInline(storage, ns, range)
            }
        }
        storage.endEditing()

        tv.typingAttributes = [.font: serif(17), .foregroundColor: ink, .paragraphStyle: bodyStyle]
    }

    // MARK: substitute glyphs

    static let bulletScalar: UInt16 = 0x2022        // •
    static let uncheckedScalar: UInt16 = 0x25A1     // □
    static let checkedScalar: UInt16 = 0x2611       // ☑

    /// Checkboxes are drawn in the UI font: the serif has no box glyphs, and
    /// the empty ballot box (U+2610) is missing from every font we ship with,
    /// so a white square stands in for it.
    static func checkboxFont(_ size: CGFloat) -> NSFont { sans(size, .regular) }

    /// Glyph ids are per-face and size-independent, so cache on face + scalar.
    /// Returns nil when the face lacks the character — substituting then would
    /// draw .notdef, an empty rectangle.
    private static var glyphCache: [String: CGGlyph] = [:]
    static func glyph(for scalar: UInt16, in font: NSFont) -> CGGlyph? {
        let key = "\(font.fontName)|\(scalar)"
        if let cached = glyphCache[key] { return cached == 0 ? nil : cached }
        var chars: [UniChar] = [scalar]
        var out = [CGGlyph](repeating: 0, count: 1)
        let ok = CTFontGetGlyphsForCharacters(font as CTFont, &chars, &out, 1)
        glyphCache[key] = ok ? out[0] : 0
        return ok ? out[0] : nil
    }

    /// The caret must never rest inside a hidden run — arrow keys go haywire
    /// there — and a ranged selection must not pick up markers whose partner
    /// lies outside it, or double-clicking "bold" selects "bold**". A
    /// selection that covers a whole construct keeps its markers, so ⌘A is
    /// untouched.
    static func clampOutOfHidden(_ range: NSRange, in storage: NSTextStorage) -> NSRange {
        let all = NSRange(location: 0, length: storage.length)
        func run(at i: Int) -> (run: NSRange, construct: NSRange)? {
            guard i >= 0, i < storage.length else { return nil }
            var eff = NSRange()
            guard let v = storage.attribute(.mdnHidden, at: i,
                                            longestEffectiveRange: &eff, in: all) as? NSValue
            else { return nil }
            return (eff, v.rangeValue)
        }

        var r = range
        if r.length == 0 {
            if let h = run(at: r.location), r.location > h.run.location {
                r.location = NSMaxRange(h.run)
            }
            return r
        }
        func covers(_ c: NSRange) -> Bool { NSIntersectionRange(r, c).length == c.length }
        while r.length > 0, let h = run(at: r.location), !covers(h.construct) {
            let end = NSMaxRange(r)
            r.location = min(NSMaxRange(h.run), end)
            r.length = end - r.location
        }
        while r.length > 0, let h = run(at: NSMaxRange(r) - 1), !covers(h.construct) {
            r.length = max(0, h.run.location - r.location)
        }
        return r
    }

    private static func styleInline(_ storage: NSTextStorage, _ ns: NSString, _ range: NSRange) {
        func hide(_ r: NSRange, construct: NSRange) {
            guard r.length > 0 else { return }
            storage.addAttributes([.foregroundColor: marker,
                                   .mdnHidden: NSValue(range: construct)], range: r)
        }

        reBold.enumerateMatches(in: ns as String, range: range) { m, _, _ in
            guard let m else { return }
            let inner = m.range(at: 1).location != NSNotFound ? m.range(at: 1) : m.range(at: 2)
            storage.addAttribute(.font, value: serifBold(17), range: inner)
            hide(NSRange(location: m.range.location, length: 2), construct: m.range)
            hide(NSRange(location: m.range.location + m.range.length - 2, length: 2), construct: m.range)
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
            hide(NSRange(location: m.range.location, length: 1), construct: m.range)
            hide(NSRange(location: m.range.location + m.range.length - 1, length: 1), construct: m.range)
        }
        reCode.enumerateMatches(in: ns as String, range: range) { m, _, _ in
            guard let m else { return }
            let ticks = m.range(at: 1).length
            storage.addAttributes([.font: mono(13), .foregroundColor: codeInk,
                                   .backgroundColor: codeBG], range: m.range(at: 2))
            hide(NSRange(location: m.range.location, length: ticks), construct: m.range)
            hide(NSRange(location: m.range.location + m.range.length - ticks, length: ticks),
                 construct: m.range)
        }
        reLink.enumerateMatches(in: ns as String, range: range) { m, _, _ in
            guard let m else { return }
            let label = m.range(at: 1)
            storage.addAttributes([.foregroundColor: rust,
                                   .underlineStyle: NSUnderlineStyle.single.rawValue], range: label)
            let afterLabel = label.location + label.length
            hide(NSRange(location: m.range.location, length: 1), construct: m.range)
            hide(NSRange(location: afterLabel, length: m.range.location + m.range.length - afterLabel),
                 construct: m.range)
        }
    }
}
