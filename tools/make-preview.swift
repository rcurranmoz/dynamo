// Generates the README preview assets in docs/.
//
// This mirrors the icon compositing in main.swift, but at a large point size so the output is
// crisp instead of an upscaled 15x20 menubar raster. It is a documentation tool, not part of the
// app: if you change how the icon is drawn, change it here too.
//
//   swiftc -O tools/make-preview.swift -o /tmp/make-preview && /tmp/make-preview
//
import AppKit
import ImageIO

let pointSize: CGFloat = 120
let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
guard let outline = NSImage(systemSymbolName: "bolt", accessibilityDescription: nil)?
        .withSymbolConfiguration(config),
      let solid = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config)
else { fatalError("bolt symbols unavailable") }

func rgb(_ hex: Int, alpha: CGFloat = 1) -> NSColor {
    let r = CGFloat((hex >> 16) & 0xff) / 255.0
    let g = CGFloat((hex >> 8) & 0xff) / 255.0
    let b = CGFloat(hex & 0xff) / 255.0
    return NSColor(srgbRed: r, green: g, blue: b, alpha: alpha)
}
let palette: [NSColor] = {
    let hexes: [Int] = [0x009DDC, 0x963D97, 0xE03A3E, 0xF5821F, 0xFDB827, 0x61BB46]
    return hexes.map { rgb($0) }
}()

let canvas = NSSize(width: max(outline.size.width, solid.size.width),
                    height: max(outline.size.height, solid.size.height))
func centered(_ img: NSImage) -> NSRect {
    NSRect(x: (canvas.width - img.size.width) / 2, y: (canvas.height - img.size.height) / 2,
           width: img.size.width, height: img.size.height)
}

// --- ink curve (same algorithm as main.swift) ---
let ss = 4
let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                           pixelsWide: Int(solid.size.width) * ss,
                           pixelsHigh: Int(solid.size.height) * ss,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
solid.draw(in: NSRect(x: 0, y: 0, width: CGFloat(rep.pixelsWide), height: CGFloat(rep.pixelsHigh)))
NSGraphicsContext.restoreGraphicsState()
let rows = rep.pixelsHigh, cols = rep.pixelsWide
var below = [Double](repeating: 0, count: rows + 1)
let data = rep.bitmapData!
for y in stride(from: rows - 1, through: 0, by: -1) {
    var ink = 0.0
    for x in 0..<cols { ink += Double(data[y * rep.bytesPerRow + x * 4 + 3]) }
    below[rows - 1 - y + 1] = below[rows - 1 - y] + ink
}
let total = below[rows]
func height(forInk fraction: Double) -> CGFloat {
    if fraction <= 0 { return 0 }
    if fraction >= 1 { return 1 }
    let target = fraction * total
    var lo = 0, hi = rows
    while lo < hi { let m = (lo + hi) / 2; if below[m] < target { lo = m + 1 } else { hi = m } }
    return CGFloat(lo) / CGFloat(rows)
}
let bandEdges = (0...palette.count).map { height(forInk: Double($0) / Double(palette.count)) }

// --- icon ---
func icon(ink: Double, outlineColor: NSColor) -> NSImage {
    let fill = height(forInk: ink)
    return NSImage(size: canvas, flipped: false) { _ in
        let line = canvas.height * fill
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: NSRect(x: 0, y: line, width: canvas.width,
                                  height: canvas.height - line)).setClip()
        outline.draw(in: centered(outline))
        NSGraphicsContext.current?.compositingOperation = .sourceAtop
        outlineColor.setFill()
        NSRect(origin: .zero, size: canvas).fill()
        NSGraphicsContext.restoreGraphicsState()
        if fill > 0 {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: NSRect(x: 0, y: 0, width: canvas.width, height: line)).setClip()
            solid.draw(in: centered(solid))
            NSGraphicsContext.current?.compositingOperation = .sourceAtop
            for (i, color) in palette.enumerated() {
                color.setFill()
                let lo = bandEdges[i] * canvas.height, hi = bandEdges[i + 1] * canvas.height
                NSRect(x: 0, y: lo, width: canvas.width, height: hi - lo).fill()
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        return true
    }
}

func png(_ image: NSImage, to path: String) {
    let d = NSBitmapImageRep(data: image.tiffRepresentation!)!
        .representation(using: .png, properties: [:])!
    try! d.write(to: URL(fileURLWithPath: path))
}

