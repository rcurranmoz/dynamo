import AppKit

final class Dynamo: NSObject, NSApplicationDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var task: Process?

    private var isAwake: Bool { task?.isRunning ?? false }

    // MARK: Icon

    // SF Symbols has no variable-value bolt, so the fill is composited: the hollow `bolt`
    // outline is drawn whole, then `bolt.fill` is drawn on top clipped to a rising rectangle.
    private static let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
    private let outline = NSImage(systemSymbolName: "bolt", accessibilityDescription: "idle")?
        .withSymbolConfiguration(Dynamo.config)
    private let solid = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "awake")?
        .withSymbolConfiguration(Dynamo.config)

    private func icon(fill: CGFloat) -> NSImage? {
        guard let outline, let solid else {
            // Degrade to the plain symbols rather than crash if either is unavailable.
            return NSImage(systemSymbolName: fill > 0.5 ? "bolt.fill" : "bolt",
                           accessibilityDescription: nil)
        }
        // The two glyphs differ by a point in height, so center each at its natural size
        // in a shared canvas instead of stretching one to fit the other.
        let canvas = NSSize(width: max(outline.size.width, solid.size.width),
                            height: max(outline.size.height, solid.size.height))
        func centered(_ img: NSImage) -> NSRect {
            NSRect(x: (canvas.width - img.size.width) / 2,
                   y: (canvas.height - img.size.height) / 2,
                   width: img.size.width, height: img.size.height)
        }
        let img = NSImage(size: canvas, flipped: false) { _ in
            outline.draw(in: centered(outline))
            if fill > 0 {
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(rect: NSRect(x: 0, y: 0,
                                          width: canvas.width,
                                          height: canvas.height * fill)).setClip()
                solid.draw(in: centered(solid))
                NSGraphicsContext.restoreGraphicsState()
            }
            return true
        }
        img.isTemplate = true   // let the menubar tint it for light/dark and highlight
        return img
    }

    // The bolt's ink sits in its upper middle, so a clip rising at constant speed spends half the
    // animation creeping up the thin tail and then snaps solid. Rasterize the glyph once, measure
    // how much ink lies below each row, and invert that curve so equal time means equal ink.
    private lazy var heightForStep: [CGFloat] = {
        let steps = Self.frames
        guard let solid,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: Int(solid.size.width) * 8,
                                         pixelsHigh: Int(solid.size.height) * 8,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: rep)
        else { return (0...steps).map { CGFloat($0) / CGFloat(steps) } }   // fall back to linear

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        solid.draw(in: NSRect(x: 0, y: 0, width: CGFloat(rep.pixelsWide), height: CGFloat(rep.pixelsHigh)))
        NSGraphicsContext.restoreGraphicsState()

        let h = rep.pixelsHigh, w = rep.pixelsWide
        guard let data = rep.bitmapData else { return (0...steps).map { CGFloat($0) / CGFloat(steps) } }
        var below = [Double](repeating: 0, count: h + 1)      // cumulative ink from the bottom up
        for y in stride(from: h - 1, through: 0, by: -1) {    // bitmap row 0 is the top
            var ink = 0.0
            for x in 0..<w { ink += Double(data[y * rep.bytesPerRow + x * 4 + 3]) }
            let fromBottom = h - 1 - y
            below[fromBottom + 1] = below[fromBottom] + ink
        }
        let total = below[h]
        guard total > 0 else { return (0...steps).map { CGFloat($0) / CGFloat(steps) } }

        return (0...steps).map { step in
            let target = Double(step) / Double(steps) * total
            var lo = 0, hi = h
            while lo < hi { let mid = (lo + hi) / 2; if below[mid] < target { lo = mid + 1 } else { hi = mid } }
            return CGFloat(lo) / CGFloat(h)
        }
    }()

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
            cache[step] = icon(fill: heightForStep[step])
        }
        item.button?.image = cache[step] ?? nil
    }

    // Animates from wherever the level currently sits, so a mid-animation click
    // reverses smoothly instead of snapping.
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
