import AppKit

final class Dynamo: NSObject, NSApplicationDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var task: Process?

    private var isAwake: Bool { task?.isRunning ?? false }

    // MARK: Glyphs

    // SF Symbols has no variable-value bolt, so the fill is composited: the hollow `bolt`
    // outline is drawn whole, then `bolt.fill` is drawn on top clipped to a rising rectangle.
    private static let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
    private let outline = NSImage(systemSymbolName: "bolt", accessibilityDescription: "idle")?
        .withSymbolConfiguration(Dynamo.config)
    private let solid = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "awake")?
        .withSymbolConfiguration(Dynamo.config)

    private static func rgb(_ hex: Int) -> NSColor {
        let r = CGFloat((hex >> 16) & 0xff) / 255.0
        let g = CGFloat((hex >> 8) & 0xff) / 255.0
        let b = CGFloat(hex & 0xff) / 255.0
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    /// The six-colour Apple logo, ordered bottom-up to match the direction of the fill.
    private static let palette: [NSColor] = {
        let hexes: [Int] = [0x009DDC, 0x963D97, 0xE03A3E, 0xF5821F, 0xFDB827, 0x61BB46]
        return hexes.map(rgb)
    }()

    // MARK: Ink curve
    //
    // The bolt's ink sits in its upper middle: the bottom third of its height holds barely a
    // tenth of its pixels. Measuring how much ink lies below each row, then inverting that
    // curve, buys two things — a fill where equal time means equal ink rather than creeping up
    // the thin tail and then snapping solid, and colour bands of equal ink rather than equal
    // height, which is what keeps green from being a sliver at the tip. Measured at runtime, so
    // it stays correct if Apple ever redraws the symbol.

    private struct Curve {
        let heightForStep: [CGFloat]   // frames + 1 entries: animation step -> height fraction
        let bandEdges: [CGFloat]       // palette.count + 1 entries: band boundaries
    }

    private lazy var curve: Curve = Self.measureInk(of: solid) ?? Curve(
        heightForStep: (0...Self.frames).map { CGFloat($0) / CGFloat(Self.frames) },
        bandEdges: (0...Self.palette.count).map { CGFloat($0) / CGFloat(Self.palette.count) }
    )

    private static func measureInk(of glyph: NSImage?) -> Curve? {
        guard let glyph,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: Int(glyph.size.width) * 8,
                                         pixelsHigh: Int(glyph.size.height) * 8,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: rep)
        else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        glyph.draw(in: NSRect(x: 0, y: 0, width: CGFloat(rep.pixelsWide), height: CGFloat(rep.pixelsHigh)))
        NSGraphicsContext.restoreGraphicsState()

        let rows = rep.pixelsHigh, cols = rep.pixelsWide
        guard let data = rep.bitmapData else { return nil }
        var below = [Double](repeating: 0, count: rows + 1)   // cumulative alpha, bottom-up
        for y in stride(from: rows - 1, through: 0, by: -1) {  // bitmap row 0 is the top
            var ink = 0.0
            for x in 0..<cols { ink += Double(data[y * rep.bytesPerRow + x * 4 + 3]) }
            let fromBottom = rows - 1 - y
            below[fromBottom + 1] = below[fromBottom] + ink
        }
        let total = below[rows]
        guard total > 0 else { return nil }

        // Height at which `fraction` of the glyph's ink lies below.
        func height(forInk fraction: Double) -> CGFloat {
            if fraction <= 0 { return 0 }
            if fraction >= 1 { return 1 }
            let target = fraction * total
            var lo = 0, hi = rows
            while lo < hi {
                let mid = (lo + hi) / 2
                if below[mid] < target { lo = mid + 1 } else { hi = mid }
            }
            return CGFloat(lo) / CGFloat(rows)
        }

        return Curve(
            heightForStep: (0...frames).map { height(forInk: Double($0) / Double(frames)) },
            bandEdges: (0...palette.count).map { height(forInk: Double($0) / Double(palette.count)) }
        )
    }

    // MARK: Icon

    /// The menubar label colour, resolved against the current system appearance. Coloured icons
    /// can't be template images, so the hollow part has to be tinted explicitly.
    private var outlineColor: NSColor {
        var color = NSColor.labelColor
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            color = NSColor.labelColor.usingColorSpace(.sRGB) ?? .labelColor
        }
        return color
    }

    private func icon(fill: CGFloat) -> NSImage? {
        // At rest, hand the menubar the plain template symbol so it tints and highlights natively.
        guard fill > 0 else {
            let img = outline ?? NSImage(systemSymbolName: "bolt", accessibilityDescription: "idle")
            img?.isTemplate = true
            return img
        }
        guard let outline, let solid else {
            return NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "awake")
        }
        // The two glyphs differ by a point in height, so centre each at its natural size in a
        // shared canvas instead of stretching one to fit the other.
        let canvas = NSSize(width: max(outline.size.width, solid.size.width),
                            height: max(outline.size.height, solid.size.height))
        func centered(_ img: NSImage) -> NSRect {
            NSRect(x: (canvas.width - img.size.width) / 2,
                   y: (canvas.height - img.size.height) / 2,
                   width: img.size.width, height: img.size.height)
        }
        let tint = outlineColor
        let img = NSImage(size: canvas, flipped: false) { _ in
            // Hollow outline, tinted to match menubar text.
            outline.draw(in: centered(outline))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.compositingOperation = .sourceAtop
            tint.setFill()
            NSRect(origin: .zero, size: canvas).fill()
            NSGraphicsContext.restoreGraphicsState()

            // Solid glyph up to the fill line, painted with the rainbow bands. sourceAtop keeps
            // the colour inside the glyph's own alpha, so the bolt shape does the masking.
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: NSRect(x: 0, y: 0,
                                      width: canvas.width,
                                      height: canvas.height * fill)).setClip()
            solid.draw(in: centered(solid))
            NSGraphicsContext.current?.compositingOperation = .sourceAtop
            for (i, color) in Self.palette.enumerated() {
                color.setFill()
                let lower = self.curve.bandEdges[i] * canvas.height
                let upper = self.curve.bandEdges[i + 1] * canvas.height
                NSRect(x: 0, y: lower, width: canvas.width, height: upper - lower).fill()
            }
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
        img.isTemplate = false   // keep our colours; the menubar must not tint these
        return img
    }

    // MARK: Animation

    private static let duration = 0.32
    private static let frames = 24        // quantization, and the size of the icon cache

    private var level: CGFloat = 0        // 0 = hollow, 1 = solid
    private var animation: Timer?
    private var cache: [Int: NSImage?] = [:]

    private func draw(_ fill: CGFloat) {
        level = fill
        let step = Int((fill * CGFloat(Self.frames)).rounded())
        if cache[step] == nil {
            cache[step] = icon(fill: curve.heightForStep[step])
        }
        item.button?.image = cache[step] ?? nil
    }

    /// Animates from wherever the level currently sits, so a mid-animation click reverses
    /// smoothly instead of snapping.
    private func animate(to target: CGFloat) {
        animation?.invalidate()
        let start = level
        guard abs(target - start) > 0.001 else { return draw(target) }
        let began = Date()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else { return timer.invalidate() }
            let p = min(1, Date().timeIntervalSince(began) / Self.duration)
            let eased = p * p * (3 - 2 * p)                     // smoothstep
            self.draw(start + (target - start) * CGFloat(eased))
            if p >= 1 {
                timer.invalidate()
                self.animation = nil
            }
        }
        // .common so the animation keeps running while a menu is tracking.
        RunLoop.main.add(timer, forMode: .common)
        animation = timer
    }

    private func render() {
        item.button?.toolTip = isAwake ? "Dynamo: keeping this Mac awake" : "Dynamo: sleep allowed"
        animate(to: isAwake ? 1 : 0)
    }

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ note: Notification) {
        let button = item.button!
        button.target = self
        button.action = #selector(clicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        draw(0)
        render()

        // The tinted outline is baked into the cached frames, so drop them on a theme switch.
        DistributedNotificationCenter.default.addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.cache.removeAll()
            self.draw(self.level)
        }
    }

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: isAwake ? "Awake (click icon to stop)" : "Sleeping",
                         action: nil, keyEquivalent: "").isEnabled = false
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q").target = self
            item.menu = menu
            item.button?.performClick(nil)   // pop the menu
            item.menu = nil                  // detach so left-click keeps toggling
            return
        }
        isAwake ? stop() : start()
        render()
    }

    private func start() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        // -w <our pid>: caffeinate exits automatically if this app ever dies uncleanly.
        p.arguments = ["-dimsu", "-w", String(ProcessInfo.processInfo.processIdentifier)]
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.render() }
        }
        try? p.run()
        task = p
    }

    private func stop() {
        task?.terminate()
        task = nil
    }

    @objc private func quit() { stop(); NSApp.terminate(nil) }

    func applicationWillTerminate(_ note: Notification) { stop() }
}

let app = NSApplication.shared
let delegate = Dynamo()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // no Dock icon, no menu bar
app.run()