struct Theme { let name: String; let bg: NSColor; let ink: NSColor }
// Background colours match GitHub's README canvas so the assets blend in.
let themes = [Theme(name: "light", bg: rgb(0xFFFFFF), ink: rgb(0x000000, alpha: 0.85)),
              Theme(name: "dark",  bg: rgb(0x0D1117), ink: rgb(0xFFFFFF, alpha: 0.85))]

// --- static filmstrip: eight stages of charge ---
let stages = (0..<8).map { Double($0) / 7.0 }
for t in themes {
    let pad: CGFloat = 26
    let cell = NSSize(width: canvas.width + pad, height: canvas.height + pad)
    let strip = NSImage(size: NSSize(width: cell.width * CGFloat(stages.count), height: cell.height))
    strip.lockFocus()
    t.bg.setFill(); NSRect(origin: .zero, size: strip.size).fill()
    for (i, ink) in stages.enumerated() {
        icon(ink: ink, outlineColor: t.ink)
            .draw(in: NSRect(x: cell.width * CGFloat(i) + pad / 2, y: pad / 2,
                             width: canvas.width, height: canvas.height))
    }
    strip.unlockFocus()
    png(strip, to: "docs/stages-\(t.name).png")
}

// --- menubar mockup: where the icon actually lives, at true menubar scale ---
// Rendered at 3x so it stays crisp, but the bolt is drawn at its real 15pt menubar size rather
// than scaled up, so this is what you actually see.
let barScale: CGFloat = 3
let barConfig = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
let neighbours = ["wifi", "battery.75", "switch.2"].compactMap {
    NSImage(systemSymbolName: $0, accessibilityDescription: nil)?.withSymbolConfiguration(barConfig)
}

/// Tints a symbol by compositing into its own transparent canvas. Doing this with .sourceAtop
/// directly on the mockup would fill a solid block, because the opaque bar behind it already
/// has alpha 1 everywhere.
func tinted(_ img: NSImage, _ color: NSColor) -> NSImage {
    NSImage(size: img.size, flipped: false) { rect in
        img.draw(in: rect)
        NSGraphicsContext.current?.compositingOperation = .sourceAtop
        color.setFill()
        rect.fill()
        return true
    }
}

func barIcon(ink: Double, outlineColor: NSColor) -> NSImage {
    guard let o = NSImage(systemSymbolName: "bolt", accessibilityDescription: nil)?
            .withSymbolConfiguration(barConfig),
          let f = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(barConfig)
    else { return NSImage(size: NSSize(width: 15, height: 20)) }
    let cv = NSSize(width: max(o.size.width, f.size.width), height: max(o.size.height, f.size.height))
    func ctr(_ i: NSImage) -> NSRect {
        NSRect(x: (cv.width - i.size.width)/2, y: (cv.height - i.size.height)/2,
               width: i.size.width, height: i.size.height)
    }
    let fill = height(forInk: ink)
    return NSImage(size: cv, flipped: false) { _ in
        let line = cv.height * fill
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: NSRect(x: 0, y: line, width: cv.width, height: cv.height - line)).setClip()
        o.draw(in: ctr(o))
        NSGraphicsContext.current?.compositingOperation = .sourceAtop
        outlineColor.setFill(); NSRect(origin: .zero, size: cv).fill()
        NSGraphicsContext.restoreGraphicsState()
        if fill > 0 {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: NSRect(x: 0, y: 0, width: cv.width, height: line)).setClip()
            f.draw(in: ctr(f))
            NSGraphicsContext.current?.compositingOperation = .sourceAtop
            for (i, color) in palette.enumerated() {
                color.setFill()
                let lo = bandEdges[i]*cv.height, hi = bandEdges[i+1]*cv.height
                NSRect(x: 0, y: lo, width: cv.width, height: hi - lo).fill()
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        return true
    }
}

struct BarTheme { let name: String; let page: NSColor; let bar: NSColor; let ink: NSColor; let dim: NSColor }
let barThemes = [
    BarTheme(name: "light", page: rgb(0xFFFFFF), bar: rgb(0xEFEFF1),
             ink: rgb(0x000000, alpha: 0.85), dim: rgb(0x000000, alpha: 0.5)),
    BarTheme(name: "dark", page: rgb(0x0D1117), bar: rgb(0x232326),
             ink: rgb(0xFFFFFF, alpha: 0.85), dim: rgb(0xFFFFFF, alpha: 0.5)),
]
let barW: CGFloat = 300, barH: CGFloat = 24, capH: CGFloat = 18, rowGap: CGFloat = 12
let fadeW: CGFloat = 70          // left edge fades out: this is a crop of a full-width menubar
let rowsSpec: [(Double, String)] = [(0.0, "sleep allowed"), (1.0, "keeping this Mac awake")]

