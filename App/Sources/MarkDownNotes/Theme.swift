import SwiftUI
import CoreText

// The Manuscript × Ledger palette, lifted from the approved mockup.
enum Theme {
    static let paper        = Color(hex: 0xFBF8F1)   // editor background
    static let pane1        = Color(hex: 0xEDE6D9)   // folder sidebar
    static let pane2        = Color(hex: 0xF5F1E7)   // note list
    static let hairline     = Color(hex: 0xE2D8C6)
    static let hairlineSoft = Color(hex: 0xE8DFCE)
    static let rust         = Color(hex: 0x9C4A22)   // accent
    static let rustPale     = Color(hex: 0xEFDCCD)   // MD badge bg (selected row)
    static let rustPale2    = Color(hex: 0xEFE4DA)   // MD badge bg
    static let inkTitle     = Color(hex: 0x1E1915)
    static let ink          = Color(hex: 0x2A241E)
    static let inkSoft      = Color(hex: 0x332C24)
    static let inkFolder    = Color(hex: 0x4A4136)
    static let quote        = Color(hex: 0x574C3F)
    static let secondary    = Color(hex: 0x6E6152)
    static let tertiary     = Color(hex: 0x8A7C6A)
    static let uiBrown      = Color(hex: 0x8A7A61)
    static let mutedLabel   = Color(hex: 0xA08C6E)
    static let eyebrow      = Color(hex: 0xB0A187)
    static let sectionLabel = Color(hex: 0xA8987C)
    static let iconBrown    = Color(hex: 0x9A8B70)
    static let dash         = Color(hex: 0xC2A98A)
    static let amber        = Color(hex: 0xC08A3E)   // "editing" dot
    static let quoteBorder  = Color(hex: 0xD9CDB6)
    static let codeBG       = Color(hex: 0xF0EADC)
    static let codeInk      = Color(hex: 0x5E5344)
    static let rowSelected  = Color(hex: 0xE9E0D0)
    static let searchBG     = Color(hex: 0xEAE2D3)
    static let txtBadgeBG   = Color(hex: 0xEAE3D5)
    static let onRust       = Color(hex: 0xFDF6F1)
    static let onRustDim    = Color(hex: 0xE0B79F)

    static private(set) var hasNewsreader = false

    static func registerFonts() {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("Fonts") else { return }
        for name in ["Newsreader.ttf", "Newsreader-Italic.ttf"] {
            let url = dir.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
        hasNewsreader = NSFont(name: "Newsreader", size: 12) != nil
    }

    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        hasNewsreader
            ? Font.custom("Newsreader", size: size).weight(weight)
            : Font.system(size: size, weight: weight, design: .serif)
    }
    static func serifItalic(_ size: CGFloat) -> Font {
        hasNewsreader
            ? Font.custom("Newsreader", size: size).italic()
            : Font.system(size: size, design: .serif).italic()
    }
    static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.system(size: size, weight: weight)
    }
    static func mono(_ size: CGFloat) -> Font {
        Font.system(size: size, design: .monospaced)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue:  Double(hex & 0xFF) / 255)
    }
}
