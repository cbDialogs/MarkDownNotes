import AppKit

// Warm-paper rounded square with a rust paragraph-ish glyph, echoing the app theme.
let sizes = [16, 32, 64, 128, 256, 512, 1024]
let iconset = URL(fileURLWithPath: "AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func draw(_ px: Int) -> NSImage {
    let s = CGFloat(px)
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    let inset = s * 0.09
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let path = NSBezierPath(roundedRect: rect, xRadius: s * 0.185, yRadius: s * 0.185)

    NSColor(srgbRed: 0.984, green: 0.973, blue: 0.945, alpha: 1).setFill() // paper
    path.fill()
    NSColor(srgbRed: 0.886, green: 0.847, blue: 0.776, alpha: 1).setStroke() // hairline
    path.lineWidth = max(1, s * 0.008)
    path.stroke()

    // three "text" lines
    let rust = NSColor(srgbRed: 0.612, green: 0.29, blue: 0.133, alpha: 1)
    let dash = NSColor(srgbRed: 0.76, green: 0.663, blue: 0.541, alpha: 1)
    let lineH = s * 0.045
    let lx = rect.minX + rect.width * 0.18
    let lw = rect.width * 0.64
    for (i, frac) in [1.0, 0.78, 0.52].enumerated() {
        let y = rect.minY + rect.height * (0.30 - CGFloat(i) * 0.10)
        let r = NSRect(x: lx, y: y, width: lw * frac, height: lineH)
        dash.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: r, xRadius: lineH/2, yRadius: lineH/2).fill()
    }

    // big serif "M" in rust
    let font = NSFont(name: "Newsreader", size: s * 0.46)
        ?? NSFont.systemFont(ofSize: s * 0.44, weight: .medium)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: rust]
    let str = NSAttributedString(string: "M", attributes: attrs)
    let sz = str.size()
    str.draw(at: NSPoint(x: rect.midX - sz.width / 2, y: rect.minY + rect.height * 0.40))

    img.unlockFocus()
    return img
}

// register bundled font so the icon glyph matches
import CoreText
for f in ["Fonts/Newsreader.ttf"] {
    CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: f) as CFURL, .process, nil)
}

for px in sizes {
    let img = draw(px)
    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { continue }
    if px <= 512 {
        try! png.write(to: iconset.appendingPathComponent("icon_\(px)x\(px).png"))
    }
    if px >= 32 {
        try! png.write(to: iconset.appendingPathComponent("icon_\(px/2)x\(px/2)@2x.png"))
    }
}
print("iconset ready")