for t in barThemes {
    let rowH = barH + capH
    let total = CGFloat(rowsSpec.count) * rowH + rowGap
    let img = NSImage(size: NSSize(width: barW * barScale, height: total * barScale))
    img.lockFocus()
    let gctx = NSGraphicsContext.current!
    gctx.imageInterpolation = .high
    gctx.cgContext.scaleBy(x: barScale, y: barScale)
    t.page.setFill(); NSRect(x: 0, y: 0, width: barW, height: total).fill()

    let capFont = NSFont.systemFont(ofSize: 11, weight: .regular)
    let clockFont = NSFont.systemFont(ofSize: 13, weight: .regular)
    let clock = NSAttributedString(string: "9:41",
        attributes: [.font: clockFont, .foregroundColor: t.ink])

    for (r, spec) in rowsSpec.enumerated() {
        let rowTop = total - CGFloat(r) * (rowH + rowGap)
        let barY = rowTop - barH
        let capY = barY - capH

        t.bar.setFill(); NSRect(x: 0, y: barY, width: barW, height: barH).fill()
        NSGradient(starting: t.page, ending: t.page.withAlphaComponent(0))!
            .draw(in: NSRect(x: 0, y: barY, width: fadeW, height: barH), angle: 0)

        var x = barW - 14
        x -= clock.size().width
        clock.draw(at: NSPoint(x: x, y: barY + (barH - clock.size().height) / 2))
        x -= 14
        for n in neighbours.reversed() {
            x -= n.size.width
            tinted(n, t.ink).draw(in: NSRect(x: x, y: barY + (barH - n.size.height) / 2,
                                             width: n.size.width, height: n.size.height))
            x -= 12
        }
        let bolt = barIcon(ink: spec.0, outlineColor: t.ink)
        x -= bolt.size.width
        bolt.draw(in: NSRect(x: x, y: barY + (barH - bolt.size.height) / 2,
                             width: bolt.size.width, height: bolt.size.height))

        let cap = NSAttributedString(string: spec.1,
            attributes: [.font: capFont, .foregroundColor: t.dim])
        cap.draw(at: NSPoint(x: min(x, barW - 14 - cap.size().width),
                             y: capY + (capH - cap.size().height) / 2))
    }
    img.unlockFocus()
    png(img, to: "docs/menubar-\(t.name).png")
}

// --- animated GIF: the real timing, up then hold then down then hold ---
let fps = 25.0, delay = 1.0 / fps, duration = 0.32
func smoothstep(_ p: Double) -> Double { p * p * (3 - 2 * p) }
var timeline: [Double] = []
let ramp = Int((duration * fps).rounded())
for i in 0...ramp { timeline.append(smoothstep(Double(i) / Double(ramp))) }      // charge up
timeline += Array(repeating: 1.0, count: 18)                                     // hold awake
for i in 0...ramp { timeline.append(1 - smoothstep(Double(i) / Double(ramp))) }  // drain
timeline += Array(repeating: 0.0, count: 12)                                     // hold idle

for t in themes {
    let pad: CGFloat = 20
    let size = NSSize(width: canvas.width + pad, height: canvas.height + pad)
    let url = URL(fileURLWithPath: "docs/charge-\(t.name).gif")
    let dest = CGImageDestinationCreateWithURL(url as CFURL, "com.compuserve.gif" as CFString,
                                               timeline.count, nil)!
    CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [
        kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    for ink in timeline {
        let frame = NSImage(size: size)
        frame.lockFocus()
        t.bg.setFill(); NSRect(origin: .zero, size: size).fill()
        icon(ink: ink, outlineColor: t.ink)
            .draw(in: NSRect(x: pad / 2, y: pad / 2, width: canvas.width, height: canvas.height))
        frame.unlockFocus()
        let cg = NSBitmapImageRep(data: frame.tiffRepresentation!)!.cgImage!
        CGImageDestinationAddImage(dest, cg, [kCGImagePropertyGIFDictionary: [
            kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
    }
    guard CGImageDestinationFinalize(dest) else { fatalError("gif write failed") }
}
print("wrote docs/stages-*.png, docs/charge-*.gif, docs/menubar-*.png")
print("gif frames: \(timeline.count) at \(Int(fps))fps")
